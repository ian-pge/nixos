#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import sys
import unittest


MODULE_PATH = Path(__file__).with_name("update-diff.py")
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("quickshell_update_diff", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"unable to load {MODULE_PATH}")
update_diff = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(update_diff)


class StoreNameTests(unittest.TestCase):
    def test_versioned_multi_output_name(self):
        name, version = update_diff.parse_store_name(
            "0033v958q3w21apy2289zj7f78igs1w8-libressl-4.3.2-man"
        )
        self.assertEqual(name, "libressl")
        self.assertEqual(version, "4.3.2-man")

    def test_hyphenated_name(self):
        name, version = update_diff.parse_store_name(
            "0" * 32 + "-nixos-system-nixos-26.11.20260805.b7c2ada"
        )
        self.assertEqual(name, "nixos-system-nixos")
        self.assertEqual(version, "26.11.20260805.b7c2ada")

    def test_versionless_name(self):
        name, version = update_diff.parse_store_name("0" * 32 + "-source")
        self.assertEqual((name, version), ("source", ""))

    def test_invalid_name(self):
        with self.assertRaises(ValueError):
            update_diff.parse_store_name("not-a-store-name")


class VersionTests(unittest.TestCase):
    def test_numeric_comparison(self):
        self.assertLess(update_diff.Version("1.9"), update_diff.Version("1.10"))

    def test_pre_release_comparison(self):
        self.assertLess(update_diff.Version("1.0pre"), update_diff.Version("1.0"))

    def test_empty_version_comparison(self):
        self.assertLess(update_diff.Version(""), update_diff.Version("1"))

    def test_separator_does_not_change_version(self):
        self.assertEqual(update_diff.Version("1.0"), update_diff.Version("1-0"))


class DocumentTests(unittest.TestCase):
    def test_accepts_format_two(self):
        info = {"hash-package-1": {"references": []}}
        self.assertIs(
            update_diff.validate_path_info(
                {"version": 2, "storeDir": "/nix/store", "info": info}
            ),
            info,
        )

    def test_rejects_other_formats(self):
        with self.assertRaises(RuntimeError):
            update_diff.validate_path_info(
                {"version": 1, "storeDir": "/nix/store", "info": {}}
            )


if __name__ == "__main__":
    unittest.main()
