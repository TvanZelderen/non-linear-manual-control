function patch_model_failure(mdlPath, sampleTime)
%PATCH_MODEL_FAILURE  Splice the aileron-hardover failure into the model.
%
%   PATCH_MODEL_FAILURE() patches
%   model/Citation simulation model 2026/Citation_FlightGear_v2.mdl in place;
%   pass a path as the first argument to patch a copy elsewhere.
%
%   PATCH_MODEL_FAILURE(mdlPath, sampleTime) overrides the failure block's
%   sample time (default '-1', inherited). Use '0.02' if Update Diagram
%   rejects the inherited rate - the function then inserts a Rate Transition
%   between fx out/1 and Mux/2.
%
%   Inside  Cessna Citation 500 / Actuators  it cuts the line
%
%       da limits (Saturate, out:1)  ->  Mux (in:2)
%
%   - the post-servo, post-saturation aileron deflection - and routes it
%   through a failure block:
%
%       da limits/1 --+--> da+t (Mux 2) --> Sidestick failure --> fx out (Demux 2)
%       Fail clock ---'        [da;t]      (Interpreted MATLAB     |1: da_actual --> Mux/2
%                                           Fcn: failure_step)     |2: armed     --> fail_armed
%
%   "Sidestick failure" runs failure_step in the interpreter each step
%   (Normal-mode simulation only). Config + latch are seeded once per run by
%   failure_open, appended to the model StartFcn after joybridge_open. The
%   node da limits/1 is left untouched - it stays the clean pre-failure
%   signal that step 3 (RLS) taps.
%
%   Idempotent and self-repairing: it deletes its own 5 blocks and rebuilds
%   the chain every call, so re-running after a code change just refreshes
%   it. A one-time backup <model>.mdl.prefailure.bak is written next to the
%   model.
%
%   Run patch_model_joystick BEFORE this (so StartFcn already carries
%   joybridge_open;, and failure_open; lands after it).
%
%   See also FAILURE_STEP, FAILURE_OPEN, FAILURE_PARAMS, PATCH_MODEL_JOYSTICK.

    if nargin < 2 || isempty(sampleTime), sampleTime = '-1'; end
    inherited = strcmp(sampleTime, '-1');

    if nargin < 1 || isempty(mdlPath)
        here = fileparts(mfilename('fullpath'));               % matlab/setup
        proj = fileparts(fileparts(here));
        mdlPath = fullfile(proj, 'model', 'Citation simulation model 2026', ...
                           'Citation_FlightGear_v2.mdl');
    end
    assert(isfile(mdlPath), 'model not found: %s', mdlPath);

    bak = [mdlPath '.prefailure.bak'];
    if ~isfile(bak)
        copyfile(mdlPath, bak);
        fprintf('backup written: %s\n', bak);
    end

    [~, mdl] = fileparts(mdlPath);
    wasLoaded = bdIsLoaded(mdl);
    if ~wasLoaded, load_system(mdlPath); end
    cleaner = onCleanup(@() cleanup(mdl, wasLoaded));

    acts = [mdl '/Cessna Citation 500/Actuators'];
    assert(blockExists(acts), 'subsystem not found: %s', acts);
    assert(blockExists([acts '/da limits']), 'block not found: %s/da limits', acts);
    assert(blockExists([acts '/Mux']),       'block not found: %s/Mux', acts);

    added = {'Fail clock', 'da+t', 'Sidestick failure', 'fx out', 'fail_armed', 'fail rt'};

    % --- tear down any previous patch --------------------------------
    for i = 1:numel(added)
        b = [acts '/' added{i}];
        if blockExists(b), delete_block(b); end   % removes most attached lines
    end
    % delete_block can leave dangling line stubs behind - sweep them
    stubs = find_system(acts, 'SearchDepth', 1, 'FindAll', 'on', ...
                        'LookUnderMasks', 'on', 'Type', 'line');
    for h = stubs(:).'
        if get_param(h, 'SrcBlockHandle') == -1 || get_param(h, 'DstBlockHandle') == -1
            delete_line(h);
        end
    end
    % make sure the splice endpoints are free: da limits/1 (tap source) and
    % Mux/2 (aileron slot). On the first-ever run this removes the original
    % da limits/1 -> Mux/2 line.
    clear_port([acts '/da limits'], 'out', 1);
    clear_port([acts '/Mux'],       'in',  2);

    % --- build the failure chain -----------------------------------
    add_block('simulink/Sources/Clock', [acts '/Fail clock'], ...
        'Position', [590, 286, 612, 304]);

    add_block('simulink/Signal Routing/Mux', [acts '/da+t'], ...
        'Inputs', '2', 'DisplayOption', 'bar', 'Position', [640, 205, 645, 251]);

    add_block('simulink/User-Defined Functions/Interpreted MATLAB Function', ...
        [acts '/Sidestick failure'], ...
        'MATLABFcn', 'failure_step', 'OutputDimensions', '2', ...
        'Output1D', 'on', 'OutputSignalType', 'real', 'SampleTime', sampleTime, ...
        'Position', [680, 200, 800, 256]);

    add_block('simulink/Signal Routing/Demux', [acts '/fx out'], ...
        'Outputs', '2', 'Position', [840, 205, 845, 251]);

    add_block('simulink/Sinks/To Workspace', [acts '/fail_armed'], ...
        'VariableName', 'fail_armed', 'SaveFormat', 'Timeseries', ...
        'Position', [900, 286, 970, 304]);

    add_line(acts, 'da limits/1',       'da+t/1',            'autorouting', 'on');
    add_line(acts, 'Fail clock/1',      'da+t/2',            'autorouting', 'on');
    add_line(acts, 'da+t/1',            'Sidestick failure/1', 'autorouting', 'on');
    add_line(acts, 'Sidestick failure/1', 'fx out/1',        'autorouting', 'on');
    add_line(acts, 'fx out/2',          'fail_armed/1',      'autorouting', 'on');

    if inherited
        add_line(acts, 'fx out/1', 'Mux/2', 'autorouting', 'on');
    else
        add_block('simulink/Signal Attributes/Rate Transition', [acts '/fail rt'], ...
            'Position', [870, 210, 900, 240]);
        add_line(acts, 'fx out/1',  'fail rt/1', 'autorouting', 'on');
        add_line(acts, 'fail rt/1', 'Mux/2',     'autorouting', 'on');
    end

    % --- StartFcn: failure_open; after joybridge_open; --------------
    add_once(mdl, 'StartFcn', 'failure_open;');

    save_system(mdl);
    fprintf('patched and saved: %s\n', mdlPath);
    fprintf('  %s\n', acts);
    fprintf('  da limits/1 -> [da+t | Fail clock] -> Sidestick failure -> fx out -> Mux/2\n');
    fprintf('                                                          \\-> fail_armed\n');
    if inherited
        fprintf('  sample time = -1  (inherited, no Rate Transition)\n');
    else
        fprintf('  sample time = %s  (+ Rate Transition before Mux/2)\n', sampleTime);
    end
    fprintf('  %s StartFcn=<%s>\n', mdl, get_param(mdl, 'StartFcn'));
end

% ------------------------------------------------------------------------
function add_once(mdl, cb, line)
%ADD_ONCE  Append a line to a model callback if it is not already there.
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

function clear_port(blk, io, idx)
%CLEAR_PORT  Delete the line on one port of a block, if any.
    try
        ph = get_param(blk, 'PortHandles');
        if strcmpi(io, 'out'), h = ph.Outport(idx); else, h = ph.Inport(idx); end
        L = get_param(h, 'Line');
        if L ~= -1, delete_line(L); end
    catch
        % nothing connected
    end
end

function cleanup(mdl, wasLoaded)
    if ~wasLoaded && bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
end
