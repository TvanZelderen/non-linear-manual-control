function patch_model_joystick(mdlPath)
%PATCH_MODEL_JOYSTICK  Swap the model's Simulink 3D Animation joystick block
%                      for the joybridge sidestick reader (macOS).
%
%   PATCH_MODEL_JOYSTICK() patches
%   model/Citation simulation model 2026/Citation_FlightGear_v2.mdl in place;
%   pass a path to patch a copy elsewhere.
%
%   Inside  Pilot / Joystick (comment out...) / Joystick  it removes the
%   <vrlib/Joystick Input> block and its calibration chain (the only SL3D
%   dependency in the model) and rebuilds the subsystem as:
%
%       tick (Constant, 0.02 s)
%         -> Sidestick (joybridge)   Interpreted MATLAB Function, 0.02 s
%         -> rt (Rate Transition)    50 Hz sampled -> continuous solver
%         -> axes (Demux 4)
%         -> delta elevator / delta aileron / delta rudder / Throttle setting
%
%   "Sidestick (joybridge)" calls joybridge_step (interpreter each step;
%   Normal-mode simulation only). The bridge itself is opened once per run by
%   joybridge_open / joybridge_close, wired into the model Start/StopFcn. The
%   4 outports keep their names, order and downstream wiring; the Virtual
%   Joystick ManualSwitch path is untouched as a fallback.
%
%   Idempotent and self-repairing: it rebuilds the chain every call, so
%   re-running after a code change just refreshes it. A one-time backup
%   <model>.mdl.prejoystick.bak is written next to the model.
%
%   See also JOYBRIDGE_STEP, JOYBRIDGE_OPEN, JOYSTICK_CALIBRATE, CHECK_ENV.

    if nargin < 1 || isempty(mdlPath)
        here = fileparts(mfilename('fullpath'));               % matlab/setup
        proj = fileparts(fileparts(here));
        mdlPath = fullfile(proj, 'model', 'Citation simulation model 2026', ...
                           'Citation_FlightGear_v2.mdl');
    end
    assert(isfile(mdlPath), 'model not found: %s', mdlPath);

    bak = [mdlPath '.prejoystick.bak'];
    if ~isfile(bak)
        copyfile(mdlPath, bak);
        fprintf('backup written: %s\n', bak);
    end

    [~, mdl] = fileparts(mdlPath);
    wasLoaded = bdIsLoaded(mdl);
    if ~wasLoaded, load_system(mdlPath); end
    cleaner = onCleanup(@() cleanup(mdl, wasLoaded));  %#ok<NASGU>

    jsPath = [mdl '/Pilot/Joystick (comment out with Ctrl+Shift+u if you don''t have a joystick)'];
    sub    = [jsPath '/Joystick'];
    assert(blockExists(sub), 'subsystem not found: %s', sub);

    order = {'delta elevator', 'delta aileron', 'delta rudder', 'Throttle setting'};

    % --- keep the 4 outports, drop everything else ---------------------
    outs = find_system(sub, 'SearchDepth', 1, 'LookUnderMasks', 'on', 'BlockType', 'Outport');
    keep = containers.Map(outs, num2cell(true(size(outs))));
    for k = 1:4
        assert(any(strcmp(outs, [sub '/' order{k}])), 'missing outport: %s', order{k});
    end

    delete_line(find_system(sub, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line'));
    blks = find_system(sub, 'SearchDepth', 1, 'LookUnderMasks', 'on', 'Type', 'block');
    for i = 1:numel(blks)
        b = blks{i};
        if strcmp(b, sub) || isKey(keep, b), continue; end
        delete_block(b);
    end
    for k = 1:4
        set_param([sub '/' order{k}], 'Position', [560, 40+60*k, 590, 54+60*k]);
    end

    % --- rebuild the chain ------------------------------------------
    % 0.02 s (50 Hz) is plenty for pilot input; the Rate Transition then
    % hands it to the continuous solver so there is no data-integrity clash
    % with the (rate-0) Input Selector Switch downstream.
    add_block('simulink/Sources/Constant', [sub '/tick'], ...
        'Value', '0', 'SampleTime', '0.02', 'Position', [30, 150, 80, 180]);

    add_block('simulink/User-Defined Functions/Interpreted MATLAB Function', ...
        [sub '/Sidestick (joybridge)'], ...
        'MATLABFcn', 'joybridge_step', 'OutputDimensions', '4', ...
        'Output1D', 'on', 'OutputSignalType', 'real', 'SampleTime', '0.02', ...
        'Position', [140, 138, 290, 192]);

    add_block('simulink/Signal Attributes/Rate Transition', [sub '/rt'], ...
        'Position', [340, 150, 380, 180]);

    add_block('simulink/Signal Routing/Demux', [sub '/axes'], ...
        'Outputs', '4', 'Position', [430, 90, 435, 240]);

    add_line(sub, 'tick/1',               'Sidestick (joybridge)/1', 'autorouting', 'on');
    add_line(sub, 'Sidestick (joybridge)/1', 'rt/1',                 'autorouting', 'on');
    add_line(sub, 'rt/1',                 'axes/1',                  'autorouting', 'on');
    for k = 1:4
        add_line(sub, sprintf('axes/%d', k), [order{k} '/1'], 'autorouting', 'on');
    end

    % --- select the real-joystick path, wire the run callbacks -------
    set_param(jsPath, 'Commented', 'off');
    sw = [mdl '/Pilot/Input Selector Switch'];
    if blockExists(sw)
        try, set_param(sw, 'sw', '0'); catch, end   % 0 = first (joystick) input
    end
    install_callbacks(mdl);

    save_system(mdl);
    fprintf('patched and saved: %s\n', mdlPath);
    fprintf('  %s\n', sub);
    fprintf('  tick -> Sidestick (joybridge) -> rt -> axes -> 4 outports\n');
    fprintf('  %s StartFcn=<%s>  StopFcn=<%s>\n', mdl, ...
        get_param(mdl, 'StartFcn'), get_param(mdl, 'StopFcn'));
end

% ------------------------------------------------------------------------
function install_callbacks(mdl)
%INSTALL_CALLBACKS  Add joybridge_open/close to the model Start/Stop callbacks
%   without disturbing anything already there. Idempotent.
    add_once(mdl, 'StartFcn', 'joybridge_open;');
    add_once(mdl, 'StopFcn',  'joybridge_close;');
end

function add_once(mdl, cb, line)
    cur = get_param(mdl, cb);
    if ischar(cur) && contains(cur, strtrim(line)), return; end
    if isempty(cur)
        set_param(mdl, cb, line);
    else
        set_param(mdl, cb, sprintf('%s\n%s', cur, line));
    end
    fprintf('  %s += %s\n', cb, strtrim(line));
end

function tf = blockExists(blk)
    try
        get_param(blk, 'BlockType');
        tf = true;
    catch
        tf = false;
    end
end

function cleanup(mdl, wasLoaded)
    if ~wasLoaded && bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
end
