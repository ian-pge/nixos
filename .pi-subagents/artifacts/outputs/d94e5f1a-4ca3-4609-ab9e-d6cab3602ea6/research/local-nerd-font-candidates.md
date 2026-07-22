# Code Context

## Files Retrieved
1. `/nix/store/xfgcrc59dijia0wqxv5lxfpg1234mipg-nerd-fonts-jetbrains-mono-3.4.0+2.304/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf` (font tables: `cmap`, `hmtx`, `glyf`, `head`) — the actual primary font selected by `fc-match`; Nerd Fonts 3.4.0 / JetBrains Mono 2.304.
2. `https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.4.0/glyphnames.json` (`METADATA` and matching glyph records) — authoritative same-version Nerd Fonts names and codepoints (downloaded to `/tmp/glyphnames.json` for inspection).
3. `home_manager/hyprland/ghostty.nix` (line 14) — config identifies `JetBrainsMono Nerd Font` as the terminal font family.
4. `home_manager/shared/zed.nix` (lines 116 and 135) — other local consumers of the same primary family.

## Key Code

### Ranked coherent animation sequences

| Rank | Candidate | Exact glyph names / codepoints | Frames | All in current primary? | Measured metrics and risk |
|---|---|---|---:|---|---|
| 1 | Material Design clock face (filled) | `md-clock_time_one` U+F143F, `two` U+F1440, `three` U+F1441, `four` U+F1442, `five` U+F1443, `six` U+F1444, `seven` U+F1445, `eight` U+F1446, `nine` U+F1447, `ten` U+F1448, `eleven` U+F1449, `twelve` U+F144A | **12** | Yes, all 12 | Every frame advance 600, LSB 0, identical bbox `(0,-56)-(832,776)`. Stable frame-to-frame, but ink is 832 units wide against a 600-unit advance and can overhang/clip or touch adjacent text in a strict one-cell renderer. Best smooth rotational sequence if visual testing confirms no clipping. Order 1→12 is clockwise; starting at 12 then 1…11 may read more naturally. |
| 2 | Material Design clock face (outline) | `md-clock_time_one_outline` U+F144B, `two_outline` U+F144C, `three_outline` U+F144D, `four_outline` U+F144E, `five_outline` U+F144F, `six_outline` U+F1450, `seven_outline` U+F1451, `eight_outline` U+F1452, `nine_outline` U+F1453, `ten_outline` U+F1454, `eleven_outline` U+F1455, `twelve_outline` U+F1456 | **12** | Yes, all 12 | Same exact 600 advance / LSB 0 / `(0,-56)-(832,776)` bbox on every frame. Same overhang risk; outline likely reads as a conventional spinner and changes less visual mass than the filled set. |
| 3 | Material Design circle slices | `md-circle_slice_1` U+F0A9E through `md-circle_slice_8` U+F0AA5 (suffixes 1–8 in ascending contiguous codepoint order) | **8** | Yes, all 8 | Every frame advance 600, LSB 0, identical bbox `(0,-56)-(832,776)`. Very coherent determinate fill animation and frame geometry is stable, but this is fill-up/reset rather than continuous rotation. Same 832/600 horizontal overhang risk. |
| 4 | Extra progress spinner | `extra-progress_spinner_1` U+EE06, `_2` U+EE07, `_3` U+EE08, `_4` U+EE09, `_5` U+EE0A, `_6` U+EE0B | **6** | Yes, all 6 | All advances exactly 600 and all ink stays inside the cell. Bboxes vary as the moving stroke traverses the cell: `(94,521)-(506,652)`, `(299,214)-(592,652)`, `(224,69)-(592,567)`, `(9,69)-(591,361)`, `(9,69)-(376,567)`, `(9,214)-(300,652)`. Lowest clipping/overlap risk and explicitly designed as a spinner, but only six frames and the changing bbox/visual centroid may look slightly uneven. |
| 5 | Material Design hexagon slices | `md-hexagon_slice_1` U+F0AC3 through `md-hexagon_slice_6` U+F0AC8 (suffixes 1–6) | **6** | Yes, all 6 | Every frame advance 600, LSB 0, identical bbox `(0,-56)-(750,776)`. Stable but still 150 units wider than advance; moderate overhang risk. A fill/reset animation, less smooth than the 8-frame circle. |

### Other systematic matches considered

- Font Awesome hourglass gives only a **4-stage** usable progression: `fa-hourglass_o` U+F250 → `fa-hourglass_1`/`fa-hourglass_start` U+F251 → `fa-hourglass_2`/`fa-hourglass_half` U+F252 → `fa-hourglass_3`/`fa-hourglass_end` U+F253. Aliases do not add frames.
- Directional arrow/chevron families can form 4-frame rotations, but are less spinner-like and have fewer frames.
- `md-loading` U+F0772, `fa-spinner` U+F110, `md-orbit` U+F0018, `md-orbit_variant` U+F15DB, refresh/sync/rotate icons, dots/ellipsis, timer icons, and progress-status icons are isolated static glyphs, not multi-frame source sequences. CSS icon fonts may normally rotate a single loading glyph, but Pi `setWorkingIndicator` needs explicit characters.
- Numeric circle sets offer 10–11 labels, but animate changing numbers rather than coherent motion and are therefore not recommended over the 12 clock hands.

