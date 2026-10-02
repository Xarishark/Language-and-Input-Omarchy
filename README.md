# Language & Input

Keyboard layouts, layout-switch shortcuts, and display languages in one
keyboard-friendly panel for **Omarchy Quattro**.

A third-party `panel` plugin with ID `xarishark.language-input`. Built with
QML/Quickshell and Omarchy's shared UI components. No top-bar widget.

![Language & Input settings panel](language-and-input.png)

## Features

- **Input Languages** — browse the system XKB catalogue by language, choose a
  layout or variant, and add, remove, or reorder your configured layouts.
- **Input Switching** — choose a layout-switch shortcut from the system list
  or record a supported combination, with keycap previews and validation.
- **System Language** — change your display language or the system language
  for the login screen, system services, and new accounts.

Layout changes and list selections autosave. Reordering saves when you drop
the language; recorded shortcuts save only after confirmation. A header icon
shows save progress and success. Errors appear in the panel.

## Requirements

Developed and tested on **Omarchy 4.0.4**, using the current Quattro plugin
architecture and Lua keyboard configuration.

- A running Omarchy Shell and Hyprland session.
- Python 3, `hyprctl`, and `xkbcli` from libxkbcommon.
- System XKB rules and locale sources, including `/usr/share/i18n/SUPPORTED`.
- `locale`, `localedef`, `systemctl`, `localectl`, and `pkexec`.
- UWSM for applying account language settings at the next login.
- `~/.config/hypr/input.lua` loaded by your Hyprland configuration.

No build step or additional Python packages are required. Node.js is needed
only for the shortcut development tests.

## Install

Run in a terminal, replacing the placeholder with this repository's Git URL:

```sh
omarchy plugin add <git-repository-url> --enable
```

The repository has not been published yet, so no public installation URL is
available. Omarchy installs plugins into
`~/.config/omarchy/plugins/<plugin-id>/`.

### Open the panel

```sh
omarchy-shell shell summon xarishark.language-input '{}'
```

To toggle it:

```sh
omarchy-shell shell toggle xarishark.language-input '{}'
```

A **Language & Input** entry in the Super+Space Omarchy menu is planned;
this plugin does not install that entry yet.

## Keyboard controls

| Context | Keys | Action |
| --- | --- | --- |
| Main menu | ↑ / ↓ | Navigate languages and actions |
| Main menu | Enter | Activate the selected action |
| Input language | Hold Alt + ↑ / ↓ | Move the selected language; release Alt to save |
| Input language | Delete | Remove the selected language |
| Searchable lists | Type | Filter the list immediately |
| Searchable lists | ↑ / ↓, Enter | Navigate and select a result |
| Hotkey recording | Ctrl+S | Save a valid combination |
| Hotkey recording | Ctrl+R | Retry recording |
| Authentication notice | Enter | Continue to administrator authentication |
| Any page | Esc | Go back, cancel a move, or close the panel |

You can also drag languages with the mouse. Drop inside the list to save,
or outside it to cancel. Clicking × removes a language. Clicking outside
the panel closes it.

## Language settings

**Change my display language** sets the language for your desktop and
applications at the next login. **Use system default** removes this plugin's
account override.

**Change system language** changes the machine-wide default. Applications
with their own language preferences, accounts with overrides, and untranslated
interface text may continue using their existing language.

The lists include generated locales and supported UTF-8 locales. A shield
marks choices requiring administrator authentication. Selecting one opens a
notice with **Enter Continue · Esc Back**. Ungenerated locales are generated
on demand; existing generated locales can be selected for your account without
root privileges.

A pending change displays **System language change pending. Please restart or
relog.** The plugin does not log you out or restart the machine automatically.

## Configuration and safeguards

Keyboard changes manage marked blocks in `~/.config/hypr/input.lua`, retaining
unrelated configuration and non-switching XKB options. The backend validates
and compiles the proposed keymap before writing, checks for concurrent edits,
backs up the file to `input.lua.language-input.bak`, writes atomically, and
verifies Hyprland after reload. Failed application triggers rollback when safe.

Account language changes use an owned UWSM fragment at
`~/.config/uwsm/env.d/zz-language-input`. System language changes use
`localectl`. Locale generation uses `pkexec /usr/bin/localedef --no-archive`;
it does not edit `locale.gen` or system locale source files. Other locale
categories are preserved. Omarchy core files are never modified.

### Current limits

- One to four keyboard layouts; device-specific overrides are retained and
  reported rather than edited.
- Recorded shortcuts must map to supported forward-cycling XKB `grp:*`
  options. Arbitrary combinations are rejected; no Hyprland bindings are created.
- Existing shortcuts can intercept recording events. Use the shortcut list
  when a combination cannot be captured.
- Full logout/login behavior, privileged locale changes, and physical
  side-specific modifier recording still need manual integration testing.

## Development

Run checks from the repository root:

```sh
omarchy plugin validate .
python3 -m unittest -v test_keyboard.py test_locale_backend.py
node test_shortcut.cjs
```

To install a local development copy:

```sh
plugin_dir="$HOME/.config/omarchy/plugins/xarishark.language-input"
mkdir -p "$plugin_dir"
cp manifest.json *.qml Shortcut.js keyboard.py locale_backend.py README.md LICENSE "$plugin_dir/"
omarchy-shell shell rescanPlugins
omarchy plugin enable xarishark.language-input
omarchy restart shell
omarchy-shell shell summon xarishark.language-input '{}'
```

Discovery is asynchronous; retry enabling if the plugin is not known yet.
Copy updated files again and restart the shell to clear cached QML. Validate
keyboard and locale integration in the real running Omarchy session.

### Project structure

| Files | Responsibility |
| --- | --- |
| `manifest.json` | Root manifest and panel registration |
| `Panel.qml`, `CenteredPanel.qml` | Panel lifecycle, navigation, and centered window |
| `InputLanguages.qml`, `LanguagePicker.qml` | Layout editing and language/variant browsing |
| `SwitchHotkey.qml`, `Shortcut.js`, `Keycaps.qml` | Shortcut recording, mapping, and display |
| `SystemLanguage.qml`, `LocaleModel.qml` | Language selection and asynchronous locale state |
| `LayoutPicker.qml` | Shared list and filtering UI |
| `keyboard.py`, `locale_backend.py` | System discovery, validation, and configuration writes |
| `test_*.py`, `test_shortcut.cjs` | Backend and shortcut regression tests |

`Panel.qml` implements `open(payloadJson)` and `close()`. Both Python helpers
expose `read` and `apply` commands with JSON input/output; presentation and
system changes remain separate. Backend tests use isolated fixtures.

## License

[MIT](LICENSE). Upstream copyright notices are retained.
