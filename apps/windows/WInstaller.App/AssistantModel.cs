using WInstaller.Core;

namespace WInstaller.App;

public enum AssistantStep
{
    Welcome = 1,
    ChooseIso,
    VerifyIso,
    InsertUsb,
    AnalyzeUsb,
    ConfirmErase,
    CreateUsb,
    Done,
}

/// <summary>
/// Coordinates the assistant flow: owns user intent, confirmation state, live
/// device data, and the running operation. Mirrors the macOS AssistantModel;
/// the flow ends at Done because the virtualization-handoff step is
/// not-applicable on Windows (docs/screen-inventory.yaml).
/// </summary>
public sealed class AssistantModel
{
    /// <summary>Raised on every state transition the UI must re-render for.</summary>
    public event Action? Changed;

    // Flow state
    public AssistantStep Step { get; private set; } = AssistantStep.Welcome;
    public InstallerIso? Iso { get; private set; }
    public UsbDrive? SelectedDrive { get; private set; }
    public OperationPlan? Plan { get; private set; }
    public List<EngineEvent> Events { get; } = [];
    public string ConfirmationText { get; private set; } = "";
    public string? ErrorMessage { get; private set; }

    // UI state
    public bool IsInspectingIso { get; private set; }
    public bool IsRefreshingDrives { get; private set; }
    public bool IsRunning { get; private set; }
    public bool SimulateMode { get; private set; }

    // Device data
    public IReadOnlyList<UsbDrive> Drives { get; private set; } = [];
    public string CommandLog { get; private set; } = "";

    private readonly BootableUsbEngine _engine = new();
    private readonly ICommandRunner _liveRunner = new ProcessCommandRunner();
    private readonly LocalLogger _logger = new();
    private CancellationTokenSource? _executionCancellation;

    public bool CanContinue => Step switch
    {
        AssistantStep.Welcome => true,
        AssistantStep.ChooseIso => Iso is not null && !IsInspectingIso,
        AssistantStep.VerifyIso => Iso?.Confidence >= DetectionConfidence.Medium,
        AssistantStep.InsertUsb => SelectedDrive is not null,
        AssistantStep.AnalyzeUsb => Plan is not null,
        AssistantStep.ConfirmErase => ConfirmationText == SelectedDrive?.DisplayName,
        AssistantStep.CreateUsb => !IsRunning,
        AssistantStep.Done => true,
        _ => false,
    };

    public bool CanGoBack => Step > AssistantStep.Welcome && Step < AssistantStep.CreateUsb;

    // MARK: Navigation

    public void ContinueFlow()
    {
        ErrorMessage = null;
        switch (Step)
        {
            case AssistantStep.Welcome:
                Step = AssistantStep.ChooseIso;
                break;
            case AssistantStep.ChooseIso:
                Step = AssistantStep.VerifyIso;
                break;
            case AssistantStep.VerifyIso:
                Step = AssistantStep.InsertUsb;
                _ = RefreshDrivesAsync();
                break;
            case AssistantStep.InsertUsb:
                CreatePlan();
                if (Plan is not null)
                {
                    Step = AssistantStep.AnalyzeUsb;
                }
                break;
            case AssistantStep.AnalyzeUsb:
                Step = AssistantStep.ConfirmErase;
                break;
            case AssistantStep.ConfirmErase:
                _ = ConfirmAndCreateAsync();
                break;
            case AssistantStep.CreateUsb:
                Step = AssistantStep.Done;
                break;
            case AssistantStep.Done:
                Reset();
                break;
        }
        RaiseChanged();
    }

    public void GoBack()
    {
        if (!CanGoBack)
        {
            return;
        }
        ErrorMessage = null;
        Step = (AssistantStep)((int)Step - 1);
        RaiseChanged();
    }

    // MARK: ISO

    public async Task ImportIsoAsync(string path)
    {
        if (!path.EndsWith(".iso", StringComparison.OrdinalIgnoreCase))
        {
            ErrorMessage = "Choose a file with the .iso extension.";
            RaiseChanged();
            return;
        }

        IsInspectingIso = true;
        ErrorMessage = null;
        RaiseChanged();
        try
        {
            var inspector = new IsoInspector(_liveRunner, _engine);
            Iso = await inspector.InspectAsync(path);
        }
        catch (IsoInspectionException exception)
        {
            ErrorMessage = exception.UserMessage;
        }
        catch (BootableUsbException exception)
        {
            ErrorMessage = exception.UserMessage;
        }
        catch (Exception exception)
        {
            ErrorMessage = exception.Message;
        }
        IsInspectingIso = false;
        RaiseChanged();
    }

