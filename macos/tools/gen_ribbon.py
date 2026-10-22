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

CALLS = ["group", "stack", "big_toggle", "big", "small", "menu_button", "mi_icon", "mi_check", "mi", "split"]
skipped = [0]
skipped_log = []

def closure_body(a):
    i = a.index("{") if "{" in a else None
    if i is None: return ""  # fn path closure
    return a[i + 1: balanced(a, i, "{", "}") - 1]

def parse(body):
    items = []
    i = 0
    pat = re.compile(r"(?<![\w.:])(%s)\(|ui\.separator\(\)" % "|".join(CALLS))
    while True:
        m = pat.search(body, i)
        if not m: break
        if m.group(0) == "ui.separator()":
            items.append({"t": "sep"}); i = m.end(); continue
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
                if it["label"] is False: skipped[0] += 1; continue
                items.append(it)
            elif name == "menu_button":
                lab = lit(args[3]); tip = lit(args[4])
                if lab is False or tip is False: skipped[0] += 1; continue
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
                if lab is False: skipped[0] += 1; continue
                cmd = lit(args[-2] if name == "mi_check" else args[3])
                items.append({"t": "item", "label": lab, "cmd": cmd or "", "params": params(args[-1])})
            elif name == "mi_icon":
                lab = lit(args[3])
                if lab is False: skipped[0] += 1; continue
                items.append({"t": "item", "icon": lit(args[2]) or "", "label": lab, "cmd": lit(args[4]) or "", "params": params(args[5])})
            else:
                skipped[0] += 1; skipped_log.append((name, 'unhandled'))
        except Exception as e:
            skipped[0] += 1; skipped_log.append((name, 'EXC ' + repr(e)))
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
