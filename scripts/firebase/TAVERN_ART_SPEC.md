# The Tavern — Environment Art Spec (`tavern_env_atlas.png`)

Target fidelity: the warm, dense, hand-authored tavern reference (plaster-and-timber
walls, arched green-glass windows, stone hearth, laden tables). Characters already
exist (`patrons_anim.png`, 35×34 frames) — **this spec covers environment + furniture only.**

## Ground rules

- **1 art pixel = 1 atlas pixel.** The engine renders a 528×340 world at 2× display
  scale. Author art at exactly the cell sizes below — no upscaling, no mixed density.
- **Palette**: warm browns for wood (shadows lean purple, highlights lean yellow),
  desaturated plaster `#c9b088`, green window glass `#3a4a3c`, stone `#493c58` ramp,
  candle gold `#e8b74a`/`#ffdf8c`, accent red `#8f2b33`. Keep total palette ≤ 48 colors.
- **Outlines**: 1px, dark warm (`#1a0f14`), selective — soften on interior details.
- **Light source**: ambient top-left + warm local light from candles/hearth.
  Bake subtle top highlights (1–2px) on every horizontal surface.
- Transparent background (PNG-32). No drop shadows in the art — the engine draws
  ground shadows and glows.

## Atlas layout (one PNG, cells at exact rects)

| Cell | x,y | w×h | Notes |
|---|---|---|---|
| floor_tile | 0,0 | 64×32 | seamless plank block, horizontal boards ~10px tall, staggered seams, knots, subtle sheen |
| wall_tile | 64,0 | 64×64 | plaster upper 2/3 + timber posts, seamless horizontally; bottom 16px = wainscot zone |
| wainscot | 128,0 | 64×16 | dark timber band w/ panel divisions, tiles horizontally |
| window | 192,0 | 72×52 | arched, green leaded glass, timber frame + sill, faint moonlight |
| hearth_f0–f3 | 264,0 / 352,0 / 440,0 / 0,64 | 88×64 each | stone chimney breast, arched firebox, mantel + clutter; 4 fire animation frames |
| shelf | 88,64 | 88×40 | two shelves: bottles top, mugs/jars below |
| banner | 176,64 | 64×44 | red banner, gold trim + emblem, pennant bottom edge |
| trophy | 240,64 | 40×44 | mounted shield + crossed blades (or antlers) |
| painting | 280,64 | 56×40 | framed dragon painting |
| lantern_f0–f1 | 336,64 / 352,64 | 16×24 each | wall lantern, 2 flicker frames |
| door | 368,64 | 40×52 | plank door + iron handle (terrace) |
| stairs | 408,64 | 64×52 | stone steps, top-down oblique |
| kitchen_pass | 472,64 | 56×40 | stone pass-through window |
| table_2top | 0,128 | 32×34 | tabletop + skirt in oblique view; 8px overhang for props baked or left clean |
| table_4top | 32,128 | 52×36 | as above, longer |
| banquet | 84,128 | 44×84 | vertical long table |
| communal | 128,128 | 90×38 | long horizontal trestle |
| nook | 218,128 | 24×50 | small wall table, vertical |
| bar | 242,128 | 84×38 | counter w/ front panelling, mugs on top |
| bench | 326,128 | 46×18 | backless bench |
| barrel | 372,128 | 18×24 | oak barrel, iron bands |
| crate | 390,128 | 20×22 | wooden crate |
| plant | 410,128 | 18×30 | potted plant |
| rug | 428,128 | 60×38 | bordered rug w/ center motif (engine stretches for resize — keep border simple) |
| torchere | 488,128 | 14×34 | standing candelabra, 3 candles |
| chair_back | 0,212 | 14×12 | chair seen from behind (above table) |
| chair_front | 14,212 | 14×14 | chair facing camera (below table) |
| props_food | 28,212 | 80×20 | strip: mug, plate w/ food, candle, roast bird, jug (engine scatters on tables) |

Minimum sheet size: **528×256**.

## Wood finish variants (optional, recommended)

The builder lets owners respec furniture finish (oak / walnut / ebony). Either:
1. author furniture cells in oak and allow the engine's hue-remap, or
2. provide 3 full furniture rows (append below y=232) — best quality.

## Generation prompts (if using an AI pipeline)

Per cell group, render at the EXACT pixel dimensions (or an integer multiple, then
downscale with nearest-neighbor):

> "16-bit pixel art, top-down oblique tavern <ITEM>, warm candlelit palette,
> dark 1px outlines, plaster-and-timber medieval interior style, hue-shifted
> shadows toward purple, highlights toward warm yellow, transparent background,
> no anti-aliasing against background, <W>×<H> pixels"

Assemble cells into the atlas at the coordinates above (any image editor;
the engine reads fixed rects).

## Drop-in test

Place `tavern_env_atlas.png` next to `tavern_live_mockup.html` and reload —
the HUD badge flips to "ENV ATLAS: loaded ✓" and every mapped cell replaces
the fallback art. Missing/incomplete cells keep falling back per-cell, so the
sheet can be filled incrementally.
