function p = citation_params()
%CITATION_PARAMS  Cessna Citation 550 data for the AE-4311 assignment.
%
%   All values transcribed from "AE4311 Assignment 2026-1-ANDI.pdf" and the
%   supplied Simulink model. Verify state/channel ordering against the model
%   before wiring the controller (the brief warns it is inconsistent).

% --- inertia [kg m^2] --------------------------------------------------
p.Ixx = 11187.8;
p.Iyy = 22854.8;
p.Izz = 31974.8;
p.Ixz = 1930.1;
p.I   = [ p.Ixx,      0, -p.Ixz ;
               0,  p.Iyy,      0 ;
         -p.Ixz,      0,  p.Izz ];

% --- geometry --------------------------------------------------------------
p.b = 13.3250;   % wing span [m]
p.S = 24.9900;   % wing area [m^2]
p.c = 1.9910;    % mean aerodynamic chord [m]

% --- ISA density model, brief eqs. (1.1)-(1.2) --------------------------
p.isa.R        = 287.05;    % gas constant [m^2 s^-2 K^-1]
p.isa.T0       = 288.15;    % sea-level temperature [K]
p.isa.lambda   = -0.0065;   % tropospheric lapse rate [K/m]
p.isa.rho0     = 1.225;     % sea-level density [kg/m^3]
p.isa.h0       = 0;         % reference altitude [m]
p.isa.h_tropo  = 11000;     % tropopause [m]
p.isa.h_strato = 20000;     % stratopause [m]
p.g            = 9.80665;   % [m/s^2]  (yacc outputs are in g -> multiply)

% --- trim condition: CitTrim_AE4311_2026_V120_A7500_M4500.tri -----------
p.trim.V    = 120;    % true airspeed [m/s]
p.trim.alt  = 7500;   % [m]
p.trim.mass = 4500;   % [kg]

% --- actuator model (Simulink "Actuators" block) -----------------------
p.act.wn     = 13;              % first-order servo bandwidth [rad/s]
p.act.lim.da = [-0.65, 0.65];   % aileron  [rad]
p.act.lim.de = [-0.35, 0.26];   % elevator [rad]
p.act.lim.dr = [-0.38, 0.38];   % rudder   [rad]

% --- failure: aileron hardover (brief eq. 1.4) -------------------------
p.fail.da_gain   = 0.5;     % halved effectiveness
p.fail.da_offset = -0.28;   % stuck offset [rad]  (-16 deg)

% --- classical baseline PI rate-controller gains (brief step 6) ---------
p.pi.da = struct('P', -1,  'I', -0.5);
p.pi.de = struct('P', -2,  'I', -0.1);
p.pi.dr = struct('P', -2,  'I', -0.1);
end
