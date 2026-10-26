//! C ABI for the Cobrain macOS app (Swift).
//!
//! The Swift side holds an opaque `CobrainDoc*` and talks to the engine only through:
//! open/save, page rasters, and `cobrain_run` (the engine's JSON command registry: the same
//! entry point the egui UI, the CLI and MCP use). Every pointer returned here must be released
//! with the matching `cobrain_free_*` function.
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;

use wordcraft_engine::Session;
use wordcraft_engine::doc::StoryRef;
use wordcraft_engine::render::{RenderOptions, render_page};

/// Opaque document handle (one editing session).
pub struct CobrainDoc {
    session: Session,
}

fn to_cstring(s: String) -> *mut c_char {
    CString::new(s.replace('\0', " ")).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `p` must be null or a valid NUL-terminated string.
unsafe fn from_cstr<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    // SAFETY: caller contract above.
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

/// Run `f`, turning a panic into `None` so it never unwinds across the FFI boundary.
fn guard<T>(f: impl FnOnce() -> Option<T>) -> Option<T> {
    catch_unwind(AssertUnwindSafe(f)).ok().flatten()
}

/// Engine version string. Free with `cobrain_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn cobrain_engine_version() -> *mut c_char {
    to_cstring(env!("CARGO_PKG_VERSION").to_string())
}

/// New blank document. Null on failure.
#[unsafe(no_mangle)]
pub extern "C" fn cobrain_new_blank() -> *mut CobrainDoc {
    guard(|| {
        let doc = wordcraft_engine::blank_document(&wordcraft_engine::Region::default());
        Some(Box::into_raw(Box::new(CobrainDoc { session: Session::new(doc) })))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// New document holding WordCraft's built-in sample ("The Open Studio Handbook"). Null on failure.
#[unsafe(no_mangle)]
pub extern "C" fn cobrain_new_sample() -> *mut CobrainDoc {
    guard(|| Some(Box::into_raw(Box::new(CobrainDoc { session: Session::new(wordcraft_engine::sample::sample_document()) }))))
        .unwrap_or(std::ptr::null_mut())
}

/// Open a document (.docx, .doc, .rtf, .odt, .md, .txt, .html…). Null on failure.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_open(path: *const c_char) -> *mut CobrainDoc {
    guard(|| {
        // SAFETY: forwarded caller contract.
        let path = unsafe { from_cstr(path) }?;
        let doc = wordcraft_engine::io::open_path(Path::new(path)).ok()?;
        let mut session = Session::new(doc);
        session.path = Some(path.into());
        session.file_name = Path::new(path).file_name().map(|n| n.to_string_lossy().into_owned());
        Some(Box::into_raw(Box::new(CobrainDoc { session })))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Save to `path`; the format follows the extension. Returns 0 on success.
///
/// # Safety
/// `doc` must come from this library; `path` must be a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_save(doc: *mut CobrainDoc, path: *const c_char) -> i32 {
    guard(|| {
        // SAFETY: forwarded caller contract.
        let (doc, path) = unsafe { (doc.as_mut()?, from_cstr(path)?) };
        wordcraft_engine::io::save_path(Path::new(path), &doc.session.doc).ok()?;
        doc.session.stamp_save();
        doc.session.dirty = false;
        Some(0)
    })
    .unwrap_or(-1)
}

/// Release a document.
///
/// # Safety
/// `doc` must be null or come from this library, and not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_free(doc: *mut CobrainDoc) {
    if !doc.is_null() {
        // SAFETY: caller contract.
        drop(unsafe { Box::from_raw(doc) });
    }
}

/// Whether the document has edits since it was opened or last saved (false on failure).
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_is_dirty(doc: *mut CobrainDoc) -> bool {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        Some(doc.session.dirty)
    })
    .unwrap_or(false)
}

/// Forget the edits so far: a new document's setup (its proofing language) isn't the user's work.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_mark_clean(doc: *mut CobrainDoc) {
    let _ = guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        doc.session.dirty = false;
        Some(())
    });
}

