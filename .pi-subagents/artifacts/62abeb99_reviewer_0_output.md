## Review
- **Correct:** `Bar.qml:376-393` exposes `itemSize`/`phase` matching shader uniforms and resolves the generated `.qsb`.
- **Correct:** `activity-border.frag:19-98` uses consistent pixel coordinates, continuous clockwise rounded-rectangle path math, std140-compatible uniforms, and correctly premultiplies RGB by alpha at line 98.
- **Correct:** `quickshell.nix:2-9` includes `qtshadertools`, copies to writable output, and invokes supported `qsb --qt6`.
- **Blocker:** None.
- **Note:** Full Nix derivation and runtime visual rendering were not exercised.