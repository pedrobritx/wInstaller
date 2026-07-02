# wInstaller for Windows

The native Windows app: **WinUI 3 + C#/.NET 8** (ADR-0004), sharing the
canonical screen flow, copy, and design tokens with the macOS and Linux apps
(ADR-0008).

## Layout

| Project | Purpose |
|---|---|
| `WInstaller.Core` | Domain logic: typed state machine, ISO detection, disk enumeration, safety gates, executor, local logging. Targets plain `net8.0` so tests run on any OS. |
| `WInstaller.Core/Scripts/*.ps1` | Bundled PowerShell helpers. Every system call is argv-only (`-File script.ps1 -Param value`) — never a shell-interpolated string. |
| `WInstaller.App` | The WinUI 3 assistant UI (unpackaged deployment). |
| `WInstaller.Core.Tests` | xunit tests for the engine, parsers, executor pipeline, and logger redaction. |

> **Transition note (ADR-0001):** the long-term plan is one shared Rust core
> behind a C ABI. Until that lands, this app mirrors the macOS approach — the
> core domain logic is implemented natively (here in C#, `WInstaller.Core`)
> against the same screen registry, copy source, and safety rules, so the
> eventual swap to the Rust core replaces internals, not behavior.

## How it talks to Windows

- **Disk enumeration**: `Get-Disk`/`Get-Partition`/`Get-Volume` via
  `list-disks.ps1`, parsed defensively as JSON. Boot/system disks are filtered
  out and refused at every layer.
- **ISO inspection**: `Mount-DiskImage -Access ReadOnly`, directory scan,
  dismount. The ISO is never modified.
- **Erase/format**: `prepare-usb.ps1` (Clear-Disk → Initialize-Disk GPT →
  New-Partition → Format-Volume FAT32). This is the only elevated step — a
  single UAC prompt scoped to the destructive operation (ADR-0003), *after*
  the type-the-drive-name confirmation. The script re-checks the
  boot/system/USB-bus gates inside the elevated context.
- **Copy**: `robocopy /E` (exit codes < 8 are success).
- **Oversized `install.wim`**: split into `.swm` parts with
  `DISM /Split-Image` (ships with Windows — no third-party tool needed).
- **Eject**: Shell.Application `InvokeVerb('Eject')`.

FAT32 note: Windows refuses to format FAT32 volumes larger than 32 GB, so on
bigger sticks wInstaller creates a 32 GB installer partition and leaves the
rest unallocated (the warning is surfaced in the plan review step).

## Build and run

Requires Windows 10 1809+ and the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

```powershell
cd apps/windows
dotnet build WInstaller.sln          # builds core + tests + WinUI app (x64)
dotnet test WInstaller.Core.Tests    # engine/parser/executor tests
dotnet run --project WInstaller.App  # launch the assistant
```

The core library and its tests also build and run on macOS/Linux
(`dotnet test WInstaller.Core.Tests`); only `WInstaller.App` needs Windows.

## Package (portable zip)

```powershell
dotnet publish WInstaller.App -c Release -r win-x64 -p:Platform=x64 `
  -p:WindowsAppSDKSelfContained=true --self-contained true -o publish
Compress-Archive publish\* wInstaller-Windows-x64.zip
```

This is what `.github/workflows/release-windows.yml` attaches to GitHub
releases. The artifact is currently **unsigned** — SmartScreen will warn on
first run until code signing is provisioned (tracked as the ADR-0006 Phase 4
exit criterion; MSIX becomes the primary format once a certificate exists).

## Strings

User-facing copy is generated — do not edit `Strings/AppStrings.resx` by hand:

```bash
# edit shared/strings/copy.yaml, then:
python3 scripts/gen_strings_dotnet.py
```

CI fails if the committed `.resx` drifts from `copy.yaml`.
