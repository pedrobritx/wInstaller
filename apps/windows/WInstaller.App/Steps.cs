using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using WInstaller.Core;

namespace WInstaller.App;

/// <summary>
/// Builds the content view for each assistant step. All user-facing copy comes
/// from the shared string table (AppStrings / copy.yaml); the step set matches
/// docs/screen-inventory.yaml. The `SCREEN:` markers below are read by
/// scripts/check_screen_parity.py.
/// </summary>
internal static class Steps
{
    public static UIElement Build(AssistantModel model, MainWindow window) => model.Step switch
    {
        AssistantStep.Welcome => Welcome(),
        AssistantStep.ChooseIso => ChooseIso(model, window),
        AssistantStep.VerifyIso => VerifyIso(model),
        AssistantStep.InsertUsb => InsertUsb(model),
        AssistantStep.AnalyzeUsb => AnalyzeUsb(model),
        AssistantStep.ConfirmErase => ConfirmErase(model, window),
        AssistantStep.CreateUsb => CreateUsb(model),
        AssistantStep.Done => Done(model),
        _ => new TextBlock { Text = "" },
    };

    // SCREEN: welcome
    private static UIElement Welcome()
    {
        var panel = Page("welcome.title", "welcome.subtitle");
        var card = Card();
        card.Children.Add(InfoRow("\uE8A5", AppStrings.Get("welcome.info_iso_title"), AppStrings.Get("welcome.info_iso_body")));
        card.Children.Add(InfoRow("\uE88E", AppStrings.Get("welcome.info_usb_title"), AppStrings.Get("welcome.info_usb_body")));
        card.Children.Add(InfoRow("\uE72E", AppStrings.Get("welcome.info_confirmation_title"), AppStrings.Get("welcome.info_confirmation_body")));
        card.Children.Add(InfoRow("\uE946", AppStrings.Get("welcome.info_local_title"), AppStrings.Get("welcome.info_local_body")));
        panel.Children.Add(Boxed(card));
        return panel;
    }

    // SCREEN: choose-iso
    private static UIElement ChooseIso(AssistantModel model, MainWindow window)
    {
        var panel = Page("choose-iso.title", "choose-iso.subtitle");

        var chooseButton = new Button
        {
            Content = AppStrings.Get("choose-iso.action_choose"),
            IsEnabled = !model.IsInspectingIso,
        };
        chooseButton.Click += async (_, _) => await window.PickIsoAsync();
        panel.Children.Add(chooseButton);

        if (model.IsInspectingIso)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
            row.Children.Add(new ProgressRing { IsActive = true, Width = 20, Height = 20 });
            row.Children.Add(Body(AppStrings.Get("choose-iso.status_mounting")));
            panel.Children.Add(row);
        }
        else if (model.Iso is { } iso)
        {
            var card = Card();
            card.Children.Add(FieldRow("File", iso.DisplayName));
            card.Children.Add(FieldRow("Size", ByteFormat.Bytes(iso.Size)));
            panel.Children.Add(Boxed(card));
        }

