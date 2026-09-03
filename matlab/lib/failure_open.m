function failure_open()
%FAILURE_OPEN  Load the failure config for one simulation run.
%
%   Installed on the model StartFcn by patch_model_failure, AFTER
%   joybridge_open (failure_step reads the sidestick through the same
%   global JOYBRIDGE that joybridge_open creates). Seeds global FAILCFG,
%   which failure_step reads every step.
%
%   failure_step is stateless, so there is no latch to reset here.
%
%   See also FAILURE_STEP, FAILURE_PARAMS, PATCH_MODEL_FAILURE.

    global FAILCFG   %#ok<GVMIS>

    FAILCFG = failure_params();

    if FAILCFG.verbose
        switch FAILCFG.mode
            case 'off'
                fprintf('failure_open: mode=off  (aileron nominal all run)\n');
            case 'on'
                fprintf(['failure_open: mode=on   (aileron jammed from t=0: ' ...
                         'da_act = %.2f*da %+.2f rad)\n'], FAILCFG.gain, FAILCFG.offset);
            case 'auto'
                if isfinite(FAILCFG.t_fail)
                    fprintf(['failure_open: mode=auto t_fail=%g s  button=%d  ' ...
                             '(da_act = %.2f*da %+.2f rad when jammed)\n'], ...
                             FAILCFG.t_fail, FAILCFG.button, FAILCFG.gain, FAILCFG.offset);
                else
                    fprintf(['failure_open: mode=auto t_fail=Inf  button=%d  ' ...
                             '(hold the button to jam)\n'], FAILCFG.button);
                end
        end
    end
end
