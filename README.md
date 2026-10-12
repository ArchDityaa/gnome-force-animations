# gnome-force-animations

Bring back **GNOME Shell desktop animations** on machines where GNOME silently
turns them off:

* **software rendering** — `llvmpipe` / `swrast`, which is what virtual machines
  without 3D acceleration (`virtio-gpu` without virgl, VirtualBox/VMware without
  3D, cloud instances, …) report; and
* **remote desktop sessions** — GNOME Remote Desktop (**RDP**) or the built-in
  VNC server, which ask GNOME Shell to disable animations while connected.

Built for **Zorin OS 18** but works on any distro with **GNOME Shell 45–48**
(Ubuntu 24.04+, Fedora 39+, Arch, …). A best-effort legacy variant for
**GNOME 40–44** is included too.

Everything is **user-scoped** — no `sudo`, no system files touched.

---

## The problem

You are on a VM (or a machine using the software renderer) and the desktop has
**no animations at all**: no overview zoom, no workspace slides, no window
open/close transitions, no Quick Settings slide. `Settings → Accessibility →
Reduce animations` is off and

```console
$ gsettings get org.gnome.desktop.interface enable-animations
true
```

…is already `true`. Yet nothing animates.

## Why it happens

GNOME Shell (since 3.36) decides whether to run animations in
`js/ui/main.js`:

```js
_shouldEnableAnimations() {
    if (this._handles.size > 0)          // remote-desktop (RDP/VNC) handle
        return false;

    if (global.force_animations)         // the official escape hatch
        return true;

    const backend = global.backend;
    if (!backend.is_rendering_hardware_accelerated())
        return false;                    // llvmpipe / software rendering

    ...
}
```

When it returns `false`, Shell calls `St.Settings.inhibit_animations()`, which
overrides the `enable-animations` GSettings key. So there are **two independent
triggers**:

1. **Software rendering.** `is_rendering_hardware_accelerated()` is `false` for
   `llvmpipe`/`swrast`, so animations are disabled.
2. **An active remote-access handle.** GNOME Remote Desktop always creates its
   screencast session with `disable-animations = TRUE`, and the `_handles`
   check runs **before** the `force_animations` check — so while you are
   connected over RDP/VNC, even `gnome-shell --force-animations` does not help.

> Note: Zorin OS ships optional "jelly" / magic-lamp effects as separate
> extensions that are **off by default**. Those are unrelated to this bug — see
> [Optional: Zorin OS effects](#optional-zorin-os-effects).

## What this does

* Adds a tiny GNOME Shell extension that:
  * sets `global.force_animations = true` (fixes cause 1), and
  * reverses the animation inhibition Shell applies for remote-access handles
    (fixes cause 2).
* Adds a systemd **user** drop-in for both the Wayland and X11 session units so
  the official `gnome-shell --force-animations` flag is passed at startup
  (redundant belt-and-suspenders for cause 1).

## Requirements

* GNOME Shell **40+** (45+ recommended).
* `gjs` (installed with GNOME; used to edit `enabled-extensions`).
* `systemd --user` for the `--force-animations` drop-in (optional — the
  extension works on its own).
* A logout/reboot to apply.

## Install

```bash
git clone https://github.com/ArchDityaa/gnome-force-animations.git
cd gnome-force-animations
./install.sh
```

Then **log out and back in** (or reboot).

## Verify

```bash
./diagnose.sh
```

A healthy result shows `force-animations: YES` and `state: ACTIVE`.

Manual checks:

```bash
# the running shell got the flag:
tr '\0' ' ' < /proc/$(pgrep -x gnome-shell | head -1)/cmdline

# the helper extension is active:
gnome-extensions info force-animations@local | grep State
```

## Uninstall

```bash
./uninstall.sh
# then log out / reboot
```

## Optional: Zorin OS effects

If you also want Zorin's signature effects (window wobble, magic-lamp minimize,
desktop cube, 3D window switcher), enable them explicitly:

```bash
gnome-extensions enable zorin-window-move-effect@zorinos.com   # wobble
gnome-extensions enable zorin-magic-lamp-effect@zorinos.com    # minimize
gnome-extensions enable zorin-desktop-cube@zorinos.com         # cube (changes workspace switching)
gnome-extensions enable zorin-spatial-window-switcher@zorinos.com  # 3D Alt+Tab
```

They are opt-in on Zorin, so they being off is not a bug.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Still no animations after login | `./diagnose.sh`; make sure you actually logged out/back in. |
| Works locally, not over RDP/VNC | The extension is what neutralises the remote handle — confirm `state: ACTIVE`. |
| Animations are choppy | Expected on `llvmpipe` (CPU rendering). See [the real fix](#the-real-fix-hardware-acceleration). |
| Extension not listed | The user extensions folder did not exist when Shell started; log out and back in. |

## The real fix: hardware acceleration

Animations will always be smoother with a real GPU. If this is a VM, enable 3D
acceleration **on the host**:

* **virt-manager / libvirt**: VM → *Video* → model **Virtio** and tick
  *3D acceleration*; connect with a local SPICE/GTK display.
* **QEMU**: `-device virtio-gpu-gl -display gtk,gl=on` (or `egl-headless`).
* **VirtualBox / VMware**: enable *3D acceleration* in the VM settings.

Then `glxinfo -B` should report something other than `llvmpipe` and
`Accelerated: yes`.

## How it works

The extension is ~50 lines. It connects to the shell's
`MetaRemoteAccessController::new-handle` signal **after** Shell itself has
connected (Shell connects while initialising its UI; extensions load later), so
for each handle it runs *after* Shell inhibited animations and simply calls
`St.Settings.uninhibit_animations()` to undo it. See
[`extension/gnome45/extension.js`](extension/gnome45/extension.js) for the
annotated source.

## Compatibility

| GNOME Shell | Variant used | Notes |
| --- | --- | --- |
| 45–48 | `extension/gnome45` | Tested on GNOME 46 (Zorin OS 18). |
| 40–44 | `extension/gnome44` | Best-effort, untested by maintainer. |
| < 40 | — | Not supported. |

## License

MIT — see [LICENSE](LICENSE).

---

## Bahasa Indonesia

**Masalah:** Di VM / mesin dengan *software rendering* (`llvmpipe`), GNOME Shell
mematikan semua animasi desktop walaupun `enable-animations` sudah `true`. Selain
itu, sesi **GNOME Remote Desktop (RDP)** juga meminta animasi dimatikan, dan
permintaan itu **didahulukan** di atas opsi `--force-animations`.

**Solusi cepat:**

```bash
git clone https://github.com/ArchDityaa/gnome-force-animations.git
cd gnome-force-animations
./install.sh
# lalu log out & login lagi, atau reboot
./diagnose.sh          # untuk memverifikasi
```

Skrip ini hanya mengubah berkas milik user (tidak perlu `sudo`). Untuk animasi
yang benar-benar mulus, aktifkan akselerasi 3D di sisi *host* VM (lihat bagian
[The real fix](#the-real-fix-hardware-acceleration)).