        return panel;
    }

    // SCREEN: verify-iso
    private static UIElement VerifyIso(AssistantModel model)
    {
        var panel = Page("verify-iso.title", "verify-iso.subtitle");
        if (model.Iso is not { } iso)
        {
            return panel;
        }

        var card = Card();
        card.Children.Add(FieldRow(AppStrings.Get("verify-iso.field_os"), iso.DetectedOs.DisplayName));
        card.Children.Add(FieldRow(AppStrings.Get("verify-iso.field_confidence"), iso.Confidence.ToString()));
        card.Children.Add(FieldRow("File", iso.DisplayName));
        card.Children.Add(FieldRow("Size", ByteFormat.Bytes(iso.Size)));
        if (!string.IsNullOrEmpty(iso.VolumeLabel))
        {
            card.Children.Add(FieldRow("Volume label", iso.VolumeLabel!));
        }
        card.Children.Add(FieldRow(AppStrings.Get("verify-iso.field_boot_files"), iso.BootFiles.Count.ToString()));
        if (iso.WindowsImageInfo is { } imageInfo)
        {
            card.Children.Add(FieldRow(
                AppStrings.Get("verify-iso.field_wim_status"),
                AppStrings.Get(imageInfo.RequiresSplit ? "verify-iso.wim_split_required" : "verify-iso.wim_no_split")));
        }
        panel.Children.Add(Boxed(card));
        return panel;
    }

    // SCREEN: insert-usb
    private static UIElement InsertUsb(AssistantModel model)
    {
        var panel = Page("insert-usb.title", "insert-usb.subtitle");

        var refreshButton = new Button
        {
            Content = AppStrings.Get("insert-usb.action_refresh"),
            IsEnabled = !model.IsRefreshingDrives,
        };
        refreshButton.Click += async (_, _) => await model.RefreshDrivesAsync();
        panel.Children.Add(refreshButton);

        if (model.IsRefreshingDrives)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
            row.Children.Add(new ProgressRing { IsActive = true, Width = 20, Height = 20 });
            row.Children.Add(Body(AppStrings.Get("insert-usb.status_looking")));
            panel.Children.Add(row);
        }
        else if (model.Drives.Count == 0)
        {
            var empty = Card();
            empty.Children.Add(Heading(AppStrings.Get("insert-usb.empty_title")));
            empty.Children.Add(Body(AppStrings.Get("insert-usb.empty_message")));
            panel.Children.Add(Boxed(empty));
        }
        else
        {
            var list = new ListView { SelectionMode = ListViewSelectionMode.Single };
            foreach (var drive in model.Drives)
            {
                var row = new StackPanel { Spacing = 2, Padding = new Thickness(4, 8, 4, 8) };
                row.Children.Add(new TextBlock { Text = drive.DisplayName });
                row.Children.Add(Caption($"{drive.Identifier} · {ByteFormat.Bytes(drive.Size)} · {drive.ConnectionType} · {drive.FileSystem}"));
                var item = new ListViewItem
                {
                    Content = row,
                    Tag = drive,
                    IsSelected = model.SelectedDrive?.DiskNumber == drive.DiskNumber,
                };
                list.Items.Add(item);
            }
            list.SelectionChanged += (_, _) =>
                model.SelectDrive((list.SelectedItem as ListViewItem)?.Tag as UsbDrive);
            panel.Children.Add(list);
        }

        return panel;
    }

    // SCREEN: analyze-usb
    private static UIElement AnalyzeUsb(AssistantModel model)
    {
        var panel = Page("analyze-usb.title", "analyze-usb.subtitle");
        if (model.Plan is not { } plan)
        {
            return panel;
        }

        var strategyCard = Card();
        strategyCard.Children.Add(FieldRow("Partition scheme", plan.Strategy.TargetPartitionScheme));
        strategyCard.Children.Add(FieldRow("File system", plan.Strategy.TargetFileSystem));
        strategyCard.Children.Add(FieldRow("Data to copy", ByteFormat.Bytes(plan.EstimatedBytesToCopy)));
        panel.Children.Add(Boxed(strategyCard));

        foreach (var warning in plan.Strategy.Warnings)
        {
            var infoBar = new InfoBar
            {
                Severity = InfoBarSeverity.Warning,
                Message = warning,
                IsOpen = true,
                IsClosable = false,
            };
            panel.Children.Add(infoBar);
        }

        var stepsCard = Card();
        foreach (var step in plan.Steps)
        {
            var row = new StackPanel { Spacing = 2 };
            var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            titleRow.Children.Add(new TextBlock { Text = step.Title });
            if (step.Command?.IsDestructive == true)
            {
                titleRow.Children.Add(new TextBlock
                {
                    Text = "DESTRUCTIVE",
                    FontSize = 11,
                    Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"],
                    VerticalAlignment = VerticalAlignment.Center,
                });
            }
            row.Children.Add(titleRow);
            row.Children.Add(Caption(step.Detail));
            stepsCard.Children.Add(row);
        }
        panel.Children.Add(Boxed(stepsCard));

        return panel;
    }

    // SCREEN: confirm-erase
    private static UIElement ConfirmErase(AssistantModel model, MainWindow window)
    {
        var panel = Page("confirm-erase.title", "confirm-erase.subtitle");
        if (model.SelectedDrive is not { } drive)
        {
            return panel;
        }

        panel.Children.Add(new InfoBar
        {
            Severity = InfoBarSeverity.Error,
            Message = AppStrings.Format("confirm-erase.warning", ("drive_name", drive.DisplayName)),
            IsOpen = true,
            IsClosable = false,
        });

        panel.Children.Add(Body(AppStrings.Format(
            "confirm-erase.detail_format",
            ("identifier", drive.Identifier),
            ("capacity", ByteFormat.Bytes(drive.Size)),
            ("volumes", drive.Volumes.Count > 0 ? string.Join(", ", drive.Volumes) : "—"))));

        var confirmationBox = new TextBox
        {
            PlaceholderText = AppStrings.Format("confirm-erase.field_placeholder", ("drive_name", drive.DisplayName)),
            Text = model.ConfirmationText,
        };
        confirmationBox.TextChanged += (_, _) =>
        {
            model.SetConfirmationText(confirmationBox.Text);
            window.RefreshContinueButton();
        };
        panel.Children.Add(confirmationBox);

        var simulateCard = Card();
        var simulateRow = new Grid();
        simulateRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        simulateRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var simulateText = new StackPanel { Spacing = 2 };
        simulateText.Children.Add(Heading(AppStrings.Get("confirm-erase.simulate_title")));
        simulateText.Children.Add(Caption(AppStrings.Get("confirm-erase.simulate_body")));
        var simulateSwitch = new ToggleSwitch { IsOn = model.SimulateMode, OnContent = null, OffContent = null };
        simulateSwitch.Toggled += (_, _) => model.SetSimulateMode(simulateSwitch.IsOn);
        Grid.SetColumn(simulateSwitch, 1);
        simulateRow.Children.Add(simulateText);
        simulateRow.Children.Add(simulateSwitch);
        simulateCard.Children.Add(simulateRow);
        panel.Children.Add(Boxed(simulateCard));

        return panel;
    }

    // SCREEN: create-usb
    private static UIElement CreateUsb(AssistantModel model)
    {
        var titleKey = model.SimulateMode ? "create-usb.title_simulate" : "create-usb.title_real";
        var subtitleKey = model.SimulateMode ? "create-usb.subtitle_simulate" : "create-usb.subtitle_real";
        var panel = new StackPanel { Spacing = 16, MaxWidth = 640, HorizontalAlignment = HorizontalAlignment.Left };
        panel.Children.Add(Title(AppStrings.Get(titleKey)));
        panel.Children.Add(Body(AppStrings.Get(subtitleKey)));

        var checklist = Card();
        foreach (var engineEvent in model.Events)
        {
            checklist.Children.Add(ChecklistRow(engineEvent));
        }
        panel.Children.Add(Boxed(checklist));

        if (model.IsRunning)
        {
            var cancelButton = new Button { Content = AppStrings.Get("create-usb.action_cancel") };
            cancelButton.Click += (_, _) => model.CancelExecution();
            panel.Children.Add(cancelButton);
        }

        return panel;
    }

    // SCREEN: done
    private static UIElement Done(AssistantModel model)
    {
        var titleKey = model.SimulateMode ? "done.title_simulate" : "done.title_real";
        var subtitleKey = model.SimulateMode ? "done.subtitle_simulate" : "done.subtitle_real";
        var panel = new StackPanel { Spacing = 16, MaxWidth = 640, HorizontalAlignment = HorizontalAlignment.Left };

        var headline = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        headline.Children.Add(new FontIcon
        {
            Glyph = "\uE930",
            FontSize = 28,
            Foreground = (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"],
        });
        headline.Children.Add(Title(AppStrings.Get(titleKey)));
        panel.Children.Add(headline);
        panel.Children.Add(Body(AppStrings.Get(subtitleKey)));

        if (model.Plan is { } plan)
        {
            var card = Card();
            card.Children.Add(FieldRow("Installer", plan.Iso.DetectedOs.DisplayName));
            card.Children.Add(FieldRow("USB drive", $"{plan.Drive.DisplayName} ({plan.Drive.Identifier})"));
            foreach (var check in plan.ValidationChecks)
            {
                var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                row.Children.Add(new FontIcon
                {
                    Glyph = "\uE73E",
                    FontSize = 12,
                    Foreground = (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"],
                });
                row.Children.Add(Body(check));
                card.Children.Add(row);
            }
            panel.Children.Add(Boxed(card));
        }

        if (!string.IsNullOrEmpty(model.CommandLog))
        {
            panel.Children.Add(Heading("Command log (redacted)"));
            var log = new TextBlock
            {
                Text = model.CommandLog,
                FontFamily = new FontFamily("Consolas"),
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
            };
            var scroller = new ScrollViewer { Content = log, MaxHeight = 180 };
            panel.Children.Add(Boxed(Wrap(scroller)));
        }

        return panel;
    }

    // MARK: Shared building blocks

    private static StackPanel Page(string titleKey, string subtitleKey)
    {
        var panel = new StackPanel { Spacing = 16, MaxWidth = 640, HorizontalAlignment = HorizontalAlignment.Left };
        panel.Children.Add(Title(AppStrings.Get(titleKey)));
        panel.Children.Add(Body(AppStrings.Get(subtitleKey)));
        return panel;
    }

    private static TextBlock Title(string text) => new()
    {
        Text = text,
        FontSize = 26,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        TextWrapping = TextWrapping.Wrap,
    };

    private static TextBlock Heading(string text) => new()
    {
        Text = text,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        TextWrapping = TextWrapping.Wrap,
    };

    private static TextBlock Body(string text) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
    };

    private static TextBlock Caption(string text) => new()
    {
        Text = text,
        FontSize = 12,
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.Resources["TextFillColorTertiaryBrush"],
    };

    private static StackPanel Card() => new() { Spacing = 12 };

    private static StackPanel Wrap(UIElement child)
    {
        var panel = Card();
        panel.Children.Add(child);
        return panel;
    }

    private static Border Boxed(UIElement content) => new()
    {
        Child = content,
        Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
        BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(8),
        Padding = new Thickness(16),
    };

    private static Grid InfoRow(string glyph, string title, string body)
    {
        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var icon = new FontIcon { Glyph = glyph, FontSize = 16, Margin = new Thickness(0, 2, 12, 0) };
        var text = new StackPanel { Spacing = 2 };
        text.Children.Add(Heading(title));
        text.Children.Add(Caption(body));
        Grid.SetColumn(text, 1);

        row.Children.Add(icon);
        row.Children.Add(text);
        return row;
    }

    private static Grid FieldRow(string label, string value)
    {
        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var caption = Caption(label);
        var content = new TextBlock { Text = value, TextWrapping = TextWrapping.Wrap };
        Grid.SetColumn(content, 1);

        row.Children.Add(caption);
        row.Children.Add(content);
        return row;
    }

    private static Grid ChecklistRow(EngineEvent engineEvent)
    {
        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        UIElement statusIcon;
        if (engineEvent.Status == ChecklistStatus.Running)
        {
            statusIcon = new ProgressRing
            {
                IsActive = true,
                Width = 16,
                Height = 16,
                Margin = new Thickness(0, 2, 12, 0),
            };
        }
        else
        {
            var (glyph, brushKey) = engineEvent.Status switch
            {
                ChecklistStatus.Complete => ("\uE73E", "SystemFillColorSuccessBrush"),
                ChecklistStatus.Warning => ("\uE7BA", "SystemFillColorCautionBrush"),
                ChecklistStatus.Failed => ("\uE711", "SystemFillColorCriticalBrush"),
                _ => ("\uE823", "TextFillColorTertiaryBrush"),
            };
            statusIcon = new FontIcon
            {
                Glyph = glyph,
                FontSize = 14,
                Margin = new Thickness(0, 2, 12, 0),
                Foreground = (Brush)Application.Current.Resources[brushKey],
            };
        }

        var text = new StackPanel { Spacing = 2 };
        text.Children.Add(new TextBlock { Text = engineEvent.Title });
        text.Children.Add(Caption(engineEvent.Detail));
        Grid.SetColumn(text, 1);

        row.Children.Add(statusIcon);
        row.Children.Add(text);
        return row;
    }
}
