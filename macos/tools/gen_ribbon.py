#!/usr/bin/env python3
"""Generates macos/Sources/Cobrain/RibbonSpecData.swift from crates/ui-egui/src/ribbon.rs.

Parses the ribbon's builder calls (group / stack / big / small / menu_button / mi …) into a JSON
tree so the Swift ribbon has the same tabs, groups and buttons as WordCraft. Anything it can't read
statically (loops, custom widgets) is skipped and counted in `skipped`.
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parents[2]
src = (root / "crates/ui-egui/src/ribbon.rs").read_text()

TABS = {
    "insert": "Insert", "draw": "Draw", "design": "Design", "layout": "Layout", "references": "References",
    "mailings": "Mailings", "review": "Review", "view": "View", "developer": "Developer", "help": "Help",
    "outlining": "Outlining", "table_design": "Table Design", "table_layout": "Table Layout",
    "picture_format": "Picture Format", "shape_format": "Shape Format", "chart_design": "Chart Design",
    "smart_art_design": "SmartArt Design", "zotero": "Zotero", "home": "Home",
}

def fn_body(name):
    m = re.search(r"\nfn %s\(app: &mut WordApp, ui: &mut Ui\) \{" % name, src)
    if not m: return None
    i = m.end(); depth = 1
    while depth:
        c = src[i]
        if c == '"': i = skip_str(src, i); continue
        if c == '{': depth += 1
        elif c == '}': depth -= 1
        i += 1
    return src[m.end():i - 1]

def local_fn_body(name):
    m = re.search(r"\nfn %s\([^)]*\) \{" % re.escape(name), src)
    if not m: return None
    i = m.end(); depth = 1
    while depth:
        c = src[i]
        if c == '"': i = skip_str(src, i); continue
        if c == '{': depth += 1
        elif c == '}': depth -= 1
        i += 1
    return src[m.end():i - 1]

def skip_str(s, i):
    i += 1
    while s[i] != '"':
        i += 2 if s[i] == '\\' else 1
    return i + 1

def balanced(s, i, open_c, close_c):
    """s[i] == open_c; returns index after the matching close."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c == '"': i = skip_str(s, i); continue
        if c == "'" and i + 2 < len(s) and s[i + 2] == "'": i += 3; continue
        if c == open_c: depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0: return i + 1
        i += 1
    return len(s)

def split_args(s):
    out, depth, cur, i = [], 0, "", 0
    while i < len(s):
        c = s[i]
        if c == '"':
            j = skip_str(s, i); cur += s[i:j]; i = j; continue
        if c in "([{|" and not (c == "|" ): depth += 1
        if c in ")]}": depth -= 1
        if c == "|":
            # closure head `|ui, app|`
            j = s.index("|", i + 1); cur += s[i:j + 1]; i = j + 1; continue
        if c == "," and depth == 0:
            out.append(cur.strip()); cur = ""
        else:
            cur += c
        i += 1
    if cur.strip(): out.append(cur.strip())
    return out

def lit(a):
    a = a.strip()
    m = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', a)
    if m: return m.group(1).encode().decode("unicode_escape")
    m = re.fullmatch(r'Some\("((?:[^"\\]|\\.)*)"\)', a)
    if m: return m.group(1).encode().decode("unicode_escape")
    if a == "None": return None
    m = re.match(r'if [^{]*\{\s*"((?:[^"\\]|\\.)*)"', a)  # `if on { "A" } else { "B" }` -> "A"
    if m: return m.group(1).encode().decode("unicode_escape").replace(" \u2713", "")
    return False  # not a literal

def params(a):
    m = re.fullmatch(r"json!\((.*)\)", a.strip(), re.S)
    if not m: return "{}"
    t = m.group(1).strip()
    try:
        json.loads(t); return t
    except Exception:
        return "{}"

