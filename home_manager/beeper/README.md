# Beeper Desktop as the local API service

Home Manager declares `beeper.service` in the user session. It starts after the
Wayland graphical environment is ready, stops with the session, and restarts
on failures (5 seconds between attempts, limited to 5 starts per minute).
The command uses the existing nixpkgs Beeper launcher and the same arguments as
its desktop entry. No new Beeper package, CLI, private API or window-hiding script
is introduced; Desktop still runs and consumes its normal resources.

## One-time Beeper preferences

In Beeper Desktop's own settings:

- Enable **Keep Beeper minimized on launch**.
- Disable **Quit Beeper when closing the main window** (relaunch when requested).
- Leave Beeper's own login autostart off, to avoid a second startup mechanism.
- Keep the local API enabled and Desktop notification sounds/alerts disabled:
  the Quickshell client handles notifications.

These preferences are not injected into private profile files. The service alone
does not hide the window if the native minimized preference is off. Tokens remain
in the keyring and are not included in the unit or Nix store.

Before the first rebuild, set these preferences and quit any manually launched
Beeper instance once. Home Manager activation can start the new service immediately
if the graphical session is active; subsequent graphical logins start it automatically.
If you have already rebuilt with a manual instance still running, quit that instance,
then run `systemctl --user start beeper.service`. Beeper is single-instance, so
starting the service while a manual instance is still running does not turn that
existing process into a supervised service and may bring its window to the front.

Diagnostics: `systemctl --user status beeper.service` and
`journalctl --user -u beeper.service -b`.
An intentional normal quit is not restarted; a crash is. If the start limit is
reached, address the cause and use `systemctl --user reset-failed beeper.service`
before starting it again.
