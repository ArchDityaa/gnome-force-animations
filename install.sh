#!/usr/bin/env bash
#
# gnome-force-animations — installer
#
# Restores GNOME Shell desktop animations on machines where they are silently
# disabled, i.e.:
#   * software rendering (llvmpipe / swrast, typical inside a VM), and
#   * an active GNOME Remote Desktop (RDP) / VNC session.
#
# Everything installed here is *user-scoped*. No root / sudo is required.
#
# Usage:  ./install.sh
#
set -euo pipefail

UUID="force-animations@local"
# Older/alternative UUIDs this project may have used; cleaned up on install.
LEGACY_UUIDS=("force-animations@airaa.local")

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '    %s\n' "$*"; }
hdr()  { printf '\n==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Add UUID to org.gnome.shell enabled-extensions (uses gjs, always present).
gfa_enable() {
    GFA_UUID="$1" gjs -c '
        const Gio = imports.gi.Gio;
        const uuid = imports.gi.GLib.getenv("GFA_UUID");
        const s = new Gio.Settings({ schema_id: "org.gnome.shell" });
        const list = s.get_strv("enabled-extensions");
        if (!list.includes(uuid)) {
            list.push(uuid);
            s.set_strv("enabled-extensions", list);
            print("enabled " + uuid);
        } else {
            print("already enabled (" + uuid + ")");
        }
    ' 2>/dev/null || warn "could not update enabled-extensions (is gjs installed?)"
}

# Remove UUID from org.gnome.shell enabled-extensions.
gfa_remove_from_enabled() {
    GFA_UUID="$1" gjs -c '
        const Gio = imports.gi.Gio;
        const uuid = imports.gi.GLib.getenv("GFA_UUID");
        const s = new Gio.Settings({ schema_id: "org.gnome.shell" });
        const list = s.get_strv("enabled-extensions");
        const filtered = list.filter(x => x !== uuid);
        if (filtered.length !== list.length) {
            s.set_strv("enabled-extensions", filtered);
            print("removed from enabled-extensions: " + uuid);
        }
    ' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# sanity checks
# ---------------------------------------------------------------------------
if ! command -v gnome-shell >/dev/null 2>&1; then
    warn "gnome-shell was not found. This tool only works on GNOME."
    exit 1
fi
if ! command -v gjs >/dev/null 2>&1; then
    warn "gjs was not found. On GNOME it is normally installed (gnome-shell depends on it)."
    exit 1
fi

GNOME_SHELL_BIN="$(command -v gnome-shell)"
SHELL_VERSION="$("$GNOME_SHELL_BIN" --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
say "GNOME Shell binary : $GNOME_SHELL_BIN"
say "GNOME Shell version: ${SHELL_VERSION:-unknown}"

if [ -n "${SHELL_VERSION:-}" ] && [ "$SHELL_VERSION" -lt 40 ]; then
    warn "GNOME Shell ${SHELL_VERSION} is too old; only GNOME 40+ is supported."
    exit 1
fi

# ---------------------------------------------------------------------------
# pick extension flavour
# ---------------------------------------------------------------------------
if [ -n "${SHELL_VERSION:-}" ] && [ "$SHELL_VERSION" -ge 45 ]; then
    FLAVOUR="gnome45"
else
    FLAVOUR="gnome44"
    warn "Using the legacy (pre-45) extension variant: best-effort, not guaranteed."
fi

# ---------------------------------------------------------------------------
# install extension
# ---------------------------------------------------------------------------
hdr "Installing extension (${FLAVOUR} variant)"
EXT_ROOT="$HOME/.local/share/gnome-shell/extensions"
EXT_DIR="$EXT_ROOT/$UUID"
mkdir -p "$EXT_DIR"
cp -f "$SCRIPT_DIR/extension/$FLAVOUR/metadata.json" "$EXT_DIR/metadata.json"
cp -f "$SCRIPT_DIR/extension/$FLAVOUR/extension.js" "$EXT_DIR/extension.js"
say "installed to $EXT_DIR"

# ---------------------------------------------------------------------------
# remove legacy copies
# ---------------------------------------------------------------------------
for old in "${LEGACY_UUIDS[@]}"; do
    if [ -d "$EXT_ROOT/$old" ]; then
        hdr "Removing legacy extension $old"
        rm -rf "$EXT_ROOT/$old"
        gfa_remove_from_enabled "$old"
    fi
done

# ---------------------------------------------------------------------------
# enable extension
# ---------------------------------------------------------------------------
hdr "Enabling extension"
gfa_enable "$UUID"

# ---------------------------------------------------------------------------
# systemd user drop-in for the official --force-animations switch
# ---------------------------------------------------------------------------
hdr "Configuring gnome-shell --force-animations (official flag)"
if "$GNOME_SHELL_BIN" --help 2>/dev/null | grep -q -- '--force-animations'; then
    for inst in wayland x11; do
        d="$HOME/.config/systemd/user/org.gnome.Shell@${inst}.service.d"
        mkdir -p "$d"
        cat > "$d/force-animations.conf" <<EOF
# Managed by gnome-force-animations.
# Force GNOME Shell animations even when hardware acceleration is unavailable.
[Service]
ExecStart=
ExecStart=$GNOME_SHELL_BIN --force-animations
EOF
    done
    say "wrote systemd user drop-ins for @wayland and @x11"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || warn "systemctl --user daemon-reload failed"
        say "ran: systemctl --user daemon-reload"
    fi
else
    say "this gnome-shell does not support --force-animations; relying on the extension only"
fi

# ---------------------------------------------------------------------------
# done
# ---------------------------------------------------------------------------
hdr "Done"
cat <<'EOF'
    A logout / reboot is required so GNOME Shell picks everything up.

      * Log out and log back in, or simply reboot.

    Then verify with:

      ./diagnose.sh
EOF
