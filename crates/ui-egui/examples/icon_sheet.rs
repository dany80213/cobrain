//! Renders every icon of `icons.rs` to PNGs (on white and on black, to recover transparency):
//! `cargo run --release -p wordcraft-ui-egui --example icon_sheet -- out_dir name1 name2 …`
//! Used by Cobrain's macOS app (`macos/tools/gen_icons.py`).

use egui::{Rect, pos2, vec2};

const CELL: f32 = 40.0;
static READY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

fn main() {
    let mut args = std::env::args().skip(1);
    let out = args.next().expect("out dir");
    let names: Vec<String> = args.collect();
    let cols = 20usize;
    let rows = names.len().div_ceil(cols);
    let size = vec2(cols as f32 * CELL, rows as f32 * CELL);
    for (tag, bg) in [("white", egui::Color32::WHITE), ("black", egui::Color32::BLACK)] {
        READY.store(false, std::sync::atomic::Ordering::Relaxed);
        let names = names.clone();
        let mut harness = egui_kittest::Harness::builder().with_size(size).with_pixels_per_point(2.0).wgpu().build_ui(move |ui| {
            if !READY.load(std::sync::atomic::Ordering::Relaxed) {
                return;
            }
            let p = ui.painter().clone();
            p.rect_filled(Rect::from_min_size(pos2(0.0, 0.0), size), 0.0, bg);
            for (i, n) in names.iter().enumerate() {
                let (cx, cy) = ((i % cols) as f32 * CELL + CELL / 2.0, (i / cols) as f32 * CELL + CELL / 2.0);
                let r = Rect::from_center_size(pos2(cx, cy), vec2(32.0, 32.0));
                wordcraft_ui_egui::icons::paint(&p, r, n, egui::Color32::from_rgb(0x42, 0x42, 0x42), egui::Color32::from_rgb(0x3B, 0x5B, 0xDB));
            }
        });
        READY.store(false, std::sync::atomic::Ordering::Relaxed);
        wordcraft_ui_egui::theme::install_fonts(&harness.ctx);
        harness.run_steps(2);
        READY.store(true, std::sync::atomic::Ordering::Relaxed);
        harness.run_steps(3);
        let img = harness.render().expect("render");
        img.save(format!("{out}/sheet-{tag}.png")).expect("save");
    }
    println!("{} icons, {cols} columns, cell {CELL} pt @2x", names.len());
}
