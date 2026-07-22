# Research: explicit Unicode/glyph frame sequences for Pi terminal working indicators

## Summary

The strongest font-specific choice is Nerd Fonts 3.4.0’s newly bundled six-frame Fira Code spinner (`U+EE06…U+EE0B`): it is a genuine frame family, not one icon that needs geometric rotation. For portability beyond Nerd Fonts, `cli-spinners` supplies mature, explicit MIT-licensed frame arrays; Braille `dots`/`dots2`, geometric `circleHalves`, block `boxBounce2`, and ASCII `line` are the best compact candidates. Standard Nerd Font icons named *spinner/loading/sync* are generally static outlines whose web demos animate them with CSS, so they are not substitutes for Pi’s required string frames.

## Findings

### Ranked catalog

1. **Nerd Fonts/Fira Code progress spinner — best match when Nerd Fonts 3.4.0 is guaranteed.**
   - Exact frames (6): `['\uEE06','\uEE07','\uEE08','\uEE09','\uEE0A','\uEE0B']` (`     `). Suggested interval from Fira Code’s own demo: **200 ms**.
   - Nerd Fonts’ v3.4.0 helper explicitly names these `progress_spinner_1` through `_6`, while `U+EE00…U+EE05` are six **bar-state components** (empty/full left/middle/right), not spinner frames. [Nerd Fonts v3.4.0 mapping](https://github.com/ryanoasis/nerd-fonts/blob/v3.4.0/bin/scripts/lib/i_extra.sh#L1-L20) The upstream Fira Code demo constructs exactly the six-character array and cycles it with `mod i 6`. [Fira Code demo, pinned commit](https://github.com/tonsky/FiraCode/blob/7e5bff99c479b731eb18d528320f8bca98a6ac19/script/progress.clj#L3-L34)
   - **In Nerd Fonts 3.4.0: yes, explicitly.** The 3.4.0 changelog says “Add Progress Indicators a la Fira Code” and notes the bugfix release is mainly for those glyphs. [NF 3.4.0 changelog](https://github.com/ryanoasis/nerd-fonts/blob/v3.4.0/changelog.md#v340)
   - License: the Fira Code font design is **SIL OFL 1.1**; Nerd Fonts says patched/glyph fonts are OFL 1.1 and source scripts are MIT. [Fira Code license](https://github.com/tonsky/FiraCode/blob/7e5bff99c479b731eb18d528320f8bca98a6ac19/LICENSE) [Nerd Fonts v3.4.0 license](https://github.com/ryanoasis/nerd-fonts/blob/v3.4.0/LICENSE)
   - Tradeoff: these are Private Use Area characters and will be tofu/wrong glyphs without a font containing this exact mapping.

2. **`cli-spinners` `dots` — best broadly supported compact terminal sequence.**
   - Exact frames (10, **80 ms**): `['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏']` = `[U+280B,U+2819,U+2839,U+2838,U+283C,U+2834,U+2826,U+2827,U+2807,U+280F]`. [Pinned `spinners.json`](https://github.com/sindresorhus/cli-spinners/blob/82c51d1e9d07e0cf95247479414d52b67d4cf019/spinners.json#L2-L17)
   - **In Nerd Fonts 3.4.0: not as a Nerd Fonts bundled icon sequence.** These are standard Unicode Braille Patterns (`U+2800…U+28FF`); coverage comes from the Nerd Font’s source/fallback font and therefore is not guaranteed by the NF icon patch. Unicode assigns the full Braille block. [Unicode Braille chart](https://www.unicode.org/charts/PDF/U2800.pdf)
   - License/provenance: the literal frame dataset is published by `cli-spinners` under **MIT**. [Pinned license](https://github.com/sindresorhus/cli-spinners/blob/82c51d1e9d07e0cf95247479414d52b67d4cf019/license)

3. **`cli-spinners` `dots2` — best denser Braille wheel.**
   - Exact frames (8, **80 ms**): `['⣾','⣽','⣻','⢿','⡿','⣟','⣯','⣷']` = `[U+28FE,U+28FD,U+28FB,U+28BF,U+287F,U+28DF,U+28EF,U+28F7]`. [Pinned `spinners.json`](https://github.com/sindresorhus/cli-spinners/blob/82c51d1e9d07e0cf95247479414d52b67d4cf019/spinners.json#L18-L31)
   - **NF 3.4.0 status:** same as `dots`: standard Unicode inherited/fallback coverage, not a bundled Nerd Fonts sequence. License: `cli-spinners` MIT; Unicode’s code chart/data terms are the Unicode License v3. [Unicode license](https://www.unicode.org/license.txt)

4. **`cli-spinners` `circleHalves` — clearest non-Braille rotation illusion.**
   - Exact frames (4, **50 ms**): `['◐','◓','◑','◒']` = `[U+25D0,U+25D3,U+25D1,U+25D2]`. This is a genuine four-string sequence; no rendering transform is needed. Nearby alternative `circleQuarters` is `['◴','◷','◶','◵']` = `[U+25F4,U+25F7,U+25F6,U+25F5]` at 120 ms. [Pinned sequence](https://github.com/sindresorhus/cli-spinners/blob/82c51d1e9d07e0cf95247479414d52b67d4cf019/spinners.json#L852-L868)
   - **NF 3.4.0 status:** standard Unicode geometric shapes, not guaranteed by the icon patch. License: `cli-spinners` MIT.

5. **`cli-spinners` `boxBounce2` — simplest solid block rotation.**
   - Exact frames (4, **100 ms**): `['▌','▀','▐','▄']` = `[U+258C,U+2580,U+2590,U+2584]`. [Pinned sequence](https://github.com/sindresorhus/cli-spinners/blob/82c51d1e9d07e0cf95247479414d52b67d4cf019/spinners.json#L787-L795) Unicode defines these in Block Elements. [Unicode Block Elements chart](https://www.unicode.org/charts/PDF/U2580.pdf)
   - **NF 3.4.0 status:** standard Unicode, not a bundled NF sequence; actual coverage depends on source/fallback font. License: `cli-spinners` MIT.

6. **`cli-spinners` `line` — safest fallback.**
   - Exact frames (4, **130 ms**): `['-','\\','|','/']` = `[U+002D,U+005C,U+007C,U+002F]`. [Pinned sequence](https://github.com/sindresorhus/cli-spinners/blob/82c51d1e9d07e0cf95247479414d52b67d4cf019/spinners.json#L623-L631)
   - **NF 3.4.0 status:** ordinary ASCII, independent of Nerd Fonts and effectively universal. License: `cli-spinners` MIT.

### Static icons that should be excluded

7. **Font Awesome/Nerd Fonts `fa-spinner`, `fa-circle-notch`, rotate/sync icons are single glyphs, not frame sets.** Font Awesome’s own animation stylesheet applies a `0deg → 359deg` CSS transform to one icon for both `fa-spin` and stepped `fa-pulse`; it does not swap Unicode strings. [Font Awesome v4.7 animation source](https://github.com/FortAwesome/Font-Awesome/blob/v4.7.0/scss/_animated.scss#L4-L34) Thus even where Nerd Fonts 3.4.0 includes the static Font Awesome glyph (for example `fa-spinner` is historically `U+F110` and `fa-circle-notch` `U+F1CE`), Pi cannot animate it without external rotation or separately drawn frames.

8. **Material Design Icons `loading` is likewise static/CSS-rotated.** The upstream preview combines one `mdi-loading` glyph with class `mdi-spin`; the same class is demonstrated on an arbitrary star, proving the motion is a CSS effect rather than alternate glyphs. [MDI preview](https://github.com/Templarian/MaterialDesign-Webfont/blob/master/preview.html) It may be bundled statically in NF’s Material Design set, but it is **not** a usable explicit multi-frame sequence.

9. **The Fira/NF family is categorically different.** Its six spinner glyphs were individually drawn/named and the upstream program indexes six codepoints. This is the only primary-source icon-font family found that is both purpose-built as a spinner state sequence and explicitly confirmed in Nerd Fonts 3.4.0. The six adjacent progress-bar glyphs are genuine discrete states/components too, but they represent determinate bar construction rather than a one-cell indeterminate working loop.

## Practical recommendation

Use the NF/Fira sequence when the application can assert Nerd Fonts `>=3.4.0`; otherwise default to `dots` and offer `line` as an ASCII fallback. Keep each frame as an explicit Pi Unicode string and preserve the listed intervals. Avoid emoji sequences for this use: presentation selectors and double-cell width make terminal replacement less predictable.

## Sources

- Kept: [Nerd Fonts v3.4.0 `i_extra.sh`](https://github.com/ryanoasis/nerd-fonts/blob/v3.4.0/bin/scripts/lib/i_extra.sh) — authoritative release-tagged names/codepoints and NF version.
- Kept: [Nerd Fonts v3.4.0 changelog](https://github.com/ryanoasis/nerd-fonts/blob/v3.4.0/changelog.md) — confirms introduction in 3.4.0.
- Kept: [Fira Code `progress.clj`, pinned](https://github.com/tonsky/FiraCode/blob/7e5bff99c479b731eb18d528320f8bca98a6ac19/script/progress.clj) — primary executable evidence of the exact six-frame cycle and timing.
- Kept: [`cli-spinners` `spinners.json`, pinned](https://github.com/sindresorhus/cli-spinners/blob/82c51d1e9d07e0cf95247479414d52b67d4cf019/spinners.json) — primary raw frame arrays and intervals (package version 3.4.0 at this commit).
- Kept: [Unicode Braille](https://www.unicode.org/charts/PDF/U2800.pdf) and [Block Elements](https://www.unicode.org/charts/PDF/U2580.pdf) charts — authoritative standard assignments.
- Kept: [Font Awesome animation SCSS, v4.7.0](https://github.com/FortAwesome/Font-Awesome/blob/v4.7.0/scss/_animated.scss) and [MDI preview](https://github.com/Templarian/MaterialDesign-Webfont/blob/master/preview.html) — direct proof that common loading icons rely on CSS rotation.
- Dropped: third-party spinner packages duplicating `cli-spinners` — redundant and weaker provenance.
- Dropped: Nerd Fonts cheat-sheet mirrors and generated language packages — useful discovery aids, but the tagged Nerd Fonts mapping is more authoritative.
- Dropped: emoji/moon/clock sequences from `cli-spinners` — genuine sequences, but unstable terminal width/presentation makes them lower quality for Pi’s indicator.

## Gaps / residual risks

- **Medium:** Nerd Fonts does not promise that every patched source font has every standard Braille/geometric/block Unicode glyph; fallback behavior must be tested in Pi’s actual terminal/font stack. Only `U+EE06…U+EE0B` is explicitly supplied by the NF 3.4.0 patch.
- **Medium:** PUA glyph widths/appearance may vary between proportional, Mono, and Propo Nerd Font builds; visually validate the exact installed font and terminal cell width.
- **Low:** The MDI preview link tracks `master`, not an immutable commit; its CSS-rotation evidence is clear, but a pinned upstream revision would improve archival stability.
- **Low:** Licensing above covers the sourced font/data artifacts and frame dataset; it is not legal advice. A project shipping font binaries must retain the applicable OFL notices.

## Acceptance

Research artifact only; no project files were edited and no tests were warranted. Findings include stable/release-pinned file paths and severity-tagged residual risks.