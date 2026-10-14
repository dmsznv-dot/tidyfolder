# Folder Tidy compatibility

Reference: Folder Tidy 2.9.7 public user guide, release notes and current rules screenshot (checked 2026-10-14): https://www.tunabellysoftware.com/folder_tidy/files/stacks-image-f567c8d-660x786.png

TidyFolder reproduces the visible categories: 3D Models, Audio, Bookmarks, Developer Files, Disk Images, eBooks, Emails, Fonts, Images, Markdown, Movies, PDFs, PowerPoint, Presentations, Scripts, Source Code, Spreadsheets, Text Files, Unknown, Word Processing, Zip & Archives, Folders, Aliases. Folders and Aliases are off initially. Unknown is the final regular-file fallback; a user can disable it. The screenshot's category names are verified; proprietary internal predicates are unavailable, so UTType + documented extension fixtures provide our independent implementation. No exact hidden-predicate parity is claimed.

Custom conditions support name, extension, UTI conformity, kind, byte size, creation/modification dates and tags; nested all/any/none; first match wins. Relative days use UTC instants and explicit comparison time. Previews, history and undo are independently implemented.

Our safeguards intentionally preserve ambiguous or modified files. Unavailable cloud files are skipped instead of automatically downloaded. Source/destination packages are kept opaque by default. Platform compatibility and live file-operation verification are recorded in release notes.
