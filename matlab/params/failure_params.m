function f = failure_params()
%FAILURE_PARAMS  Aileron-hardover failure configuration for the AE-4311 model.
%
%   f = FAILURE_PARAMS() returns the failure config struct used by
%   failure_open / failure_step. Defaults come from citation_params; any
%   field present in a base-workspace struct named FAIL overrides the
%   matching default, so a run script can do:
%
%       FAIL = struct('mode','auto','t_fail',30);   % jam at t = 30 s
%       FAIL.button = 4;                             % + sidestick toggle
%
%   Fields
%     mode     'off' | 'on' | 'auto'                  (default 'auto')
%                off  - aileron never fails
%                on   - failed from t = 0
%                auto - scheduled jam OR button held (below)
%     t_fail   scheduled jam time [s], auto mode      (default Inf = button only)
%     button   sidestick button index that jams the   (default 2, a guess -
%              aileron while held                       resolve with find_button)
%     gain     loss of aileron effectiveness          (default 0.5)
%     offset   stuck deflection added after the gain  (default -0.28 rad)
%     verbose  print the config line at StartFcn      (default true)
%
%   auto-mode logic (evaluated every step in failure_step, stateless):
%     armed = (t >= t_fail) OR (sidestick button <button> held down).
%   The scheduled jam is one-way by construction; the button is momentary
%   (jam while held) - a convenience for messing around, not the workflow.
%
%   See also FAILURE_OPEN, FAILURE_STEP, CITATION_PARAMS, PATCH_MODEL_FAILURE,
%   FIND_BUTTON.

    p = citation_params();

    f = struct( ...
        'mode',    'auto', ...
        't_fail',  Inf, ...
        'button',  1, ...
        'gain',    p.fail.da_gain, ...     % 0.5
        'offset',  p.fail.da_offset, ...   % -0.28 rad
        'verbose', true);

    % --- overlay base-workspace FAIL, if the user set one -----------------
    if evalin('base', 'exist(''FAIL'',''var'') == 1')
        u = evalin('base', 'FAIL');
        assert(isstruct(u), 'FAIL must be a struct');
        for c = fieldnames(u).'
            k = c{1};
            assert(isfield(f, k), 'unknown FAIL field: %s', k);
            f.(k) = u.(k);
        end
    end

    f.mode = validatestring(f.mode, {'off','on','auto'}, 'failure_params', 'mode');
    validateattributes(f.t_fail, {'numeric'}, {'scalar','real','nonnegative'}, ...
        'failure_params', 't_fail');
    validateattributes(f.button, {'numeric'}, {'scalar','integer','positive'}, ...
        'failure_params', 'button');
    validateattributes(f.gain,   {'numeric'}, {'scalar','real','finite'}, ...
        'failure_params', 'gain');
    validateattributes(f.offset, {'numeric'}, {'scalar','real','finite'}, ...
        'failure_params', 'offset');
end
