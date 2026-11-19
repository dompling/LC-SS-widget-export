#!/usr/bin/env python3
"""Build/run the production live-view overview in an isolated UIKit fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline-without-switcher', action='store_true', help='Verify the fixture fails without the production overview')
parser.add_argument('--device', default=os.environ.get('ORBIT_SIMULATOR_DEVICE'))
parser.add_argument('--output-dir', type=Path)
parser.add_argument('--build-only', action='store_true', help='Compile simulator and device fixtures without claiming UIKit execution')
parser.add_argument('--grid-screenshot', action='store_true', help='Capture the iPad grid in the final simulator screenshot')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = (args.output_dir or root / '.omx/artifacts/task-switcher-uikit').resolve()
output.mkdir(parents=True, exist_ok=True)
for name in ['result.json', 'portrait.png', 'landscape.png', 'landscape-error.png', 'portrait-screen.png', 'reading-focused.png', 'notes-focused.png']:
    (output / name).unlink(missing_ok=True)

def command(*argv, timeout=45, **kwargs):
    return subprocess.run([str(a) for a in argv], timeout=timeout, check=True, text=True, **kwargs)

def capture(*argv, timeout=25):
    return command(*argv, timeout=timeout, stdout=subprocess.PIPE).stdout.strip()

simctl = os.environ.get('ORBIT_SIMCTL', 'simctl')

def sim(*argv):
    return [simctl, *argv] if simctl != 'simctl' else ['xcrun', 'simctl', *argv]

bundle = 'local.orbit.TaskSwitcherRegression'
with tempfile.TemporaryDirectory(prefix='orbit-task-switcher-') as temporary:
    app = Path(temporary) / 'TaskSwitcherRegression.app'
    app.mkdir()
    source = root / 'LCOrbit/Core/LCOrbitTaskSwitcher.m'
    for platform, target in [('iphonesimulator', f'{capture("uname", "-m")}-apple-ios16.0-simulator'), ('iphoneos', 'arm64-apple-ios16.0')]:
        sdk = capture('xcrun', '--sdk', platform, '--show-sdk-path')
        executable = app / 'TaskSwitcherRegression' if platform == 'iphonesimulator' else output / 'TaskSwitcherRegression-device'
        build = ['xcrun', 'clang', '-target', target, '-isysroot', sdk, '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-O0', '-g', '-I', str(root), '-framework', 'UIKit', '-framework', 'Foundation', '-framework', 'QuartzCore', '-framework', 'CoreGraphics', str(root / 'LCOrbit/Tests/UIKitTaskSwitcher/main.m')]
        if source.exists() and not args.baseline_without_switcher:
            build.append(str(source))
        build.extend(['-o', str(executable)])
        with (output / f'build-{platform}.log').open('w') as log:
            result = subprocess.run(build, stdout=log, stderr=subprocess.STDOUT, timeout=60)
        if result.returncode:
            print((output / f'build-{platform}.log').read_text(), file=sys.stderr)
            sys.exit(result.returncode)
    if args.build_only:
        print(f'Compiled simulator and arm64-device UIKit fixtures. No runtime assertions executed. Logs: {output}')
        sys.exit(0)
    try:
        devices = json.loads(capture(*sim('list', 'devices', 'available', '--json')))['devices']
    except subprocess.TimeoutExpired:
        sys.exit('Simulator service did not respond within 25s; fixture compiled for simulator/device but UIKit tests did not run')
    available = [d for runtime, group in devices.items() if '.iOS-' in runtime for d in group if d.get('isAvailable')]
    device = next((d for d in available if args.device in (d['udid'], d['name'])), None) if args.device else next((d for d in available if d['state'] == 'Booted'), None)
    if device is None and not args.device:
        device = next((d for d in available if d['name'].startswith('iPhone')), None)
    if device is None:
        sys.exit('No available iOS simulator; fixture compiled, UIKit tests did not run')
    udid = device['udid']
    if device['state'] != 'Booted':
        command(*sim('boot', udid))
    command(*sim('bootstatus', udid, '-b'), timeout=60)
    (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleName': 'TaskSwitcherRegression', 'CFBundleExecutable': 'TaskSwitcherRegression', 'CFBundlePackageType': 'APPL', 'MinimumOSVersion': '16.0', 'UIDeviceFamily': [1, 2], 'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'], 'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False, 'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{'UISceneConfigurationName': 'Fixture', 'UISceneDelegateClassName': 'TaskSwitcherSceneDelegate'}]}}}))
    command('codesign', '-s', '-', '--force', app, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(sim('terminate', udid, bundle), timeout=20, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    command(*sim('install', udid, app))
    container = Path(capture(*sim('get_app_container', udid, bundle, 'data')))
    report = container / 'Documents/TaskSwitcherEvidence/result.json'
    shutil.rmtree(report.parent, ignore_errors=True)
    launch_env = dict(os.environ, SIMCTL_CHILD_ORBIT_GRID_SCREENSHOT='1' if args.grid_screenshot else '0')
    command(*sim('launch', udid, bundle), env=launch_env)
    deadline = time.monotonic() + 35
    while not report.exists() and time.monotonic() < deadline:
        time.sleep(.25)
    if not report.exists():
        sys.exit('UIKit fixture produced no report within 35s')
    command(*sim('io', udid, 'screenshot', '--type=png', output / 'portrait-screen.png'), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for item in report.parent.iterdir():
        shutil.copy2(item, output / item.name)
    result = json.loads(report.read_text())
    result['visualArtifacts'] = ['portrait-screen.png', 'portrait.png', 'reading-focused.png', 'notes-focused.png', 'landscape.png']
    result['sourceSHA256'] = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [source, root / 'LCOrbit/Core/LCOrbitTaskSwitcher.h', root / 'LCOrbit/Tests/UIKitTaskSwitcher/main.m', Path(__file__).resolve()] if path.exists()}
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f"UIKit task switcher: {result['count'] - result['failures']}/{result['count']} passed on {device['name']}")
    for check in result['results']:
        if not check['passed']:
            print(f"FAIL {check['name']}: {check['details']}")
    print(f'Evidence: {output}')
    sys.exit(bool(result['failures']))
