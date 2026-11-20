#!/usr/bin/env python3
"""Run LC's auto-sign transaction against a mocked signer in an iOS simulator."""
import json
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import time
import sys

root = Path(__file__).resolve().parents[2]
source = root / "LCOrbit/Tests/plugin_autosign_tests.m"
updater = root / "LCOrbit/Core/LCOrbitPluginUpdater.m"
def capture(*cmd):
    return subprocess.check_output(cmd, text=True).strip()
def run(*cmd):
    subprocess.run(cmd, check=True)
sdk = capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
arch = capture("uname", "-m")
devices = json.loads(capture("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
available = [d for runtime, rows in devices.items() if ".iOS-" in runtime for d in rows if d.get("isAvailable")]
device = next((d for d in available if d["state"] == "Booted"), None)
if device is None:
    device = next((d for d in available if d["name"].startswith("iPhone")), None)
if device is None:
    sys.exit("No available iPhone simulator")
udid = device["udid"]
if device["state"] != "Booted":
    run("xcrun", "simctl", "boot", udid)
run("xcrun", "simctl", "bootstatus", udid, "-b")
bid = "local.orbit.PluginAutoSignFixture"
with tempfile.TemporaryDirectory(prefix="orbit-autosign-") as temporary:
    app = Path(temporary) / "PluginAutoSignFixture.app"
    app.mkdir()
    executable = app / "PluginAutoSignFixture"
    run("xcrun", "clang", "-target", f"{arch}-apple-ios16.0-simulator",
        "-isysroot", sdk, "-fobjc-arc", "-Wl,-export_dynamic",
        "-framework", "UIKit", "-framework", "Foundation", "-framework", "Security",
        str(source), str(updater), "-o", str(executable))
    (app / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier":bid, "CFBundleExecutable":executable.name,
        "CFBundleName":"PluginAutoSignFixture", "CFBundlePackageType":"APPL",
        "MinimumOSVersion":"16.0", "UIDeviceFamily":[1],
        "UILaunchScreen":{}, "UISupportedInterfaceOrientations":["UIInterfaceOrientationPortrait"]}))
    run("codesign", "-s", "-", "--force", str(app))
    subprocess.run(["xcrun", "simctl", "uninstall", udid, bid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run("xcrun", "simctl", "install", udid, str(app))
    container = Path(capture("xcrun", "simctl", "get_app_container", udid, bid, "data"))
    report = container / "Documents/PluginAutoSignResult.txt"
    report.unlink(missing_ok=True)
    subprocess.run(["xcrun", "simctl", "launch", udid, bid], check=False)
    deadline = time.monotonic() + 20
    while not report.exists() and time.monotonic() < deadline:
        time.sleep(.2)
    if not report.exists():
        sys.exit("Auto-sign fixture produced no result")
    result = report.read_text().split(" ", 2)
    print("Auto-sign transaction:", result[2])
    if int(result[1]) != 0:
        sys.exit(1)
