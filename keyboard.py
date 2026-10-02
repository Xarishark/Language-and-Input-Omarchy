#!/usr/bin/env python3
"""JSON backend: `read` or `apply <JSON>`; never invokes a shell or sudo."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

BEGIN = "-- BEGIN xarishark.language-input keyboard\n"
END = "-- END xarishark.language-input keyboard\n"
HOTKEY_BEGIN = "-- BEGIN xarishark.language-input switch hotkey\n"
HOTKEY_END = "-- END xarishark.language-input switch hotkey\n"
CONFIG = Path.home() / ".config/hypr/input.lua"
RULES = Path("/usr/share/X11/xkb/rules")


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip() or f"{args[0]} failed")
    return result.stdout


def catalog(rules=""):
    # Discover the active system rules catalogue, including its extra layouts.
    name = rules or "evdev"
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        raise ValueError("Unsupported custom XKB rules path")
    entries = {}
    for path in (RULES / f"{name}.xml", RULES / f"{name}.extras.xml"):
        if not path.exists():
            continue
        for layout in ET.parse(path).findall(".//layoutList/layout"):
            code = layout.findtext("configItem/name")
            label = layout.findtext("configItem/description") or code
            entries[(code, "")] = {"layout": code, "variant": "", "label": label, "groupLabel": label}
            for variant in layout.findall("variantList/variant"):
                v = variant.findtext("configItem/name")
                description = variant.findtext("configItem/description") or v
                entries[(code, v)] = {"layout": code, "variant": v, "label": description, "groupLabel": label}
    if not entries:
        raise ValueError(f"No system XKB catalogue found for {name}")
    return sorted(entries.values(), key=lambda row: (row["label"].casefold(), row["layout"], row["variant"]))


def switch_catalog(rules=""):
    name = rules or "evdev"
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        raise ValueError("Unsupported custom XKB rules path")
    entries = {}
    for path in (RULES / f"{name}.xml", RULES / f"{name}.extras.xml"):
        if path.exists():
            for item in ET.parse(path).findall(".//optionList/group/option/configItem"):
                code = item.findtext("name") or ""
                if code.startswith("grp:"):
                    entries[code] = {"option": code, "label": item.findtext("description") or code}
    return sorted(entries.values(), key=lambda row: row["label"].casefold())


def replace_switch(options, chosen, available):
    if not isinstance(chosen, str) or (chosen and chosen not in {r["option"] for r in available}):
        raise ValueError("Unsupported XKB layout-switch shortcut")
    # Only grp:* options select/switch layouts. Keep compose, LEDs, etc. intact.
    other = [item for item in options.split(",") if item and not item.startswith("grp:")]
    return ",".join(other + ([chosen] if chosen else []))


def update_hotkey(data, options):
    if not re.fullmatch(r"[A-Za-z0-9_:,+\-]*", options):
        raise ValueError("Unsupported XKB option syntax; refusing to rewrite options")
    text = data.decode("utf-8")
    block = HOTKEY_BEGIN + 'hl.config({ input = { kb_options = "' + options + '" } })\n' + HOTKEY_END
    pattern = re.escape(HOTKEY_BEGIN) + r'hl\.config\(\{ input = \{ kb_options = "[A-Za-z0-9_:,+\-]*" \} \}\)\n' + re.escape(HOTKEY_END)
    if HOTKEY_BEGIN.strip() in text or HOTKEY_END.strip() in text:
        matches = list(re.finditer(pattern, text))
        if len(matches) != 1 or text.count(HOTKEY_BEGIN.strip()) != 1 or text.count(HOTKEY_END.strip()) != 1:
            raise ValueError("Managed shortcut block was edited or is malformed; refusing to overwrite it")
        match = matches[0]
        text = text[:match.start()] + block + text[match.end():]
    else:
        text += ("" if text.endswith("\n") else "\n") + "\n" + block
    return text.encode("utf-8")


def live():
    return {key: json.loads(run("hyprctl", "-j", "getoption", "input:kb_" + key))["str"]
            for key in ("layout", "variant", "options", "rules", "model")}


def rows_from_live(state):
    layouts = state["layout"].split(",")
    variants = state["variant"].split(",") if state["variant"] else []
    if len(variants) > len(layouts) and any(variants[len(layouts):]):
        raise ValueError("Layout and variant counts disagree; edit the configuration manually")
    return [{"layout": layout, "variant": variants[i] if i < len(variants) else ""}
            for i, layout in enumerate(layouts)]


def config_bytes():
    if CONFIG.is_symlink() or not CONFIG.is_file():
        raise ValueError("Expected a regular ~/.config/hypr/input.lua file")
    return CONFIG.read_bytes()


def revision(data, state):
    return hashlib.sha256(data + json.dumps(state, sort_keys=True).encode()).hexdigest()


def read_state():
    state = live()
    available = catalog(state["rules"])
    labels = {(r["layout"], r["variant"]): r["label"] for r in available}
    rows = rows_from_live(state)
    for row in rows:
        row["label"] = labels.get((row["layout"], row["variant"]),
                                  row["layout"] + (" / " + row["variant"] if row["variant"] else ""))
    devices = json.loads(run("hyprctl", "-j", "devices")).get("keyboards", [])
    overrides = [d["name"] for d in devices
                 if d.get("layout", state["layout"]) != state["layout"]
                 or d.get("variant", state["variant"]) != state["variant"]]
    return {"ok": True, "layouts": rows, "available": available,
            "revision": revision(config_bytes(), state), "deviceOverrides": overrides,
            "switchOptions": switch_catalog(state["rules"]),
            "currentSwitchOptions": [option for option in state["options"].split(",") if option.startswith("grp:")]}


def validate_rows(rows, available):
    if not isinstance(rows, list) or not 1 <= len(rows) <= 4:
        raise ValueError("Choose between one and four keyboard layouts")
    known = {(r["layout"], r["variant"]) for r in available}
    pairs = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("Invalid layout entry")
        pair = (row.get("layout"), row.get("variant", ""))
        if not all(isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9_-]*", v) for v in pair):
            raise ValueError("Invalid layout or variant identifier")
        if pair not in known:
            raise ValueError(f"Layout/variant is not in the system XKB catalogue: {pair}")
        if pair in pairs:
            raise ValueError("Duplicate layout/variant")
        pairs.append(pair)
    return ",".join(p[0] for p in pairs), ",".join(p[1] for p in pairs)


def update_config(data, layout, variant):
    text = data.decode("utf-8")
    block = (BEGIN + 'hl.config({ input = {\n' + f'  kb_layout = "{layout}",\n'
             + f'  kb_variant = "{variant}",\n' + '} })\n' + END)
    if BEGIN.strip() in text or END.strip() in text:
        pattern = (re.escape(BEGIN) + r'hl\.config\(\{ input = \{\n'
                   + r'  kb_layout = "[A-Za-z0-9_,\-]*",\n'
                   + r'  kb_variant = "[A-Za-z0-9_,\-]*",\n'
                   + r'\} \}\)\n' + re.escape(END))
        matches = list(re.finditer(pattern, text))
        if len(matches) != 1 or text.count(BEGIN.strip()) != 1 or text.count(END.strip()) != 1:
            raise ValueError("Managed keyboard block was edited or is malformed; refusing to overwrite it")
        match = matches[0]
        text = text[:match.start()] + block + text[match.end():]
    else:
        text += ("" if text.endswith("\n") else "\n") + "\n" + block
    return text.encode("utf-8")


def atomic_write(path, data, mode):
    fd, name = tempfile.mkstemp(prefix=".language-input-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def check_applied(layout, variant, options=None):
    # Config reload and keyboard recreation can finish after IPC returns.
    for _ in range(20):
        errors = run("hyprctl", "configerrors").strip()
        if errors:
            raise ValueError("Hyprland configuration error: " + errors)
        state = live()
        if state["layout"] == layout and rows_from_live(state) == rows_from_live(
                {"layout": layout, "variant": variant}) and (options is None or state["options"] == options):
            return
        time.sleep(0.1)
    raise ValueError("Another configuration override prevented the requested keyboard settings from applying")


def apply(request):
    with (CONFIG.parent / ".language-input.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        before = config_bytes()
        state = live()
        if request.get("revision") != revision(before, state):
            raise ValueError("Keyboard configuration changed since opening the panel. Reload and try again")
        if run("hyprctl", "configerrors").strip():
            raise ValueError("Fix the existing Hyprland configuration errors before changing layouts")
        layout, variant = validate_rows(request.get("layouts", rows_from_live(state)), catalog(state["rules"]))
        options = (replace_switch(state["options"], request["switchOption"], switch_catalog(state["rules"]))
                   if "switchOption" in request else state["options"])
        run("xkbcli", "compile-keymap", "--test", "--rules", state["rules"] or "evdev",
            "--model", state["model"] or "pc105", "--layout", layout, "--variant", variant,
            "--options", options)
        after = update_config(before, layout, variant) if "layouts" in request else before
        if "switchOption" in request:
            after = update_hotkey(after, options)
        mode = CONFIG.stat().st_mode & 0o777
        # Recheck after compilation so external edits during validation aren't lost.
        if config_bytes() != before or live() != state:
            raise ValueError("Keyboard configuration changed during validation. Reload and try again")
        backup = CONFIG.parent / "input.lua.language-input.bak"
        if backup.is_symlink():
            raise ValueError("Backup path is a symlink; refusing to overwrite it")
        atomic_write(backup, before, mode)
        atomic_write(CONFIG, after, mode)
        try:
            run("hyprctl", "reload")
            check_applied(layout, variant, options)
        except Exception as error:
            if config_bytes() != after:
                raise ValueError(f"{error}. Configuration was edited externally; restore {backup} manually") from error
            atomic_write(CONFIG, before, mode)
            try:
                run("hyprctl", "reload")
                check_applied(state["layout"], state["variant"], state["options"])
            except Exception as rollback:
                raise ValueError(f"{error}. File restored but reload failed: {rollback}") from error
            raise ValueError(f"{error}. Previous configuration restored") from error
        return read_state()


def main():
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "read":
            result = read_state()
        elif len(sys.argv) == 3 and sys.argv[1] == "apply":
            request = json.loads(sys.argv[2])
            if not isinstance(request, dict):
                raise ValueError("Expected a JSON object")
            result = apply(request)
        else:
            raise ValueError("Usage: keyboard.py read | apply <JSON>")
        print(json.dumps(result))
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
