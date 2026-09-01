function cal = joystick_calibrate(varargin)
%JOYSTICK_CALIBRATE  Interactive calibration of the pilot sidestick (macOS).
%
%   cal = JOYSTICK_CALIBRATE() walks through centring the stick and moving
%   each flight channel (roll, pitch, yaw, throttle) to both extremes, works
%   out which HID axis carries which channel and in which sense, and writes
%   matlab/params/joystick_cal.mat (variable "joycal"). joystick_params.m
%   turns that file into the numeric mapping the model uses.
%
%   Name/value options:
%     'VendorID' , 'ProductID'  restrict to one device (default: first found)
%     'Port'                     UDP port for the helper      (default 25147)
%     'HoldSeconds'             averaging window per prompt   (default 0.6)
%     'DeadZone'               normalised dead-zone           (default 0.03)
%     'OutFile'               where to save   (default matlab/params/joystick_cal.mat)
%     'Quick'   true           no prompts: record centre only, assume full
%                              [0,1] throw per axis, X/Y/Rz/Slider -> r/p/y/thr
%
%   Requires the joybridge helper (matlab/lib/joybridge/build.sh).
%
%   See also JOYBRIDGE, JOYSTICK_PARAMS, CHECK_ENV.

    ip = inputParser;
    ip.addParameter('VendorID',  hex2dec('044F'));   % Thrustmaster
    ip.addParameter('ProductID', hex2dec('0406'));   % T.A320 sidestick
    ip.addParameter('Port', 25147);
    ip.addParameter('HoldSeconds', 0.6);
    ip.addParameter('DeadZone', 0.03);
    ip.addParameter('OutFile', default_outfile());
    ip.addParameter('Quick', false, @(x)islogical(x) || ismember(x,[0 1]));
    ip.parse(varargin{:});
    opt = ip.Results;

    chan = {'roll','pitch','yaw','throttle'};
    ctype = {'bipolar','bipolar','bipolar','unipolar'};
    posHint = { ...
        'roll RIGHT (right wing down), hold', ...
        'pitch UP (pull back), hold', ...
        'yaw RIGHT (nose right), hold', ...
        'throttle to MAX, hold'};
    negHint = { ...
        'roll LEFT (left wing down), hold', ...
        'pitch DOWN (push forward), hold', ...
        'yaw LEFT (nose left), hold', ...
        'throttle to IDLE, hold'};

    j = JoyBridge('VendorID', opt.VendorID, 'ProductID', opt.ProductID, 'Port', opt.Port);
    cleaner = onCleanup(@() j.close());

    fprintf('\n=== joystick calibration ===\n');
    fprintf('device : %s  (0x%04X/0x%04X)\n', j.Name, j.VendorID, j.ProductID);
    fprintf('axes   : %d   (HID usages %s)\n', j.NumAxes, mat2str(j.AxisUsages));
    fprintf('buttons: %d\n\n', j.NumButtons);

    nA = j.NumAxes;
    cal = struct();
    cal.device     = j.Name;
    cal.vid        = j.VendorID;
    cal.pid        = j.ProductID;
    cal.axisUsages = j.AxisUsages;
    cal.channels   = chan;
    cal.type       = ctype;
    cal.axisIndex  = nan(1,4);
    cal.center     = nan(1,4);
    cal.lo         = nan(1,4);
    cal.hi         = nan(1,4);
    cal.invert     = false(1,4);
    cal.deadzone   = opt.DeadZone;
    cal.created    = datetime('now');

    if opt.Quick
        c = sample_axes(j, opt.HoldSeconds);
        guess = [find(j.AxisUsages==48,1), find(j.AxisUsages==49,1), ...
                 find(j.AxisUsages==53,1), find(j.AxisUsages==54,1)];
        for k = 1:4
            if isempty(guess(k)) || k > numel(guess), continue; end
            gi = guess(k);
            cal.axisIndex(k) = gi;
            cal.center(k) = c(gi);
            cal.lo(k) = 0; cal.hi(k) = 1;
        end
    else
        % --- centre -----------------------------------------------------
        wait_enter('Centre the stick, throttle at IDLE, hands off. Press ENTER.');
        c0 = sample_axes(j, opt.HoldSeconds);
        fprintf('   centre raw: %s\n\n', num2str(c0, ' %.3f'));

        % --- per channel ---------------------------------------------
        for k = 1:4
            fprintf('-- %s --\n', upper(chan{k}));
            resp = wait_enter(sprintf('Move %s. Press ENTER (or type s to skip).', posHint{k}));
            if strcmpi(strtrim(resp), 's')
                fprintf('   skipped.\n\n'); continue;
            end
            cp = sample_axes(j, opt.HoldSeconds);

            wait_enter(sprintf('Move %s. Press ENTER.', negHint{k}));
            cn = sample_axes(j, opt.HoldSeconds);

            travel = abs(cp - cn);
            [~, ax] = max(travel);
            if travel(ax) < 0.15
                warning('joystick_calibrate:smallTravel', ...
                    '%s: largest axis travel only %.2f - check you moved the right control.', ...
                    chan{k}, travel(ax));
            end

            cal.axisIndex(k) = ax;
            cal.center(k)    = c0(ax);
            cal.lo(k)        = min(cp(ax), cn(ax));
            cal.hi(k)        = max(cp(ax), cn(ax));
            % "positive intent" pose should map to +1
            cal.invert(k)    = cp(ax) < cn(ax);

            fprintf('   %-8s -> axis %d (usage %d)  raw[%.3f .. %.3f] centre %.3f  invert %d\n\n', ...
                chan{k}, ax, j.AxisUsages(ax), cal.lo(k), cal.hi(k), cal.center(k), cal.invert(k));
        end
    end

    % --- save --------------------------------------------------------------
    outdir = fileparts(opt.OutFile);
    if ~isempty(outdir) && ~isfolder(outdir), mkdir(outdir); end
    joycal = cal;  %#ok<NASGU>
    save(opt.OutFile, 'joycal');
    fprintf('saved: %s\n', opt.OutFile);

    print_summary(cal);

    % --- live check ------------------------------------------------------
    if ~opt.Quick
        jp = joystick_params(opt.OutFile);
        fprintf('\nLive normalised output (5 s) - move the stick to verify signs:\n');
        t = tic;
        while toc(t) < 5
            j.poll();
            n = jp.apply(j.axis());
            fprintf('\r  roll % .2f  pitch % .2f  yaw % .2f  thr %.2f    ', n(1), n(2), n(3), n(4));
            pause(0.05);
        end
        fprintf('\n');
    end
