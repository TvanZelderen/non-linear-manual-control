function jp = joystick_params(calFile)
%JOYSTICK_PARAMS  Sidestick axis-to-channel mapping for the Citation model.
%
%   jp = JOYSTICK_PARAMS() loads matlab/params/joystick_cal.mat (written by
%   joystick_calibrate.m) and returns the numeric mapping plus a helper:
%
%     jp.valid       true if a calibration file was loaded
%     jp.channels    {'roll','pitch','yaw','throttle'}
%     jp.axisIndex   index into the JoyBridge axis vector per channel (NaN = none)
%     jp.center      raw [0,1] value at rest per channel
%     jp.lo, jp.hi   raw [0,1] extremes per channel
%     jp.halfspan    max(hi-center, center-lo) per channel (bipolar scaling)
%     jp.invert      logical, per channel
%     jp.isUni       logical, true for unipolar channels (throttle)
%     jp.deadzone    normalised dead-zone
%     jp.apply(ax)   map a raw JoyBridge axis vector -> [roll pitch yaw throttle]
%                    roll/pitch/yaw in [-1,1] (+1 = right/up/nose-right),
%                    throttle in [0,1]. Missing channels return 0.
%
%   With no calibration file it warns and returns a passthrough default for
%   the Thrustmaster T.A320 (axes X,Y,Rz,Slider), so the model still runs.
%
%   The prefilters the brief asks for (raw stick -> smooth rate reference)
%   belong in the Simulink model, downstream of jp.apply, not here.
%
%   See also JOYSTICK_CALIBRATE, JOYBRIDGE.

    if nargin < 1 || isempty(calFile)
        here = fileparts(mfilename('fullpath'));           % matlab/params
        calFile = fullfile(here, 'joystick_cal.mat');
    end

    jp.channels = {'roll','pitch','yaw','throttle'};
    jp.isUni    = logical([0 0 0 1]);

    if isfile(calFile)
        S = load(calFile, 'joycal');
        c = S.joycal;
        jp.valid     = true;
        jp.source    = calFile;
        jp.device    = c.device;
        jp.axisIndex = c.axisIndex;
        jp.center    = c.center;
        jp.lo        = c.lo;
        jp.hi        = c.hi;
        jp.invert    = logical(c.invert);
        jp.deadzone  = c.deadzone;
        if isfield(c,'type'), jp.isUni = strcmp(c.type, 'unipolar'); end
    else
        warning('joystick_params:noCalibration', ...
            ['No calibration at %s - using Thrustmaster T.A320 passthrough. ' ...
             'Run joystick_calibrate to fix signs and end stops.'], calFile);
        jp.valid     = false;
        jp.source    = '';
        jp.device    = 'T.A320 Copilot (assumed)';
        jp.axisIndex = [1 2 3 4];        % X, Y, Rz, Slider in JoyBridge order
        jp.center    = [0.5 0.5 0.5 0];
        jp.lo        = [0 0 0 0];
        jp.hi        = [1 1 1 1];
        jp.invert    = false(1,4);
        jp.deadzone  = 0.03;
    end

    jp.halfspan = max(jp.hi - jp.center, jp.center - jp.lo);
    jp.halfspan(jp.halfspan < eps) = 1;   % guard divide-by-zero

    jp.apply = @(ax) map_axes(ax, jp);
end

% ------------------------------------------------------------------------
function out = map_axes(ax, jp)
    out = zeros(1,4);
    for k = 1:4
        idx = jp.axisIndex(k);
        if isnan(idx) || idx < 1 || idx > numel(ax), continue; end
        u = ax(idx);
        if jp.isUni(k)
            span = jp.hi(k) - jp.lo(k);
            if span < eps, span = 1; end
            v = (u - jp.lo(k)) / span;
            if jp.invert(k), v = 1 - v; end   % e.g. T.A320 slider: 1=idle, 0=full
            v = min(1, max(0, v));
        else
            v = (u - jp.center(k)) / jp.halfspan(k);
            if jp.invert(k), v = -v; end
            v = min(1, max(-1, v));
            v = apply_deadzone(v, jp.deadzone);
        end
        out(k) = v;
    end
end

function v = apply_deadzone(v, dz)
    if dz <= 0, return; end
    a = abs(v);
    if a <= dz
        v = 0;
    else
        v = sign(v) * (a - dz) / (1 - dz);
    end
end
