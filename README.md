# vMini

Native macOS text editor, aimed at simplicity and minimum resource usage.

## External editor workflow

You can edit the Swift files in IntelliJ IDEA and use the scripts in `scripts/` for the common Xcode
tasks.

Xcode still needs to be installed.

## Commands

Build the app:

```bash
./scripts/build.sh
```

Build the release app:

```bash
CONFIGURATION=Release ./scripts/build.sh
```

Build and run the app:

```bash
./scripts/run.sh
```

Create a distributable archive and zip:

```bash
./scripts/package.sh
```

If you have a real Apple team configured for distribution signing, pass it in:

```bash
DEVELOPMENT_TEAM=YOURTEAMID ./scripts/package.sh
```

## Profile interactions

Record a CLI trace for focus, tab switching, and sidebar file-open latency:

```bash
./scripts/profile-interactions.sh --duration 30s
```

The script builds the app, launches it under `xctrace`, and records `Time Profiler` plus the app's
signpost intervals.

While the trace is running, reproduce these interactions:

- Bring `vMini` to the foreground from the Dock while it is already open
- Switch tabs a few times
- Click files from the sidebar folders section

Artifacts are saved under `profiles/`:

- `vmini.trace`: raw Instruments trace
- `trace-toc.xml`: exported trace table-of-contents metadata
- `run-info.txt`: basic run details

Use `--skip-build` to reuse the current build:

```bash
./scripts/profile-interactions.sh --skip-build --duration 30s
```

## GitHub Release

- Push a tag like `v1.0.0`
- GitHub Actions will run `.github/workflows/release.yml`
- The workflow builds `build/vMini.zip` and attaches it to the GitHub Release page

## Regenerate app icon

Override [icon_512x512@2x.png](vmini/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png) with
the new `1024x1024` icon, then run:

```bash
./scripts/generate-app-icon-set.sh
```

Then clear build data and restart dock to see the new icon:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
killall Dock
```
