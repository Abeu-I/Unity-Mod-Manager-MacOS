# Mac AutoPlay

An experimental, macOS-compatible UMM cheat mod for ADOFAI. It uses ADOFAI's
own cross-platform `RDC.auto` gameplay mode and does not simulate keyboard
input or call Windows DLLs.

- Autoplay defaults to off.
- Press F8 or use the UMM settings checkbox to toggle it.
- Disabling the mod forces autoplay off.
- Use it only for local/custom-level testing. Do not use it to misrepresent
  scores, clears, achievements, or competitive play.

Build and install it from the repository root with:

```bash
./build_mac_autoplay.sh --install
```

The build requires Mono's `mcs` compiler (`brew install mono`).
