# Research: Qt 6 / Qt Quick animation frame pacing on mixed-refresh Wayland

## Summary

The strongest explanation is not that rendering is necessarily capped at 60 FPS, but that ordinary QML animations (`NumberAnimation`, including one inside a `Behavior`) are advanced on the GUI thread and Qt deliberately falls back to a roughly 16 ms system-timer driver when more than one `QQuickWindow` is visible. A Quickshell configuration commonly creates one `PanelWindow` per output, so a 120 Hz + 165 Hz setup naturally enters the multi-window path; many rendered frames can therefore repeat the same property value and look approximately 60 FPS even if the compositor and swapchains present faster. Qt 6.5+'s `QSG_USE_SIMPLE_ANIMATION_DRIVER=1`, fewer visible windows, scene-graph `Animator` types where applicable, and avoiding live window resizing are the most evidence-backed experiments/workarounds.

## Findings

1. **Critical — multiple visible Qt Quick windows force ordinary animations away from render-synchronized pacing.** Qt's official scene-graph documentation says the threaded loop installs a GUI-thread driver for ordinary animations such as `NumberAnimation` and a render-thread driver for `Animator` types. It also says the ideal smooth case requires **exactly one** on-screen `QQuickWindow`; with more than one, multiple render threads/sync points make a stable presentation-driven GUI animation clock impossible, so Qt transparently falls back to the system-timer mechanism used by the basic loop. That default timer is documented as typically 16 ms, which yields only about 62.5 property samples/second—visually close to a 60 FPS cap on both 120 and 165 Hz outputs. [Qt Quick Scene Graph: Driving Animations](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html#driving-animations) and [multiple-window section](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html#what-if-there-is-no-or-more-than-one-window-visible)

2. **High — Quickshell's normal multi-monitor pattern creates precisely this condition.** Quickshell's `Variants` documentation says each model value creates a delegate instance and explicitly points to using it to create copies of a window per screen. `PanelWindow` is a `QsWindow`, i.e. a real decorationless shell window. Thus two visible per-screen panels are enough to trigger Qt's multi-`QQuickWindow` timer fallback even if only one panel is visibly animating. [Quickshell `Variants`](https://quickshell.outfoxxed.me/docs/types/Quickshell/Variants/) [Quickshell `PanelWindow`](https://quickshell.outfoxxed.me/docs/types/Quickshell/PanelWindow/)

3. **High — the legacy/default threaded animation driver is initialized from the primary screen, not each window's current screen.** Current Qt source in `qtdeclarative/src/quick/scenegraph/qsgcontext.cpp` constructs `QSGAnimationDriver` from `QGuiApplication::primaryScreen()->refreshRate()` and computes `m_vsync = 1000 / refreshRate` (falling back to 60 Hz if bogus). The same source comments that the elapsed-timer alternative is correct on a secondary screen with a different refresh rate and is not tied to the primary screen. On a 120/165 pair, primary-screen selection, moving windows, and per-surface Wayland callbacks can therefore make the assumed animation increment disagree with actual presentation cadence in the single-window/default-driver case; in the usual multi-window Quickshell case, finding 1 remains more directly applicable. [Qt source, `qsgcontext.cpp` lines 85–104 and 234–257](https://codebrowser.dev/qt6/qtdeclarative/src/quick/scenegraph/qsgcontext.cpp.html#85)

