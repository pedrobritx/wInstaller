# UI Guidelines

## Design References

Use Apple's Human Interface Guidelines as the source of truth:

- App icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
- Interface icons: https://developer.apple.com/design/human-interface-guidelines/icons
- General HIG: https://developer.apple.com/design/human-interface-guidelines

The app should follow current macOS conventions, including the Liquid Glass direction introduced across Apple's platform design language. Use native system materials and controls instead of recreating them.

## Platform

- macOS 26+ design target.
- SwiftUI first.
- AppKit only where needed.
- Native menus, windows, alerts, sheets, and file pickers.
- Native drag and drop for ISO selection if added.

## App Shape

wInstaller is an assistant. It should open directly into the workflow, not a landing page.

Primary layout:

- Sidebar with numbered steps.
- Main content region with the current task.
- Footer status for privacy and safety.
- Toolbar for help, log, and settings when needed.

## Visual Language

- Calm, dimensional, and precise.
- Use system materials and blur with restraint.
- Use depth to clarify hierarchy, not to decorate.
- Use skeuomorphic product imagery only where it helps understanding: USB drive, ISO disk, VM window, validation badge.
- Avoid web-app patterns such as marketing hero sections, Bootstrap cards, Material Design controls, and oversized promotional copy.

## Native Controls

Use familiar controls:

- File importer for ISO selection.
- Lists and tables for disks.
- ProgressView for progress.
- Toggle for binary preferences.
- Segmented controls for small mode choices.
- Menus for secondary actions.
- Native alerts and confirmation dialogs.
- SF Symbols for toolbar and inline interface icons.

Do not create custom controls when a native control communicates the same action.

## Navigation

- The assistant controls the main path.
- Users can go back before destructive work begins.
- After erase starts, back navigation is disabled until the app reaches a safe state.
- Completed steps remain visible in the sidebar.
- Errors should keep the user in context.

## Copywriting

- Use direct, plain language.
- Lead with the user's goal.
- Explain technical details only when they affect a decision.
- Use "USB drive" instead of "disk" in user-facing copy unless showing a device identifier.
- Use exact drive names and identifiers for safety.

## Destructive Warnings

The erase confirmation must be visually and behaviorally distinct from normal steps.

It must show:

- Drive name.
- BSD identifier.
- Capacity.
- Current volume names if available.
- Plain statement that all data on the selected drive will be erased.

The primary destructive button should use the system destructive role.

## Motion

- Use subtle transitions between assistant steps.
- Use progress animations only when useful.
- Respect Reduce Motion.
- Avoid decorative looping animations.

## Accessibility

- Every control has a VoiceOver label.
- Progress includes accessible status text.
- Color is never the only status indicator.
- Keyboard navigation covers the whole workflow.
- Focus moves predictably after step changes.
- Respect Increase Contrast, Reduce Motion, and Reduce Transparency.

## Mockup Notes

The supplied mockup is a direction reference, not a literal implementation contract. Preserve its strengths:

- A clear app identity.
- A calm assistant sidebar.
- A large readable main task area.
- Trust-building local-only footer.
- USB and OS visual metaphor.

Improve before implementation:

- Keep all text within native control sizes.
- Avoid overusing card containers.
- Prefer live system controls over static rendered elements.
- Make destructive warnings more explicit than the welcome screen warning.