## Architecture

`fc-match 'JetBrainsMono Nerd Font'` resolves to the non-`Mono` patched `JetBrainsMonoNerdFont-Regular.ttf`. Fontconfig reports `spacing=100` (monospaced), and direct `hmtx` inspection confirms every shortlisted character has a 600-unit advance. However, Nerd Fonts' non-`Mono` variant preserves oversized icon outlines: the Material Design candidates have ink bboxes wider than their advance. Thus terminal cursor/cell progression should remain one cell, while rasterizers may permit overlap, clip to a cell, or visually crowd following text. The six `extra-progress_spinner_*` glyphs are the only shortlisted set whose measured ink fits wholly inside its 600-unit cell.

The names/codepoints were selected by systematically filtering Nerd Fonts v3.4.0 metadata for `spinner`, `loading`, `progress`, `circle`, `slice`, `rotate`, `timer`, `clock`, `dots`, `orbit`, `ellipsis`, `hourglass`, `sync`, `refresh`, `loader`, and `motion`, then verifying every proposed codepoint against the installed font's `cmap`. Metrics came from its `hmtx` and `glyf` tables.

## Recommendation

1. Try the **12 outline clock frames** first: maximum frame count, obvious clockwise motion, stable geometry.
2. If the Pi UI clips or crowds these oversized Material glyphs, use **`extra-progress-spinner` (6 frames)**: it is purpose-built and provably cell-contained.
3. Use **circle slices (8)** when a fill/pulse semantics is acceptable; it is smoother than six frames but resets visibly.

A practical clock order is U+F1456 (twelve outline), then U+F144B..U+F1455 (one through eleven outline), avoiding a semantic jump at loop boundaries.

## Start Here

Open the installed `JetBrainsMonoNerdFont-Regular.ttf` listed above with a glyph viewer and preview U+F144B–U+F1456 in the actual Pi terminal/UI. The remaining uncertainty is renderer-specific clipping, not font presence or advance consistency.

## Residual risks

- **medium:** The primary family is the non-`Mono` Nerd Font variant; Material glyph ink exceeds its 600-unit advance. Actual clipping/overlap depends on Pi's renderer and surrounding indicator text.
- **low:** Font fallback or a different weight/style selected at runtime could alter outlines; this inspection attests Regular, which `fc-match` currently selects.
- **low:** Metadata establishes intended sequence naming but not animation timing/direction; visual cadence should be checked manually (roughly 70–120 ms/frame is a reasonable starting range).

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Concrete same-version metadata and installed-font cmap/hmtx/glyf findings are reported with exact source paths, codepoints, frame counts, measured advances/bboxes, rankings, and severity-tagged residual risks."
    }
  ],
  "changedFiles": [],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "fc-match 'JetBrainsMono Nerd Font' and fc-query",
      "result": "passed",
      "summary": "Resolved the primary Regular TTF and confirmed fontconfig monospacing (spacing=100) and charset coverage."
    },
    {
      "command": "curl Nerd Fonts v3.4.0 glyphnames.json; Node keyword/filter inspection",
      "result": "passed",
      "summary": "Systematically enumerated matching names/codepoints from same-version upstream metadata."
    },
    {
      "command": "fontTools ttx dumps of cmap, hmtx, head, and glyf",
      "result": "passed",
      "summary": "Verified all shortlisted glyphs are present and measured their 600-unit advances, bearings, and bounding boxes."
    }
  ],
  "validationOutput": [
    "All 44 shortlisted sequence glyphs (12 filled clocks, 12 outline clocks, 8 circle slices, 6 extra spinners, 6 hexagon slices) occur in the installed primary font.",
    "Every shortlisted glyph has advance width 600; extra spinner ink remains in-cell, while Material sequences overhang horizontally."
  ],
  "residualRisks": [
    "medium: Renderer-specific clipping/overlap remains for Material glyph bboxes wider than their 600-unit advance.",
    "low: Runtime selection of another weight/style or fallback font was not exercised.",
    "low: Animation cadence and perceived direction require visual UI testing."
  ],
  "noStagedFiles": true,
  "diffSummary": "No repository files edited; one requested research artifact was written outside tracked source files.",
  "reviewFindings": [
    "medium: installed JetBrainsMonoNerdFont-Regular.ttf - Material clock/circle glyph ink widths (750–832 units) exceed the 600-unit cell advance and may clip or overlap.",
    "no blockers: all ranked candidate frames are present and have consistent advances."
  ],
  "manualNotes": "The six extra-progress-spinner frames are the safest fallback because their ink is entirely within the cell."
}
```
