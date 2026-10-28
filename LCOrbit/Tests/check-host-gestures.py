from pathlib import Path
root=Path(__file__).resolve().parents[2]
s=(root/'LCOrbit/Core/LCOrbitHostSettings.m').read_text()
assert 'UILongPressGestureRecognizer' in s, 'No host gesture rescue installed'
assert 'numberOfTouchesRequired=2' in s, 'Independent two-finger recovery must be available'
assert 'minimumPressDuration=' in s
assert 'IsDataManagementTitle' in s, 'Data Management row must be a recognized anchor'
assert 'shouldReceiveTouch:(UITouch *)touch' in s, 'Row gesture must be restricted to Data Management'
assert 'UIWindowDidBecomeVisibleNotification' in s and 'UISceneDidActivateNotification' in s
assert 'OpenPluginSettings(scene)' in s, 'Must open actual existing settings'
assert 'LCOrbitHost isHostUI' in s, 'Must be limited to host'
assert 'class_replaceMethod(UINavigationBar.class' not in s, 'No SwiftUI navigation hooks'
assert 'initWithWindowScene:' not in s, 'No overlay windows'
print('Gesture-based host settings recovery source check: PASS')
