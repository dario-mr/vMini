# vMini

Native macOS text editor, aimed at simplicity and minimum resource usage.

## External editor workflow

You can edit the Swift files in IntelliJ IDEA and use the scripts in `scripts/` for the common Xcode
tasks.

Xcode still needs to be installed because it provides:

- the macOS SDK
- `xcodebuild`
- code signing for local runs
- app launching/debugging support

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

Publish a downloadable build on GitHub:

- Push a tag like `v1.0.0`
- GitHub Actions will run `.github/workflows/release.yml`
- The workflow builds `build/vMini.zip` and attaches it to the GitHub Release page

Without a real Apple Developer signing team, the uploaded app is still useful for downloads, but macOS will treat it as an unsigned/local-signed app and may warn users on first launch.

Regenerate app icon for all resolutions, based on source `icon_512x512@2x.png`:

```bash
./scripts/generate-app-icon-set.sh
```
