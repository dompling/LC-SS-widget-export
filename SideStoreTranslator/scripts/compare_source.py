#!/usr/bin/env python3
"""Offline, conservative comparison of a SideStore checkout and plugin JSON.

This is a lexical audit, not a Swift parser or proof of runtime interception.
Only selected UI calls/localization lookups and Interface Builder/catalog text
contribute to exact-source coverage. Named arguments are review candidates.
Interpolated strings are reported separately, never invented as format keys.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import textwrap
import xml.etree.ElementTree as ET

DIRECT = re.compile(r'(NSLocalizedString|Text|Label|Button|Toggle|Section|Picker|NavigationLink|navigationTitle|navigationBarTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint)\s*\(\s*$')
LOCALIZED = re.compile(r'String\s*\(\s*localized:\s*$')
CANDIDATE = re.compile(r'\b(title|message|description|subtitle|placeholder|failureReason|recoverySuggestion)\s*:\s*$|\b(text|title|message|placeholder)\s*=\s*$|Text\s*\(\s*verbatim:\s*$')
RUNTIME = re.compile(r'\bText\s*\(\s*(?:verbatim:\s*)?[A-Za-z_][A-Za-z_0-9.]*\s*\)')



def string_end(source, start):
    delimiter = '\"\"\"' if source.startswith('\"\"\"', start) else '\"'
    index = start + len(delimiter)
    while index < len(source):
        if source.startswith(delimiter, index):
            return index + len(delimiter)
        if source.startswith(r'\(', index):
            depth = 1
            index += 2
            while index < len(source) and depth:
                if source[index] == '\"':
                    index = string_end(source, index)
                    continue
                if source[index] == '(':
                    depth += 1
                elif source[index] == ')':
                    depth -= 1
                index += 1
        elif source[index] == '\\':
            index += 2
        else:
            index += 1
    return len(source)


def swift_tokens(source):
    index = 0
    while index < len(source):
        start = index
        if source.startswith('//', index):
            end = source.find('\n', index)
            index = len(source) if end < 0 else end
        elif source.startswith('/*', index):
            depth = 1
            index += 2
            while index < len(source) and depth:
                if source.startswith('/*', index):
                    depth += 1
                    index += 2
                elif source.startswith('*/', index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
        elif source[index] == '\"':
            index = string_end(source, index)
        else:
            index += 1
            continue
        yield start, index, source[start:index]


def swift_string(token):
    """Decode ordinary Swift escapes; leave unsupported raw strings unclaimed."""
    if token.startswith('"""'):
        value = token[3:-3]
        if value.startswith('\n'):
            value = textwrap.dedent(value[1:]).rstrip('\n ')
    else:
        value = token[1:-1]
    if r'\(' in value:
        return None
    escapes = {'n': '\n', 'r': '\r', 't': '\t', '0': '\0', '"': '"', "'": "'", '\\': '\\'}
    value = re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m[1], 16)), value)
    return re.sub(r'\\([nrt0"\'\\])', lambda m: escapes[m[1]], value)


def swift_entries(source):
    masked = list(source)
    entries, dynamic = [], []
    for start, end, token in swift_tokens(source):
        if token.startswith('/'):
            for i in range(start, end):
                if masked[i] != '\n':
                    masked[i] = ' '
            continue
        prefix = ''.join(masked[max(0, start - 200):start])
        # Swift raw literals have different escaping/interpolation semantics.
        raw = start > 0 and source[start - 1] == '#'
        direct = DIRECT.search(prefix)
        if LOCALIZED.search(prefix) or (direct and direct[1] == 'NSLocalizedString'):
            kind = 'localized_lookup'
        elif direct:
            kind = 'swiftui_literal'
        elif CANDIDATE.search(prefix):
            kind = 'runtime_ui_candidate'
        else:
            kind = None
        line = source.count('\n', 0, start) + 1
        if kind and not raw:
            value = swift_string(token)
            if value is None:
                dynamic.append({'template': token, 'line': line, 'kind': kind})
            elif value.strip():
                entries.append({'key': value, 'line': line, 'kind': kind})
        for i in range(start, end):
            if masked[i] != '\n':
                masked[i] = ' '
    runtime = [{'expression': m[0], 'line': source.count('\n', 0, m.start()) + 1}
               for m in RUNTIME.finditer(''.join(masked))]
    return {'entries': entries, 'dynamicTemplates': dynamic, 'runtimeTextSites': runtime}