/// Keep the custom dictionary (Add to Dictionary) in the file named `dir`/`custom-dictionary.txt`:
/// read it now and save every word added from this document there. Returns 0 on success.
///
/// # Safety
/// `doc` must come from this library; `dir` must be a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_use_user_dictionary(doc: *mut CobrainDoc, dir: *const c_char) -> i32 {
    guard(|| {
        // SAFETY: forwarded caller contract.
        let (doc, dir) = unsafe { (doc.as_mut()?, from_cstr(dir)?) };
        let path = Path::new(dir).join(Session::USER_DICT_FILE);
        if path.exists() {
            wordcraft_engine::proof::load_user_dictionary(&path);
        }
        doc.session.user_dict_path = Some(path);
        Some(0)
    })
    .unwrap_or(-1)
}

/// Number of laid-out pages (0 on failure).
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_page_count(doc: *mut CobrainDoc) -> u32 {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        Some(doc.session.layout().pages.len() as u32)
    })
    .unwrap_or(0)
}

/// Page size in points. Returns 0 on success.
///
/// # Safety
/// `doc` must come from this library; `w` and `h` must be valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_page_size(doc: *mut CobrainDoc, index: u32, w: *mut f32, h: *mut f32) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let layout = doc.session.layout();
        let page = layout.pages.get(index as usize)?;
        // SAFETY: caller contract.
        unsafe {
            *w.as_mut()? = page.w;
            *h.as_mut()? = page.h;
        }
        Some(0)
    })
    .unwrap_or(-1)
}

/// Rasterise a page to straight (non-premultiplied) RGBA8. `scale` is pixels per point.
/// Returns null on failure; free with `cobrain_free_buffer(ptr, width * height * 4)`.
///
/// # Safety
/// `doc` must come from this library; `out_w` and `out_h` must be valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_render_page(doc: *mut CobrainDoc, index: u32, scale: f32, out_w: *mut u32, out_h: *mut u32) -> *mut u8 {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let layout = doc.session.layout();
        let page = layout.pages.get(index as usize)?;
        let img = render_page(&doc.session.doc, page, scale.clamp(0.1, 8.0), &RenderOptions::default());
        let pixels = img.to_straight().into_boxed_slice();
        // SAFETY: caller contract.
        unsafe {
            *out_w.as_mut()? = img.width;
            *out_h.as_mut()? = img.height;
        }
        Some(Box::into_raw(pixels) as *mut u8)
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Release a buffer from `cobrain_render_page`.
///
/// # Safety
/// `ptr`/`len` must be exactly what `cobrain_render_page` produced (`len = width * height * 4`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_free_buffer(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        // SAFETY: caller contract.
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)) });
    }
}

/// Run an engine command (`id`, JSON `params`). Returns `{"ok": …}` or `{"error": "…"}` as a
/// JSON string; free with `cobrain_free_string`. Null only if the handle or id is invalid.
///
/// # Safety
/// `doc` must come from this library; `id` and `params_json` must be valid NUL-terminated
/// UTF-8 strings (`params_json` may be null for `{}`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_run(doc: *mut CobrainDoc, id: *const c_char, params_json: *const c_char) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let (doc, id) = unsafe { (doc.as_mut()?, from_cstr(id)?) };
        // SAFETY: caller contract.
        let params = unsafe { from_cstr(params_json) }.unwrap_or("{}");
        let params: serde_json::Value = serde_json::from_str(params).unwrap_or_else(|_| serde_json::json!({}));
        let out = match doc.session.run(id, &params) {
            Ok(v) => serde_json::json!({ "ok": v }),
            Err(e) => serde_json::json!({ "error": e.to_string() }),
        };
        Some(to_cstring(out.to_string()))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// The engine's command catalog as a JSON array of `{id,label,location,shortcut,params,mutates}`
/// (`location` is e.g. `Home › Font`). Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_commands(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        Some(to_cstring(doc.session.registry.describe().to_string()))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Headings for the Navigation pane: JSON `[{"level":1,"text":"…","page":0}]`. Free with
/// `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_outline(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let state = doc.session.run("outline.state", &serde_json::json!({})).ok()?;
        let levels: Vec<u64> = state.get("levels")?.as_array()?.iter().filter_map(|v| v.as_u64()).collect();
        let mut out = Vec::new();
        for (i, block) in doc.session.doc.body.iter().enumerate() {
            let level = levels.get(i).copied().unwrap_or(10);
            if let wordcraft_engine::doc::Block::Para(p) = &**block
                && level < 10
            {
                out.push(serde_json::json!({ "level": level, "text": p.plain_text(), "block": i }));
            }
        }
        Some(to_cstring(serde_json::Value::Array(out).to_string()))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Ids of the commands that are disabled right now (the ribbon greys them out), as a JSON array.
/// Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_disabled_commands(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let reg = doc.session.registry.clone();
        let ids: Vec<&str> = reg.all().iter().filter(|s| (s.enabled)(&doc.session).is_some()).map(|s| s.id).collect();
        Some(to_cstring(serde_json::to_string(&ids).ok()?))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Pressed state of toggle commands as JSON `{"id": bool}`. Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_toggle_states(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let s = &doc.session;
        let map = serde_json::json!({
            "review.trackChanges": s.doc.settings.track_changes,
            "view.marks": s.view.marks,
            "view.ruler": s.view.ruler,
            "view.gridlines": s.view.gridlines,
            "view.navigationPane": s.view.nav_pane,
            "view.hideWhiteSpace": s.view.hide_white_space,
        });
        Some(to_cstring(map.to_string()))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Ribbon tabs for the current selection, as a JSON array (`Table Design`, `Picture Format`…).
/// Same rules as WordCraft's `contextual_tabs`. Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_contextual_tabs(doc: *mut CobrainDoc) -> *mut c_char {
    use wordcraft_engine::cmd::objects::selected;
    use wordcraft_engine::doc::para::InlineObject;
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let s = &doc.session;
        let mut tabs: Vec<&str> = Vec::new();
        if s.sel.focus.path.cell().is_some() {
            tabs.extend(["Table Design", "Table Layout"]);
        }
        let obj = selected(s);
        if matches!(obj, Some((_, InlineObject::Image { .. }))) {
            tabs.push("Picture Format");
        }
        if obj.as_ref().is_some_and(|(_, o)| matches!(o, InlineObject::Shape { .. }) || o.is_canvas()) {
            tabs.push("Shape Format");
        }
        if wordcraft_engine::cmd::smart_art::selected_smart_art(s).is_some() {
            tabs.push("SmartArt Design");
        }
        if wordcraft_engine::cmd::chart::selected_chart(s).is_some() {
            tabs.push("Chart Design");
        }
        if s.math.is_some() {
            tabs.push("Equation");
        }
        if s.view.mode == wordcraft_engine::layout::ViewMode::Outline {
            tabs.push("Outlining");
        }
        Some(to_cstring(serde_json::to_string(&tabs).ok()?))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// The document's theme colours as a JSON array of `RRGGBB` strings. Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_theme_colors(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let hex: Vec<String> = doc.session.doc.settings.theme_colors.iter().map(|c| c.hex()).collect();
        Some(to_cstring(serde_json::to_string(&hex).ok()?))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Styles of the Styles gallery in gallery order: JSON `[{"id","name"}]`. Free with
/// `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_gallery_styles(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let v: Vec<serde_json::Value> = doc.session.doc.styles.gallery().iter().map(|s| serde_json::json!({ "id": s.id, "name": s.name })).collect();
        Some(to_cstring(serde_json::Value::Array(v).to_string()))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Rasterise the "AaBbCcDd" sample of style `id` (`w` x `h` points at `scale` px/pt) to straight
/// RGBA8, like the Styles gallery tiles. Free with `cobrain_free_buffer(ptr, w*h*4)`.
///
/// # Safety
/// `doc` must come from this library; `id` a valid NUL-terminated string; out pointers valid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_style_preview(
    doc: *mut CobrainDoc,
    id: *const c_char,
    w: f32,
    h: f32,
    scale: f32,
    out_w: *mut u32,
    out_h: *mut u32,
) -> *mut u8 {
    use std::sync::Arc;
    use wordcraft_engine::doc::{Block, CharProps, Document, Paragraph};
    guard(|| {
        // SAFETY: caller contract.
        let (doc, id) = unsafe { (doc.as_mut()?, from_cstr(id)?) };
        let base = &doc.session.doc;
        let mut p = Paragraph::with_text("AaBbCcDd", CharProps::default()).styled(id);
        p.props.space_before = Some(0.0);
        p.props.align = Some(wordcraft_engine::doc::Align::Left);
        let first = base.styles.resolve_para(&p.props).indent_first;
        p.props.indent_left = Some(if first.is_finite() { (-first).max(0.0) } else { 0.0 });
        p.props.borders = None;
        p.props.shading = None;
        let margin = 1.0;
        let mut d = Document::new();
        d.styles = base.styles.clone();
        d.numbering = base.numbering.clone();
        d.body = vec![Arc::new(Block::Para(p))].into_iter().collect();
        d.last_section.page_w = w + 2.0 * margin;
        d.last_section.page_h = 2000.0;
        d.last_section.margin_left = margin;
        d.last_section.margin_right = margin;
        d.last_section.margin_top = margin;
        d.last_section.margin_bottom = 0.0;
        let l = wordcraft_layout::layout(&d, &mut wordcraft_layout::LayoutCache::new(), &Default::default());
        let page = l.pages.first()?;
        let opts = RenderOptions { text_darkening: true, ..RenderOptions::default() };
        let img = wordcraft_render::render_area(&d, page, 0.0, 0.0, w + 2.0 * margin, h + margin, scale.clamp(0.5, 4.0), &opts);
        let pixels = img.to_straight().into_boxed_slice();
        // SAFETY: caller contract.
        unsafe {
            *out_w.as_mut()? = img.width;
            *out_h.as_mut()? = img.height;
        }
        Some(Box::into_raw(pixels) as *mut u8)
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Requests the engine made of the UI since the last call (`{"open": "font"}`, `{"scrollTo":
/// "caret"}`…), as a JSON array; the queue is emptied. Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_take_ui_requests(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let reqs = std::mem::take(&mut doc.session.ui_requests);
        Some(to_cstring(serde_json::Value::Array(reqs).to_string()))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Resolved formatting of the paragraph at the caret (alignment, indents, spacing…) as JSON.
/// Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_para_state(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let focus = doc.session.sel_ends().focus.clone();
        let p = doc.session.doc.para_at(&focus)?;
        let r = doc.session.doc.styles.resolve_para(&p.props);
        Some(to_cstring(serde_json::to_string(&r).ok()?))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Selection and Find highlight rectangles in page points, as JSON
/// `{"selection": [[page,x,y,w,h]…], "find": […]}`. Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_selection_rects(doc: *mut CobrainDoc) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let layout = doc.session.layout();
        let hint = doc.session.page_hint;
        let row = |(pi, r): (usize, wordcraft_geom::Rect)| serde_json::json!([pi, r.x, r.y, r.w, r.h]);
        let mut sel = Vec::new();
        if !doc.session.sel.is_collapsed() {
            if let Some(range) = doc.session.cell_range() {
                sel.extend(wordcraft_engine::cmd::table_mouse::cell_rects(&layout, &doc.session.doc, range).into_iter().map(row));
            } else {
                let (a, b) = doc.session.sel.ordered();
                sel.extend(wordcraft_engine::cmd::table_mouse::selection_rects(&layout, &doc.session.doc, &a, &b, hint).into_iter().map(row));
            }
        }
        let marks: Vec<_> = doc.session.find_highlights().iter().take(5000).cloned().collect();
        let mut find = Vec::new();
        for (a, b) in &marks {
            find.extend(layout.selection_rects(&doc.session.doc, a, b, hint).into_iter().map(row));
        }
        Some(to_cstring(serde_json::json!({ "selection": sel, "find": find }).to_string()))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// State for an inline ribbon widget (`paraFields`, `tableLook`) as JSON; `{}` when it does not
/// apply (no table at the caret…). Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library; `kind` a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_widget_state(doc: *mut CobrainDoc, kind: *const c_char) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let (doc, kind) = unsafe { (doc.as_mut()?, from_cstr(kind)?) };
        let focus = doc.session.sel.focus.clone();
        let s = &doc.session;
        let out = match kind {
            "paraFields" => s
                .doc
                .para_at(&focus)
                .map(|p| {
                    let r = s.doc.styles.resolve_para(&p.props);
                    serde_json::json!({ "left": r.indent_left, "right": r.indent_right, "before": r.space_before, "after": r.space_after })
                })
                .unwrap_or_default(),
            "tableLook" => focus
                .path
                .cell()
                .and_then(|(tp, _, _)| s.doc.table(focus.story, &tp))
                .map(|t| {
                    let l = &t.props.look;
                    serde_json::json!({
                        "headerRow": l.header_row, "firstColumn": l.first_column, "totalRow": l.total_row,
                        "lastColumn": l.last_column, "bandedRows": l.banded_rows, "bandedColumns": l.banded_columns
                    })
                })
                .unwrap_or_default(),
            "cellSize" => {
                // The caret cell's laid-out box (a row without a set height shows the height its text gives it).
                let layout = doc.session.layout();
                focus
                    .path
                    .cell()
                    .and_then(|(tp, r, c)| {
                        layout.pages.iter().flat_map(|pg| pg.items.iter()).find_map(|it| match it {
                            wordcraft_layout::Placed::Cell { rect, table, row, cell, story, .. }
                                if *table == tp && *row == r && *cell == c && *story == focus.story =>
                            {
                                Some(serde_json::json!({ "height": rect.h, "width": rect.w }))
                            }
                            _ => None,
                        })
                    })
                    .unwrap_or_default()
            }
            _ => serde_json::Value::Null,
        };
        Some(to_cstring(if out.is_null() { "{}".to_string() } else { out.to_string() }))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Release a string returned by this library.
///
/// # Safety
/// `s` must be null or come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_free_string(s: *mut c_char) {
    if !s.is_null() {
        // SAFETY: caller contract.
        drop(unsafe { CString::from_raw(s) });
    }
}

/// Place the caret at point (x, y) (page points) on `page`. Returns 0 on success.
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_click(doc: *mut CobrainDoc, page: u32, x: f32, y: f32) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let pos = doc.session.layout().hit(page as usize, x, y, StoryRef::Body)?;
        doc.session.run("caret.set", &serde_json::json!({ "pos": pos })).ok()?;
        Some(0)
    })
    .unwrap_or(-1)
}

