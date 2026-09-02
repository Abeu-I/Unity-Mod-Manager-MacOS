<p align="center">
  <img src="assets/github-logo.png" alt="ADOFAI Unity Mod Manager for macOS logo" width="280">
</p>
<h1 align="center">
  <a href="https://abeu-i.github.io/Unity-Mod-Manager-MacOS/">
    <strong>🌐 Open the Interactive Website</strong>
  </a>
</h1>

# ADOFAI + Unity Mod Manager on macOS

This setup runs the Intel slice of A Dance of Fire and Ice through Apple's
Rosetta 2 and uses a small native in-bundle launcher to inject the macOS
`UnityDoorstop` 4 library patched for Unity 6 universal Mach-O files. The
launcher keeps Steam's original app launch and process ID, so the Steam
overlay, Workshop, playtime, and achievements stay connected. Doorstop starts
Unity Mod Manager's managed runtime, which loads ordinary mods from
`Mods/<mod-id>/Info.json`.

It does **not** use Wine, Whisky, CrossOver, or disable System Integrity
Protection.

Version 1.1 pins the verified Doorstop 4 loader that successfully injects UMM
and loads all five bundled mods on the current ADOFAI Unity 6 build. Its SHA-256
is checked before packaging, preventing the incompatible fallback and later
bootstrap experiments from being installed accidentally.

## Install

### Native app

Build the polished SwiftUI installer app from source:

```bash
./package_app.sh
open "dist/ADOFAI Mod Installer.app"
```

The app provides a friendly three-tab interface:

- install, repair, diagnostics, and safe vanilla restore;
- view installed mods, enable/disable them, or remove them to a recoverable backup;
- drag and drop a UMM mod ZIP (archives are checked before extraction);
- install verified recommended releases of ADOFAI Tweaks, JALib, Jipper
  Resource Pack, Jipper Overlayer, Modern UMM UI, and Mac AutoPlay.

### Modern in-game UMM interface

`ModernUMMUI` is an optional UI-only mod included with the installer. It
replaces UMM's old window renderer with a clearer mod dashboard, dedicated
settings pages, an activity log, and concise status labels. It does not change
Doorstop, Steam integration, mod loading, or individual mod components. Disable
the mod to return to UMM's original interface.

The command-line workflow remains available below.

### Command line

In Terminal, change to the folder containing the script and run:

```bash
chmod +x ./setup_adofai_umm_macos.sh
./setup_adofai_umm_macos.sh install --mod "$HOME/Downloads/AdofaiTweaks"
```

To validate downloads, native components, Rosetta, and paths without changing the
game, run this first:

```bash
./setup_adofai_umm_macos.sh install --dry-run --mod "$HOME/Downloads/AdofaiTweaks"
```

The repository is source-only. On first installation it downloads the pinned,
checksum-verified Doorstop loader from this repository's v1.1 release, compiles
the Steam launcher locally with Apple's command-line tools, downloads the
official UMM package, installs the UMM runtime, and creates a terminal launcher
next to the game:

```text
run_adofai_umm_macos.sh
```

The installer also backs up the original universal game executable and places
a reversible Intel launcher at its bundle entry point. Press **Control+F10**
in the game to open the UMM window. On a Mac keyboard where F10 controls audio, press
**Control+Fn+F10** instead.

## Launch modded from Steam

No custom Steam launch option is used. If an older installer configured one,
quit Steam completely and run:

```bash
./configure_adofai_steam_launch.sh enable
```

Then reopen Steam and launch ADOFAI normally. Steam launches the original app
bundle, while the in-bundle launcher enables the mods without breaking its
Steamworks context.

To remove any custom launch option without checking the mod installation, run:

```bash
./configure_adofai_steam_launch.sh disable
```

The configurator creates a timestamped backup of Steam's `localconfig.vdf`
before every change.

## Add another UMM mod

Unpack the mod first. Its folder must contain `Info.json`, then run:

```bash
./setup_adofai_umm_macos.sh add-mod --mod "/full/path/to/UnpackedMod"
```

You can also install a ZIP directly and manage installed mods:

```bash
./setup_adofai_umm_macos.sh install-zip --zip "$HOME/Downloads/SomeMod.zip"
./setup_adofai_umm_macos.sh list-mods
./setup_adofai_umm_macos.sh disable-mod --mod-id SomeMod
./setup_adofai_umm_macos.sh enable-mod --mod-id SomeMod
./setup_adofai_umm_macos.sh remove-mod --mod-id SomeMod
```

## Build a DMG or publish a release

Run `./create_dmg.sh` to create `dist/ADOFAI-Mod-Installer.dmg`. Tagged GitHub
releases are built automatically by `.github/workflows/release.yml`. An unsigned
build works without secrets. For a Gatekeeper-ready public release, configure
the repository secrets `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`,
`KEYCHAIN_PASSWORD`, `DEVELOPER_ID_APPLICATION`, `APPLE_ID`,
`APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`. Apple Developer membership
is required for Developer ID signing and notarization.

## Optional Mac AutoPlay cheat mod

The repository includes source for an experimental macOS-native autoplay mod.
It wraps ADOFAI's own cross-platform autoplay mode and uses no Windows APIs.
Autoplay defaults to off and can be toggled with F8. Build and install it with:

```bash
./build_mac_autoplay.sh --install
```

Use it only for local/custom-level testing, not to misrepresent scores, clears,
achievements, or competitive play.

## Check the installation

```bash
./setup_adofai_umm_macos.sh doctor
```

## Remove the loader

```bash
./setup_adofai_umm_macos.sh uninstall
```

Uninstalling preserves the `Mods` directory and moves the loader to a dated
backup folder rather than deleting it permanently.

## Notes

- The game is deliberately launched as x86_64. This avoids the older
  Harmony/MonoMod native ARM64 detour failure on Apple Silicon.
- The install and uninstall actions back up and restore the app's original
  universal executable. Steam updates may restore it first; rerun the installer
  after an update if the doctor reports that the bundle launcher is missing.
- The installer does not replace ADOFAI's `System.Xml.dll` or patch
  `Assembly-CSharp.dll`.
- This is an experimental native path because UMM itself does not ship an
  official macOS installer.