    // MARK: USB

    public async Task RefreshDrivesAsync()
    {
        IsRefreshingDrives = true;
        RaiseChanged();
        try
        {
            var enumerator = new DiskEnumerator(_liveRunner);
            Drives = await enumerator.RemovableDrivesAsync();
        }
        catch (Exception)
        {
            Drives = [];
        }
        if (SelectedDrive is not null && Drives.All(drive => drive.DiskNumber != SelectedDrive.DiskNumber))
        {
            SelectedDrive = null;
        }
        IsRefreshingDrives = false;
        RaiseChanged();
    }

    public void SelectDrive(UsbDrive? drive)
    {
        SelectedDrive = drive;
        RaiseChanged();
    }

    private void CreatePlan()
    {
        if (Iso is null || SelectedDrive is null)
        {
            return;
        }
        try
        {
            Plan = _engine.MakePlan(Iso, SelectedDrive);
            SeedEvents(Plan);
        }
        catch (BootableUsbException exception)
        {
            ErrorMessage = exception.UserMessage;
        }
    }

    // MARK: Confirmation input (does not raise Changed: the text box owns focus)

    public void SetConfirmationText(string text) => ConfirmationText = text;

    public void SetSimulateMode(bool enabled) => SimulateMode = enabled;

    // MARK: Execution

    private async Task ConfirmAndCreateAsync()
    {
        if (Plan is null || SelectedDrive is null)
        {
            return;
        }
        try
        {
            _engine.ConfirmErase(SelectedDrive, ConfirmationText);
        }
        catch (BootableUsbException exception)
        {
            ErrorMessage = exception.UserMessage;
            RaiseChanged();
            return;
        }

        Step = AssistantStep.CreateUsb;
        IsRunning = true;
        ErrorMessage = null;
        SeedEvents(Plan);
        RaiseChanged();

        var executor = SimulateMode
            ? Simulation.Executor(Plan, _logger)
            : new OperationExecutor(_liveRunner, logger: _logger);

        _executionCancellation = new CancellationTokenSource();
        try
        {
            await foreach (var engineEvent in executor.Run(Plan, _executionCancellation.Token))
            {
                Apply(engineEvent);
            }
            IsRunning = false;
            CommandLog = _logger.ExportText();
            Step = AssistantStep.Done;
        }
        catch (ExecutionException exception)
        {
            IsRunning = false;
            ErrorMessage = exception.UserMessage;
            CommandLog = _logger.ExportText();
        }
        catch (Exception exception)
        {
            IsRunning = false;
            ErrorMessage = exception.Message;
        }
        RaiseChanged();
    }

    public void CancelExecution()
    {
        _executionCancellation?.Cancel();
        _executionCancellation = null;
    }

    private void Apply(EngineEvent engineEvent)
    {
        var index = Events.FindIndex(existing => existing.Id == engineEvent.Id);
        if (index >= 0)
        {
            Events[index] = engineEvent;
        }
        else
        {
            Events.Add(engineEvent);
        }
        RaiseChanged();
    }

    private void SeedEvents(OperationPlan plan)
    {
        Events.Clear();
        var seeds = new List<(string Id, string Title)>
        {
            ("mount-iso", "Mount ISO read-only"),
            ("verify-usb", "Re-check USB identity"),
            ("prepare-usb", "Erase and format USB drive"),
            ("copy-files", "Copy installer files"),
        };
        if (plan.Strategy.RequiresWimSplit)
        {
            seeds.Add(("split-wim", "Split oversized Windows image"));
        }
        seeds.Add(("validate", "Validate boot files"));
        seeds.Add(("eject", "Eject USB safely"));

        Events.AddRange(seeds.Select(seed =>
            new EngineEvent(seed.Id, EngineState.Idle, seed.Title, "Waiting…", ChecklistStatus.Waiting)));
    }

    // MARK: Reset

    private void Reset()
    {
        CancelExecution();
        _engine.Reset();
        Step = AssistantStep.Welcome;
        Iso = null;
        SelectedDrive = null;
        Plan = null;
        Events.Clear();
        ConfirmationText = "";
        ErrorMessage = null;
        CommandLog = "";
        IsRunning = false;
    }

    private void RaiseChanged() => Changed?.Invoke();
}
