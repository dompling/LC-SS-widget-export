from pathlib import Path
root=Path(__file__).resolve().parents[2]
s=(root/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
assert 'OrbitDockShouldSuppress(' in s
assert 'WindowDidAddSubview(' in s, 'must handle native Swift addSubview after task launch'
assert 'Replace(UIWindow.class,@"didAddSubview:"' in s
assert 'ApplyDockSurfaceVisibility(NativeDockSurface,BeadMenu())' in s, 'dock surface must follow ownership-preserving visibility policy'
assert 'SyncNativeDockSurface();' in s[s.index('+ (void)refreshPresentation'):], 'menu switch must sync already-shown dock'
assert 'OriginalShowDock' in s and 'OriginalShowHidden' in s
assert 'removeRunningApp' not in s[s.index('static void SyncNativeDockSurface'):s.index('static void WindowDidAddSubview')], 'never remove running tasks'
print('Native Dock surface lifecycle contract: PASS')
