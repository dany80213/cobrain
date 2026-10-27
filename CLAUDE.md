# Cobrain — instructions for agents

Cobrain is a **native macOS (SwiftUI/AppKit) word processor** built on the WordCraft Rust engine. The goal is a UI **identical to WordCraft's** (ribbon, icons, panes, dialogs, status bar), but written in Swift. The original egui UI (`crates/ui-egui`) is the visual and behavioural reference; it is not shipped in Cobrain.

```
macos/ (Swift)  ──C ABI (crates/cobrain-ffi)──▶  wordcraft-engine / layout / render / docx …
```

The rest of this file (below "WordCraft rules") is upstream's and still governs the Rust crates. Everything in `crates/` except `cobrain-ffi` stays in sync with `upstream` (`git fetch upstream && git merge upstream/main`); keep Cobrain changes out of those crates.

## Build, run, look at it
- `macos/scripts/build-app.sh` → `macos/build/Cobrain.app` (needs Xcode, and Rust: `brew install rustup && rustup default stable`, PATH `/opt/homebrew/opt/rustup/bin`).
- **Look at the result.** Screen capture is not available to agents; use the app's own snapshot: `COBRAIN_TAB=Insert macos/build/Cobrain.app/Contents/MacOS/Cobrain --snapshot out.png [file.docx]` (1100×760 pt window → PNG), then read the PNG.
- **Reference screenshots** of the real WordCraft UI: `cargo build --release -p wordcraft-ui-egui --example ui_shot`, then a JSONL script (`{"width":1100,"height":760}`, `{"method":"ui.tab","params":{"tab":"Insert"}}`, `{"shot":"/abs/out.png"}`) → `./target/release/examples/ui_shot script.jsonl`. Compare mine and the reference side by side for every tab/dialog you touch; "identical" is judged on that comparison.
- FFI test: `cargo test -p cobrain-ffi`.

## How the Swift side is built
- Every action is an engine command: `DocumentModel.run("<id>", params)` → `cobrain_run`. Ids/params: `wordcraft-cli commands --json` or `Engine.commands()`. Never reimplement document logic in Swift.
- **Ribbon tabs are generated** from `crates/ui-egui/src/ribbon.rs` by `macos/tools/gen_ribbon.py` → `RibbonSpecData.swift` (do not hand-edit; rerun the script). `SpecRibbon.swift` renders it. Home is hand-written (`HomeRibbon.swift`) because of its combos and gallery.
- **Icons** are WordCraft's own code-drawn set (`crates/ui-egui/src/icons.rs`), exported to `macos/Resources/icons/*.png` with `crates/ui-egui/examples/icon_sheet.rs` + `macos/tools/gen_icons.py` (needs numpy + pillow in a venv). Never use Microsoft/Adobe artwork; keep upstream's asset rules (below).
- New engine data the UI needs goes through `crates/cobrain-ffi` (the only crate allowed `unsafe`; keep `catch_unwind` guards, no panics) and `macos/Sources/CCobrain/include/cobrain.h`.

