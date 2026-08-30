
% LieFx(Fx, Yx, variables) computes the n^th order symbolic Lie derivative of Y 
%   with respect to the vector field F, with variables given in x as follows:
%   LieFx(Fx,Yx,x,n) = L^n_F(x) Y(x) = L^(n-1)_F(x) (Y(x)dY(x) / dx)  * F(x)
%   If n = 0, LieFx(Fx,Yx,x,0) = Yx
%   if n = 1, LieFx(Fx,Yx,x,1) = L_F(x) Y(x) = (Y(x)dY(x) / dx)  * F(x)
%   Note that if 3 arguments are given, it is assumed n = 1
function L = LieFx(Fx, Yx, x, n)

    if (nargin < 4)
        n = 1;
    end

    if (n == 0)
        L = Yx;
        return;
    end
    % Solve for the first Lie derivative along the vector field Fx
    L = jacobian(Yx, x)*Fx; 
    
    % Solve for the nth Lie derivative along the vector field Fx
    for i = 2:n
        L = jacobian(L, x)*Fx;
    end
end