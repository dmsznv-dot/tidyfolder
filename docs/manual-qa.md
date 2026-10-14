# Native UI verification — 14 October 2026

Host: Apple Silicon, macOS 15.7.1, Swift 6.2, Command Line Tools.

The debug app bundle was launched through macOS, rather than treating a successful compile as a UI test.

| Check | Observed result |
| --- | --- |
| Native 1080 × 720 window | Sidebar, cards, rules list and footer visible in screenshots |
| Folder selection | NSOpenPanel accepted a disposable project fixture; destination defaulted to source |
| Preview | Four files shown with PDF, Markdown, Images and archive destinations |
| Organize | Four processed, zero skipped, zero issues |
| Undo | All four original paths and exact fixture bytes restored; independently checked from disk |
| Rules | 23 categories, 21 enabled by default, readable native accessibility labels |
| Custom rule editor | Typed property/comparison controls, add condition/group, invalid draft cannot save |
| Keyboard | Command-comma opens settings; Command-Shift-G works in native folder panel |
| English/dark and Russian/light | Both observed in native UI; language switch changes labels without changing saved destination names |

Not yet exercised: 820 × 560 layout, VoiceOver navigation, Reduce Motion, drag-and-drop, and Intel runtime. These are open checks, not inferred passes. Full Xcode UI test automation is unavailable on this host.

Interface strings are selected from English/Russian pairs by the persisted language setting. The app bundle also declares both localizations. Core filesystem errors and some diagnostic state messages currently remain English.
