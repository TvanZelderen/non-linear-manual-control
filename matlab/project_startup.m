function project_startup()
%PROJECT_STARTUP  Add all AE4-311 project folders to the MATLAB path.
%
%   Run this once at the start of a session (from anywhere):
%       run('<project>/matlab/project_startup.m')
%
%   It puts our code, the teaching demos, and the extracted Citation model
%   folder on the path so initcit / the model data files resolve.

here = fileparts(mfilename('fullpath'));      % .../matlab
proj = fileparts(here);                       % project root

addpath(genpath(fullfile(proj, 'matlab')));
addpath(fullfile(proj, 'reference'));
addpath(fullfile(proj, 'model', 'Citation simulation model 2026'));

fprintf('AE4-311 project paths added.\n');
fprintf('  check_env    verify MATLAB version, toolboxes, C compiler\n');
fprintf('  build_mex    compile ac_atmos / ac_axes for this Mac (S1)\n');
fprintf('  citation_params   struct of aircraft data from the brief\n');
end
