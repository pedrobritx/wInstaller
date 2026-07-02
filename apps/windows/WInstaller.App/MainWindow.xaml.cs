using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;

namespace WInstaller.App;

public sealed partial class MainWindow : Window
{
    private static readonly (AssistantStep Step, string Title, string Glyph)[] SidebarSteps =
    [
        (AssistantStep.Welcome, "Welcome", "\uE80F"),
        (AssistantStep.ChooseIso, "Choose ISO", "\uE8A5"),
        (AssistantStep.VerifyIso, "Verify ISO", "\uE73E"),
        (AssistantStep.InsertUsb, "Insert USB", "\uE88E"),
        (AssistantStep.AnalyzeUsb, "Analyze USB", "\uE9D9"),
        (AssistantStep.ConfirmErase, "Confirm Erase", "\uE7BA"),
        (AssistantStep.CreateUsb, "Create USB", "\uE895"),
        (AssistantStep.Done, "Done", "\uE930"),
    ];

    internal AssistantModel Model { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = "wInstaller";
        SystemBackdrop = new MicaBackdrop();
        Model.Changed += Render;
        Render();
    }

    private void Render()
    {
        RenderSidebar();
        StepContent.Content = Steps.Build(Model, this);
        BackButton.IsEnabled = Model.CanGoBack;
        BackButton.Visibility = Model.CanGoBack ? Visibility.Visible : Visibility.Collapsed;
        ContinueButton.Content = ContinueLabel();
        ContinueButton.IsEnabled = Model.CanContinue;
        ErrorText.Text = Model.ErrorMessage ?? "";
    }

    /// <summary>Called by the confirm-erase text box without a full re-render.</summary>
    internal void RefreshContinueButton() => ContinueButton.IsEnabled = Model.CanContinue;

    private string ContinueLabel() => Model.Step switch
    {
        AssistantStep.ConfirmErase => AppStrings.Get("confirm-erase.action_confirm"),
        AssistantStep.Done => "Start Over",
        _ => "Continue",
    };

    private void RenderSidebar()
    {
        SidebarPanel.Children.Clear();
        foreach (var (step, title, glyph) in SidebarSteps)
        {
            var isCurrent = Model.Step == step;
            var isReached = Model.Step >= step;

            var row = new Grid
            {
                Padding = new Thickness(10, 8, 10, 8),
                CornerRadius = new CornerRadius(6),
            };
            if (isCurrent)
            {
                row.Background = (Brush)Application.Current.Resources["AccentFillColorDefaultBrush"];
            }
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var icon = new FontIcon { Glyph = glyph, FontSize = 14, Margin = new Thickness(0, 0, 10, 0) };
            var label = new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(label, 1);

            if (isCurrent)
            {
                icon.Foreground = (Brush)Application.Current.Resources["TextOnAccentFillColorPrimaryBrush"];
                label.Foreground = (Brush)Application.Current.Resources["TextOnAccentFillColorPrimaryBrush"];
            }
            else if (!isReached)
            {
                icon.Foreground = (Brush)Application.Current.Resources["TextFillColorTertiaryBrush"];
                label.Foreground = (Brush)Application.Current.Resources["TextFillColorTertiaryBrush"];
            }

            row.Children.Add(icon);
            row.Children.Add(label);
            SidebarPanel.Children.Add(row);
        }
    }

    private void OnContinue(object sender, RoutedEventArgs args) => Model.ContinueFlow();

    private void OnBack(object sender, RoutedEventArgs args) => Model.GoBack();

    internal async Task PickIsoAsync()
    {
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.Downloads,
        };
        picker.FileTypeFilter.Add(".iso");

        // Unpackaged apps must associate the picker with a window handle.
        var handle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, handle);

        var file = await picker.PickSingleFileAsync();
        if (file is not null)
        {
            await Model.ImportIsoAsync(file.Path);
        }
    }
}
