from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import locale_backend as backend


class LocaleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.user = self.root / "uwsm/env.d/zz-language-input"
        self.system = self.root / "locale.conf"
        self.system.write_bytes(b'LANG=el_GR.UTF-8\nLC_NUMERIC="en_US.UTF-8"\n')
        for name, value in (("CONFIG_HOME", self.root), ("USER_FILE", self.user), ("SYSTEM_FILE", self.system), ("SUPPORTED", self.root / "SUPPORTED")):
            patcher = patch.object(backend, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.available = [{"locale": "en_US.UTF-8"}, {"locale": "el_GR.UTF-8"}]

    def request(self, scope="user", code="en_US.UTF-8"):
        return {"scope": scope, "locale": code,
                "revision": backend.revision(backend.read_file(self.user), self.system.read_bytes())}

    def test_user_apply_writes_only_owned_fragment_and_needs_no_system_command(self):
        before = self.system.read_bytes()
        self.user.parent.mkdir(parents=True)
        unrelated = self.user.parent / "my-vars"
        unrelated.write_bytes(b"export EDITOR=vim\n")
        with patch.object(backend, "catalog", return_value=self.available), \
             patch.object(backend, "read_state", return_value={"ok": True}), \
             patch.object(backend, "run") as run:
            backend.apply(self.request())
        self.assertEqual(backend.user_choice(self.user.read_bytes()), "en_US.UTF-8")
        self.assertIn(b"unset LC_ALL", self.user.read_bytes())
        self.assertEqual(self.user.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.system.read_bytes(), before)
        self.assertEqual(unrelated.read_bytes(), b"export EDITOR=vim\n")
        run.assert_not_called()

    def test_inherit_system_removes_only_owned_fragment(self):
        self.user.parent.mkdir(parents=True)
        self.user.write_bytes(backend.user_block("en_US.UTF-8"))
        with patch.object(backend, "catalog", return_value=self.available), \
             patch.object(backend, "read_state", return_value={"ok": True}):
            backend.apply(self.request(code=""))
        self.assertFalse(self.user.exists())
        self.assertIn(b"LANG=el_GR.UTF-8", self.system.read_bytes())

    def test_invalid_unavailable_and_stale_locales_never_write(self):
        with patch.object(backend, "catalog", return_value=self.available):
            for code in ('en_US; bad()', "xx_YY.UTF-8", None):
                with self.assertRaises(ValueError):
                    backend.apply(self.request(code=code))
            request = self.request()
            request["revision"] = "stale"
            with self.assertRaisesRegex(ValueError, "changed since"):
                backend.apply(request)
        self.assertFalse(self.user.exists())

    def test_edited_fragment_and_symlink_are_rejected(self):
        self.user.parent.mkdir(parents=True)
        self.user.write_bytes(b"export LANG=en_US.UTF-8\n# personal edits\n")
        with patch.object(backend, "catalog", return_value=self.available), self.assertRaisesRegex(ValueError, "edited"):
            backend.apply(self.request())
        self.user.unlink()
        self.user.symlink_to(self.system)
        with self.assertRaisesRegex(ValueError, "regular file"):
            backend.read_file(self.user)

    def test_system_apply_delegates_authentication_and_preserves_other_categories(self):
        def localectl(*args, **kwargs):
            self.assertEqual(args[:2], ("localectl", "set-locale"))
            self.assertIn("LC_NUMERIC=en_US.UTF-8", args)
            self.assertIn("LC_MESSAGES=en_US.UTF-8", args)
            self.system.write_text("\n".join(args[2:]) + "\n")
            return ""
        with patch.object(backend, "catalog", return_value=self.available), \
             patch.object(backend, "run", side_effect=localectl), \
             patch.object(backend, "read_state", return_value={"ok": True}):
            backend.apply(self.request(scope="system"))
        self.assertFalse(self.user.exists())
        self.assertEqual(backend.assignments(self.system.read_bytes())["LC_NUMERIC"], "en_US.UTF-8")

    def test_authentication_failure_is_visible_without_user_write(self):
        with patch.object(backend, "catalog", return_value=self.available), \
             patch.object(backend, "run", side_effect=ValueError("Authentication cancelled")), \
             self.assertRaisesRegex(ValueError, "Authentication cancelled"):
            backend.apply(self.request(scope="system"))
        self.assertFalse(self.user.exists())

    def test_state_compares_configured_language_to_actual_session(self):
        with patch.object(backend, "catalog", return_value=self.available), \
             patch.object(backend, "run", return_value="LANG=el_GR.UTF-8\n"):
            self.assertFalse(backend.read_state()["needsLogin"])
            self.user.parent.mkdir(parents=True)
            self.user.write_bytes(backend.user_block("en_US.UTF-8"))
            state = backend.read_state()
            self.assertTrue(state["needsLogin"])
            self.assertEqual(state["activeLocale"], "el_GR.UTF-8")
            self.assertEqual(state["userLocale"], "en_US.UTF-8")

    def test_generation_uses_authenticated_system_tool_before_user_write(self):
        source = self.root / "sources"
        source.mkdir()
        (source / "fr_FR").write_text('language "French"\n')
        available = [{"locale": "fr_FR.UTF-8", "requiresGeneration": True}]
        with patch.object(backend, "catalog", return_value=available), \
             patch.object(backend, "LOCALE_SOURCES", source), \
             patch.object(backend, "run", side_effect=["", "fr_FR.utf8\n"]) as run, \
             patch.object(backend, "read_state", return_value={"ok": True}):
            backend.apply(self.request(code="fr_FR.UTF-8"))
        run.assert_any_call("pkexec", "/usr/bin/localedef", "--no-archive", "-i", "fr_FR", "-f", "UTF-8", "fr_FR.UTF-8", timeout=180)
        self.assertEqual(backend.user_choice(self.user.read_bytes()), "fr_FR.UTF-8")

    def test_cancelled_generation_does_not_change_user_locale(self):
        source = self.root / "sources"
        source.mkdir()
        (source / "fr_FR").write_text('language "French"\n')
        with patch.object(backend, "catalog", return_value=[{"locale": "fr_FR.UTF-8", "requiresGeneration": True}]), \
             patch.object(backend, "LOCALE_SOURCES", source), \
             patch.object(backend, "run", side_effect=ValueError("Authentication cancelled")), \
             self.assertRaisesRegex(ValueError, "Authentication cancelled"):
            backend.apply(self.request(code="fr_FR.UTF-8"))
        self.assertFalse(self.user.exists())

    def test_catalog_uses_generated_locales_and_system_language_names(self):
        source = self.root / "sources"
        source.mkdir()
        (self.root / "SUPPORTED").write_text("el_GR.UTF-8 UTF-8\nfr_FR.UTF-8 UTF-8\nfr_FR ISO-8859-1\n")
        (source / "el_GR").write_text('language "Greek"\nterritory "Greece"\n')
        with patch.object(backend, "LOCALE_SOURCES", source), \
             patch.object(backend, "run", return_value="C\nC.utf8\nel_GR.utf8\n"):
            rows = backend.catalog()
        self.assertEqual({row["locale"] for row in rows}, {"C", "C.UTF-8", "el_GR.UTF-8", "fr_FR.UTF-8"})
        self.assertTrue(next(row for row in rows if row["locale"] == "fr_FR.UTF-8")["requiresGeneration"])
        self.assertFalse(next(row for row in rows if row["locale"] == "el_GR.UTF-8")["requiresGeneration"])
        self.assertIn("Greek — Greece", next(row["label"] for row in rows if row["locale"] == "el_GR.UTF-8"))


if __name__ == "__main__":
    unittest.main()
