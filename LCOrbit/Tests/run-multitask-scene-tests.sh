#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/orbit-scene-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT" "$WORK/scene.inc" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'LCOrbit/Core/LCOrbitMultitaskUI.m').read_text()
parts=[]
for signature in ['static BOOL OrbitValidFrame(', 'static UIEdgeInsets PortraitInsets(',
                  'static void RememberGuestOrientation(', 'static BOOL FullscreenGeometry(', 'static void ApplyGeometry(',
                  'static void ConfigureSafeArea(', 'static void UpdateScene(',
                  'static void SceneSettings(', 'static void FinalSceneSettings(',
                  'static void InitialSceneSettings(', 'static void PresenterReady(']:
    if signature in source:
        start=source.index(signature)
        parts.append(source[start:source.index('\n}',start)+2])
if 'static void SceneSettings(' not in source:
    # The baseline has no final AppScene hook. Its native resize path runs
    # unmodified; exercising that boundary reproduces the missing enforcement.
    parts.append('static void SceneSettings(id scene,SEL selector,void (^block)(id)) { NativeSettings(scene,selector,block); }')
if 'static void FinalSceneSettings(' not in source:
    parts.append('static void FinalSceneSettings(id scene,SEL selector,void (^block)(id,id)) { NativeRemoteSettings(scene,selector,block); }')
if 'static void InitialSceneSettings(' not in source:
    parts.insert(0,'static void InitialSceneSettings(id parameters,SEL selector,void (^block)(id)) { NativeParameterSettings(parameters,selector,block); }')
app=(Path(sys.argv[1])/'MultitaskSupport/AppSceneViewController.m').read_text()
work=Path(sys.argv[2]).parent
start=app.index('    void (^updateSceneSettings)(id)')
end=app.index('\n    if (@available(iOS 18.0',start)
(work/'initial-settings.inc').write_text(app[start:end])
start=app.index('        [scene configureParameters:^')
end=app.index('\n        }];',start)+len('\n        }];')
(work/'hosting-parameters.inc').write_text(app[start:end])
start=app.index('        [parameters updateSettingsWithBlock:updateSceneSettings];',end)
end=app.index('\n        FBScene *scene =',start)
(work/'legacy-parameters.inc').write_text(app[start:end])
native=(Path(sys.argv[1])/'MultitaskSupport/UIKitHooks.m').read_text()
start=native.index('void hook_FBScene_performUpdateWithoutActivation(')
parts.append(native[start:native.index('\n}',start)+2])
Path(sys.argv[2]).write_text('\n'.join(parts))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -Wno-unused-parameter -Wno-unused-function -framework Foundation -framework CoreGraphics \
    -I "$WORK" "$ROOT/LCOrbit/Tests/multitask_scene_tests.m" -o "$WORK/scene-tests"
"$WORK/scene-tests"
