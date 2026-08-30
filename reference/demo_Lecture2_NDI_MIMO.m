
% clear all;


% define states
x1 = sym('x1');
x2 = sym('x2');
x3 = sym('x3');
u1 = sym('u1'); % 1st actual control
u2 = sym('u2'); % 2nd actual control
nu1 = sym('nu1'); % virtual control
nu2 = sym('nu2'); % virtual control
% state vector
x = [x1; x2; x3];
% input vector
u = [u1; u2];
% virtual controls
nu = [nu1; nu2];

% define system equations 
% xdot = f(x) + g(x)*u
% y = h(x) 
% First define f(x):
fx = [sin(x2) + (x2+1)*x3;
    x1^5 + x3;
    x1^2];

% Then define the control effectiveness function g(x):
Gx = [0 0; 1 0; 0 1];

% Finally, the output function y = h(x):
hx = [cos(x1); sin(x3)];

%%
% First output state coordinate transforms 
z11 = hx(1);
z12 = LieFx(fx, hx(1), x);
z13 = LieFx(fx, hx(1), x, 2);

% 1st output state coordinate transform time derivatives
z11dot = LieFx(fx, hx(1), x) + LieFx(Gx, hx(1), x)*u; % = z2

b1x = LieFx(fx, hx(1), x, 2);
a1x = LieFx(Gx, LieFx(fx, hx(1), x), x);
z12dot =  b1x + a1x*u;

% u_ndi = 1/a1x*(nu1 - b1x);
% z13dot = LieFx(fx,hx,x,3) + LieFx(Gx, LieFx(fx, hx, x, 2), x) * u_ndi;
% z13dot_u = LieFx(fx,hx,x,3) + LieFx(Gx, LieFx(fx, hx, x, 2), x) * u;

% Second output state coordinate transforms
z21 = hx(2);
z22 = LieFx(fx, hx(2), x);
z23 = LieFx(fx, hx(2), x, 2);

% 2nd output state coordinate transform time derivatives
b2x = LieFx(fx, hx(2), x);
a2x = LieFx(Gx, hx(2), x);
z21dot = b2x + a2x*u; % = z2

% z22dot is not required, as total relative degree = 3!/
% z22dot =  LieFx(fx, hx(2), x, 2) + LieFx(Gx, LieFx(fx, hx(2), x), x)*u;

% u_ndi = 1/a1x*(nu1 - b1x);
% 
% z23dot = LieFx(fx,hx,x,3) + LieFx(Gx, LieFx(fx, hx, x, 2), x) * u_ndi;
% z23dot_u = LieFx(fx,hx,x,3) + LieFx(Gx, LieFx(fx, hx, x, 2), x) * u;

%% 
% Compute complete A(x) matrix 
Ax1 = LieFx(Gx, LieFx(fx, hx(1), x), x);
Ax2 = LieFx(Gx, hx(2), x);
Ax = [Ax1; Ax2];
% And the b(x) vector:
bx = [b1x; b2x];

% MIMO NDI control law (symbolic!):
u_ndi = inv(Ax)*(nu - bx);

%% 
% Do tracking task:
dt = 0.01;
t = (0:dt:10);
N = length(t);

% desired system output
y1d = 0.5*sin(t); % works well
y2d = ones(1,N);
% y1d = .5*ones(1,N); % not so nice tracking
% y2d = 0.5*sin(t);
Yd = [y1d; y2d];

% initial values for output (derivatives)
Yd0 = Yd(:,1);
dYd0 = [0; 0];
ddYd0 = [0; 0];

X = [1; 0; 0]; % initial state
Y0 = double(subs(hx, {x1,x2,x3}, X'));
dY0 = [0; 0];
ddY0 = [0; 0];

Xset  = zeros(3, N); % state history
Yset  = zeros(2, N); % output history
Uset  = zeros(2, N); % control history
NUset = zeros(2, N); % virtual control history

% gains (first input-output)-> Tuning is tricky!
k11 = 100;
k12 = 1000;
k13 = 1000;

% gains (second input-output)-> Tuning is tricky!
k21 = 1;
k22 = 0.1;
k23 = 0.1;

% NDI loop
for i = 1:N
    Y    = double(subs(hx, {x1,x2,x3}, X')); % system output
    Yset(:,i) = Y;

    % output derivatives
    dY      = Y - Y0;
    ddY     = dY - dY0;
    dddY    = ddY - ddY0;
    % desired output derivatives
    dYd      = Yd(:,i) - Yd0(:,i);
    ddYd     = dYd - dYd0;
    dddYd    = ddYd - ddYd0;

    % error dynamics
    e       = Yd(:,i) - Y; 
    de      = dYd - dY0;
    dde     = ddYd - ddY0;

    % virtual control computation
    NU1     = dddYd(1) + (k11*e(1) + k12*de(1) + k13*dde(1)); % virtual control
    NU2     = dddYd(2) + (k21*e(2) + k22*de(2) + k23*dde(2)); % virtual control
    NUset(:,i) = [NU1; NU2];

    % non-input related system dynamics function
    FX = double(subs(fx, {x1,x2,x3}, X'));
    % control effectiveness function
    GX = double(subs(Gx, {x1,x2,x3}, X'));
    % NDI control input
    U = double(subs(u_ndi, {x1,x2,x3,nu1,nu2}, [X', NU1, NU2]));
    Uset(:,i) = U;

    % Compute xdot
    dX = FX + GX * U;
    
    X = X + dX*dt; % first order integration
    Xset(:,i) = X;

    % compute output (derivative) updates
    Y0 = Y;
    dY0 = dY;
    ddY0 = ddY;

    Yd0 = Yd;
    dYd0 = dYd;
    ddYd0 = ddYd;

end


%%
close all;



plotID = 1001;
figure(plotID);
set(plotID, 'Position', [0 50 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
hold on;
plot(t, Yd(1,:), 'b--');
plot(t, Yd(2,:), 'r--');
plot(t, Yset(1,:), 'b');
plot(t, Yset(2,:), 'r');
legend('Yd(1)', 'Yd(2)', 'Y(1)_{NDI}', 'Y(2)_{NDI}');
xlabel('time');
ylabel('Y');
title('NDI tracking performance');


plotID = 1011;
figure(plotID);
set(plotID, 'Position', [0 550 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
hold on;
plot(t, Xset(1,:), 'b');
plot(t, Xset(2,:), 'r');
plot(t, Xset(3,:), 'k');
legend('x(1)', 'x(2)', 'x(3)');
xlabel('time');
ylabel('X');
title('System states');


plotID = 1002;
figure(plotID);
set(plotID, 'Position', [640 50 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
hold on;
plot(t, NUset(1,:), 'b');
plot(t, NUset(2,:), 'r');
legend('\nu(1)', '\nu(2)');
xlabel('time');
ylabel('virtual control');
title('NDI virtual control');

plotID = 1003;
figure(plotID);
set(plotID, 'Position', [640 550 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
hold on;
plot(t, Uset(1,:), 'b');
plot(t, Uset(2,:), 'r');
legend('u(1)', 'u(2)');
xlabel('time');
ylabel('u');
title('NDI actual control');



