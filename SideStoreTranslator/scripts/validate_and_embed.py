#!/usr/bin/env python3
"""Validate human-curated SideStore zh-Hans translations and embed JSON.

Offline-only. The upstream catalog was extracted from SideStore/SideStore
PR #1495 (commit a8bfc4945a444d4b844bc1aff2e0c2ae097a2d95).
"""
import json
import re
import sys
from pathlib import Path

FORMAT = re.compile(r"%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|h|l|z|t|j|L)?[@dDuUxXfFeEgGaAcCsSpPoO%]")


def placeholder_signature(text):
    return sorted(m.group(0) for m in FORMAT.finditer(text) if m.group(0) != "%%")


def run(dictionary_path, inventory_path, output_path):
    data = json.loads(dictionary_path.read_text(encoding="utf-8"))
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    assert data["schemaVersion"] == 1, "unsupported schemaVersion"
    assert data["language"] == "zh-Hans", "wrong language"
    assert isinstance(data["enabled"], bool), "enabled must be boolean"
    translations = data["translations"]
    assert isinstance(translations, dict) and translations, "no translations"
    original_keys = set(inventory["keys"])
    assert len(original_keys) == inventory["keyCount"], "upstream inventory count mismatch"
    # Additional text verified directly against the current SideStore fork.
    # Preserve the historical upstream PR inventory and its original count.
    supplemental = inventory.get("supplementalKeys", {})
    assert isinstance(supplemental, dict), "invalid supplemental key manifest"
    assert all(isinstance(k, str) and k and isinstance(v, str) and v
               for k, v in supplemental.items()), "invalid supplemental source mapping"
    assert not (set(supplemental) & original_keys), "duplicate original key in supplement"
    keys = original_keys | set(supplemental)
    assert not (set(translations) - keys), "translations contain unknown SideStore source keys"
    for source, target in translations.items():
        assert isinstance(source, str) and source and isinstance(target, str) and target
        assert source != target, f"unchanged translation: {source}"
        assert placeholder_signature(source) == placeholder_signature(target), (
            f"placeholder mismatch: {source!r} -> {target!r}"
        )
        assert "\x00" not in source and "\x00" not in target
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    assert len(payload) < 1024 * 1024, "embedded JSON too large"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    header = (
        "// Auto-generated from zh-Hans.json. Do not edit manually.\n"
        "#pragma once\n"
        "static const unsigned char STBuiltinJSON[] = {\n"
    )
    chunks = [", ".join(f"0x{b:02x}" for b in payload[i:i + 20])
              for i in range(0, len(payload), 20)]
    header += ",\n".join(chunks) + ",\n0x00\n};\n"
    output_path.write_text(header, encoding="ascii")
    print(f"Validated {len(translations)}/{len(keys)} official keys; embedded {len(payload)} bytes.")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: validate_and_embed.py zh-Hans.json inventory.json header.h")
    run(*[Path(name) for name in sys.argv[1:]])
