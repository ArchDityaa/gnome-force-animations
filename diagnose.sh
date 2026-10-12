#!/usr/bin/env bash
#
# gnome-force-animations — diagnostics
#
# Prints everything relevant to "GNOME Shell has no animations" on software
# rendering / remote desktop setups, plus whether this project's fix is active.
#
set -uo pipefail

UUID="force-animations@local"

line() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
kv()   { printf '   %-26s %s\n' "$1" "$2"; }

line "System"
if [ -r /etc/os-release ]; then
    . /etc/os-release
    kv "OS" "${PRETTY_NAME:-unknown}"
fi
kv "Kernel" "$(uname -r)"
kv "Session type" "${XDG_SESSION_TYPE:-unknown}"
kv "Desktop" "${XDG_CURRENT_DESKTOP:-unknown}"
kv "gnome-shell" "$(gnome-shell --version 2>/dev/null || echo 'not found')"
kv "Remote (loginctl)" "$(loginctl show-session "$(loginctl 2>/dev/null | awk '$3==ENVIRON["USER"]{print $1; exit}')" -p Remote --value 2>/dev/null || echo '?')"

line "GPU / renderer"
if command -v glxinfo >/dev/null 2>&1; then
    glxinfo -B 2>/dev/null | grep -iE 'OpenGL renderer|Accelerated' | sed 's/^/   /'
else
    echo "   (glxinfo not installed; falling back to logs)"
fi
journalctl --user -b --no-pager 2>/dev/null \
    | grep -iE 'llvmpipe|swrast|falling back to|software render' \
    | tail -3 | sed 's/^/   /'

line "Animation settings"
kv "enable-animations" "$(gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null || echo '?')"

line "GNOME Shell flags"
SHELL_PID="$(pgrep -x gnome-shell | head -1 || true)"
if [ -n "$SHELL_PID" ]; then
    CMDLINE="$(tr '\0' ' ' < "/proc/$SHELL_PID/cmdline" 2>/dev/null || true)"
    kv "cmdline" "${CMDLINE:-?}"
    case "$CMDLINE" in
        *--force-animations*) kv "force-animations" "YES" ;;
        *)                    kv "force-animations" "no" ;;
    esac
else
    kv "gnome-shell process" "not running"
fi

line "Extension"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
if [ -d "$EXT_DIR" ]; then
    kv "installed" "yes ($EXT_DIR)"
else
    kv "installed" "no"
fi
if command -v gnome-extensions >/dev/null 2>&1; then
    STATE="$(gnome-extensions info "$UUID" 2>/dev/null | awk -F': ' '/State/{print $2}')"
    kv "state" "${STATE:-not loaded / unknown}"
fi
ENABLED="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null | tr -d ' ' || echo '')"
case "$ENABLED" in
    *"$UUID"*) kv "in enabled-extensions" "yes" ;;
    *)         kv "in enabled-extensions" "no" ;;
esac

line "Remote desktop activity"
if ss -tnp 2>/dev/null | grep -q ':3389'; then
    ss -tnp 2>/dev/null | grep ':3389' | sed 's/^/   /'
elif command -v ss >/dev/null 2>&1 && sudo -n ss -tnp 2>/dev/null | grep -q ':3389'; then
    sudo -n ss -tnp 2>/dev/null | grep ':3389' | sed 's/^/   /'
else
    echo "   no active RDP (port 3389) connection detected"
fi

line "Verdict"
HAS_FLAG=no
HAS_EXT=no
[ -n "${CMDLINE:-}" ] && case "$CMDLINE" in *--force-animations*) HAS_FLAG=yes ;; esac
[ "${STATE:-}" = "ACTIVE" ] && HAS_EXT=yes

if [ "$HAS_FLAG" = yes ] && [ "$HAS_EXT" = yes ]; then
    echo "   Fix is ACTIVE (flag + extension). Animations should be running."
elif [ "$HAS_FLAG" = yes ] || [ "$HAS_EXT" = yes ]; then
    echo "   Fix is PARTIALLY active."
    echo "   If you are connected over RDP/VNC, enable the extension (./install.sh) too."
else
    echo "   Fix is NOT active."
    echo "   Run ./install.sh and log out / reboot."
fi
