function results = run_experiment(specs, opts)
%RUN_EXPERIMENT  Batch-run the Citation model on the desktop over a spec list.
%
%   results = RUN_EXPERIMENT(specs) runs each spec by writing the base-
%   workspace FAIL struct, selecting the pilot input path, setting StopTime,
%   then starting the sim with set_param(mdl,'SimulationCommand','start')
%   and polling SimulationStatus until 'stopped'. It never calls sim() -
%   that segfaults this model (see handover 2026-09-02). Logged data and the
%   fail_armed signal are saved to results/<yyyymmdd-HHMMSS>/<label>.mat and
%   a summary.txt is written.
%
%   specs : struct array, one element per run
%     .label      char, result filename stem
%     .fail       struct written to base FAIL   ([] -> struct('mode','off'))
%     .tstop      stop time [s]                 (default opts.tstop)
%     .input      'asis'    leave the Pilot switch as saved            (default)
%                 'zero'    select the joystick path; with no bridge
%                           joybridge_step holds it at 0 -> trim + jam only
%                 'virtual' select the Virtual Joystick / Signal Builder path
%                 [t u]     recorded-stick replay - NOT YET IMPLEMENTED
%     .controller informational tag ('pi' | 'ndi' | ...) - not acted on yet
%
%   opts (optional struct)
%     .mdl      model name            (default 'Citation_FlightGear_v2')
%     .tstop    default stop time [s] (default 120)
%     .outdir   results root          (default results/<timestamp>)
%     .timeout  wall-clock cap per run [s]  (default 6*tstop + 60)
%
%   results(k) : .label .file .status .vars (cellstr of saved variables)
%
%   See also VALIDATION_MATRIX, FAILURE_PARAMS, PATCH_MODEL_FAILURE.

    if nargin < 2, opts = struct(); end
    dfl = struct('mdl', 'Citation_FlightGear_v2', 'tstop', 120, ...
                 'outdir', '', 'timeout', []);
    opts = merge_opts(dfl, opts);
    if isempty(opts.outdir)
        here = fileparts(mfilename('fullpath'));          % matlab/run
        proj = fileparts(fileparts(here));
        opts.outdir = fullfile(proj, 'results', datestr(now, 'yyyymmdd-HHMMSS')); %#ok<TNOW1,DATST>
    end
    if ~isfolder(opts.outdir), mkdir(opts.outdir); end

    mdl = opts.mdl;
    if ~bdIsLoaded(mdl), load_system(mdl); end
    restoreFail = onCleanup(@() evalin('base', 'clear FAIL'));

    n = numel(specs);
    results = repmat(struct('label', '', 'file', '', 'status', '', 'vars', {{}}), n, 1);
    logLines = {};

    for k = 1:n
        s = specs(k);
        if ~isfield(s, 'label') || isempty(s.label), s.label = sprintf('run%02d', k); end
        fl = s;
        if ~isfield(fl, 'fail') || isempty(fl.fail), fl.fail = struct('mode', 'off'); end
        if ~isfield(fl, 'tstop') || isempty(fl.tstop), fl.tstop = opts.tstop; end
        if ~isfield(fl, 'input') || isempty(fl.input), fl.input = 'asis'; end

        assert(~isnumeric(fl.input), ...
            'run_experiment: recorded-stick replay ([t u]) is not implemented yet');

        fprintf('\n=== run %d/%d : %s ===\n', k, n, s.label);
        assignin('base', 'FAIL', fl.fail);
        select_input(mdl, fl.input);
        set_param(mdl, 'StopTime', num2str(fl.tstop));

        tmo = opts.timeout;
        if isempty(tmo), tmo = 6 * fl.tstop + 60; end
        status = start_and_wait(mdl, tmo);

        vars = grab_outputs();
        outFile = fullfile(opts.outdir, [s.label '.mat']);
        if isempty(fieldnames(vars))
            warning('run_experiment:noData', 'run %s produced no capturable outputs', s.label);
        else
            save(outFile, '-struct', 'vars');
        end

        results(k).label  = s.label;
        results(k).file   = outFile;
        results(k).status = status;
        results(k).vars   = fieldnames(vars);

        logLines{end+1} = sprintf('%-14s  %-8s  t_stop=%-4g  input=%-8s  mode=%-4s  t_fail=%-5g  -> %s', ...
            s.label, status, fl.tstop, fl.input, getf(fl.fail,'mode','?'), ...
            getf(fl.fail,'t_fail',Inf), strjoin(results(k).vars, ',')); %#ok<AGROW>
    end

    summ = fullfile(opts.outdir, 'summary.txt');
    fid = fopen(summ, 'w');
    fprintf(fid, 'run_experiment  %s\nmodel: %s\n\n', datestr(now), mdl); %#ok<TNOW1,DATST>
    fprintf(fid, '%s\n', logLines{:});
    fclose(fid);
    fprintf('\nsummary: %s\n', summ);
end

% ------------------------------------------------------------------------
function o = merge_opts(o, u)
    for c = fieldnames(u).'
        o.(c{1}) = u.(c{1});
    end
end

function select_input(mdl, mode)
%SELECT_INPUT  Position the Pilot ManualSwitch. 'asis' -> no-op.
    sw = [mdl '/Pilot/Input Selector Switch'];
    try
        switch lower(mode)
            case 'asis'
                % leave as saved
            case {'zero', 'joystick'}
                set_param(sw, 'sw', '0');   % first input = joystick path
            case 'virtual'
                set_param(sw, 'sw', '1');   % second input = Virtual Joystick / SigBuilder
            otherwise
                warning('run_experiment:input', 'unknown input mode "%s" - leaving as is', mode);
        end
    catch err
        warning('run_experiment:switch', 'could not set Pilot switch (%s)', err.message);
    end
end

function status = start_and_wait(mdl, timeout)
    set_param(mdl, 'SimulationCommand', 'start');
    t0 = tic;
    while ~strcmp(get_param(mdl, 'SimulationStatus'), 'stopped')
        if toc(t0) > timeout
            set_param(mdl, 'SimulationCommand', 'stop');
            status = 'TIMEOUT';
            return
        end
        pause(0.2);
    end
    status = 'stopped';
end

function vars = grab_outputs()
%GRAB_OUTPUTS  Pull whatever the run left in the base workspace.
    vars = struct();
    for name = {'tout', 'yout', 'xout', 'logsout', 'fail_armed', 'out'}
        nm = name{1};
        if evalin('base', sprintf('exist(''%s'',''var'')==1', nm))
            vars.(nm) = evalin('base', nm);
        end
    end
end

function v = getf(s, f, dflt)
    if isstruct(s) && isfield(s, f), v = s.(f); else, v = dflt; end
end