def expand_loops(body):
    """Unrolls `for (a, b) in [(..), (..)] { … }` over literal arrays, substituting the loop variables
    (also inside `format!("… {a} …")`), so the call parser sees plain `mi(ui, app, "Label", …)`."""
    out, i = "", 0
    pat = re.compile(r"(?<![\w])for\s+(\([^)]*\)|\w+)\s+in\s+\[")
    while True:
        m = pat.search(body, i)
        if not m:
            out += body[i:]; break
        out += body[i:m.start()]
        arr_start = m.end() - 1
        arr_end = balanced(body, arr_start, "[", "]")
        rest = body[arr_end:]
        mb = re.match(r"\s*\{", rest)
        if not mb:
            out += body[m.start():arr_end]; i = arr_end; continue
        bstart = arr_end + mb.end() - 1
        bend = balanced(body, bstart, "{", "}")
        inner = body[bstart + 1:bend - 1]
        vars_ = [v.strip() for v in m.group(1).strip("()").split(",")]
        elems = split_args(body[arr_start + 1:arr_end - 1])
        expanded = ""
        ok = True
        for e in elems:
            vals = [e] if not e.startswith("(") else split_args(e[1:-1])
            if len(vals) != len(vars_): ok = False; break
            copy = inner
            for v, val in zip(vars_, vals):
                plain = val.strip().strip('"')
                copy = re.sub(r"\{%s(:[^}]*)?\}" % re.escape(v), lambda mm: plain.split(".")[0] if mm.group(1) else plain, copy)
                copy = re.sub(r"(?<![\w\"])%s(?![\w\"])" % re.escape(v), lambda mm: val.strip(), copy)
            copy = re.sub(r"&format!\((\"(?:[^\"\\]|\\.)*\")\)", r"\1", copy)
            expanded += copy + "\n"
        if not ok:
            out += body[m.start():bend]
        else:
            out += expanded
        i = bend
    return out

LOCAL_FNS = sorted(set(re.findall(r"\nfn (\w+)\(ui: &mut Ui, app: &mut WordApp", src)) - {"mi_icon", "mi_text", "mi_check", "format_painter_button", "gallery_pen", "shape_effects_menu"})

# Menus whose labels are computed at runtime: written out by hand (same entries as the Rust code).
OVERRIDES = {
    "margins_items": '''
        mi(ui, app, "Normal  1\\" all", "layout.margins", json!({"preset": "normal"}));
        mi(ui, app, "Narrow  0.5\\" all", "layout.margins", json!({"preset": "narrow"}));
        mi(ui, app, "Moderate", "layout.margins", json!({"preset": "moderate"}));
        mi(ui, app, "Wide", "layout.margins", json!({"preset": "wide"}));
        mi(ui, app, "Mirrored", "layout.margins", json!({"preset": "mirrored"}));
        mi(ui, app, "Office 2003 Default", "layout.margins", json!({"preset": "office2003"}));
        mi(ui, app, "Custom Margins…", "ui.dialog", json!({"name": "pageSetup"}));
    ''',
}

CALLS = ["group", "stack", "big_toggle", "big", "small", "menu_button", "mi_icon", "mi_check", "mi", "split"]
skipped = [0]
skipped_log = []

def closure_body(a):
    if "citations::STYLES" in a:
        return "".join('mi_check(ui, app, "%s", false, "references.citationStyle", json!({"style": "%s"}));\n' % (n, n) for n in ["APA", "MLA", "Chicago", "IEEE"])
    a0 = a.strip()
    if re.fullmatch(r"\w+", a0) and local_fn_body(a0) is not None:  # `menu_button(…, margins_items)`
        return OVERRIDES.get(a0) or local_fn_body(a0)
    i = a.index("{") if "{" in a else None
    if i is None: return ""  # fn path closure
    return a[i + 1: balanced(a, i, "{", "}") - 1]

