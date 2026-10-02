import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import keyboard


class KeyboardTests(unittest.TestCase):
    def setUp(self):
        self.available = [{"layout": "us", "variant": ""},
                          {"layout": "us", "variant": "intl"},
                          {"layout": "ro", "variant": ""}]
        self.state = {"layout": "us", "variant": "", "options": "compose:caps",
                      "rules": "", "model": ""}

    def test_catalog_variants_keep_their_language_country_group(self):
        with tempfile.TemporaryDirectory() as directory:
            rules = Path(directory)
            (rules / "evdev.xml").write_text('<xkbConfigRegistry><layoutList><layout><configItem><name>gr</name><description>Greek</description></configItem><variantList><variant><configItem><name>polytonic</name><description>Greek (polytonic)</description></configItem></variant></variantList></layout></layoutList></xkbConfigRegistry>')
            with patch.object(keyboard, "RULES", rules):
                rows = keyboard.catalog()
            self.assertEqual(len(rows), 2)
            self.assertEqual({row["groupLabel"] for row in rows}, {"Greek"})
            self.assertEqual({row["variant"] for row in rows}, {"", "polytonic"})

    def test_variants_follow_layouts_when_reordered(self):
        self.assertEqual(keyboard.validate_rows([self.available[2], self.available[1]],
                                                self.available), ("ro,us", ",intl"))

    def test_invalid_empty_duplicate_and_excess_layouts_are_rejected(self):
        for rows in ([], [self.available[0]] * 2, [self.available[0]] * 5,
                     [{"layout": 'us"; os.execute("bad")', "variant": ""}],
                     [{"layout": "xx", "variant": ""}], ["us"]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                keyboard.validate_rows(rows, self.available)

    def test_missing_variants_are_padded_and_extra_nonempty_variants_rejected(self):
        self.assertEqual(keyboard.rows_from_live({"layout": "us,ro", "variant": "intl"}),
                         [self.available[1], self.available[2]])
        with self.assertRaises(ValueError):
            keyboard.rows_from_live({"layout": "us", "variant": ",intl"})

    def test_managed_block_preserves_unrelated_bytes_and_does_not_duplicate(self):
        original = '-- Personal settings: café\nhl.config({ input = { repeat_rate = 40 } })\n'.encode()
        once = keyboard.update_config(original, "us,ro", ",")
        twice = keyboard.update_config(once, "ro,us", ",intl")
        self.assertTrue(twice.startswith(original))
        self.assertEqual(twice.count(keyboard.BEGIN.encode()), 1)
        self.assertIn(b'kb_variant = ",intl"', twice)

    def test_malformed_or_manually_edited_block_is_not_overwritten(self):
        valid = keyboard.update_config(b"-- user\n", "us", "")
        for data in (valid.replace(b'kb_layout = "us"', b'kb_layout = get_layout()'),
                     valid + valid, keyboard.BEGIN.encode()):
            with self.subTest(data=data), self.assertRaises(ValueError):
                keyboard.update_config(data, "ro", "")

    def test_switch_replaces_only_group_options_and_can_disable(self):
        available = [{"option": "grp:alt_shift_toggle"}]
        original = "compose:caps,grp:ctrl_shift_toggle,led:caps,grp:switch"
        self.assertEqual(keyboard.replace_switch(original, "grp:alt_shift_toggle", available),
                         "compose:caps,led:caps,grp:alt_shift_toggle")
        self.assertEqual(keyboard.replace_switch(original, "", available), "compose:caps,led:caps")
        for option in ("Super+Q", "grp:invented", None, 'grp:x"; bad()'):
            with self.subTest(option=option), self.assertRaises(ValueError):
                keyboard.replace_switch(original, option, available)

    def test_hotkey_block_preserves_keyboard_block_and_other_bytes(self):
        original = keyboard.update_config(b"-- user settings\n", "us,ro", ",")
        once = keyboard.update_hotkey(original, "compose:caps,grp:alt_shift_toggle")
        twice = keyboard.update_hotkey(once, "compose:caps,grp:ctrl_shift_toggle")
        self.assertTrue(twice.startswith(original))
        self.assertEqual(twice.count(keyboard.HOTKEY_BEGIN.encode()), 1)
        self.assertIn(b"grp:ctrl_shift_toggle", twice)
        self.assertNotIn(b"grp:alt_shift_toggle", twice)
        self.assertIn(b"grp:ctrl_shift_toggle", keyboard.update_config(twice, "ro,us", ","))
        for data in (once + once, once.replace(b"kb_options =", b"kb_options= ")):
            with self.assertRaises(ValueError):
                keyboard.update_hotkey(data, "")
        with self.assertRaises(ValueError):
            keyboard.update_hotkey(original, 'grp:x"; bad()')

    def test_option_override_is_detected_even_when_layout_matches(self):
        with patch.object(keyboard, "run", return_value=""), \
             patch.object(keyboard, "live", return_value=self.state), \
             patch.object(keyboard.time, "sleep"):
            with self.assertRaises(ValueError):
                keyboard.check_applied("us", "", "compose:caps,grp:alt_shift_toggle")
            keyboard.check_applied("us", "", "compose:caps")

    def test_hotkey_only_apply_compiles_preserving_non_group_options(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.lua"
            original = b"-- user settings\n"
            path.write_bytes(original)
            request = {"revision": keyboard.revision(original, self.state), "switchOption": "grp:alt_shift_toggle"}
            with patch.object(keyboard, "CONFIG", path), \
                 patch.object(keyboard, "live", return_value=self.state), \
                 patch.object(keyboard, "catalog", return_value=self.available), \
                 patch.object(keyboard, "switch_catalog", return_value=[{"option": "grp:alt_shift_toggle"}]), \
                 patch.object(keyboard, "run", return_value="") as run, \
                 patch.object(keyboard, "check_applied") as check, \
                 patch.object(keyboard, "read_state", return_value={"ok": True}):
                keyboard.apply(request)
            self.assertTrue(path.read_bytes().startswith(original))
            self.assertNotIn(keyboard.BEGIN.encode(), path.read_bytes())
            self.assertIn(b"compose:caps,grp:alt_shift_toggle", path.read_bytes())
            check.assert_called_once_with("us", "", "compose:caps,grp:alt_shift_toggle")
            compile_call = next(call for call in run.call_args_list if call.args[0] == "xkbcli")
            self.assertEqual(compile_call.args[-1], "compose:caps,grp:alt_shift_toggle")

    def test_atomic_write_preserves_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.lua"
            keyboard.atomic_write(path, b"test", 0o640)
            self.assertEqual(path.read_bytes(), b"test")
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)

    def test_stale_snapshot_does_not_write(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.lua"
            path.write_bytes(b"-- original\n")
            with patch.object(keyboard, "CONFIG", path), patch.object(keyboard, "live", return_value=self.state):
                with self.assertRaisesRegex(ValueError, "changed since"):
                    keyboard.apply({"revision": "stale", "layouts": [self.available[2]]})
            self.assertEqual(path.read_bytes(), b"-- original\n")

    def test_failed_reload_rolls_back_and_keeps_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.lua"
            original = b"-- original\n"
            path.write_bytes(original)
            request = {"revision": keyboard.revision(original, self.state), "layouts": [self.available[2]]}
            with patch.object(keyboard, "CONFIG", path), \
                 patch.object(keyboard, "live", return_value=self.state), \
                 patch.object(keyboard, "catalog", return_value=self.available), \
                 patch.object(keyboard, "run", return_value=""), \
                 patch.object(keyboard, "check_applied", side_effect=[ValueError("apply failed"), None]):
                with self.assertRaisesRegex(ValueError, "Previous configuration restored"):
                    keyboard.apply(request)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual((path.parent / "input.lua.language-input.bak").read_bytes(), original)

    def test_external_edit_during_reload_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.lua"
            original = b"-- original\n"
            path.write_bytes(original)
            request = {"revision": keyboard.revision(original, self.state), "layouts": [self.available[2]]}

            def changed(*args):
                path.write_bytes(b"-- external change\n")
                raise ValueError("changed externally")

            with patch.object(keyboard, "CONFIG", path), \
                 patch.object(keyboard, "live", return_value=self.state), \
                 patch.object(keyboard, "catalog", return_value=self.available), \
                 patch.object(keyboard, "run", return_value=""), \
                 patch.object(keyboard, "check_applied", side_effect=changed):
                with self.assertRaisesRegex(ValueError, "restore .* manually"):
                    keyboard.apply(request)
            self.assertEqual(path.read_bytes(), b"-- external change\n")


if __name__ == "__main__":
    unittest.main()
