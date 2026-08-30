# ADOFAI + Unity Mod Manager on macOS (no Wine)

This setup runs the Intel slice of A Dance of Fire and Ice through Apple's
Rosetta 2 and uses a small native in-bundle launcher to inject the macOS
`UnityDoorstop` 4 library patched for Unity 6 universal Mach-O files. The
launcher keeps Steam's original app launch and process ID, so the Steam
overlay, Workshop, playtime, and achievements stay connected. Doorstop starts
Unity Mod Manager's managed runtime, which loads ordinary mods from
`Mods/<mod-id>/Info.json`.

It does **not** use Wine, Whisky, CrossOver, or disable System Integrity
Protection.

## Install

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

The repository is source-only. On first installation it compiles Doorstop and
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
