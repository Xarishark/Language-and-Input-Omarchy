import json
from pathlib import Path
import tempfile
import unittest

from menu_setup import register, without_comments


class MenuSetupTests(unittest.TestCase):
    def test_preserves_comments_commands_and_is_idempotent(self):
        for ending in ['', ',']:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'menu.jsonc'
                original = '{\n// existing menu\n"notes": {"action": "echo https://example.com/*hello*/"}' + ending + '\n}\n'
                path.write_text(original)
                register(path)
                result = path.read_text()
                self.assertIn(original[:-2], result)
                self.assertIn('"language-input"', result)
                register(path)
                self.assertEqual(path.read_text(), result)

    def test_creates_missing_menu(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'extensions/menu.jsonc'
            register(path)
            data = json.loads(without_comments(path.read_text()))
            self.assertEqual(data['language-input']['label'], 'Language & Input')

    def test_preserves_user_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'menu.jsonc'
            original = '{"language-input": {"label": "My custom label"}}'
            path.write_text(original)
            register(path)
            self.assertEqual(path.read_text(), original)

    def test_invalid_menu_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'menu.jsonc'
            path.write_text('invalid')
            with self.assertRaises(ValueError):
                register(path)
            self.assertEqual(path.read_text(), 'invalid')


if __name__ == '__main__':
    unittest.main()
