#!/usr/bin/env python3
"""Build production menu/Core into an isolated UIKit simulator regression app."""
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
parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
parser.add_argument('--device', default=os.environ.get('ORBIT_SIMULATOR_DEVICE'))
parser.add_argument('--output-dir', type=Path)
args = parser.parse_args()
root = args.source_root.resolve()
output = (args.output_dir or root / '.omx/artifacts/drawer-uikit').resolve()
output.mkdir(parents=True, exist_ok=True)
(output / 'result.json').unlink(missing_ok=True)

def command(*argv, **kwargs):
    return subprocess.run([str(a) for a in argv], check=True, text=True, **kwargs)

def capture(*argv):
    return subprocess.check_output([str(a) for a in argv], text=True).strip()

devices = json.loads(capture('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
all_devices = [d for runtime, group in devices.items() if '.iOS-' in runtime
               for d in group if d.get('isAvailable')]
device = next((d for d in all_devices if args.device in (d['udid'], d['name'])), None) if args.device else next((d for d in all_devices if d['state'] == 'Booted'), None)
if device is None and not args.device:
    device = next((d for d in all_devices if d['name'].startswith('iPhone')), None)
if device is None:
    parser.error('No matching available iOS simulator; install a runtime or pass --device NAME_OR_UDID')
udid = device['udid']
if device['state'] != 'Booted':
    command('xcrun', 'simctl', 'boot', udid)
command('xcrun', 'simctl', 'bootstatus', udid, '-b', stdout=subprocess.DEVNULL)
sdk = capture('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path')
arch = capture('uname', '-m')
core_names = ['LCOrbitCore', 'LCOrbitHost', 'LCOrbitGuestService', 'LCOrbitMultitask', 'LCOrbitAutomaticPiP', 'LCOrbitMultitaskUI', 'LCOrbitHostSettings', 'LCOrbitEventBus', 'LCOrbitOverlayManager', 'LCOrbitStorage', 'LCOrbitLog', 'LCOrbitTweakAudit', 'LCOrbitTweakSync', 'LCOrbitTweakCenter', 'LCOrbitTweakCenterViews', 'LCOrbitSharedTweaksViewController', 'LCOrbitLogViewer']
bundle_id = 'local.orbit.DrawerRegression'
with tempfile.TemporaryDirectory(prefix='orbit-drawer-uikit-') as temporary:
    # Freeze unmodified production files so concurrent edits cannot change the
    # implementation between compilation and source-contract reporting.
    build_root = Path(temporary) / 'source'
    for relative in ['LCOrbit/Core', 'LCOrbit/SDK', 'LCFloatingMenu']:
        shutil.copytree(root / relative, build_root / relative)
    source_hashes = {str(path.relative_to(build_root)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in sorted(build_root.rglob('*')) if path.suffix in ('.m', '.h')}
    source = (build_root / 'LCFloatingMenu/LCFloatingMenu.m').read_text()
    app = Path(temporary) / 'DrawerRegression.app'
    app.mkdir()
    build = ['xcrun', 'clang', '-target', f'{arch}-apple-ios16.0-simulator', '-isysroot', sdk, '-fobjc-arc', '-O0', '-g', '-I', str(build_root)]
    for framework in ['UIKit', 'Foundation', 'QuartzCore', 'CoreGraphics']:
        build.extend(['-framework', framework])
    build.extend(str(build_root / 'LCOrbit/Core' / f'{name}.m') for name in core_names)
    build.extend([str(build_root / 'LCFloatingMenu/LCFloatingMenu.m'), str(Path(__file__).parent / 'UIKitDrawer/main.m'), '-o', str(app / 'DrawerRegression')])
    with (output / 'build.log').open('w') as log:
        result = subprocess.run(build, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((output / 'build.log').read_text(), file=sys.stderr)
        sys.exit(result.returncode)
    (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle_id, 'CFBundleName': 'DrawerRegression', 'CFBundleExecutable': 'DrawerRegression', 'CFBundlePackageType': 'APPL', 'MinimumOSVersion': '16.0', 'UIDeviceFamily': [1, 2], 'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait']}))
    command('codesign', '-s', '-', '--force', app, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Uninstall only this dedicated fixture app to reset preferences/evidence.
    subprocess.run(['xcrun', 'simctl', 'uninstall', udid, bundle_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    command('xcrun', 'simctl', 'install', udid, app)
    container = Path(capture('xcrun', 'simctl', 'get_app_container', udid, bundle_id, 'data'))
    command('xcrun', 'simctl', 'launch', udid, bundle_id)
    report = container / 'Documents/DrawerEvidence/result.json'
    deadline = time.monotonic() + 45
    while not report.exists() and time.monotonic() < deadline:
        time.sleep(.25)
    if not report.exists():
        sys.exit('UIKit app produced no report within 45 seconds; inspect simulator crash logs')
    evidence = report.parent
    for item in evidence.iterdir():
        shutil.copy2(item, output / item.name)
    result = json.loads(report.read_text())
    result['sourceSHA256'] = source_hashes
    pan_start = source.index('- (void)pan:')
    pan_end = source.index('\n- (', pan_start + 1)
    contracts = [{'name': 'reduce-motion-docking-guard',
                  'passed': 'UIAccessibilityIsReduceMotionEnabled()' in source[pan_start:pan_end],
                  'kind': 'source-contract',
                  'limitation': 'Checks production docking method for the accessibility guard; does not toggle the system C accessibility function or prove the live animation timing.'}]
    result['sourceContracts'] = contracts
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f"UIKit drawer: {result['count'] - result['failures']}/{result['count']} passed on {device['name']} iOS {result['runtime']}")
    for check in result['results']:
        if not check['passed']:
            print(f"FAIL {check['name']}: {check['details']}")
    for contract in contracts:
        print(f"{'PASS' if contract['passed'] else 'FAIL'} source contract {contract['name']}")
    print(f'Evidence: {output}')
    sys.exit(1 if result['failures'] or any(not c['passed'] for c in contracts) else 0)
