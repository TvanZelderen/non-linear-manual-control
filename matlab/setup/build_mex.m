function build_mex()
%BUILD_MEX  Recompile the Windows-only S-functions for this Mac.
%
%   The Citation model ships ac_atmos and ac_axes only as .mexw32/.mexw64.
%   Their C sources are included and portable (simstruc.h + math.h only), so
%   this rebuilds them as .mexmaca64 (or whatever mexext this MATLAB uses).
%
%   Prerequisite: a configured C compiler.  Run check_env first.

srcs = {'ac_atmos.c', 'ac_axes.c'};
md = model_dir();
assert(isfolder(md), 'Model folder not found: %s', md);

if isempty(mex.getCompilerConfigurations('C', 'Selected'))
    error('build_mex:noCompiler', ...
        'No C compiler selected. Run:  mex -setup C');
end

old = cd(md);
restore = onCleanup(@() cd(old));

fprintf('Building in %s\n', md);
for i = 1:numel(srcs)
    src = srcs{i};
    assert(isfile(src), 'Missing source: %s', src);
    fprintf('  mex %s ... ', src);
    mex(src);
    out = [src(1:end-2) '.' mexext];
    assert(isfile(out), 'Expected output not produced: %s', out);
    fprintf('-> %s\n', out);
end

fprintf('\nDone. Built for %s (%s).\n', computer('arch'), mexext);
fprintf('Next: run initcit, open the model, Ctrl+D, run a 60 s trimmed sim.\n');
end

function d = model_dir()
here = fileparts(mfilename('fullpath'));           % .../matlab/setup
proj = fileparts(fileparts(here));
d = fullfile(proj, 'model', 'Citation simulation model 2026');
end
