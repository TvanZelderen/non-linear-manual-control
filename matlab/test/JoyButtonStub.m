classdef JoyButtonStub < handle
%JOYBUTTONSTUB  Minimal stand-in for JoyBridge in failure_step unit tests.
%
%   Exposes just button() so failure_step's duck-typed guard
%   (isobject + isvalid + ismethod 'button') accepts it. Set .state to a
%   logical scalar or vector to drive the toggle logic.
%
%   See also TEST_FAILURE, FAILURE_STEP.

    properties
        state = false
    end

    methods
        function obj = JoyButtonStub(state)
            if nargin > 0, obj.state = state; end
        end

        function b = button(obj, idx)
            b = logical(obj.state);
            if nargin > 1, b = b(idx); end
        end
    end
end