## iPad app (Cobrain)
`ios/` is an XcodeGen project (`ios/project.yml`): the same Cobrain on iPad, one app for word documents and whiteboards. Home (templates, whiteboard, recent files from the app's Documents folder, visible in Files) → word editor or whiteboard. It links the Rust engine built for iOS (`cargo build --release -p cobrain-ffi --target aarch64-apple-ios-sim`, or `aarch64-apple-ios` for a device) and shares `macos/Sources/Cobrain/Engine.swift` and `macos/Sources/Cobrain/Board/` (whiteboard model, drawing, input logic; UIKit/AppKit only behind `#if`) with the Mac app. iPad-only code is in `ios/Sources/`.
- Build/run: `ios/scripts/build-sim.sh` (simulator, no signing); `ios/scripts/build-device.sh` with `DEVELOPMENT_TEAM=…` for a real iPad. `-open file` as launch argument starts inside a file (screenshots, tests).
- Word editor: pages from the engine in a SwiftUI scroll view, tap/double-tap/long-press-drag selection, typing through an invisible `UIKeyInput` responder (hardware keyboard shortcuts come from the engine registry), a touch formatting bar (styles, size, B/I/U/S, colour, lists, alignment, table), autosave after 2 s. Still missing versus the Mac app: the generated ribbon tabs (Insert, Layout, References…), dialogs, find/replace UI, rulers, navigation pane, spelling menu, pictures.
- Subjects ("materie"): folders are subjects, shown as notebooks (cover colour, pattern, symbol kept in a hidden `.cobrain-subject.json` inside the folder) by `macos/Sources/Cobrain/Shared/Notebook.swift`, used by both apps: Mac Home (`Notebooks.swift`, on top of `ProjectStore`) and iPad Home/`SubjectScreen`. Whiteboards live in subjects next to documents.
- Templates: `macos/Sources/Cobrain/Shared/Templates.swift` (both apps): built-in document templates (blocks written through engine commands, Italian or English by locale) and whiteboard templates (lists of shapes), for every subject or for a kind of subject (`SubjectKind`, from the subject's name), plus your own: File › Save as Template… keeps a copy in `<project>/.cobrain-templates/_all|<Subject>/`. `TemplateGallery` is the picker (Mac: subject view and Home › More Templates…; iPad: Home and subject view).
- Whiteboard: Apple Pencil pressure ink, double-tap/squeeze toggles the eraser, a finger scrolls (palette toggle lets it draw), palm rejection, autosave.

## Status
Done and checked against the reference screenshots:
- Open/save (.docx etc.), page rendering, typing, deleting, arrows, undo/redo, system clipboard, print/PDF export, multiple windows, AutoSave.
- Mouse: click, drag, shift-click, double/triple click; selection and Find highlights drawn; shortcuts come from the engine registry (`performKeyEquivalent`).
- Ribbon: all tabs generated from `ribbon.rs` with WordCraft's icons, split buttons, responsive folding (compact Styles gallery, then drop-downs), enabled/pressed state, contextual tabs (Table, Picture, Shape, Chart, SmartArt, Outlining), Zotero tab.
- Home tab hand-written (Clipboard/Font/Paragraph/Styles/Editing/Voice/Editor) with engine-rendered style previews.
- Menus: table grid, theme/standard colour grid (+ system colour panel), symbol grid.
- Dialogs: Font, Paragraph, Page Setup, Find/Replace, Insert Table, Link, Bookmark, Go To, Field, Watermark, Zoom, Word Count, Symbol, Line Numbers, Hyphenation, command search. Anything else the engine asks for shows “not ported yet” (`DialogKind.unavailable`).
- Chrome: title toolbar (AutoSave, save/undo/redo, title, “Search commands and help”, Comments/Editing/Share), File backstage (Info/New/Open/Save/Save As/Export/Print), vertical and horizontal rulers, status bar, Navigation (headings), dark-mode icons (inverted).

## TO DO before starting the rest (in this order)
Items 1–9 of the first plan are done as far as listed above; what is still **missing** from them:
1. **Generator** (`gen_ribbon.py`): now unrolls literal `for` loops, inlines the local helper fns of `ribbon.rs`, reads `ui.checkbox` rows, number-field groups and the 3×3 cell-alignment grid; labels keep their Unicode. Compared against the reference at 1440 pt and matching: Insert, Layout, View, References, Mailings, Help, Review, Table Layout (Draw/Design only partly). Still missing:
   - **Design › Document Formatting**: the style-set gallery (`style_set_box`, 7 tiles with previews).
   - **Table Design › Table Styles**: the table-style tile gallery (`previews::table_style_tile`) and the Shading colour split button (shows “·”).
   - **Draw**: pressed state of the active pen tool (lives in `app.canvas`, not the engine), “Ink to Math” greyed out in the reference.
   - **Review**: Translate greyed when no language pair; Tracking group dialog launcher (⇲) not drawn (same for the other group launchers).
   - **Picture/Shape/Chart/SmartArt Format**: Size groups (width/height/rotation fields), not compared yet; `cell_size_boxes` shows the cell's laid-out size but edits only through `table.rowHeight`/`table.columnWidth`.
   - ~5 calls with computed labels are still skipped (`python3 macos/tools/gen_ribbon.py -v`).
2. **Ribbon fit**: only Styles has a compact variant; `ribbon_fit.rs` also shrinks Font/Paragraph. Folded groups show a generic “…” icon (upstream picks a group icon).
3. **Menus** still missing: shapes gallery, bullet/numbering libraries, WordArt/text effects galleries, table styles gallery (`previews::table_style_tile`), font combo with recent fonts and previews, Margins/Size/Columns menus with their live previews, theme gallery.
4. **Dialogs** not ported (see `dialogs*.rs`, ~16k lines): Tabs, Borders and Shading, Bullets/Numbering definitions, Columns, Table Properties, Insert Picture, Chart, SmartArt, Table of Contents, Citations/Sources, Mail Merge, Track Changes options, Customize Ribbon/Keyboard, Options, Manage Styles, Colors (custom). Existing ones are simplified versions: units are always inches, no tabs inside Font/Paragraph (Advanced, Line and Page Breaks), no preview pane.
5. **Chrome**: title bar uses the system toolbar (not upstream's integrated one); ruler has no indent markers/tab stops and is not draggable; backstage lacks Home/recent files, Options, Close; dark mode only inverts icons (document pane/ribbon tokens from `theme.rs` are not ported); no Reading/Web/Outline view modes.
6. **Editing**: IME/marked text (`NSTextInputClient`), drag-and-drop of text, spelling squiggles come from the page render but the context menu with suggestions (`canvas.rs`) is missing, right-click menu, object selection/resizing (pictures, shapes, tables), table mouse tools, scroll-to-caret (`scrollTo` request is only counted, not acted on).
7. **Documents**: no `NSDocument` (versions, window restoration, dirty-state close prompts, `.docx` UTI registration beyond Info.plist), password-protected files, recent files menu in the backstage.

Item 10 of the first plan (packaging: own icon, bundle id, signing/notarization, CI) was deliberately left out by the owner.

After the items above, Cobrain-specific features can start (to be defined with `dany80213`, `thomas-addamo`, `alessandro-guttadauro`).

## Working rules
- Commit after each arc that builds; message says what and which tab/dialog (`Review: generator handles split()`); keep the Co-Authored-By trailer.
- Work in small, verified steps: build → snapshot → compare with the reference → commit.
- Don’t edit upstream crates except to expose something through `cobrain-ffi`; if you must, keep the diff minimal so merges from `upstream` stay clean.

---

# WordCraft rules (upstream)


WordCraft is a clean-room, open-source, Rust-native word processor targeting Microsoft Word parity — and going further on speed, openness and agent control. It runs natively on macOS, Windows, Linux and BSD, and on the web via WASM. Siblings with the same conventions: `../photocraft` (Photoshop), `../vectorcraft` (Illustrator), `../filmcraft` (Premiere), `../lightcraft` (Lightroom), `../pdfcraft` (Acrobat), `../effectcraft` (After Effects), `../designcraft` (InDesign). Shared rules and learnings: [`storytold/craftrules`](https://github.com/storytold/craftrules) (`../../craftrules`) — read its `AGENTS.md`.

## Start every session here
1. Read `plan/STATUS.md` (current milestone, next task), then the task in `plan/execution-plan.md` and the relevant `plan/architecture.md` section. `plan/` is gitignored (local only); if it's missing, start from `ROADMAP.md`, `docs/gaps.md` and `docs/roadmap.md` (Current focus).
2. Follow the autonomous operation protocol (`plan/execution-plan.md` §5). Don't stop to ask unless a decision is genuinely the owner's (licensing, publishing, pushing to new remotes, secrets).

## Never crash
People trust WordCraft with their writing; a crash loses their work. **This outranks feature work**: never ship a feature through a panic path, and fix a crash before building on top of it. Standard: [`craftrules/standards/never-crash.md`](https://github.com/storytold/craftrules/blob/main/standards/never-crash.md).
- **No panics in non-test code:** no `unwrap()`, `expect()`, `panic!`, `unreachable!`, `todo!`, `unimplemented!`; no `unsafe` (`unsafe_code = "forbid"`).
- **Errors are `Result<T, E>`** through the crate's error type and `?`. An unfinished feature returns an error or is disabled; it never panics.
- **Input-derived numbers are hostile** (files, commands, MCP/control params): `get()` instead of `[i]`, slice strings only at char boundaries, checked/saturating arithmetic, clamp sizes, cap allocations, bound recursion.
- **Last-resort guard:** `Session::run` turns an escaped panic into an error and restores the document. It's a safety net, not a licence.
- **Prove it:** every crash fix lands with a regression test. `crates/engine/src/tests.rs::hostile_params_never_panic` runs every command with junk params — keep it green.
- Production crate roots carry `#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]`; new crates start with it. Tests may `unwrap` (`clippy.toml`).

## Assets: absolutely no Microsoft (or Adobe/Avid/Autodesk) iconography or images
**This rule is non-negotiable.** Breaking it is the worst mistake you can make in this repo.
- Never copy, trace, screenshot-crop or recreate icons, images, templates, themes, clip art, fonts, cursors, sounds or any other asset from Microsoft Word/Office or any Microsoft, Adobe, Avid or Autodesk product. Not even "temporarily".
- Every asset must be **original** (drawn in code — prefer this: `crates/ui-egui/src/icons.rs`), **public domain / CC0**, **OSI open source**, or **Creative Commons that allows redistribution**, or licensed open source by a contributor who made it.
- **Every asset file has a row in [`ATTRIBUTION.md`](ATTRIBUTION.md)** (author, source, licence). `cargo xtask assets` (part of `cargo xtask ci`) fails otherwise. Add the row in the same commit as the file.
- Fonts: new font files go to [`storytold/craft-fonts`](https://github.com/storytold/craft-fonts), never this repo; it's an optional build input (`CRAFT_FONTS_DIR`). Documents asking for proprietary fonts (Calibri, Aptos, Cambria…) are rendered with installed system fonts or metric-compatible open substitutes (`crates/fonts/src/word.rs`) — never bundle proprietary fonts.
- Templates, sample documents and themes are our own text and colours (`crates/engine/src/sample.rs`, `cmd/design.rs`). Demo images are public domain, with sources recorded.

## Clean room
- Microsoft Word is installed on the dev machine and may be **observed** black-box: run it, use its UI with synthetic documents, take screenshots **of its window only** (by window id — the machine runs other work; never capture the whole desktop) stored only under `plan/word/screenshots/` (gitignored, never committed).
- Never read, disassemble or copy anything inside the Word bundle (file names/listings only). Never commit files produced by Word. Never copy Microsoft wording beyond feature names.
- File formats come from public specs: ECMA-376 / ISO 29500 (OOXML), the published RTF spec, OASIS ODF 1.3. Never copy GPL/LGPL/AGPL code (LibreOffice, AbiWord, pandoc…).

## Architecture (see `plan/architecture.md`)
| Layer | Crate | Job |
|---|---|---|
| L0 | `geom` | units, rects, measurement parsing |
| L1 | `doc`, `fonts` | document model + edit primitives; font DB, shaping, Word font substitution |
| L2 | `layout`, `docx`, `formats` | line breaking, pagination, tables, headers/footers, hit testing; OOXML I/O; TXT/MD/HTML/RTF/ODT |
| L3 | `render`, `pdf`, `proof` | vello_cpu rasteriser; krilla PDF; proofing |
| L4 | `engine` | Session, undo, **command registry**, Word feature catalog, samples, I/O dispatch |
| L5 | `mcp` | MCP server (headless or bridged to the app) |
| L6 | `ui-egui` | Word-style egui front end (swappable) |
| apps | `apps/wordcraft`, `apps/wordcraft-cli`, `apps/wordcraft-web` | binaries |

- **Everything is a command.** User-visible behaviour = a `CommandSpec` in `crates/engine/src/cmd/*.rs` (id, label, ribbon location, shortcut, params doc, `enabled`, `run`) + tests. UI-only commands (`ui.*`) live in `crates/ui-egui/src/lib.rs`. The ribbon, shortcuts, command search, CLI, control channel and MCP all dispatch by id. Programmatic calls never open dialogs.
- **Parity is measured:** `crates/engine/src/catalog.rs` lists Word's ribbon/menu features with command ids. `cargo xtask parity` writes `docs/parity-checklist.md`; a test enforces a floor that only rises. Implement missing ids to raise it.
- **Layering** is enforced by `cargo xtask layers`. Nothing below L6 depends on egui/eframe/winit/rfd. The UI is thin and reads `Session` state; colours come from `theme::Tokens`.
- **Rust only** (no handwritten JS/TS). **Never break wasm** (`cargo xtask wasm`).

## Quality gates
Before every commit: `cargo xtask ci` (fmt, clippy -D warnings, tests, assets, layers, wasm). Commit after every arc of work that builds, with a task id in the message (`M2.1: line spacing dialog`).

## Typing behaves like Word
Typing, Enter, Backspace, Tab, lists, AutoCorrect and AutoFormat follow Word's observed behaviour in [`docs/typing-parity.md`](docs/typing-parity.md), pinned by `crates/engine/src/tests_typing.rs` (keys go through the same commands as the keyboard). Change behaviour, doc and tests together; a typing fix lands with a test there. Compare headlessly (`ui_shot`); don't drive GUIs with keystrokes on the shared machine.

## Running and looking at the app
- `cargo run --release -p wordcraft -- --sample --control 7981` (sample document + control channel).
- Drive it with JSON lines on `127.0.0.1:7981`, each with the window's key from `~/.config/wordcraft/control-key.local-7981` (macOS: `~/Library/Application Support/WordCraft/`), e.g. `{"id":1,"key":"…","method":"engine.execute","params":{"command":"text.insert","params":{"text":"Hello"}}}` then `{"id":2,"key":"…","method":"ui.screenshot","params":{"path":"/tmp/shot.png"}}`. Methods: `crates/ui-egui/src/control.rs`; docs: `docs/control-protocol.md` (Keys).
- **Headless window screenshots** (no focus stealing, works with a locked screen): `cargo run --release -p wordcraft-ui-egui --example ui_shot -- script.jsonl` (see the example's header).
- **For UI work, look at the result** (screenshot, read the PNG) and compare with Word side by side.
- CLI: `wordcraft-cli convert in.docx out.pdf`, `wordcraft-cli run --template sample --cmd 'select.text={"text":"Studio"}' --cmd format.bold --save out.docx`, `wordcraft-cli commands`, `wordcraft-cli parity`.
- MCP: `wordcraft-cli mcp` (headless) or `wordcraft-cli mcp --connect 127.0.0.1:7981` (drives the running app). See `docs/mcp.md`.
- Shell gotcha: `mv`/`cp` may be aliased interactive — use `/bin/mv -f` / `/bin/cp -f`.
- Parallel agents: separate `CARGO_TARGET_DIR` per agent; edit only the crates you own; delete your target dir when done (disk).

## Roadmap
Progress docs follow [`craftrules/standards/progress-docs.md`](https://github.com/storytold/craftrules/blob/main/standards/progress-docs.md): `ROADMAP.md` (stage, headline numbers, progress log), `docs/target-app-parity.md` (the assessment), `docs/gaps.md` (ranked work list), `docs/roadmap.md` (milestones, Current focus), `docs/architecture.md`, and the parity checklists `docs/file-format-parity.md`, `docs/layout-parity.md`, `docs/typing-parity.md`, `docs/ui-parity.md`, `docs/hardware-parity.md`, `docs/localization-parity.md`. When work lands, update the gap, the parity doc and the progress log, and bump each touched doc's status line and revision history.