def parse(body):
    body = expand_loops(body)
    items = []
    i = 0
    pat = re.compile(r"(?<![\w.:])(%s)\(|ui\.separator\(\)|crate::dialogs::table_grid_picker\(ui, app\)"
                     r"|crate::colors::menu\(ui, app, [^;]*?Target::cmd\(\"([^\"]+)\"\)"
                     r"|ui\.checkbox\(&mut \w+, tl!\(\"([^\"]+)\"\)\)\.changed\(\) \{\s*let _ = app\.run\(\"([^\"]+)\""
                     r"|crate::equation_tab::insert_button\(ui, app\)"
                     r"|egui::Grid::new\(\"(?:syms|layout_para|look)\"\)|(?<![\w.:])(?:%s)\(ui, app[^)]*\)|cell_size_boxes\(ui, app\)|crate::wordart_menus::style_gallery\(ui, app, \"([^\"]+)\"\)" % ("|".join(CALLS), "|".join(LOCAL_FNS)))
    while True:
        m = pat.search(body, i)
        if not m: break
        g0 = m.group(0)
        if g0 == "ui.separator()":
            items.append({"t": "sep"}); i = m.end(); continue
        if g0.startswith("crate::dialogs::table_grid_picker"):
            items.append({"t": "widget", "kind": "tableGrid"}); i = m.end(); continue
        if g0.startswith("crate::colors::menu"):
            items.append({"t": "widget", "kind": "colors", "cmd": m.group(2)}); i = m.end(); continue
        if g0.startswith("crate::equation_tab::insert_button"):
            items.append({"t": "menu", "big": True, "icon": "equation", "label": "Equation", "tip": "Equation", "cmd": "insert.equation",
                          "items": [{"t": "item", "label": "Insert New Equation", "cmd": "insert.equation", "params": "{}"}]})
            i = m.end(); continue
        if g0.startswith("ui.checkbox"):
            mc = re.match(r'ui\.checkbox\(&mut \w+, tl!\("([^"]+)"\)\)\.changed\(\) \{\s*let _ = app\.run\("([^"]+)"', g0)
            items.append({"t": "check", "label": mc.group(1), "cmd": mc.group(2)}); i = m.end(); continue
        if g0.startswith("egui::Grid::new"):
            kind = {"syms": "symbols", "layout_para": "paraFields", "look": "tableLook"}[re.search(r'"(\w+)"', g0).group(1)]
            items.append({"t": "widget", "kind": kind}); i = m.end(); continue
        if g0.startswith("cell_size_boxes"):
            items.append({"t": "widget", "kind": "cellSize"}); i = m.end(); continue
        mfn = re.match(r"(\w+)\(ui, app", g0)
        if mfn and mfn.group(1) in LOCAL_FNS:
            j2 = body.index("(", m.start()); end2 = balanced(body, j2, "(", ")")
            fargs = split_args(body[j2 + 1:end2 - 1])
            fb = OVERRIDES.get(mfn.group(1)) or local_fn_body(mfn.group(1))
            if fb is not None:
                # `label: Option<&str>` parameters: pass the call's argument down.
                if len(fargs) > 2: fb = re.sub(r"\blabel\b", fargs[2], fb)
                items.extend(parse(fb))
            i = end2; continue
        if g0.startswith("crate::wordart_menus::style_gallery"):
            items.append({"t": "widget", "kind": "wordArt", "cmd": m.group(3)}); i = m.end(); continue
        name = m.group(1)
        j = m.end() - 1
        end = balanced(body, j, "(", ")")
        args = split_args(body[j + 1:end - 1])
        i = end
        try:
            if name == "group":
                title = lit(args[1])
                if title is False: skipped[0] += 1; skipped_log.append(('group', args[1])); continue
                items.append({"t": "group", "title": title, "items": parse(closure_body(args[-1]))})
            elif name == "stack":
                items.append({"t": "stack", "items": parse(closure_body(args[-1]))})
            elif name in ("big", "big_toggle"):
                lab = lit(args[3])
                if lab is False: skipped[0] += 1; skipped_log.append((name, args[3])); continue
                it = {"t": "big", "icon": lit(args[2]) or "", "label": lab, "cmd": lit(args[4]) or "",
                      "params": params(args[5]) if name == "big" else "{}"}
                items.append(it)
            elif name == "small":
                it = {"t": "small", "icon": lit(args[2]) or "", "label": lit(args[3]) or None, "tip": lit(args[4]) or "",
                      "cmd": lit(args[5]) or "", "params": params(args[6])}
                if it["label"] is False: skipped[0] += 1; skipped_log.append((name, args[3][:60])); continue
                items.append(it)
            elif name == "menu_button":
                lab = lit(args[3]); tip = lit(args[4])
                if lab is False and tip == "Citation Style": lab = "Style: APA"
                if lab is False and "show_markup" in args[3]: lab = "All Markup"
                if lab is False or tip is False: skipped[0] += 1; skipped_log.append((name, (args[3] + " | " + args[4])[:80])); continue
                items.append({"t": "menu", "icon": lit(args[2]) or "", "label": lab, "tip": tip,
                              "big": args[5].strip() == "true", "cmd": lit(args[6]) or "",
                              "items": parse(closure_body(args[7]))})
            elif name == "split":
                tip = lit(args[3])
                if tip is False: skipped[0] += 1; skipped_log.append((name, args[3])); continue
                items.append({"t": "split", "icon": lit(args[2]) or "", "tip": tip, "cmd": lit(args[4]) or "",
                              "params": params(args[5]), "items": parse(closure_body(args[-1]))})
            elif name in ("mi", "mi_check"):
                lab = lit(args[2])
                if lab is False: skipped[0] += 1; skipped_log.append((name, args[2][:60])); continue
                cmd = lit(args[-2] if name == "mi_check" else args[3])
                items.append({"t": "item", "label": lab, "cmd": cmd or "", "params": params(args[-1])})
            elif name == "mi_icon":
                lab = lit(args[3])
                if lab is False: skipped[0] += 1; skipped_log.append((name, args[3][:60])); continue
                icon = lit(args[2]) or ""
                if "{" in icon or icon == "":
                    icon = {"Straight Connector": "shape.straightConnector", "Straight Arrow Connector": "shape.straightArrowConnector",
                            "Elbow Connector": "shape.elbowConnector", "Elbow Arrow Connector": "shape.elbowArrowConnector",
                            "Curved Connector": "shape.curvedConnector", "Curved Arrow Connector": "shape.curvedArrowConnector"}.get(lab, "")
                items.append({"t": "item", "icon": icon, "label": lab, "cmd": lit(args[4]) or "", "params": params(args[5])})
            else:
                skipped[0] += 1; skipped_log.append((name, 'unhandled'))
        except Exception as e:
            skipped[0] += 1; skipped_log.append((name, 'EXC ' + repr(e) + ' ' + str(args)[:150]))
    return items

spec = {}
for fn, tab in TABS.items():
    body = fn_body(fn)
    if body is None: continue
    spec[tab] = [g for g in parse(body) if g["t"] == "group"]

icons = sorted({i["icon"] for t in spec.values() for g in t for i in walk(g)} if False else set())
def walk(n):
    yield n
    for c in n.get("items", []): yield from walk(c)
icons = sorted({n.get("icon", "") for t in spec.values() for g in t for n in walk(g)} - {""})

out = root / "macos/Sources/Cobrain/RibbonSpecData.swift"
out.write_text("// Generated by macos/tools/gen_ribbon.py from crates/ui-egui/src/ribbon.rs. Do not edit.\n"
               "enum RibbonSpecData {\n    static let json = #\"\"\"\n" + json.dumps(spec, ensure_ascii=False) + "\n\"\"\"#\n}\n")
print("tabs:", {t: len(g) for t, g in spec.items()}, "skipped:", skipped[0])
print(*skipped_log, sep="\n") if "-v" in sys.argv else None
print("icons:", len(icons)); print(" ".join(icons))
