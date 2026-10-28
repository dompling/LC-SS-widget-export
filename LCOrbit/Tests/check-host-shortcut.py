from pathlib import Path
root=Path(__file__).resolve().parents[2]
s=(root/'LCOrbit/Core/LCOrbitHostSettings.m').read_text()
assert 'initWithWindowScene:' in s, 'A host-scene entry window is required; UINavigationBar injection was unreliable'
assert 'UIWindowLevelNormal+' in s, 'Shortcut window should be independent of SwiftUI NavigationView'
assert '[entry setTitle:@"微珠设置"' in s, 'User needs a visible named shortcut'
assert '[entry addTarget:' in s and 'action:@selector(open)' in s
assert 'OpenPluginSettings(scene)' in s, 'Tap should open the full settings directly'
assert 'entryWindow.hidden=NO;' in s, 'The shortcut must actually be shown'
assert 'LCOrbitHost isHostUI' in s, 'Must not leak into Guest and SideStore'
assert 'activeWindow' in s, 'Hide while the user is using a multitask Guest'
assert 'UIApplicationDidBecomeActiveNotification' in s and 'UISceneDidActivateNotification' in s
assert 'class_replaceMethod(UINavigationBar.class' not in s, 'Do not depend on private SwiftUI navigation layout'
print('Host settings rescue shortcut contract: PASS')
