import json
from pathlib import Path
import tempfile
import unittest

from validate_and_embed import run


class PlaceholderValidationTests(unittest.TestCase):
    def validate_pair(self, source, target):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            dictionary = root / "translations.json"
            inventory = root / "inventory.json"
            output = root / "embedded.h"
            dictionary.write_text(json.dumps({
                "schemaVersion": 1, "language": "zh-Hans", "enabled": True,
                "translations": {source: target},
            }))
            inventory.write_text(json.dumps({"keys": [source], "keyCount": 1}))
            run(dictionary, inventory, output)
            self.assertTrue(output.read_text().endswith("0x00\n};\n"))

    def test_rejects_swapped_implicit_arguments(self):
        with self.assertRaisesRegex(AssertionError, "argument order mismatch"):
            self.validate_pair("Delete %d profiles for %@", "删除 %@ 的 %d 份描述文件")

    def test_accepts_preserved_implicit_arguments(self):
        self.validate_pair("Delete %d profiles for %@", "删除 %d 份描述文件（团队：%@）")

    def test_accepts_reordered_explicit_arguments(self):
        self.validate_pair("Delete %1$d profiles for %2$@", "删除 %2$@ 的 %1$d 份描述文件")

    def test_preserves_literal_percent_and_precision(self):
        self.validate_pair("Progress %.2f%% for %@", "进度 %.2f%%（%@）")

    def test_rejects_changed_argument_type(self):
        with self.assertRaisesRegex(AssertionError, "placeholder mismatch"):
            self.validate_pair("Delete %d profiles", "删除 %@ 份描述文件")


if __name__ == "__main__":
    unittest.main()
