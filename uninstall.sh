#!/usr/bin/env bash
#
# gnome-force-animations — uninstaller
#
# Removes the extension, unregisters it and drops the systemd user drop-in.
#
set -euo pipefail

UUID="force-animations@local"
LEGACY_UUIDS=("force-animations@airaa.local")

say()  { printf '    %s\n' "$*"; }
hdr()  { printf '\n==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }

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

EXT_ROOT="$HOME/.local/share/gnome-shell/extensions"

hdr "Disabling and removing extension"
gfa_remove_from_enabled "$UUID"
rm -rf "$EXT_ROOT/$UUID"
say "removed $EXT_ROOT/$UUID"

for old in "${LEGACY_UUIDS[@]}"; do
    if [ -d "$EXT_ROOT/$old" ]; then
        gfa_remove_from_enabled "$old"
        rm -rf "$EXT_ROOT/$old"
        say "removed $EXT_ROOT/$old"
    fi
done

hdr "Removing systemd user drop-ins"
for inst in wayland x11; do
    d="$HOME/.config/systemd/user/org.gnome.Shell@${inst}.service.d"
    if [ -f "$d/force-animations.conf" ]; then
        rm -f "$d/force-animations.conf"
        say "removed $d/force-animations.conf"
        rmdir "$d" 2>/dev/null || true
    fi
done

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || warn "systemctl --user daemon-reload failed"
fi

hdr "Done"
cat <<'EOF'
    Log out and back in (or reboot) for the changes to take effect.
EOF
