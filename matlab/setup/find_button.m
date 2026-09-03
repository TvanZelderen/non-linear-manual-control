function idx = find_button(timeout)
%FIND_BUTTON  Identify a sidestick button index by pressing it.
%
%   idx = FIND_BUTTON() opens a JoyBridge, waits for exactly one button to
%   go down, prints and returns its index. Use it to set the failure toggle
%   button (failure_params 'button' field, or FAIL.button).
%
%   idx = FIND_BUTTON(timeout) overrides the 15 s wait.
%
%   Requires the joybridge helper (matlab/lib/joybridge/build.sh) and a
%   connected stick. Not needed for the scheduled jam (t_fail) - only for
%   the button toggle.
%
%   See also FAILURE_PARAMS, JOYBRIDGE, JOYSTICK_CALIBRATE.

    if nargin < 1 || isempty(timeout), timeout = 15; end

    j = JoyBridge();
    cleaner = onCleanup(@() j.close());

    fprintf('press and hold the button to use as the failure toggle (%g s)...\n', timeout);
    t0 = tic;
    while toc(t0) < timeout
        j.poll();
        k = find(j.button());
        if isscalar(k)
            idx = k;
            fprintf(['button %d down  ->  set failure_params ''button'' = %d ' ...
                     '(or FAIL.button = %d)\n'], idx, idx, idx);
            return
        end
        pause(0.03);
    end
    error('find_button:timeout', ...
        'no single button press detected in %g s', timeout);
end
