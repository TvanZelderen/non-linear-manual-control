function add_cockpit_view(mdlPath)
%ADD_COCKPIT_VIEW  Add a live 3-D aircraft view to the Citation model (macOS).
%
%   ADD_COCKPIT_VIEW() adds an Aerospace Blockset "MATLAB Animation" block
%   ("Cockpit View") at the root of Citation_FlightGear_v2.mdl. It opens a
%   MATLAB figure during simulation and flies a 3-D aircraft in real time -
%   no FlightGear, no Simulink 3D Animation, both of which the model would
%   otherwise want on macOS.
%
%   It taps the root output demux:
%       Demux1 out:3  = [phi theta psi]  (DEG)   -> *pi/180 -> Euler port (rad)
%       Demux1 out:4  = [h  xe  ye]      (m)     -> [xe ye -h] -> Position port
%   The DASMAT output bus reports Euler angles and body rates in DEGREES
%   (the model's own FlightGear block converts them with Angle Conversion
%   deg->rad); the MATLAB Animation block wants radians, hence "Deg2Rad".
%
%   Idempotent: re-running removes and re-adds the blocks. Pass a path to
%   patch a copy elsewhere. FlightGear stays available in parallel
%   (scripts/runfg.sh); this is the toolbox-free alternative.
%
%   See also PATCH_MODEL_JOYSTICK.

    if nargin < 1 || isempty(mdlPath)
        here = fileparts(mfilename('fullpath'));
        proj = fileparts(fileparts(here));
        mdlPath = fullfile(proj, 'model', 'Citation simulation model 2026', ...
                           'Citation_FlightGear_v2.mdl');
    end
    assert(isfile(mdlPath), 'model not found: %s', mdlPath);

    [~, mdl] = fileparts(mdlPath);
    wasLoaded = bdIsLoaded(mdl);
    if ~wasLoaded, load_system(mdlPath); end
    cleaner = onCleanup(@() cleanup(mdl, wasLoaded));  %#ok<NASGU>

    demux = [mdl '/Demux1'];
    assert(blockExists(demux), 'root Demux1 not found - model layout changed?');

    view  = [mdl '/Cockpit View'];
    gain  = [mdl '/Pos NED'];
    d2r   = [mdl '/Deg2Rad'];
    rtPos = [mdl '/view rt1'];
    rtEul = [mdl '/view rt2'];
    dt    = '0.1';

    % --- clear any previous instance ----------------------------------
    for b = {view, gain, d2r, rtPos, rtEul}
        if blockExists(b{1})
            delete_line_if(b{1});
            delete_block(b{1});
        end
    end

    % --- add ------------------------------------------------------------
    add_block(sprintf('aerolibanim/MATLAB\nAnimation'), view, ...
        'Open', 'on', 'SampleTime', dt, ...
        'Position', [1230, 300, 1320, 370]);

    add_block('simulink/Math Operations/Gain', gain, ...
        'Gain', '[0 1 0; 0 0 1; -1 0 0]', ...     % [h xe ye] -> [xe ye -h]
        'Multiplication', 'Matrix(K*u)', ...
        'Position', [1050, 336, 1090, 364]);

    add_block('simulink/Math Operations/Gain', d2r, ...
        'Gain', 'pi/180', ...                     % [phi theta psi] deg -> rad
        'Position', [1050, 396, 1090, 424]);

    % continuous -> 0.1 s sampled, so the animation rate does not clash
    % with the (rate-0) plant signals feeding it
    add_block('simulink/Signal Attributes/Rate Transition', rtPos, ...
        'OutPortSampleTime', dt, 'Position', [1130, 334, 1170, 366]);
    add_block('simulink/Signal Attributes/Rate Transition', rtEul, ...
        'OutPortSampleTime', dt, 'Position', [1130, 394, 1170, 426]);

    add_line(mdl, 'Demux1/4',   'Pos NED/1',       'autorouting', 'on');
    add_line(mdl, 'Pos NED/1',  'view rt1/1',      'autorouting', 'on');
    add_line(mdl, 'view rt1/1', 'Cockpit View/1',  'autorouting', 'on');
    add_line(mdl, 'Demux1/3',   'Deg2Rad/1',       'autorouting', 'on');
    add_line(mdl, 'Deg2Rad/1',  'view rt2/1',      'autorouting', 'on');
    add_line(mdl, 'view rt2/1', 'Cockpit View/2',  'autorouting', 'on');

    save_system(mdl);
    fprintf('added "Cockpit View" (MATLAB Animation) to %s and saved.\n', mdl);
    fprintf('  a 3-D figure opens on Run; no FlightGear / SL3D needed.\n');
end

% ------------------------------------------------------------------------
function tf = blockExists(blk)
    try, get_param(blk, 'BlockType'); tf = true; catch, tf = false; end
end

function delete_line_if(blk)
    lh = get_param(blk, 'LineHandles');
    h = [lh.Inport(:); lh.Outport(:)];
    delete_line(h(h > 0));
end

function cleanup(mdl, wasLoaded)
    if ~wasLoaded && bdIsLoaded(mdl), close_system(mdl, 0); end
end
