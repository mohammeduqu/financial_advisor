# Tadbeer / تدبير branding

The approved identity is the **filled mint wallet with a gold compartment on a blue-to-teal gradient**. The user approved this preview before its application.

## Source and assets

- `assets/branding/source/tadbeer-filled-blue-teal-approved.png`: exact approved opaque artwork, copied without modifications.
- `assets/branding/source/tadbeer-filled-generation-prompts.json`: built-in image generation prompt record.
- `assets/branding/tadbeer-icon-1024.png`: 1024 px master.
- `assets/branding/tadbeer-logo.png` plus `2.0x/`, `3.0x/`, `4.0x/`: Flutter 64/128/192/256 px variants.
- `assets/branding/icon-preview.png`: current platform previews and actual small exports.
- `assets/branding/icon-manifest.json`: all 47 exported images and Android resource paths.
- `lib/widgets/tadbeer_logo.dart`: shared logo in onboarding and the dashboard.

The source artwork was produced with the built-in image generation tool. Standard color exports are direct resizes of the approved image. The exporter does not read any experimental cutouts; the wallet face remains fully opaque.

## Platform behavior

Android legacy launcher icons are 48/72/96/144/192 px. Adaptive color layers place the entire approved image inside the central 72 dp viewport of a 108 dp layer, with transparent padding outside the artwork only. A blue-to-teal gradient drawable fills the outer background. Keeping the approved color artwork intact avoids introducing holes or altering its design. Android 13 themed icons use a separate filled-wallet vector silhouette, so the square color-image alpha does not become the themed icon.

iOS uses all 15 opaque RGB catalog PNGs, including the 1024 px store icon. Web includes regular and maskable 192/512 px icons, a 180 px Apple touch icon, 16/32/48 px favicons and ICO. Maskable exports extend the approved background edge pixels before resizing to keep the wallet inside the safe area. macOS uses its seven catalog PNGs; Windows uses a multi-size ICO.

The logo's background is blue-to-teal. The app's existing dark UI canvas and web theme colors remain the same. English/Arabic names, package IDs, binary names, preferences and existing financial records are unaffected.

## Regenerate

With Python and Pillow installed, from the Flutter project:

```powershell
python tools/generate_app_icons.py
```

The script performs size conversion and platform padding only. Flutter bundles just its runtime logo variants. The preceding icon set and exporter are backed up in `output/branding-backup-20260918-filled/`.

## Platform references

- [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
- [Apple app icon asset catalogs](https://developer.apple.com/documentation/xcode/configuring-your-app-icon/)
- [Web maskable icon safe area](https://web.dev/articles/maskable-icon)

Native Apple builds require macOS/Xcode. An installed launcher may cache its old icon until the updated app is installed and relaunched; clearing financial data is unnecessary.
