
clear all;
close all;
% NDI full relative degree
% System equations:
% dx1/dt = exp(x2)*u
% dx2/dt = x1 + x2^3 + exp(x2) * u
% dx3/dt = exp(x2)*u
% y      = x3

% k1 = 100; % first gain
% k2 = 50;  % second gain
% k3 = 10;  % third gain
k1 = 100; % first gain
k2 = k1/2;  % second gain
k3 = k1/10;  % third gain
% defaults
% k1 = 100; % first gain
% k2 = 50;  % second gain
% k3 = 10;  % third gain

N = 3000;
dt = 0.001;
time = 0:dt:(N-1)*dt;

x = [0 0 10]'; %initial states
 
yd    = zeros(size(time));
dyd   = zeros(size(time));
ddyd  = zeros(size(time));
dddyd = zeros(size(time));

% omega_yd = 1.5;
% amp_yd = 2;
% yd    = amp_yd*sin(omega_yd*time);
% dyd   = amp_yd*cos(omega_yd*time);
% ddyd  = -amp_yd*sin(omega_yd*time);
% dddyd = -amp_yd*cos(omega_yd*time);

% NDI loop
dx_0 = 0;
for i = 1:N
    y       = x(3);
    yv(i)   = y;
    xv(:,i) = x;
    dy      = x(1) - x(2);
    ddy     = -x(1) - x(2)^3;
    e       = yd(i) - y;
    de      = dyd(i) - dy;
    dde     = ddyd(i) - ddy;
    v       = dddyd(i) + (k1*e + k2*de + k3*dde); % virtual control
    
    vv(i) = v;
    ainv = -1 / ((1 + 3*x(2)^2)*exp(x(2)));
    b = -3*x(2)^2 * (x(1) + x(2)^3);    
    u = ainv*(v - b); % actual control input
    uv(i) = u;
    dx = [exp(x(2))*u;
          x(1) + x(2)^3 + exp(x(2))*u;
          x(1) - x(2)];
%     x = x +  1/2*dt*(dx_0 + dx); % trapezium rule integration
%     dx_0 = dx;
    x = x + dx*dt; % first order integration

end
%%

% PID loop (unstable!)
x = [0 0 1]'; %initial states
k1 = 0.1; % first gain
k2 = k1/2;  % second gain
k3 = k1/10;  % third gain
for i = 1:N
    y           = x(3);
    yvpid(i)    = y;
    xvpid(:,i)  = x;
    dy          = x(1) - x(2);
    ddy         = -x(1) - x(2)^3;
    e           = yd(i) - y;
    de          = dyd(i) - dy;
    dde         = ddyd(i) - ddy;
    u           = dddyd(i) + (k1*e + k2*de + k3*dde); % control input
    
    uvpid(i) = u;
    dx = [exp(x(2))*u;
          x(1) + x(2)^3 + exp(x(2))*u;
          x(1) - x(2)];
    x = x + dx*dt; % first order integration
end

%
close all;



plotID = 1001;
figure(plotID);
set(plotID, 'Position', [0 50 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
hold on;
plot(time, yd, 'r');
plot(time, yvpid, 'b');
legend('reference', 'y_{PID}');
xlabel('time');
ylabel('y');
title('PID tracking performance');

plotID = 1011;
figure(plotID);
set(plotID, 'Position', [640 50 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
hold on;
plot(time, uvpid, 'b');
legend('control input');
xlabel('time');


plotID = 1002;
figure(plotID);
set(plotID, 'Position', [0 500 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
hold on;
plot(time, yd, 'r');
plot(time, yv, 'b');
% plot(time, yvpid);
legend('reference', 'y_{NDI}');
xlabel('time');
ylabel('y');
title('NDI tracking performance');

% plotID = 1012;
% figure(plotID);
% set(plotID, 'Position', [640 50 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
% plot(time, yv-yd) 
% xlabel('time');
% ylabel('y-yd');

plotID = 1013;
figure(plotID);
set(plotID, 'Position', [640 500 640 480], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
hold on;
plot(time, vv, 'r') 
plot(time, uv, 'b');
legend('virtual control', 'control input');
xlabel('time');



% %%
% plotID = 1001;
% 
% figure(plotID);
% set(plotID, 'Position', [600 150 800 800], 'defaultaxesfontsize', 10, 'defaulttextfontsize', 10, 'PaperPositionMode', 'auto');
% hold on;
% grid on;
% minz = min(val_spline);
% maxz = max(val_spline);
% trimesh(TRI, PHI(:, 1), PHI(:, 2), minz*ones(size(PHI,1),1), 'EdgeColor', 'b');
% % surf(xxe, yye, reshape(val_spline, size(xxe)));
% trisurf(TRIeval, XIeval(:,1), XIeval(:,2), val_spline);%, reshape(val_spline, size(xxe)));
% poslight = light('Position',[1.5 2.5 7],'Style','local');
% material([.3 .8 .9 25]);
% lighting phong;
% shading interp;
% view(viewaz, viewel);
% titstr = sprintf('Spline function of degree %d, continuity order %d defined on %d Simplices',d,r,T);
% title(titstr);
% if (printfigs == 1001 || printfigs == 1)
%     fname = sprintf('fig_SplineResults_d%dr%d_T%d', d, r, T);
%     savefname = strcat(figpath, fname);
%     print(plotID, '-dpng', '-r300', savefname);
%     saveas(plotID, savefname);
%     matlabfrag(savefname);
%     fprintf('Printed <%s>\n', savefname);
% end




