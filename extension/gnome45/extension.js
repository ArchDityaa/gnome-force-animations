import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import St from 'gi://St';

/*
 * GNOME Shell (>= 3.36) silently disables desktop animations in two cases:
 *
 *   1. The renderer is not hardware accelerated (llvmpipe / swrast, which is
 *      what a VM without 3D acceleration reports).
 *
 *   2. A remote-access handle requests it. GNOME Remote Desktop (RDP) and the
 *      VNC server always create their screencast session with
 *      "disable-animations = TRUE".
 *
 * The official `gnome-shell --force-animations` switch only covers (1): in
 * Shell's `_shouldEnableAnimations()` the remote-handle check runs *before*
 * the `global.force_animations` check, like this:
 *
 *     if (this._handles.size > 0)          // <-- RDP/VNC handle wins
 *         return false;
 *     if (global.force_animations)
 *         return true;
 *     if (!backend.is_rendering_hardware_accelerated())
 *         return false;                    // <-- llvmpipe
 *
 * This extension therefore:
 *   - sets `global.force_animations = true` (covers case 1), and
 *   - re-asserts animations right after Shell inhibited them for a new remote
 *     access handle (covers case 2).
 *
 * The "new-handle" handler below is connected *after* Shell's own handler
 * (Shell connects during UI initialisation, extensions load later), so it runs
 * afterwards and wins for that signal emission.
 */
export default class ForceAnimationsExtension extends Extension {
    enable() {
        this._previousForceAnimations = global.force_animations;
        global.force_animations = true;

        this._settings = St.Settings.get();

        // A remote-access handle may already exist when we are enabled.
        this._reassertAnimations();

        this._controller = global.backend.get_remote_access_controller();
        this._handlerId = 0;
        if (this._controller) {
            this._handlerId = this._controller.connect(
                'new-handle',
                (_controller, handle) => {
                    if (handle.get_disable_animations())
                        this._reassertAnimations();
                });
        }
    }

    disable() {
        if (this._controller && this._handlerId) {
            this._controller.disconnect(this._handlerId);
            this._handlerId = 0;
        }
        this._controller = null;
        this._settings = null;

        global.force_animations = this._previousForceAnimations ?? false;
    }

    _reassertAnimations() {
        if (this._settings && !this._settings.enable_animations)
            this._settings.uninhibit_animations();
    }
}
