function ok = check_env()
%CHECK_ENV  Verify the toolchain needed for the AE-4311 assignment.
%
%   Checks MATLAB build, required toolboxes, a configured C compiler for
%   MEX, and whether the platform-native S-functions have been built yet.
%
%   ok = CHECK_ENV() returns true if nothing is missing.

ok = true;
fprintf('MATLAB %s   arch=%s   mexext=%s\n', version, computer('arch'), mexext);

% --- toolboxes (tag -> friendly name) ---------------------------------------
need = { ...
    'aeroblks', 'Aerospace Blockset'; ...
    'symbolic', 'Symbolic Math Toolbox (MIMO NDI derivation)'; ...
    'control',  'Control System Toolbox'; ...
    'ident',    'System Identification Toolbox'; ...
    'stats',    'Statistics and Machine Learning Toolbox'};
fprintf('\nToolboxes:\n');
for i = 1:size(need, 1)
    have = ~isempty(ver(need{i, 1}));
    ok = ok && have;
    fprintf('  [%-7s] %s\n', tf(have), need{i, 2});
end

% --- C compiler for MEX ----------------------------------------------------
fprintf('\nC compiler for MEX:\n');
cc = mex.getCompilerConfigurations('C', 'Selected');
if isempty(cc)
    ok = false;
    fprintf('  [MISSING] none selected. Run:  mex -setup C\n');
    fprintf('            (needs Xcode Command Line Tools: xcode-select --install)\n');
else
    fprintf('  [ok     ] %s (%s)\n', cc.Name, cc.Version);
end

% --- native S-functions already built? ----------------------------------
fprintf('\nS-functions for this platform:\n');
md = model_dir();
for s = {'ac_atmos', 'ac_axes'}
    built = isfile(fullfile(md, [s{1} '.' mexext]));
    fprintf('  [%-7s] %s.%s%s\n', tf(built), s{1}, mexext, ...
        ternchar(built, '', '   <-- run build_mex'));
    ok = ok && built;
end

% --- pilot sidestick bridge (macOS: no Simulink 3D Animation) -----------
fprintf('\nJoystick (joybridge helper):\n');
jb = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'lib', 'joybridge', 'joybridge');
if isfile(jb)
    fprintf('  [ok     ] helper built\n');
    [st, out] = system(['"' jb '" --list']);
    dev = strtrim(out);
    if st == 0 && ~isempty(dev) && ~contains(dev, 'no HID')
        fprintf('  [ok     ] %s\n', dev);
    else
        fprintf('  [note   ] no joystick detected right now (connect it, or use Virtual Joystick)\n');
    end
else
    fprintf('  [MISSING] not built - run:  sh "%s"\n', ...
        fullfile(fileparts(jb), 'build.sh'));
    [sc, ~] = system('command -v swiftc');
    if sc ~= 0
        fprintf('            needs swiftc:  xcode-select --install\n');
    end
    % informational only - the model still runs on the Virtual Joystick path
end

fprintf('\n%s\n', ternchar(ok, 'Environment OK.', ...
    'Environment INCOMPLETE - see [MISSING] lines above.'));
end

% ------------------------------------------------------------------------
function s = tf(b),        s = ternchar(b, 'ok', 'MISSING'); end
function s = ternchar(b, a, c), if b, s = a; else, s = c; end, end

function d = model_dir()
here = fileparts(mfilename('fullpath'));           % .../matlab/setup
proj = fileparts(fileparts(here));
d = fullfile(proj, 'model', 'Citation simulation model 2026');
end
