"""Regression tests for the deliberately bounded source inventory extractor."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / 'compare_source.py'
spec = importlib.util.spec_from_file_location('compare_source', SCRIPT)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ExtractionTests(unittest.TestCase):
    def test_swift_lookup_and_literal_are_distinct_from_candidates(self):
        source = '''
Text("Refresh All")
NSLocalizedString("Install %@", comment: "button")
String(localized: "Settings")
row(title: "App Groups", systemImage: "folder.fill")
let storageKey = "password"
// Text("Commented out")
/* Text("Also commented out") */
'''
        result = audit.swift_entries(source)
        entries = {r['key']: r['kind'] for r in result['entries']}
        self.assertEqual(entries, {'Refresh All': 'swiftui_literal', 'Install %@': 'localized_lookup',
                                  'Settings': 'localized_lookup', 'App Groups': 'runtime_ui_candidate'})

    def test_dynamic_interpolation_is_never_an_exact_dictionary_key(self):
        result = audit.swift_entries('Text("Expires in \\(days) days")\nText(title)\nText(verbatim: "Debug")')
        self.assertEqual([r['key'] for r in result['entries']], ['Debug'])
        self.assertEqual(result['entries'][0]['kind'], 'runtime_ui_candidate')
        self.assertEqual(len(result['dynamicTemplates']), 1)
        self.assertEqual(len(result['runtimeTextSites']), 1)

    def test_interpolation_with_nested_quotes_does_not_invent_fragment_keys(self):
        source = 'Text("Remove \\(team?.name ?? "") profiles")\nText("Keep")'
        result = audit.swift_entries(source)
        self.assertEqual([r['key'] for r in result['entries']], ['Keep'])
        self.assertEqual(len(result['dynamicTemplates']), 1)

    def test_swift_escapes_and_multiline(self):
        result = audit.swift_entries('Text("Line 1\\nLine 2 \\"quoted\\"")\nText("""\n    Reset account\n    Keep apps\n    """)')
        self.assertEqual([r['key'] for r in result['entries']], ['Line 1\nLine 2 "quoted"', 'Reset account\nKeep apps'])

    def test_storyboard_entities_and_internal_attributes(self):
        source = '<document><label id="internal-id" text="Apps &amp; IDs"/><button><state key="normal" title="Refresh"/></button><textField placeholder="Apple ID"/><string key="text">Allow &lt;access&gt;</string><image name="not-a-label"/></document>'
        self.assertEqual({r['key'] for r in audit.storyboard_entries(source)},
                         {'Apps & IDs', 'Refresh', 'Apple ID', 'Allow <access>'})

    def test_catalog_ignores_metadata_and_empty_key(self):
        self.assertEqual([r['key'] for r in audit.catalog_entries({'strings': {'': {}, 'Refresh': {'comment': 'hint'}}})], ['Refresh'])

    def test_report_deduplicates_and_keeps_candidates_separate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'SideStore').mkdir()
            (root / 'SideStore' / 'Screen.swift').write_text('Text("Refresh")\nText("Refresh")\nrow(title: "Missing row")\nText("Missing label")')
            report = audit.compare(root, {'Refresh': '刷新'}, {'Refresh'})
            self.assertEqual(report['coverage']['exactSourceKeys'], 2)
            self.assertEqual(report['coverage']['translatedExactSourceKeys'], 1)
            self.assertEqual(report['missingExactKeys'][0]['key'], 'Missing label')
            self.assertEqual(report['missingRuntimeCandidates'][0]['key'], 'Missing row')
            self.assertEqual(len(next(r for r in report['entries'] if r['key'] == 'Refresh')['locations']), 2)


if __name__ == '__main__':
    unittest.main()