end

% ------------------------------------------------------------------------
function f = default_outfile()
    here = fileparts(mfilename('fullpath'));            % matlab/setup
    f = fullfile(fileparts(here), 'params', 'joystick_cal.mat');
end

function resp = wait_enter(msg)
    resp = input([msg ' '], 's');
end

function m = sample_axes(j, secs)
%SAMPLE_AXES  Mean of each axis over a short window.
    acc = []; n = 0; t = tic;
    while toc(t) < secs
        j.poll();
        a = j.axis();
        if ~isempty(a)
            if isempty(acc), acc = zeros(size(a)); end
            acc = acc + a; n = n + 1;
        end
        pause(0.01);
    end
    if n == 0, m = j.axis(); else, m = acc / n; end
end

function print_summary(cal)
    fprintf('\n%-9s %-8s %-6s %-7s %-7s %-7s %-6s\n', ...
        'channel','type','axis','raw_lo','raw_hi','centre','invert');
    for k = 1:4
        if isnan(cal.axisIndex(k))
            fprintf('%-9s %-8s   --     (skipped)\n', cal.channels{k}, cal.type{k});
        else
            fprintf('%-9s %-8s  %-5d %-7.3f %-7.3f %-7.3f %-6d\n', ...
                cal.channels{k}, cal.type{k}, cal.axisIndex(k), ...
                cal.lo(k), cal.hi(k), cal.center(k), cal.invert(k));
        end
    end
end