/// Like `cobrain_click`, but with `extend` the selection grows from its anchor (drag, shift-click).
///
/// # Safety
/// `doc` must come from this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_click_extend(doc: *mut CobrainDoc, page: u32, x: f32, y: f32, extend: bool) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let pos = doc.session.layout().hit(page as usize, x, y, StoryRef::Body)?;
        doc.session.run("caret.set", &serde_json::json!({ "pos": pos, "extend": extend })).ok()?;
        Some(0)
    })
    .unwrap_or(-1)
}

/// The command bound to a shortcut such as `Mod+B` or `Mod+Shift+Z` (`Mod` = ⌘), or null.
/// Free with `cobrain_free_string`.
///
/// # Safety
/// `doc` must come from this library; `key` a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_shortcut(doc: *mut CobrainDoc, key: *const c_char) -> *mut c_char {
    guard(|| {
        // SAFETY: caller contract.
        let (doc, key) = unsafe { (doc.as_mut()?, from_cstr(key)?) };
        let id = doc.session.registry.by_shortcut(key)?.id;
        Some(to_cstring(id.to_string()))
    })
    .unwrap_or(std::ptr::null_mut())
}

/// Caret rectangle of the selection focus: page index and x/top/height in page points.
/// Returns 0 on success.
///
/// # Safety
/// `doc` must come from this library; the out pointers must be valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cobrain_caret(doc: *mut CobrainDoc, page: *mut u32, x: *mut f32, top: *mut f32, height: *mut f32) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let doc = unsafe { doc.as_mut()? };
        let focus = doc.session.sel_ends().focus.clone();
        let c = doc.session.layout().caret(&focus)?;
        // SAFETY: caller contract.
        unsafe {
            *page.as_mut()? = c.page as u32;
            *x.as_mut()? = c.x;
            *top.as_mut()? = c.top;
            *height.as_mut()? = c.height;
        }
        Some(0)
    })
    .unwrap_or(-1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blank_doc_types_lays_out_and_renders() {
        let doc = cobrain_new_blank();
        assert!(!doc.is_null());
        let run = |id: &str, p: &str| unsafe {
            let (id, p) = (CString::new(id).unwrap(), CString::new(p).unwrap());
            let out = cobrain_run(doc, id.as_ptr(), p.as_ptr());
            let s = CStr::from_ptr(out).to_string_lossy().into_owned();
            cobrain_free_string(out);
            s
        };
        assert!(run("text.insert", r#"{"text":"Hello Cobrain"}"#).contains("ok"));
        assert!(run("no.such.command", "{}").contains("error"));
        unsafe {
            assert!(cobrain_page_count(doc) >= 1);
            let (mut w, mut h) = (0u32, 0u32);
            let px = cobrain_render_page(doc, 0, 1.0, &mut w, &mut h);
            assert!(!px.is_null() && w > 0 && h > 0);
            cobrain_free_buffer(px, (w * h * 4) as usize);
            let (mut pg, mut x, mut t, mut hh) = (0u32, 0f32, 0f32, 0f32);
            assert_eq!(cobrain_caret(doc, &mut pg, &mut x, &mut t, &mut hh), 0);
            assert_eq!(cobrain_click(doc, 0, x, t + 1.0), 0);
            let c = cobrain_commands(doc);
            let json = CStr::from_ptr(c).to_string_lossy().into_owned();
            cobrain_free_string(c);
            assert!(json.contains("Home \u{203a} Font"), "catalog should list Home groups");
            cobrain_free(doc);
        }
    }

    /// The app asks "save changes?" only when this says so: fresh and saved documents are clean,
    /// an edit or a click that moves nothing doesn't count, an edit does.
    #[test]
    fn dirty_flag_follows_edits_and_saves() {
        let path = std::env::temp_dir().join(format!("cobrain-dirty-{}.docx", std::process::id()));
        let cpath = CString::new(path.to_string_lossy().into_owned()).unwrap();
        unsafe {
            for doc in [cobrain_new_blank(), cobrain_new_sample()] {
                assert!(!doc.is_null());
                assert!(!cobrain_is_dirty(doc), "a new document has no edits");
                let (mut pg, mut x, mut t, mut hh) = (0u32, 0f32, 0f32, 0f32);
                assert_eq!(cobrain_caret(doc, &mut pg, &mut x, &mut t, &mut hh), 0);
                assert_eq!(cobrain_click(doc, 0, x, t + 1.0), 0);
                assert!(!cobrain_is_dirty(doc), "placing the caret is not an edit");
                let (id, p) = (CString::new("text.insert").unwrap(), CString::new(r#"{"text":"x"}"#).unwrap());
                cobrain_free_string(cobrain_run(doc, id.as_ptr(), p.as_ptr()));
                assert!(cobrain_is_dirty(doc), "typing is an edit");
                assert_eq!(cobrain_save(doc, cpath.as_ptr()), 0);
                assert!(!cobrain_is_dirty(doc), "saving clears it");
                cobrain_free(doc);
            }
            let doc = cobrain_open(cpath.as_ptr());
            assert!(!doc.is_null());
            assert!(!cobrain_is_dirty(doc), "an opened file has no edits");
            cobrain_free(doc);
        }
        let _ = std::fs::remove_file(path);
    }

    /// A new document's setup can be forgotten, and Add to Dictionary writes to the folder given.
    #[test]
    fn mark_clean_and_custom_dictionary_file() {
        let dir = std::env::temp_dir().join(format!("cobrain-dict-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let cdir = CString::new(dir.to_string_lossy().into_owned()).unwrap();
        let run = |doc: *mut CobrainDoc, id: &str, p: &str| unsafe {
            let (id, p) = (CString::new(id).unwrap(), CString::new(p).unwrap());
            cobrain_free_string(cobrain_run(doc, id.as_ptr(), p.as_ptr()));
        };
        unsafe {
            let doc = cobrain_new_blank();
            run(doc, "review.language", r#"{"lang":"it-IT","default":true}"#);
            cobrain_mark_clean(doc);
            assert!(!cobrain_is_dirty(doc));
            assert_eq!(cobrain_use_user_dictionary(doc, cdir.as_ptr()), 0);
            run(doc, "review.addToDictionary", r#"{"word":"Cobrainese"}"#);
            cobrain_free(doc);
        }
        let saved = std::fs::read_to_string(dir.join(Session::USER_DICT_FILE)).unwrap_or_default();
        assert!(saved.lines().any(|l| l == "cobrainese"), "the added word is saved (lowercased): {saved:?}");
        let _ = std::fs::remove_dir_all(dir);
    }
}
