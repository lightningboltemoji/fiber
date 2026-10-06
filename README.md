<p align="center">
<img width="190" height="190" alt="App icon" src="https://github.com/user-attachments/assets/1d479a69-8c0d-4123-881a-16edaa53835b" />
</p>

# Fiber

a Chromium-based browser for macOS

## Development

```sh
make sync       # fetch Chromium at CHROMIUM_VERSION (~31GB), apply patches
make build      # configure out/Default and build (first build: hours)
make run        # launch with a dev profile in chromium/dev-profile (URL=… to open a page)
make size       # what Chrome's code costs by directory, what the linker strips, what moved
make harness    # just the UI, against a mock browser, without Chromium
make patches    # regenerate patches/chromium/ from edits in chromium/src
make icon       # regenerate the app icon (core/branding/icon)

make dist       # self-contained dist/Fiber.app from out/Release, plus a zip
make install    # the same app, into /Applications
```

After editing a file under `chromium/src`, run `make patches` to regenerate `patches/chromium/`. Every build applies what changed in `patches/chromium/` first (after a pull, say), without touching edits that aren't in a patch yet. Put new code in `core/` rather than adding files to the Chromium tree.

To move to a newer Chromium, set `CHROMIUM_VERSION` and run `make sync`, which rebases the patches onto it; [`.claude/skills/upgrade-chromium`](.claude/skills/upgrade-chromium/SKILL.md) has the rest.
