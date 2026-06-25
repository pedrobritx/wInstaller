# UI Prompt

Use this prompt when asking an AI coding agent to implement or refine the app interface.

```text
You are refining the wInstaller macOS SwiftUI interface.

Read:
- AI_RULES.md
- UI_GUIDELINES.md
- DESIGN_SYSTEM.md
- USER_FLOW.md
- ICON_GUIDELINES.md

Task:
Build the assistant UI as the first screen. Follow the supplied product mockup as direction, but use native macOS controls and Apple's Human Interface Guidelines. Implement the step sidebar, main step content, local-only footer, ISO card, USB selector, live checklist, confirmation dialog, and technical details panel.

Constraints:
- No web-style landing page.
- No third-party UI frameworks.
- Use SF Symbols for interface icons.
- Text must fit at small and large window sizes.
- Support light mode, dark mode, high contrast, keyboard navigation, VoiceOver, Reduce Motion, and Reduce Transparency.

Deliver:
- SwiftUI views and previews.
- Accessibility labels.
- Mock data for every state.
- Screenshot or verification notes for main states.
```

