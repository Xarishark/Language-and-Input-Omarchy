.pragma library

// Deliberate XKB mappings, not arbitrary Hyprland bindings. The backend checks
// every result against the active system catalogue before writing it.
function optionFor(keys) {
  var exact = keys.slice().sort().join("+")
  var pairs = {
    "Left Shift+Right Shift": "grp:shifts_toggle",
    "Left Ctrl+Right Ctrl": "grp:ctrls_toggle",
    "Left Alt+Right Alt": "grp:alts_toggle"
  }
  if (pairs[exact]) return pairs[exact]
  if (keys.length === 1) {
    var single = {"Left Alt": "grp:lalt_toggle", "Right Alt": "grp:toggle",
      "Left Ctrl": "grp:lctrl_toggle", "Right Ctrl": "grp:rctrl_toggle",
      "Left Shift": "grp:lshift_toggle", "Right Shift": "grp:rshift_toggle",
      "Left Super": "grp:lwin_toggle", "Right Super": "grp:rwin_toggle",
      "Caps Lock": "grp:caps_toggle", "Menu": "grp:menu_toggle", "Scroll Lock": "grp:sclk_toggle"}
    return single[keys[0]] || ""
  }
  var generic = keys.map(function(key) { return key.replace(/^(Left|Right) /, "") }).sort().join("+")
  var common = {"Alt+Shift": "grp:alt_shift_toggle", "Ctrl+Shift": "grp:ctrl_shift_toggle",
    "Alt+Ctrl": "grp:ctrl_alt_toggle", "Alt+Space": "grp:alt_space_toggle",
    "Ctrl+Space": "grp:ctrl_space_toggle", "Space+Super": "grp:win_space_toggle",
    "Alt+Caps Lock": "grp:alt_caps_toggle", "Caps Lock+Shift": "grp:shift_caps_toggle"}
  return common[generic] || ""
}
