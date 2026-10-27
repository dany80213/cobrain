# Changelog

Versions follow [semantic versioning](https://semver.org): MAJOR for changes that break saved files or workflows, MINOR for new features, PATCH for fixes. The current version is in `VERSION`; `scripts/release.sh` publishes a release.

## [1.0.0] - 2026-10-27

First release of Cobrain, the native Mac and iPad word processor on the WordCraft engine.

### Mac
- Word processor with WordCraft's ribbon, icons, panes, dialogs and status bar: open and save `.docx` and other formats, typing, selection, undo/redo, clipboard, print and PDF export, AutoSave.
- File backstage with a Home page: greeting, template tiles and recent files.
- Whiteboard documents (`.cobrainboard`): shapes, lines and arrows, pen, text, sticky notes, colours, zoom and pan, undo, eraser, PNG export, save prompts.
- Projects and subjects: folders as subjects, shown as colourful notebooks on Home (customizable cover, pattern and symbol), a notebook view with every document and whiteboard, iCloud-ready projects, search across a project, export a subject as one PDF.
- Templates: built-in documents and whiteboards for every subject and for kinds of subject (maths, Italian, history, languages, science, art and more), your own templates saved for one subject or for all.
- Italian spell-checking with a language menu and right-click suggestions, Pages-style lists.
- Unsaved-changes prompts, and an Update button that brings a source build up to date with GitHub.

### iPad
- One Cobrain app for documents and whiteboards, running the same Rust engine: Home with notebooks, templates and recent files.
- Word editor with a touch formatting bar, hardware-keyboard shortcuts and autosave.
- Whiteboard built for Apple Pencil: pressure-sensitive ink, double-tap or squeeze for the eraser, palm rejection, finger scrolls.
- Subjects as notebooks, templates and "Save as Template" like on the Mac.
