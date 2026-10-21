# Cobrain

A native macOS word processor written in Swift, powered by the [WordCraft](https://github.com/storytold/wordcraft) engine.

Cobrain keeps WordCraft's Rust core (document model, .docx/RTF/ODT I/O, layout, PDF export, the command registry)
and replaces the egui front end with a SwiftUI/AppKit app.

```
macos/ (SwiftUI + AppKit)  ──C ABI──▶  crates/cobrain-ffi  ──▶  wordcraft-engine / layout / render / docx …
```

## Status (v0.1)

- Open `.docx`, `.doc`, `.rtf`, `.odt`, `.md`, `.txt`, `.html`; save/export by extension (`.docx`, `.pdf`, …)
- Page rendering from the engine's layout, zoom, click-to-place caret
- Typing, deleting, arrow navigation (with Shift to select), undo/redo, bold/italic/underline
- Everything else goes through `Engine.run("<command id>", params)`: the same command ids the WordCraft UI, CLI and MCP use (`wordcraft-cli commands` lists them)

## Build and run

Requirements: macOS 14+, Xcode 26 (Swift 6), Rust (`brew install rustup && rustup default stable`).

```bash
macos/scripts/build-app.sh
open macos/build/Cobrain.app
```

## Layout

| Path | What |
|---|---|
| `macos/` | Swift package: app, views, `Engine` wrapper |
| `crates/cobrain-ffi/` | C-ABI bridge (the only crate with `unsafe`); header in `macos/Sources/CCobrain/include/cobrain.h` |
| everything else | WordCraft upstream (kept in sync via the `upstream` remote) |

## Roadmap

1. Mouse selection (drag, double/triple click), IME / marked text, copy/paste
2. Ribbon-style toolbar and inspector driven by the engine's command catalog (`catalog.rs`)
3. Native Open/Save with `NSDocument`, autosave, recent files, multiple windows/tabs
4. Styles gallery, tables, images, headers/footers, track changes UI
5. Own app icon and branding (the icon is currently WordCraft's placeholder)
6. Cobrain-specific features (to be defined)

## License and credits

Dual-licensed MIT OR Apache-2.0, as WordCraft. See `LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE` and `ATTRIBUTION.md`.
The original project README is in [README-WORDCRAFT.md](README-WORDCRAFT.md). WordCraft is by the ArtCraft team and contributors.
Cobrain follows WordCraft's rules on assets: no Microsoft/Adobe iconography (see `CLAUDE.md`).
