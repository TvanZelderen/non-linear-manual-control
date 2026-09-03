function y = failure_step(u)
%FAILURE_STEP  Aileron-hardover failure on the post-servo deflection.
%
%   y = FAILURE_STEP([da_cmd; t])  ->  y = [da_actual; armed]
%
%     da_cmd    commanded aileron deflection AFTER servo lag + saturation
%               (tapped from Actuators/da limits) [rad]
%     t         simulation time [s]
%     da_actual deflection passed on to the aero model [rad]
%     armed     1 while the failure is active, else 0  (logged for the report)
%
%   When armed:   da_actual = FAILCFG.gain * da_cmd + FAILCFG.offset
%   otherwise:    da_actual = da_cmd
%
%   Meant for an Interpreted MATLAB Function block (Normal-mode sim only),
%   sample time -1 so it inherits the continuous rate of "da limits" and
%   needs no Rate Transition before the Mux. FAILCFG is seeded once per run
%   by failure_open (model StartFcn).
%
%   Deliberately STATELESS - the arm decision is recomputed from t and the
%   live button every step, so it does not depend on MATLAB state persisting
%   across steps inside the interpreter (which is unreliable here).
%
%   Arm logic by FAILCFG.mode:
%     'off'   armed = false always
%     'on'    armed = true  always
%     'auto'  armed = (t >= FAILCFG.t_fail)  OR  sidestick button
%             FAILCFG.button currently held down. The scheduled jam is
%             one-way by construction; the button is momentary (jam while
%             held) - a convenience for messing around, not the workflow.
%
%   If the sidestick bridge is not up the button term is just false and the
%   scheduled jam still works.
%
%   See also FAILURE_OPEN, FAILURE_PARAMS, JOYBRIDGE_STEP.

    global FAILCFG JOYBRIDGE   %#ok<GVMIS>

    da = u(1);
    t  = u(2);

    % --- block ran before StartFcn: pass through -----------------------
    if isempty(FAILCFG)
        y = [da; 0];
        return
    end

    switch FAILCFG.mode
        case 'off'
            armed = false;
        case 'on'
            armed = true;
        otherwise   % 'auto'
            armed = t >= FAILCFG.t_fail;
            if ~armed && button_down(JOYBRIDGE, FAILCFG.button)
                armed = true;
            end
    end

    if armed
        da = FAILCFG.gain * da + FAILCFG.offset;
    end
    y = [da; double(armed)];
end

% ------------------------------------------------------------------------
function tf = button_down(jb, idx)
%BUTTON_DOWN  True if sidestick button <idx> is currently pressed.
%   Duck-typed on purpose (any object with a button() method) so the guard
%   also catches a stale / unexpected JOYBRIDGE value. joybridge_step has
%   already polled the bridge this step.
    tf = false;
    if ~isempty(jb) && isobject(jb) && isvalid(jb) && ismethod(jb, 'button')
        try
            b = jb.button();
            if numel(b) >= idx
                tf = logical(b(idx));
            end
        catch
            % transient read failure - treat as not pressed
        end
    end
end
