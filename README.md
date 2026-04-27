# vMini

Native macOS text editor .

## External-editor workflow

You can edit the Swift files in IntelliJ IDEA and use the scripts in `scripts/` for the common Xcode
tasks.

Xcode still needs to be installed because it provides:

- the macOS SDK
- `xcodebuild`
- code signing for local runs
- app launching/debugging support

You do not need to use Xcode as your day-to-day editor.

## Commands

Build the app:

```bash
./scripts/build.sh
```

Build and run the app:

```bash
./scripts/run.sh
```

Regenerate app icon for all resolutions, based on source `icon_512x512@2x.png`:

```bash
./scripts/generate-app-icon-set.sh
```