4. **High — `NumberAnimation`/`Behavior` is not a render-thread animation.** `NumberAnimation` is a regular `PropertyAnimation`; placing it in `Behavior on width/x/...` does not change its driver or thread. Qt documents that `Animator` types instead operate directly on scene-graph primitives and can continue on the render thread even if the UI thread blocks. Available practical substitutions include `XAnimator`, `YAnimator`, `OpacityAnimator`, `ScaleAnimator`, and `RotationAnimator`; width/height/layout have no equivalent Animator and must still update GUI/QML state. Animator values also do not update the QML property during the animation, which may affect bindings/hit testing. [Animator QML type](https://doc.qt.io/qt-6/qml-qtquick-animator.html) [NumberAnimation QML type](https://doc.qt.io/qt-6/qml-qtquick-numberanimation.html)

5. **High — GUI-thread work can turn regular-animation sampling into irregular motion even when GPU rendering is cheap.** In the threaded loop, scene synchronization blocks the GUI thread, while ordinary QML animation and binding/layout work occurs there; a missed frame is intentionally not immediately caught up by the default driver because Qt's source says catching up would introduce a second visible distortion. Expensive JavaScript, binding reevaluation, layout/polish, synchronous I/O/image work, or several windows synchronizing can therefore cause repeated values followed by uneven jumps. Scene-graph Animators isolate only the supported transform/opacity cases; Qt recommends asynchronous work rather than relying on Animator to mask GUI stalls. [Qt threaded frame sequence](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html#threaded-render-loop-threaded) [Qt source, skip handling in `qsgcontext.cpp` lines 160–190](https://codebrowser.dev/qt6/qtdeclarative/src/quick/scenegraph/qsgcontext.cpp.html#160) [Qt Quick performance guidance](https://doc.qt.io/qt-6/qtquick-performance.html)

6. **High — animating the native window's dimensions is a distinct stutter source in Quickshell.** In Quickshell issue #18, the project maintainer explicitly says dynamically resizing the window itself causes stutters and recommends a transparent window fixed at the largest required size, animating content inside it instead. For geometry-expanding launchers/popups, this is stronger Quickshell-specific evidence than changing easing or duration. [Quickshell issue #18 maintainer response](https://github.com/quickshell-mirror/quickshell/issues/18#issuecomment-2675814078)

7. **Medium — Wayland pacing is per surface and compositor-controlled, unlike compositor-native effects.** The Wayland protocol defines `wl_surface.frame` as a one-shot hint telling a client when it is a good time to draw/commit the next animation frame, and allows callbacks to be withheld for invisible surfaces. Qt's Wayland platform window has per-window frame-callback state and a callback timeout (`qtbase/src/plugins/platforms/wayland/qwaylandwindow.cpp`, `QT_WAYLAND_FRAME_CALLBACK_TIMEOUT`). Multiple Qt windows therefore have independently paced client surfaces, while a compositor-native workspace/window animation can update compositor-owned transforms every output cycle without waiting for new QML values, GUI-thread synchronization, client rendering, or buffer commits. This explains why compositor effects can look native-165-Hz while client-side `Behavior` motion looks much lower. [Wayland protocol specification](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_surface) [Qt Wayland source](https://codebrowser.dev/qt6/qtbase/src/plugins/platforms/wayland/qwaylandwindow.cpp.html#58)

8. **Medium — Qt has historical Wayland frame-callback/render-loop bugs, but the old reports are corroboration, not proof of a current Qt 6 regression.** QTBUG-72578 records heavy Qt Quick stuttering on Wayland after frame-callback changes and different bad behavior among render loops; QTBUG-69077 records blocking involving frame callbacks and multiple/hidden windows. They establish that this boundary has been failure-prone, but both concern older Qt generations/compositors and should not be treated as the primary diagnosis on a current Qt 6 build without traces. [QTBUG-72578](https://bugreports.qt.io/browse/QTBUG-72578) [QTBUG-69077](https://bugreports.qt.io/browse/QTBUG-69077)

9. **Medium — reported FPS and perceived animation FPS can differ.** `frameSwapped`/present counts can be 120 or 165 while a GUI-thread `NumberAnimation` produces only ~60 distinct property states, or while frame intervals alternate irregularly. Conversely, measuring a screen capture or phone video can alias mixed refresh rates. Validate both (a) present/frame intervals per window and (b) distinct animation-property sampling/main-thread stalls. Qt's own qmlbench notes that basic/timer-driven animation commonly skips once or twice per frame and recommends first verifying stable swap pacing. [qmlbench methodology](https://code.qt.io/cgit/qt-labs/qmlbench.git/about/#sustained-fps-shell)

## Diagnostics

Run controlled A/B tests, changing one variable at a time:

- `QSG_INFO=1` — prints scene-graph backend/render-loop information. Equivalent fine-grained logging starts with `QT_LOGGING_RULES="qt.scenegraph.general=true"`.
- `QT_LOGGING_RULES="qt.scenegraph.general=true;qt.scenegraph.renderloop=true;qt.scenegraph.time.renderloop=true"` — exposes chosen driver/loop, per-window/render-thread activity, animation-driver mode changes, broken-vsync detection, and frame timing. These categories are declared in `qtdeclarative/src/quick/scenegraph/qsgcontext.cpp` and recommended by the official scene-graph documentation. [Source categories](https://codebrowser.dev/qt6/qtdeclarative/src/quick/scenegraph/qsgcontext.cpp.html#43)
- `QSG_RENDER_TIMING=1` — textual polish/sync/render/swap timing; use the QML Profiler as the deeper check for JavaScript, bindings, animation, and GUI-thread stalls. [Qt Creator timing documentation](https://doc.qt.io/qtcreator/creator-qml-performance-monitor.html)
- `QSG_RENDER_LOOP=threaded` versus `QSG_RENDER_LOOP=basic` — diagnostic A/B. `threaded` should be the preferred production candidate; `basic` intentionally uses the approximately 16 ms timer for ordinary animations and can confirm timer-like behavior. Do not assume forcing `threaded` defeats the multi-window fallback—it does not. [Render-loop docs](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html#scene-graph-and-rendering)
- `QSG_USE_SIMPLE_ANIMATION_DRIVER=1` (Qt 6.5+) — the most relevant A/B on mixed-refresh, multiple-window systems. Logs should say `Animation Driver: using QElapsedTimer` for GUI and render threads. [Official docs](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html#driving-animations) [Implementation](https://codebrowser.dev/qt6/qtdeclarative/src/quick/scenegraph/qsgcontext.cpp.html#234)
- `QSG_NO_VSYNC=1` (Qt 6.4+) — diagnostic/fallback for broken vsync throttling; it makes the threaded loop stop trusting vsync and use timers. It is not a high-refresh smoothness fix and can worsen pacing, but can reveal incorrect vsync assumptions. [Official docs](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html#what-if-vsync-based-throttling-is-dysfunctional-globally-disabled-or-the-application-disabled-it-itself)
- `QSG_RHI_BACKEND=opengl` versus `vulkan` (when both work) — isolates RHI/driver/swapchain behavior from QML animation scheduling. [Scene graph adaptations](https://doc.qt.io/qt-6/qtquick-visualcanvas-adaptations.html)
- `QT_WAYLAND_FRAME_CALLBACK_TIMEOUT=<milliseconds>` — advanced Qt Wayland diagnostic only. The source confirms the knob, but changing it can bypass normal compositor throttling after timeout and should not be a normal fix. Enable Wayland QPA logging alongside it if investigating missing callbacks. [Qt Wayland source](https://codebrowser.dev/qt6/qtbase/src/plugins/platforms/wayland/qwaylandwindow.cpp.html#58)
- `QSG_FIXED_ANIMATION_STEP=1` — private/implementation-level diagnostic found in current `qsgcontext.cpp`; it selects consistent fixed animation steps and is likely to make high-refresh/mixed-refresh realism worse. Do not ship it as a fix. [Qt source](https://codebrowser.dev/qt6/qtdeclarative/src/quick/scenegraph/qsgcontext.cpp.html#74)

Suggested minimal matrix: one visible window on 120 Hz; one on 165 Hz; both visible; primary output swapped; default driver versus `QSG_USE_SIMPLE_ANIMATION_DRIVER=1`; `NumberAnimation` versus an applicable `XAnimator`/`OpacityAnimator`. Record per-window intervals from `qt.scenegraph.time.renderloop` and a QML Profiler trace.

## Fixes and workarounds (priority order)

1. **Set `QSG_USE_SIMPLE_ANIMATION_DRIVER=1` on Qt 6.5+ and retest.** Qt explicitly designed this elapsed-time driver to avoid the multi-window timer-fallback infrastructure, primary-screen refresh coupling, vsync drift, VRR, and broken-vsync problems. Trade-off: Qt warns some animations may look less smooth than the ideal single-window vsync-driven case.
2. **Reduce simultaneously visible `QQuickWindow`s where feasible.** Confirm by hiding all but one panel/window. Avoid invisible-but-still-visible shell surfaces; destroy or make them non-renderable for the test.
3. **Keep shell windows fixed-size and animate items inside.** For Quickshell popups/launchers, allocate the maximum transparent surface and animate clipping/content/transform rather than changing the native window width/height. This is the direct Quickshell maintainer recommendation.
4. **Use scene-graph Animators for pure visual transforms/opacity.** Replace `Behavior on x { NumberAnimation {} }` with an appropriate `XAnimator`/`YAnimator`, or prefer scale/opacity transforms over width/height layout animation where semantics allow. Keep hit areas/QML state limitations in mind. Combine with the simple driver if render-thread animator timing is also suspect.
5. **Keep the GUI thread below the smallest frame budget.** At 165 Hz the budget is ~6.06 ms and at 120 Hz ~8.33 ms. Remove synchronous I/O, large JS loops, repeated model rebuilding, binding loops, synchronous image decoding, and costly layout/polish from animation frames; load asynchronously.
6. **Upgrade Qt/Quickshell and test both Vulkan and OpenGL RHI backends.** Old Wayland callback bugs exist, so reproduce on the newest supported Qt patch release before filing. Include compositor, GPU/Mesa/driver, Qt, Quickshell, output modes, primary-output designation, VRR state, and the logging/profiler trace.
7. **Use `QSG_RENDER_LOOP=basic` or `QSG_NO_VSYNC=1` only as correctness fallbacks.** They may fix too-fast/wrong-duration animations when throttling is broken, but timer-driven ordinary animation is exactly the mechanism likely to look near 60 FPS here.

## Sources

- Kept: [Qt Quick Scene Graph](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html) — primary documentation; directly specifies 16 ms default timing, threaded drivers, multi-window fallback, mixed-screen simple driver, environment variables, and caveats.
- Kept: [Qt `qsgcontext.cpp`](https://codebrowser.dev/qt6/qtdeclarative/src/quick/scenegraph/qsgcontext.cpp.html) — current implementation evidence for primary-screen refresh, driver modes/heuristics, logging, and environment switches.
- Kept: [Qt `qsgthreadedrenderloop.cpp`](https://github.com/qt/qtdeclarative/blob/dev/src/quick/scenegraph/qsgthreadedrenderloop.cpp) — current implementation states one render thread/QRhi per window and shows per-frame animator advancement.
- Kept: [Animator QML type](https://doc.qt.io/qt-6/qml-qtquick-animator.html) — authoritative distinction between regular property animation and render-thread animation.
- Kept: [Qt Wayland `qwaylandwindow.cpp`](https://codebrowser.dev/qt6/qtbase/src/plugins/platforms/wayland/qwaylandwindow.cpp.html) and [Wayland protocol](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_surface) — per-window callback implementation and protocol semantics.
- Kept: [Quickshell `Variants`](https://quickshell.outfoxxed.me/docs/types/Quickshell/Variants/), [`PanelWindow`](https://quickshell.outfoxxed.me/docs/types/Quickshell/PanelWindow/), and [issue #18](https://github.com/quickshell-mirror/quickshell/issues/18#issuecomment-2675814078) — evidence for per-screen windows and project-specific resize guidance.
- Kept with caution: [QTBUG-72578](https://bugreports.qt.io/browse/QTBUG-72578), [QTBUG-69077](https://bugreports.qt.io/browse/QTBUG-69077) — historical direct reports; useful context but stale for current Qt 6.
- Dropped: Reddit 165 Hz report — anecdotal and no validated root cause.
- Dropped: generic SEO/render-loop explainers — superseded by official Qt documentation/source.
- Dropped: unrelated Quickshell VRR crash reports — no evidence about animation pacing.

## Gaps / residual risks

- No directly matching current Quickshell issue was found for “two mixed-refresh monitors make `NumberAnimation` look ~60 FPS.” The conclusion is a strong mechanism-based diagnosis, not confirmation against the user's exact trace.
- Actual behavior depends on exact Qt patch level, compositor (KWin, Hyprland, niri, etc.), GPU/RHI, output marked primary, VRR, and how many Quickshell windows remain exposed. Qt's private implementation can change between releases.
- The simple elapsed-time driver corrects animation time but cannot create missing presentations or remove GUI-thread stalls; it may preserve duration while motion remains uneven.
- `Animator` substitutions can change semantics because the QML property is not updated during execution and geometry/layout properties cannot all be moved to the render thread.
- Historical Qt bug reports do not establish a currently open Qt 6 defect; a minimal reproducer and trace are needed before assigning a Qt/Quickshell bug.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Review findings give severity-ranked causes and concrete upstream paths including qtdeclarative/src/quick/scenegraph/qsgcontext.cpp, qtdeclarative/src/quick/scenegraph/qsgthreadedrenderloop.cpp, and qtbase/src/plugins/platforms/wayland/qwaylandwindow.cpp, with source URLs and residual risks."
    }
  ],
  "changedFiles": [],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "No shell commands run (web/source research only)",
      "result": "not-run",
      "summary": "Research used official documentation, upstream source, issue trackers, and protocol specifications."
    }
  ],
  "validationOutput": [
    "Cross-checked the multi-window timer fallback and QSG_USE_SIMPLE_ANIMATION_DRIVER behavior against both official Qt documentation and current qtdeclarative source.",
    "Cross-checked Quickshell multi-screen window creation and dynamic-resize guidance against Quickshell documentation and a maintainer response."
  ],
  "residualRisks": [
    "No trace or minimal reproducer from the target 120 Hz + 165 Hz system was available.",
    "Exact pacing remains dependent on Qt patch level, compositor, RHI/GPU driver, VRR, primary-screen designation, and exposed-window count.",
    "Historical QTBUG reports are contextual and may not apply to current Qt 6."
  ],
  "noStagedFiles": true,
  "diffSummary": "No repository files edited; research artifact only.",
  "reviewFindings": [
    "critical: qtdeclarative scene-graph animation design - more than one visible QQuickWindow falls back ordinary QML animations to a roughly 16 ms system timer, causing apparent ~60 FPS property motion on 120/165 Hz outputs.",
    "high: qtdeclarative/src/quick/scenegraph/qsgcontext.cpp:91-100 - default driver derives its vsync interval from the primary screen, creating mixed-refresh mismatch risk.",
    "high: Quickshell Variants/PanelWindow usage - a window per screen naturally activates Qt's multi-window path.",
    "high: Quickshell issue #18 - dynamically resizing native windows is a maintainer-confirmed stutter source; fixed transparent windows with animated content are recommended.",
    "medium: qtbase/src/plugins/platforms/wayland/qwaylandwindow.cpp - per-window Wayland frame callbacks add independent pacing points unlike compositor-native transforms."
  ],
  "manualNotes": "Artifact written to the runtime-specified output path; no NixOS repository source files were modified."
}
```