def storyboard_entries(source):
    result = []
    for element in ET.fromstring(source).iter():
        for attribute in ('text', 'title', 'placeholder', 'prompt'):
            value = element.get(attribute)
            if value and value.strip():
                result.append({'key': value, 'kind': 'interface_builder', 'objectID': element.get('id')})
        if element.tag == 'string' and element.get('key') in ('text', 'title', 'placeholder', 'prompt'):
            if element.text and element.text.strip():
                result.append({'key': element.text, 'kind': 'interface_builder'})
    return result


def catalog_entries(document):
    return [{'key': key, 'kind': 'catalog'} for key in document.get('strings', {}) if key.strip()]


def compare(root, translations, inventory):
    found, dynamic, runtime = {}, [], []
    scanned = 0
    # No vendored dependencies, generated artifacts, or unrelated repository tools.
    for directory in ('AltStore', 'SideStore', 'Shared', 'AltWidget', 'SideBackup'):
        for path in sorted((root / directory).rglob('*')):
            if not path.is_file() or path.suffix not in ('.swift', '.storyboard', '.xib', '.xcstrings'):
                continue
            relative = path.relative_to(root).as_posix()
            source = path.read_text(encoding='utf-8')
            scanned += 1
            if path.suffix == '.swift':
                result = swift_entries(source)
                rows = result['entries']
                dynamic.extend(dict(item, path=relative) for item in result['dynamicTemplates'])
                runtime.extend(dict(item, path=relative) for item in result['runtimeTextSites'])
            elif path.suffix == '.xcstrings':
                rows = catalog_entries(json.loads(source))
            else:
                rows = storyboard_entries(source)
            for item in rows:
                key = item['key']
                entry = found.setdefault(key, {'key': key, 'translated': key in translations,
                                               'inInventory': key in inventory, 'locations': []})
                entry['locations'].append(dict({k: v for k, v in item.items() if k != 'key'}, path=relative))
    entries = [found[key] for key in sorted(found)]
    exact = [entry for entry in entries if any(location['kind'] != 'runtime_ui_candidate' for location in entry['locations'])]
    candidates = [entry for entry in entries if entry not in exact]
    return {'schemaVersion': 1, 'scannedFiles': scanned,
            'coverage': {'exactSourceKeys': len(exact), 'translatedExactSourceKeys': sum(e['translated'] for e in exact),
                         'runtimeCandidateKeys': len(candidates), 'translatedRuntimeCandidates': sum(e['translated'] for e in candidates)},
            'missingExactKeys': [e for e in exact if not e['translated']],
            'missingRuntimeCandidates': [e for e in candidates if not e['translated']],
            'dynamicTemplates': dynamic, 'runtimeTextSites': runtime, 'entries': entries,
            'limitations': [
                'Source coverage is not runtime coverage: SwiftUI literal lookup interception is experimental.',
                'Runtime String Text arguments bypass localization; dictionary additions alone cannot fix them.',
                'Interpolations are templates, not exact keys. Formatting before lookup defeats exact matching.',
                'Named UI arguments are review candidates, not verified visible text; inspect their callees.',
                'Lexical extraction omits raw Swift strings, indirect constants, Objective-C, and dependency/server text.',
                'Includes iOS/tvOS/widget sources irrespective of compile conditions; brands/placeholders may intentionally remain unchanged.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    default_root = Path(__file__).resolve().parents[1]
    parser.add_argument('--dictionary', type=Path, default=default_root / 'zh-Hans.json')
    parser.add_argument('--inventory', type=Path, default=default_root / 'upstream-key-inventory.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.source_root.resolve()
    if not (root / 'SideStore').is_dir():
        parser.error('--source-root must contain the SideStore directory')
    translations = json.loads(args.dictionary.read_text(encoding='utf-8'))['translations']
    inventory = json.loads(args.inventory.read_text(encoding='utf-8'))
    report = compare(root, translations, set(inventory['keys']) | set(inventory.get('supplementalKeys', {})))
    report['sourceRoot'] = str(root)
    revision = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    report['sourceCommit'] = revision.stdout.strip() if revision.returncode == 0 else None
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'coverage': report['coverage'], 'dynamicTemplates': len(report['dynamicTemplates']),
                      'runtimeTextSites': len(report['runtimeTextSites']), 'output': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
