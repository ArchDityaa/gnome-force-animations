/*
 * Legacy (GNOME 40-44) variant of gnome-force-animations.
 *
 * Before GNOME 45, extensions used the imported-entry-point API instead of ES
 * modules (`init()` / `enable()` / `disable()` with `imports.gi`).
 *
 * See the GNOME 45+ variant (extension/gnome45/extension.js) for the full
 * explanation of why this is needed. The logic is identical:
 *   1. force `global.force_animations = true` (software rendering), and
 *   2. undo the animation inhibition Shell applies for remote-access handles
 *      (RDP/VNC) by calling `St.Settings.uninhibit_animations()` right after
 *      Shell's own "new-handle" handler runs.
 *
 * NOTE: best-effort, not tested by the maintainer on every version.
 */
const St = imports.gi.St;

const ForceAnimations = class {
    constructor() {
        this._previousForceAnimations = false;
        this._settings = null;
        this._controller = null;
        this._handlerId = 0;
    }

    enable() {
        this._previousForceAnimations = global.force_animations;
        global.force_animations = true;

        this._settings = St.Settings.get();
        this._reassertAnimations();

        this._controller = global.backend.get_remote_access_controller();
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

        global.force_animations = this._previousForceAnimations;
    }

    _reassertAnimations() {
        if (this._settings && !this._settings.enable_animations)
            this._settings.uninhibit_animations();
    }
};

let _instance = null;

function init() {
    _instance = new ForceAnimations();
}

function enable() {
    if (_instance === null)
        init();
    _instance.enable();
}

function disable() {
    if (_instance)
        _instance.disable();
    _instance = null;
}
