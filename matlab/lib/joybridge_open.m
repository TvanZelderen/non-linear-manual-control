function joybridge_open()
%JOYBRIDGE_OPEN  Start the sidestick bridge for a simulation run.
%
%   Called from the model StartFcn (installed by patch_model_joystick). Opens
%   one JoyBridge and loads the calibration into globals that joybridge_step
%   reads every step, so the bridge is created once per run, not per step.
%
%   Safe to call repeatedly; a failure just leaves the sidestick inactive and
%   joybridge_step holds its outputs at zero.
%
%   See also JOYBRIDGE_STEP, JOYBRIDGE_CLOSE, PATCH_MODEL_JOYSTICK.

    global JOYBRIDGE JOYBRIDGE_MAP   %#ok<GVMIS>

    try
        if isempty(JOYBRIDGE) || ~isa(JOYBRIDGE, 'JoyBridge') || ~isvalid(JOYBRIDGE)
            JOYBRIDGE = JoyBridge();
        end
        JOYBRIDGE_MAP = joystick_params();
        fprintf('joybridge_open: %s ready (%d axes)\n', ...
            JOYBRIDGE.Name, JOYBRIDGE.NumAxes);
    catch err
        warning('joybridge_open:fail', ...
            'sidestick unavailable (%s) - commands held at zero', err.message);
        JOYBRIDGE = [];
        JOYBRIDGE_MAP = [];
    end
end
