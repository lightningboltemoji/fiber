#!/usr/bin/env python3
"""Compiles Fiber's app icon for the app bundle.

Writes Assets.car and app.icns, the names Chrome's Info.plist expects
(CFBundleIconName is AppIcon, from AppIcon.icon; CFBundleIconFile is app.icns).
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--minimum-deployment-target", required=True)
    parser.add_argument("--depfile", required=True)
    parser.add_argument("packages", nargs="+", help=".icon and .xcassets")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        command = [
            "xcrun", "actool",
            "--output-format=xml1", "--errors", "--warnings", "--notices",
            "--platform=macosx", "--target-device=mac",
            # Use actool's bundled asset frameworks, so the output doesn't
            # depend on the macOS release it runs on (as Xcode does).
            "--lightweight-asset-runtime-mode=enabled",
            "--app-icon=AppIcon",
            f"--minimum-deployment-target={args.minimum_deployment_target}",
            f"--output-partial-info-plist={os.path.join(tmp, 'partial.plist')}",
            f"--compile={tmp}",
        ] + args.packages
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
            return 1

        os.makedirs(args.output_dir, exist_ok=True)
        shutil.copyfile(os.path.join(tmp, "Assets.car"),
                        os.path.join(args.output_dir, "Assets.car"))
        shutil.copyfile(os.path.join(tmp, "AppIcon.icns"),
                        os.path.join(args.output_dir, "app.icns"))

    with open(args.depfile, "w") as f:
        output = os.path.join(args.output_dir, "Assets.car")
        f.write(f"{output}: {' '.join(package_files(args.packages))}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
