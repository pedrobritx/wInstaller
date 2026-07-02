# Vision

wInstaller should feel like something Apple might have shipped if Boot Camp Assistant had evolved into a modern universal operating system installer.

The app is an assistant, not a utility. It should guide the user through a sequence, explain why each step exists, and make the next safe action obvious.

## Principles

## Native First

Use macOS conventions before inventing custom patterns. Navigation, sheets, sidebars, progress views, alerts, menus, keyboard focus, accessibility, and help should all feel native.

## Invisible Complexity

The app may perform complex work, but the user should see a meaningful summary instead of raw implementation detail. Terminal output belongs in logs and expandable technical panels, not in the primary path.

## Destructive Actions Are Sacred

Erasing a USB drive is the riskiest part of the workflow. The app must slow down, name the selected drive, show capacity and identifier, and require explicit confirmation.

## Explain While Doing

When a constraint appears, wInstaller explains it at the moment it matters.

Example:

Problem: The Windows ISO contains an `install.wim` file larger than 4 GB.

Why this happens: FAT32 cannot store a single file larger than 4 GB, but UEFI boot workflows commonly require FAT32.

What wInstaller will do: Split the image into `.swm` parts that Windows Setup can read automatically.

## Automation With Consent

The app should automate repetitive work, but not surprise the user. It should never execute a destructive operation without prior confirmation.

## Local Trust

wInstaller should be trustworthy before it is clever. No telemetry, no uploads, no remote processing, and no vague "optimizing" language.

## Recoverable Failure

Every expected failure state should produce:

- What happened.
- Why it likely happened.
- What the app can try next.
- What the user can do manually if needed.

## Professional Restraint

The interface can be beautiful, dimensional, and modern, but it should not become a marketing page. The first screen is the assistant itself.

