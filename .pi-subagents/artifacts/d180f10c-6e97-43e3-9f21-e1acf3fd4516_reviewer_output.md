## Review

- **Correct:** No blocker found. The TabCtl package is reproducibly pinned by `flake.lock:274-282`, uses a fixed vendor hash in `packages/tabctl.nix:14-15`, and builds successfully as version 2.0.0.
- **Correct:** Chrome policy and native-host configuration are structurally correct. `system/hyprland/chrome-extensions.nix:5-12` force-installs the expected Web Store ID, while `home_manager/hyprland/tabctl.nix:47-63` restricts native messaging to that exact origin and uses an immutable Nix-store executable.
- **Correct:** Monitor exclusivity is coherent. `Bar.qml:20-45` gates rendering and keyboard focus by target monitor; `Bar.qml:69-70` grants exclusive keyboard focus only to the active panel. Transition metadata in `StatusData.qml:603-624` and localization in `Bar.qml:237-240` preserve workspaces on other monitors. Rapid launcher/tabs transition smoke testing produced no QML errors.
- **Correct:** The dirty error-handling change in `home_manager/hyprland/tabctl.nix:20-25` returns concise valid JSON when no browser mediator is available.

- **Blocker:** None identified.

- **Note — Medium:** **The browser extension is not reproducible with the mediator.** The mediator source is pinned (`flake.lock:274-282`), but `system/hyprland/chrome-extensions.nix:8-10` installs whatever version the mutable Chrome Web Store currently serves. A future protocol-breaking extension update can leave the pinned mediator unusable. At minimum, deployment validation should run `quickshell-chrome-tabs status` and assert protocol compatibility; that helper already exists at `home_manager/hyprland/tabctl.nix:36-37`.

- **Note — Medium:** **Stale tabs remain actionable during refresh.** `requestChromeTabs()` only sets loading state (`StatusData.qml:526-532`); reopening the launcher at `StatusData.qml:670-684` does not clear or disable the previous catalog. Keyboard and mouse actions remain enabled in `ChromeTabsLauncher.qml:99-135,306-315`, so an old tab may be activated or closed while a potentially long request is pending. Clear the old catalog or disable destructive actions while loading.

- **Note — Medium:** **Activation and close failures are invisible.** `StatusData.qml:545-568` uses detached processes, hides the launcher before activation, and removes a tab optimistically before close succeeds. Browser disconnects or stale IDs therefore produce no user-visible error and can leave UI state inconsistent. Managed `Process` objects or a refresh/error callback would make failures observable.

- **Note — Medium, security residual:** The native manifest correctly limits which extension can launch the mediator, but the documented Native Messaging → D-Bus architecture (`DESIGN_GUIDE.md:310-320`) leaves tab URLs and control methods available to other processes on the same user session bus while the mediator runs. This is an upstream architectural trust boundary, not a wildcard-origin defect; it should be explicitly accepted or hardened upstream.

- **Note — Medium, missing validation:** The validation procedure at `DESIGN_GUIDE.md:445-492` checks QML loading, Nix parsing/building, IPC toggles, reservations, and border restoration, but not Chrome policy recognition, extension installation, protocol compatibility, successful listing, activation/close, or moving the overlay between monitors. The current machine had no browser mediator, so only the structured failure path was exercised.

- **Note — Low, optional polish:** `ChromeTabsLauncher.qml:227-288` uses blue, green, and orange accents, contrary to the central capsule’s pink/yellow-only rule in `DESIGN_GUIDE.md:90-112`.