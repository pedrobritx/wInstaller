# User Flow

The app uses an assistant flow. Each screen has one primary decision and one clear next action.

## Global Layout

- Window title: `wInstaller`.
- Sidebar: numbered steps with current, completed, and pending states.
- Main panel: current step content.
- Footer: local-only trust message and contextual status.
- Help buttons: user guide and support details.

## Step 1: Welcome

Purpose: Set expectations and establish trust.

Primary content:

- What wInstaller does.
- What the user will need: an ISO file and a USB drive.
- A warning that selected USB data will be erased later, before it happens.
- Local-only privacy statement.

Primary action: Continue.

## Step 2: Choose ISO

Purpose: Import the operating system installer.

Primary content:

- File picker call-to-action.
- Recent selected ISO if available.
- Supported media summary.

Validation:

- File extension is `.iso`.
- File exists and is readable.
- File size is plausible for installation media.

Failure states:

- File missing.
- Unsupported file type.
- Permission denied.
- Mount failed.

## Step 3: Verify ISO

Purpose: Explain what the app detected.

Primary content:

- ISO name, size, volume label, and detected OS.
- Confidence level.
- Required boot strategy.
- Windows WIM status when applicable.

Primary action: Continue when confidence is sufficient.

Secondary action: Choose a different ISO.

## Step 4: Insert USB

Purpose: Detect removable drives.

Primary content:

- Empty state while no removable drive is found.
- Refresh control.
- USB drive list with name, capacity, connection, and identifier.

Safety:

- Internal disks are hidden by default.
- Drives with insufficient capacity are disabled with an explanation.
- Ambiguous devices require additional confirmation.

## Step 5: Analyze USB

Purpose: Explain what will change.

Primary content:

- Selected drive details.
- Current partition scheme and filesystem.
- Required format.
- Estimated operations.

Primary action: Continue to confirmation.

Secondary action: Choose another USB drive.

## Step 6: Confirm Erase

Purpose: Prevent accidental data loss.

Primary content:

- Large warning with the selected drive name.
- Drive identifier and capacity.
- Statement that all data on the selected drive will be erased.
- Confirmation field or high-friction native confirmation.

Primary action: Erase and Create Bootable USB.

Secondary action: Cancel.

## Step 7: Create Bootable USB

Purpose: Execute the plan with visible progress.

Progress groups:

- Preparing drive.
- Formatting.
- Mounting ISO.
- Copying files.
- Splitting WIM if needed.
- Validating boot files.
- Ejecting USB.

Live checklist:

- ISO verified.
- USB selected.
- USB erased.
- Files copied.
- WIM split completed.
- Boot files validated.
- USB ejected.

User controls:

- Cancel when safe.
- Reveal technical details.
- Keep Mac awake hint if operation is long.

## Step 8: Done

Purpose: Confirm result and guide next action.

Primary content:

- Success summary.
- USB name and identifier.
- Detected operating system.
- Validation checklist.

Primary action: Open VMware instructions.

Secondary actions:

- Create another USB.
- Show log.
- Eject status if not already ejected.

## Step 9: Use With VMware Fusion

Purpose: Help the user continue.

Primary content:

- VMware Fusion detected or not detected.
- Suggested VM settings for the detected ISO.
- Reminder that a Windows license may be required.
- Steps to create or start a VM.

Behavior:

- Do not automate VM creation in the first release.
- Offer to open VMware Fusion if installed.

## Error Flow

Every error page or inline error must include:

- What happened.
- Why it may have happened.
- What wInstaller can do next.
- A safe retry or recovery action.
- A way to reveal technical details.

## First Release Happy Path

1. User opens wInstaller.
2. User selects a Windows ISO.
3. App mounts and analyzes the ISO.
4. User inserts a USB drive.
5. App analyzes and selects boot strategy.
6. User confirms erase.
7. App formats, copies, splits WIM if needed, validates, and ejects.
8. App shows VMware Fusion next steps.

