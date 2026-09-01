function u = joybridge_step(~)
%JOYBRIDGE_STEP  One-call sidestick read for the Simulink Pilot subsystem.
%
%   u = JOYBRIDGE_STEP() returns u = [de; da; dr; thr] :
%       de   elevator command  [rad]
%       da   aileron  command  [rad]
%       dr   rudder   command  [rad]
%       thr  throttle setting  [0..1]
%
%   Meant for an Interpreted MATLAB Function block (one dummy input, ignored),
%   so it runs in the MATLAB interpreter each step - Normal-mode simulation
%   only. The bridge is opened once per run by joybridge_open (model StartFcn)
%   and read here through globals; this function does no I/O setup and never
%   blocks on construction. If the bridge is not up it holds the last command
%   (zeros at t=0) so the model still trims.
%
%   Signs and travel live in CFG below - flip a sign after a bench check if a
%   surface moves the wrong way. Travel matches the Citation actuator limits
%   (citation_params: da +-0.65, de +0.26/-0.35, dr +-0.38 rad).
%
%   See also JOYBRIDGE_OPEN, JOYBRIDGE_CLOSE, JOYBRIDGE, JOYSTICK_PARAMS.

    % channel = CFG.sign .* CFG.travel .* jp.apply(axes)   [roll pitch yaw thr]
    CFG.sign   = [ +1, -1, +1, +1 ];   % roll, pitch, yaw, throttle
    CFG.travel = [ 0.65, 0.35, 0.38, 1 ];

    global JOYBRIDGE JOYBRIDGE_MAP   %#ok<GVMIS>
    persistent last
    if isempty(last), last = [0; 0; 0; 0]; end

    if isempty(JOYBRIDGE) || ~isa(JOYBRIDGE, 'JoyBridge') || ~isvalid(JOYBRIDGE) ...
            || isempty(JOYBRIDGE_MAP)
        u = last; return
    end

    try
        JOYBRIDGE.poll();
        n = JOYBRIDGE_MAP.apply(JOYBRIDGE.axis());   % 1x4, roll/pitch/yaw [-1,1], thr [0,1]
        c = CFG.sign .* CFG.travel .* n;             % stick order
        last = [ c(2); c(1); c(3); c(4) ];           % -> [de; da; dr; thr]
    catch
        % transient read failure - keep the last good command
    end
    u = last;
end
