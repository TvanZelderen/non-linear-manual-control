function joybridge_close()
%JOYBRIDGE_CLOSE  Stop the sidestick bridge after a simulation run.
%
%   Called from the model StopFcn (installed by patch_model_joystick). Closes
%   the JoyBridge opened by joybridge_open and clears the globals.
%
%   See also JOYBRIDGE_OPEN, JOYBRIDGE_STEP.

    global JOYBRIDGE JOYBRIDGE_MAP   %#ok<GVMIS>

    try
        if ~isempty(JOYBRIDGE) && isa(JOYBRIDGE, 'JoyBridge') && isvalid(JOYBRIDGE)
            JOYBRIDGE.close();
        end
    catch
    end
    JOYBRIDGE = [];
    JOYBRIDGE_MAP = [];
end
