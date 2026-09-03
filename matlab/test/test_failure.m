function test_failure()
%TEST_FAILURE  Pure-function checks for the aileron-hardover failure (S2).
%
%   Runs the two Simulink-free checks from the S2 build plan:
%     T1  failure_step   - pass-through, scheduled jam, offset math,
%                          'off'/'on' modes, momentary button (jam while held)
%     T2  failure_params - base-workspace FAIL overlay + validation
%
%   No model, no sim() - safe under `matlab -batch`. The in-model checks
%   (patch idempotency, scheduled jam, live button, runner) are done in the
%   desktop per the plan's Verification section.
%
%   Usage:  test_failure

    fprintf('== test_failure ==\n');
    t1_failure_step();
    t2_failure_params();
    fprintf('\nALL PURE-FUNCTION CHECKS PASSED\n');
end

% ------------------------------------------------------------------------
function t1_failure_step()
    clearvars -global FAILCFG JOYBRIDGE
    global FAILCFG JOYBRIDGE   %#ok<GVMIS>

    FAILCFG = struct('mode','auto','t_fail',5,'button',2, ...
                     'gain',0.5,'offset',-0.28,'verbose',false);

    y0 = failure_step([0.10; 0.00]);     % before t_fail -> pass through
    y1 = failure_step([0.10; 4.99]);     % still before
    y2 = failure_step([0.10; 5.00]);     % jam: 0.5*0.10 - 0.28 = -0.23
    y3 = failure_step([0.20; 7.00]);     % jammed: 0.5*0.20 - 0.28 = -0.18
    y4 = failure_step([0.10; 4.00]);     % t < t_fail again -> pass through (stateless)

    check('T1 pass-through before t_fail',  isequal(y0,[0.10;0]) && isequal(y1,[0.10;0]));
    check('T1 jam triggers at t_fail',      y2(2)==1 && abs(y2(1) - (-0.23)) < 1e-12);
    check('T1 jam law after t_fail',        y3(2)==1 && abs(y3(1) - (-0.18)) < 1e-12);
    check('T1 stateless: no memory of jam', isequal(y4,[0.10;0]));

    % --- 'off' / 'on' modes --------------------------------------------
    FAILCFG.mode = 'off';
    check('T1 mode=off never fails', isequal(failure_step([0.10; 99]), [0.10;0]));

    FAILCFG.mode = 'on';
    yon = failure_step([0.10; 0]);
    check('T1 mode=on fails from t=0', yon(2)==1 && abs(yon(1) - (-0.23)) < 1e-12);

    % --- momentary button: jam while held ---------------------------
    FAILCFG.mode = 'auto';  FAILCFG.t_fail = Inf;  FAILCFG.button = 1;
    JOYBRIDGE = JoyButtonStub(false);

    b0 = failure_step([0.1; 1]);  check('T1 button up -> nominal',        isequal(b0,[0.1;0]));
    JOYBRIDGE.state = true;
    b1 = failure_step([0.1; 2]);  check('T1 button held -> jammed',       b1(2)==1 && abs(b1(1)-(-0.23))<1e-12);
    b2 = failure_step([0.1; 3]);  check('T1 button still held -> jammed', b2(2)==1);
    JOYBRIDGE.state = false;
    b3 = failure_step([0.1; 4]);  check('T1 button released -> nominal',  isequal(b3,[0.1;0]));

    % --- scheduled jam OR button (either arms it) ------------------
    FAILCFG.t_fail = 10;
    c1 = failure_step([0.1; 8]);   check('T1 before t_fail, button up -> nominal', isequal(c1,[0.1;0]));
    JOYBRIDGE.state = true;
    c2 = failure_step([0.1; 8]);   check('T1 before t_fail, button held -> jammed', c2(2)==1);
    JOYBRIDGE.state = false;
    c3 = failure_step([0.1; 12]);  check('T1 after t_fail, button up -> jammed',    c3(2)==1);

    % --- wrong button index / no bridge -> button term is just false --
    FAILCFG.button = 9;  FAILCFG.t_fail = Inf;
    JOYBRIDGE.state = true;                       % button 1 down, but cfg wants 9
    d1 = failure_step([0.1; 3]);  check('T1 out-of-range button -> nominal', isequal(d1,[0.1;0]));
    JOYBRIDGE = [];
    d2 = failure_step([0.1; 3]);  check('T1 no bridge -> nominal',           isequal(d2,[0.1;0]));

    % --- ran before StartFcn (FAILCFG empty) -> pass through ----------
    clearvars -global FAILCFG
    check('T1 no config -> pass through', isequal(failure_step([0.42; 1]), [0.42;0]));

    clearvars -global FAILCFG JOYBRIDGE
end

% ------------------------------------------------------------------------
function t2_failure_params()
    evalin('base', 'clear FAIL');

    f = failure_params();
    check('T2 defaults', strcmp(f.mode,'auto') && isinf(f.t_fail) && ...
                         f.gain==0.5 && abs(f.offset - (-0.28)) < 1e-12);

    assignin('base', 'FAIL', struct('mode','on','t_fail',12));
    f = failure_params();
    check('T2 overlay', strcmp(f.mode,'on') && f.t_fail==12 && f.gain==0.5);

    assignin('base', 'FAIL', struct('bogus',1));
    check('T2 rejects unknown field', throws(@failure_params));

    assignin('base', 'FAIL', struct('mode','sideways'));
    check('T2 rejects bad mode', throws(@failure_params));

    assignin('base', 'FAIL', struct('t_fail',-3));
    check('T2 rejects negative t_fail', throws(@failure_params));

    evalin('base', 'clear FAIL');
end

% ------------------------------------------------------------------------
function tf = throws(fn)
    tf = false;
    try
        fn();
    catch
        tf = true;
    end
end

function check(name, cond)
    if cond
        fprintf('  ok   %s\n', name);
    else
        error('test_failure:fail', 'FAILED: %s', name);
    end
end
