#!/usr/bin/env python3
"""Check, run, test, or accessibility-audit Climb Log on a standard iPhone simulator."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
DEVICE_TYPES = {
    "iphone16": ("Climb Log - iPhone 16", "com.apple.CoreSimulator.SimDeviceType.iPhone-16"),
    "se": ("Climb Log - iPhone SE", "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"),
}


def run(*args, capture=False):
    return subprocess.run(args, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def simulator(device, fresh_boot=False):
    name, device_type = DEVICE_TYPES[device]
    runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "--json", capture=True))["runtimes"]
    compatible = [runtime for runtime in runtimes if runtime["isAvailable"] and
                  any(item["identifier"] == device_type for item in runtime.get("supportedDeviceTypes", []))]
    if not compatible:
        raise RuntimeError("No compatible iOS runtime is installed. Install one in Xcode > Settings > Components.")
    runtime = max(compatible, key=lambda value: tuple(int(part) for part in value["version"].split(".")))
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture=True))["devices"]
    existing = next((item for item in devices.get(runtime["identifier"], []) if item["name"] == name), None)
    if existing:
        identifier = existing["udid"]
        booted = existing["state"] == "Booted"
    else:
        identifier = run("xcrun", "simctl", "create", name, device_type, runtime["identifier"], capture=True).strip()
        booted = False
    # iOS accessibility probes can leave testmanagerd busy after a completed run.
    # Isolate audit invocations with a clean boot, retaining all simulator data.
    if booted and fresh_boot:
        run("xcrun", "simctl", "shutdown", identifier)
        booted = False
    print(f"Using {name} / {runtime['name']} / {identifier}", flush=True)
    if not booted:
        run("xcrun", "simctl", "boot", identifier)
    run("xcrun", "simctl", "bootstatus", identifier, "-b")
    return identifier


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "run", "test", "audit"])
    parser.add_argument("--device", choices=DEVICE_TYPES, default="iphone16")
    args = parser.parse_args()
    run("xcodebuild", "-version")
    run("xcodebuild", "-checkFirstLaunchStatus")
    run("swift", "--version")
    base = ["xcodebuild", "-project", "ClimbingApp.xcodeproj", "-scheme", "ClimbingApp"]
    if args.action == "check":
        run(*base, "-resolvePackageDependencies")
        run("xcrun", "simctl", "list", "runtimes")
        print("Requirements checked. Apple frameworks are bundled; pinned Google Sign-In dependencies resolved.")
        return
    identifier = simulator(args.device, fresh_boot=args.action == "audit")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    build_dir = ROOT / "build"
    build_dir.mkdir(exist_ok=True)
    # Synced Documents folders can inject Finder metadata into bundles, breaking codesign.
    # Simulator builds use Xcode's local ad-hoc signing; no paid Apple team is required.
    cache_dir = Path.home() / "Library/Caches/ClimbLog"
    derived_data = cache_dir / "DerivedData"
    legacy_packages = build_dir / "DerivedData/SourcePackages"
    packages = legacy_packages if legacy_packages.exists() else cache_dir / "SourcePackages"
    command = base + ["-destination", f"platform=iOS Simulator,id={identifier}",
                      "-derivedDataPath", str(derived_data), "-clonedSourcePackagesDirPath", str(packages),
                      "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
    if args.action in ("test", "audit"):
        if args.action == "audit":
            command += ["-only-testing:ClimbingAppUITests/AccessibilityAuditUITests"]
        command += ["-parallel-testing-enabled", "NO", "-resultBundlePath",
                    str(build_dir / f"{args.device}-{stamp}.xcresult"), "test"]
    else:
        command += ["build"]
    log = build_dir / f"{args.device}-{args.action}-{stamp}.log"
    print(f"Build output: {log}", flush=True)
    with log.open("w") as output:
        completed = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if completed.returncode:
        print("\n".join(log.read_text().splitlines()[-60:]), file=sys.stderr)
        raise RuntimeError(f"Xcode failed; see {log}")
    print(f"{args.action.capitalize()} succeeded.")
    if args.action == "run":
        app = derived_data / "Build/Products/Debug-iphonesimulator/ClimbingApp.app"
        run("xcrun", "simctl", "install", identifier, str(app))
        # Ensure a prior UI-test launch cannot leave the app in its isolated guest mode.
        subprocess.run(["xcrun", "simctl", "terminate", identifier, "com.frozenpop.ClimbingApp"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run("xcrun", "simctl", "launch", identifier, "com.frozenpop.ClimbingApp")
        developer = Path(run("xcode-select", "-p", capture=True).strip())
        # Xcode 27 uses Device Hub; older versions use Simulator.app.
        hosts = [developer.parent / "Applications/DeviceHub.app", developer / "Applications/Simulator.app"]
        for host in hosts:
            if host.exists():
                run("open", str(host))
                break


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, RuntimeError) as error:
        sys.exit(str(error))
