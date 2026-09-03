function specs = validation_matrix(varargin)
%VALIDATION_MATRIX  Canonical run set for the AE-4311 handling-quality comparison.
%
%   specs = VALIDATION_MATRIX() returns the 4-run spec array the report
%   needs per controller: classical PI baseline vs ANDI/INDI, each with and
%   without the aileron failure.
%
%   Name/value options:
%     't_fail'  scheduled jam time [s]           (default 30)
%     'tstop'   stop time [s]                    (default 120)
%     'input'   pilot input source for run_experiment
%                 'asis' | 'zero' | 'virtual'    (default 'asis')
%
%   The 'controller' field is informational until step 5/7 wire the loops;
%   run_experiment currently executes every row with whatever controller
%   path the model has saved. Run rows 1-2 now (classical), 3-4 once ANDI/
%   INDI exists.
%
%   Example
%     specs = validation_matrix('t_fail',20,'tstop',40);
%     R = run_experiment(specs(1:2));
%
%   See also RUN_EXPERIMENT, FAILURE_PARAMS.

    ip = inputParser;
    ip.addParameter('t_fail', 30, @(x)isscalar(x) && x >= 0);
    ip.addParameter('tstop', 120, @(x)isscalar(x) && x > 0);
    ip.addParameter('input', 'asis', @(x)ischar(x) || isstring(x));
    ip.parse(varargin{:});
    o = ip.Results;

    jam = struct('mode', 'auto', 't_fail', o.t_fail);
    off = struct('mode', 'off');

    mk = @(label, fail, ctrl) struct( ...
        'label', label, 'fail', fail, 'tstop', o.tstop, ...
        'input', char(o.input), 'controller', ctrl);

    specs = [ ...
        mk('pi_nominal',  off, 'pi'); ...
        mk('pi_fail',     jam, 'pi'); ...
        mk('ndi_nominal', off, 'ndi'); ...
        mk('ndi_fail',    jam, 'ndi') ];
end
