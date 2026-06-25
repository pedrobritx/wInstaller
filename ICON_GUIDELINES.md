# Icon Guidelines

## Official References

Use Apple's current guidance as the source of truth:

- App icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
- Interface icons: https://developer.apple.com/design/human-interface-guidelines/icons
- Apple Design Resources and Icon Composer: https://developer.apple.com/design/resources/

## Concept

The app icon should communicate:

```text
USB-C installer drive
+ neutral operating system glyph
+ native macOS depth
```

Meaning: "This creates operating system installers."

The icon must not use the Windows logo as the primary identity. wInstaller supports Windows workflows, but the product is broader than one vendor and should avoid trademark-dependent branding.

## Visual Direction

- Rounded macOS squircle canvas.
- Layered translucent background compatible with current macOS icon language.
- Brushed aluminum USB-C flash drive body.
- Sapphire-blue USB-C connector detail.
- Neutral `OS` glyph or abstract operating-system mark.
- Subtle depth and reflections.
- Native macOS perspective.
- Recognizable at small sizes.
- Works in light, dark, tinted, and high contrast contexts.

## App Icon Requirements

- Build from a 1024 x 1024 master source.
- Export an Xcode `AppIcon.appiconset`.
- Include standard macOS sizes and scale factors:
  - 16 x 16
  - 16 x 16 @2x
  - 32 x 32
  - 32 x 32 @2x
  - 128 x 128
  - 128 x 128 @2x
  - 256 x 256
  - 256 x 256 @2x
  - 512 x 512
  - 512 x 512 @2x
- Preserve legibility at 16 x 16.
- Avoid thin outlines that disappear at small sizes.
- Avoid embedding long text.

## Icon Composer Direction

If using Apple's Icon Composer workflow:

- Keep layers named and editable.
- Separate background, USB body, connector, glyph, highlights, and shadows.
- Preview light, dark, clear, and tinted appearances.
- Check small-size rendering before export.
- Keep source files in `Assets/Icon`.

## Interface Icons

Use SF Symbols for interface icons wherever possible.

Suggested symbols:

- ISO: `opticaldisc`
- USB: `cable.connector`
- Continue: `arrow.right.circle.fill`
- Help: `questionmark.circle`
- User guide: `book`
- Logs: `doc.text.magnifyingglass`
- Warning: `exclamationmark.triangle`
- Success: `checkmark.circle.fill`
- Eject: `eject`
- Privacy/local: `lock.shield`

Rules:

- Keep symbols visually aligned with adjacent text.
- Use system rendering modes unless a state color communicates status.
- Do not mix custom icon styles with SF Symbols in the same control group.
- Provide accessibility labels for icon-only buttons.

## Do

- Make the USB silhouette identifiable immediately.
- Use depth and material to feel at home on macOS.
- Use a neutral OS glyph.
- Keep contrast strong at small sizes.
- Test the icon in Finder, Dock, Launchpad, Spotlight, and Settings.

## Do Not

- Do not use the Windows logo.
- Do not show a full app screenshot inside the icon.
- Do not rely on tiny text.
- Do not use a generic cloud or download metaphor.
- Do not make the icon look like a removable disk utility from an older macOS era.

## Acceptance Checklist

- The icon reads as a USB installer at 1024 x 1024.
- The icon still reads at 32 x 32.
- The `OS` glyph is legible but not dominant.
- The icon looks native next to Apple apps.
- The source file is layered and editable.
- The exported asset catalog contains all required macOS sizes.

