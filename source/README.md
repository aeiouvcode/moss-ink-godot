# Moss / Ink - Field Study 03 (Godot)

A dithered 3D island rebuilt as a real Godot 4 world and exported for the web. Layered soil strata, hanging roots, rocks, a fallen log, modeled flowers, shrubs and grass, lit per pixel by a movable sun and printed in five inks.

Sibling of the WebGL study: https://github.com/aeiouvcode/moss-ink

## How the ink works

- Every surface is lit per pixel (sun, soft sky term, cast shadows), then quantised to five inks: deep, mid, ash, fog, lift. One berry signal color marks a few flowers and fruit.
- The dither threshold is anchored to the surface, not the screen. Each pixel reads an 8x8 Bayer pattern from its rest-pose world position, and the pattern scale follows the pixel's footprint in power-of-two octaves. Dots stay attached to the world while the camera orbits, instead of swimming.
- Wind bends stems, grass, roots and shrubs in the vertex shader; the dither follows the rest pose so swaying plants keep their dots.

## Field instrument

Seed, canopy density, solar angle and wind shape the field. State lives in the address (`?s=moss41&d=62&l=38&w=34`, same format as the WebGL study), so a field can be reopened exactly. Tap the moss to germinate a new stem. No accounts, network calls, analytics or storage.

## Build

Godot 4.7.2, Compatibility renderer. Web export preset `Web` (single-threaded, so it runs on plain static hosting without cross-origin isolation headers).

```sh
godot --headless --export-release Web build/web/index.html
cd build/web && python3 -m http.server 8000
```

Fonts: Instrument Serif and IBM Plex Mono, both under the SIL Open Font License (see `fonts/`).
