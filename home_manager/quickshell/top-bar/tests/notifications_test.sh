#!/usr/bin/env bash
set -euo pipefail

notification_test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PATH="$notification_test_dir/fixtures:$PATH"
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
export QT_NO_XDG_DESKTOP_PORTAL=1
export QUICKSHELL_NOTIFICATION_TEST=1

# Never contend for org.freedesktop.Notifications on the desktop session bus.
exec dbus-run-session -- timeout 45s qs -p "$notification_test_dir/tst_NotificationData.qml" --no-color
