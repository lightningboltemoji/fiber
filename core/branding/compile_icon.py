#!/usr/bin/env python3
"""Compiles Fiber's app icon for the app bundle.

Writes Assets.car and app.icns, the names Chrome's Info.plist expects
(CFBundleIconName is AppIcon, from AppIcon.icon; CFBundleIconFile is app.icns),
and alert_helper/Assets.car, the .icon packages alone for the alert helpers,
which never show the document badge.
"""

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile


def package_files(paths):
    for path in paths:
        for root, _, names in os.walk(path):
            for name in sorted(names):
                yield os.path.join(root, name)


def compile_catalog(packages, minimum_deployment_target, output_dir):
    """Runs actool on `packages`, writing Assets.car and AppIcon.icns into
    `output_dir`. Returns whether it succeeded."""
    os.makedirs(output_dir)
    command = [
        "xcrun", "actool",
        "--output-format=xml1", "--errors", "--warnings", "--notices",
        "--platform=macosx", "--target-device=mac",
        # Use actool's bundled asset frameworks, so the output doesn't
        # depend on the macOS release it runs on (as Xcode does).
        "--lightweight-asset-runtime-mode=enabled",
        "--app-icon=AppIcon",
        f"--minimum-deployment-target={minimum_deployment_target}",
        f"--output-partial-info-plist={os.path.join(output_dir, 'partial.plist')}",
        f"--compile={output_dir}",
        # actool (as of Xcode 27) resolves relative inputs against the wrong
        # directory.
    ] + [os.path.abspath(package) for package in packages]
    process = subprocess.run(command, capture_output=True)
    results = plistlib.loads(process.stdout) if process.stdout else {}

    # actool reports missing inputs as notices, so treat anything it
    # reports as a failure.
    problems = [
        item
        for key, items in results.items()
        if key.endswith((".errors", ".warnings", ".notices"))
        for item in items
    ]
    if process.returncode or problems:
        print(f"actool failed: {problems}", file=sys.stderr)
        sys.stderr.buffer.write(process.stderr)
        return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--minimum-deployment-target", required=True)
    parser.add_argument("--depfile", required=True)
    parser.add_argument("packages", nargs="+", help=".icon and .xcassets")
    args = parser.parse_args()

    icons = [package for package in args.packages if package.endswith(".icon")]
    with tempfile.TemporaryDirectory() as tmp:
        app = os.path.join(tmp, "app")
        helper = os.path.join(tmp, "alert_helper")
        if not (compile_catalog(args.packages, args.minimum_deployment_target,
                                app) and
                compile_catalog(icons, args.minimum_deployment_target,
                                helper)):
            return 1

        os.makedirs(os.path.join(args.output_dir, "alert_helper"),
                    exist_ok=True)
        shutil.copyfile(os.path.join(app, "Assets.car"),
                        os.path.join(args.output_dir, "Assets.car"))
        shutil.copyfile(os.path.join(app, "AppIcon.icns"),
                        os.path.join(args.output_dir, "app.icns"))
        shutil.copyfile(os.path.join(helper, "Assets.car"),
                        os.path.join(args.output_dir, "alert_helper",
                                     "Assets.car"))

    with open(args.depfile, "w") as f:
        output = os.path.join(args.output_dir, "Assets.car")
        f.write(f"{output}: {' '.join(package_files(args.packages))}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
