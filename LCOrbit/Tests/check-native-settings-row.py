from pathlib import Path
base=Path(__file__).resolve().parents[2]
s=(base/'LiveContainerSwiftUI/Views/Settings/LCSettingsView.swift').read_text()
t=(base/'LCOrbit/Core/LCOrbitHostSettings.m').read_text()
start=s.index('NavigationLink {\n                        LCDataManagementView()')
end=s.index('\n                Section {',start)
chunk=s[start:end]
assert 'Button {' in chunk and 'Text("微珠设置")' in chunk, 'Settings row missing after Data Management'
assert chunk.index('Text("lc.settings.dataManagement".loc)') < chunk.index('Text("微珠设置")'), 'Entry must immediately follow Data Management'
assert chunk.count('NavigationLink') == 1, 'Do not alter existing navigation links'
assert 'LCOrbitOpenHostSettings' in chunk and 'NSMutableDictionary' in chunk, 'Native row must notify plugin and have a response'
assert 'showFloatingMenuUnavailable = true' in chunk, 'Missing plugin must show a helpful error'
assert 'LCOrbitOpenHostSettings' in t and 'reply[@"handled"]' in t, 'Plugin must respond to row action'
assert 'OpenPluginSettings(scene)' in t, 'Plugin must open full settings'
assert 'class_replaceMethod(UINavigationBar.class' not in t and 'initWithWindowScene:' not in t, 'Remove failed navigation and floating injections'
print('Native settings row and plugin handshake: PASS')
