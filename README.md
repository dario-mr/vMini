# vMini

Native macOS text editor, aimed at simplicity and minimum resource usage.

In Markdown files, Cmd-click the text inside `[label](destination)` to open the link.
Web links open in your default browser; file links open in an editor tab. Relative paths
resolve from the Markdown file's folder.

Use the mouse's browser Back/Forward buttons or Cmd-[ / Cmd-] to revisit cursor positions
and previously visited tabs. Cursor clicks, search results, Go to Line, and page/document
jumps create checkpoints. Closing a tab removes its checkpoints. History lasts for the
current session; edits can shift the saved cursor positions.

## External editor workflow

You can edit the Swift files in IntelliJ IDEA and use the scripts in `scripts/` for the common Xcode
tasks.

Xcode still needs to be installed.

## Commands

Build the app:

```shell
./scripts/build.sh
```

Build the release app:

```shell
CONFIGURATION=Release ./scripts/build.sh
```

Build and run the app:

```shell
./scripts/run.sh
```

Run tests:

```shell
swift test -c release
```

Create a distributable archive and zip:

```shell
./scripts/package.sh
```

If you have a real Apple team configured for distribution signing, pass it in:

```shell
DEVELOPMENT_TEAM=YOURTEAMID ./scripts/package.sh
```

## Performance profiling

See [profiling.md](docs/profiling.md) for interaction profiling and benchmark instructions.

## GitHub Release

- Push a tag like `v1.0.0`
- GitHub Actions will run `.github/workflows/release.yml`
- The workflow builds `build/vMini.zip` and attaches it to the GitHub Release page

## Regenerate app icon

Override [icon_512x512@2x.png](vmini/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png) with
the new `1024x1024` icon, then run:

```shell
./scripts/generate-app-icon-set.sh
```

Then clear build data and restart dock to see the new icon:

```shell
rm -rf ~/Library/Developer/Xcode/DerivedData
killall Dock
```
