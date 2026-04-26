# TextEditorApp

Native macOS text editor MVP built with Swift, AppKit, `NSDocument`, and `NSTextView`.

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

Run the app after building:

```bash
./scripts/run.sh
```

Clean the build products:

```bash
./scripts/clean.sh
```

Print the resolved `.app` path:

```bash
./scripts/app-path.sh
```

## Suggested IntelliJ setup

1. Open this folder in IntelliJ IDEA.
2. Edit files under `TextEditorApp/`.
3. Create run configurations that call:
    - `./scripts/build.sh`
    - `./scripts/run.sh`
4. Keep Xcode installed, but only open it when you need macOS-specific debugging or project
   settings.

## Project layout

- `TextEditorApp/`: AppKit source files
- `vmini.xcodeproj/`: Xcode project wrapper
- `scripts/`: terminal-friendly build and run entry points
