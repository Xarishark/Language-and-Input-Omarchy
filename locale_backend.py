#!/usr/bin/env python3
"""Locale JSON interface. User settings use UWSM; system settings use localed."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

from keyboard import atomic_write

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
USER_FILE = CONFIG_HOME / "uwsm/env.d/zz-language-input"
SYSTEM_FILE = Path("/etc/locale.conf")
LOCALE_SOURCES = Path("/usr/share/i18n/locales")
SUPPORTED = Path("/usr/share/i18n/SUPPORTED")
HEADER = "# Managed by xarishark.language-input; language for the next UWSM login.\n"
LOCALE_KEYS = {"LANG", "LANGUAGE", "LC_CTYPE", "LC_NUMERIC", "LC_TIME", "LC_COLLATE",
               "LC_MONETARY", "LC_MESSAGES", "LC_PAPER", "LC_NAME", "LC_ADDRESS",
               "LC_TELEPHONE", "LC_MEASUREMENT", "LC_IDENTIFICATION"}


def run(*args, timeout=15):
    result = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True,
                            text=True, timeout=timeout, env={**os.environ, "LC_ALL": "C.UTF-8"})
    if result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip() or f"{args[0]} failed")
    return result.stdout


def normalize(code):
    return re.sub(r"[.](utf-?8)", ".UTF-8", code, flags=re.I)


def catalog():
    rows = []
    generated = {normalize(code) for code in run("locale", "-a").splitlines()}
    supported = set()
    if SUPPORTED.is_file():
        for line in SUPPORTED.read_text().splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1] == "UTF-8":
                supported.add(normalize(parts[0]))
    for name in sorted(generated | supported):
        if not re.fullmatch(r"[A-Za-z0-9_.@-]+", name):
            continue
        base = re.sub(r"\.[^@]+", "", name)
        source = LOCALE_SOURCES / base
        details = {}
        if source.is_file():
            for key in ("language", "territory"):
                match = re.search(r'^' + key + r'\s+"([^"\n]+)"', source.read_text(), re.M)
                if match:
                    details[key] = match[1]
        if base in ("C", "POSIX"):
            label = "English (portable)" if name in ("C", "POSIX") else "English (Unicode)"
        else:
            label = details.get("language", base)
            if details.get("territory"):
                label += " — " + details["territory"]
        rows.append({"locale": name, "label": label + " [" + name + "]", "requiresGeneration": name not in generated})
    return sorted(rows, key=lambda row: row["label"].casefold())


def read_file(path):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f"Expected a regular file: {path}")
    return path.read_bytes() if path.exists() else b""


def assignments(data):
    result = {}
    for line in data.decode("utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"\s*([A-Z_]+)=(.*)", line)
        if not match or match[1] not in LOCALE_KEYS:
            raise ValueError("Unrecognised locale.conf setting; refusing to replace it")
        values = shlex.split(match[2], comments=True)
        if len(values) != 1:
            raise ValueError("Invalid locale.conf value")
        result[match[1]] = values[0]
    return result


def user_block(code):
    language = code.split(".")[0].split("@")[0]
    return (HEADER + f"export LANG='{code}'\nexport LC_MESSAGES='{code}'\n"
            + f"export LANGUAGE='{language}'\nunset LC_ALL\n").encode()


def user_choice(data):
    if not data:
        return ""
    match = re.search(rb"export LANG='([A-Za-z0-9_.@-]+)'", data)
    if not match or user_block(match[1].decode()) != data:
        raise ValueError("The managed user language file was edited; refusing to overwrite it")
    return match[1].decode()


def revision(user, system):
    return hashlib.sha256(user + b"\0" + system).hexdigest()


def read_state():
    user, system = read_file(USER_FILE), read_file(SYSTEM_FILE)
    system_values = assignments(system)
    # The manager reflects the actual graphical session, unlike a developer's
    # subprocess environment which can contain temporary LC_ALL overrides.
    active = dict(line.split("=", 1) for line in run("systemctl", "--user", "show-environment").splitlines()
                  if "=" in line and line.split("=", 1)[0] in LOCALE_KEYS | {"LC_ALL"})
    configured_user = user_choice(user)
    system_lang = system_values.get("LANG", "C.UTF-8")
    target = configured_user or system_lang
    messages = configured_user or system_values.get("LC_MESSAGES", target)
    active_lang = active.get("LANG", "C.UTF-8")
    active_messages = active.get("LC_ALL") or active.get("LC_MESSAGES") or active_lang
    return {"ok": True, "available": catalog(), "userLocale": configured_user,
            "systemLocale": system_lang, "activeLocale": active_lang,
            "activeMessages": active_messages, "revision": revision(user, system),
            "needsLogin": normalize(active_lang) != normalize(target)
                          or normalize(active_messages) != normalize(messages)}


def apply(request):
    code, scope = request.get("locale"), request.get("scope")
    if scope not in ("user", "system") or not isinstance(code, str):
        raise ValueError("Choose a user or system locale")
    entry = next((row for row in catalog() if row["locale"] == code), None)
    if not (scope == "user" and code == "") and entry is None:
        raise ValueError("Locale is not supported on this system")
    CONFIG_HOME.mkdir(parents=True, exist_ok=True)
    with (CONFIG_HOME / ".language-input-locale.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        user, system = read_file(USER_FILE), read_file(SYSTEM_FILE)
        user_choice(user)
        if request.get("revision") != revision(user, system):
            raise ValueError("Locale settings changed since opening the panel. Reopen and try again")
        if entry and entry.get("requiresGeneration"):
            source = re.sub(r"\.[^@]+", "", code)
            if not re.fullmatch(r"[A-Za-z0-9_@.-]+", code) or not (LOCALE_SOURCES / source).is_file():
                raise ValueError("Missing locale definition")
            # Generate only this locale using the system tool. No changes to
            # locale.gen, installed source definitions, or unrelated locales.
            run("pkexec", "/usr/bin/localedef", "--no-archive", "-i", source, "-f", "UTF-8", code, timeout=180)
            generated = {normalize(value) for value in run("locale", "-a").splitlines()}
            if code not in generated:
                raise ValueError("Locale generation did not produce the selected locale")
            if read_file(USER_FILE) != user or read_file(SYSTEM_FILE) != system:
                raise ValueError("Language settings changed during authentication; reopen and try again")
        if scope == "user":
            USER_FILE.parent.mkdir(parents=True, exist_ok=True)
            if read_file(USER_FILE) != user:
                raise ValueError("User language was edited during validation")
            if code:
                atomic_write(USER_FILE, user_block(code), USER_FILE.stat().st_mode & 0o777 if USER_FILE.exists() else 0o600)
            elif USER_FILE.exists():
                USER_FILE.unlink()
        else:
            values = assignments(system)
            values.update(LANG=code, LC_MESSAGES=code, LANGUAGE=code.split(".")[0].split("@")[0])
            # localed owns atomic system writes and polkit authentication.
            run("localectl", "set-locale", *(f"{key}={value}" for key, value in sorted(values.items())), timeout=120)
            actual = assignments(read_file(SYSTEM_FILE))
            if any(actual.get(key) != value for key, value in values.items()):
                raise ValueError("System locale verification failed; reopen to inspect the effective setting")
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
            raise ValueError("Usage: locale_backend.py read | apply <JSON>")
        print(json.dumps(result))
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
