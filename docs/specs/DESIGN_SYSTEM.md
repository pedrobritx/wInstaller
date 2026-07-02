# Design System

## Goals

The design system keeps wInstaller native, consistent, and testable. It should define enough reusable pieces to prevent drift without turning the app into a custom UI framework.

## Color

Use semantic system colors first:

- `primary`
- `secondary`
- `tertiary`
- `background`
- `windowBackground`
- `controlBackground`
- `separator`
- `accentColor`

Suggested product accents:

- Sapphire blue for USB connector and primary progress.
- Graphite for neutral operating system glyphs.
- System green for completed validation.
- System yellow for recoverable warnings.
- System red for destructive and blocking errors.

Avoid a one-note blue or purple interface. The app can use blue as an accent, but the base should be native macOS materials and semantic colors.

## Typography

Use system typography:

- Large title for step headlines only.
- Title for screen sections.
- Headline for checklist item titles.
- Body for explanations.
- Callout for secondary details.
- Caption for identifiers, paths, and technical metadata.

Do not scale font sizes with viewport width.

## Spacing

Use a consistent spacing scale:

- 4: tight icon-text gap.
- 8: compact control padding.
- 12: grouped control gap.
- 16: section gap.
- 24: major content gap.
- 32: screen-level spacing.

## Radius

- Prefer native control radii.
- Use 8 px or less for repeated cards and panels unless the system component provides its own shape.
- App icon and product artwork may use the official macOS squircle shape.

## Materials

- Use system materials for sidebar and floating control layers.
- Use opacity and blur only through native APIs.
- Respect Reduce Transparency.
- Avoid decorative gradient blobs or background ornaments.

## Components

### Step Sidebar

Displays assistant progress.

States:

- Pending.
- Current.
- Complete.
- Warning.
- Failed.

Requirements:

- Stable row height.
- Keyboard accessible.
- VoiceOver announces step number and state.

### ISO Card

Shows selected ISO metadata.

Fields:

- File name.
- Size.
- Volume label.
- Detected OS.
- Confidence.
- WIM status when applicable.

### USB Selector

Shows removable drives.

Fields:

- Display name.
- Capacity.
- Connection type.
- BSD identifier.
- Current filesystem.
- Safety status.

Requirements:

- Internal disks hidden by default.
- Insufficient drives disabled.
- Advanced reveal requires warning.

### Live Checklist

Shows technical progress in user-friendly language.

States:

- Waiting.
- Running.
- Complete.
- Warning.
- Failed.

Each row includes a symbol, title, and optional detail.

### Terminal Details Panel

An expandable technical area.

Requirements:

- Hidden by default.
- Monospaced output.
- Redacted paths where appropriate.
- Copy button.
- Export local log button.

### Confirmation Dialog

Used before erase.

Requirements:

- Destructive role.
- High-friction confirmation.
- Exact drive identity.
- Clear cancel path.

## Iconography

- Use SF Symbols for interface icons.
- Use filled variants only when they improve state recognition.
- Pair destructive actions with text labels.
- Never use the Windows logo in the app icon.
- Use a neutral `OS` or abstract operating-system glyph for the app identity.

## Empty States

Empty states should be useful, not promotional.

Examples:

- No ISO selected: "Choose an ISO file to begin."
- No USB detected: "Connect a removable USB drive."
- VMware not detected: "VMware Fusion is not installed on this Mac."

Each empty state should offer one obvious next action.

## Quality Bar

Before shipping a screen:

- Text fits at small and large window sizes.
- VoiceOver reads controls in a useful order.
- Keyboard navigation works.
- Light, dark, high contrast, and reduced transparency appearances are checked.
- Long file names and disk names do not break layout.

