classdef JoyBridge < handle
%JOYBRIDGE  Read a macOS HID joystick in MATLAB via the joybridge helper.
%
%   On Apple Silicon MATLAB has no built-in way to read a generic HID
%   joystick (Simulink 3D Animation is not supported, the Aerospace Blockset
%   Pilot Joystick block is Windows-only, HebiJoystick ships no arm64 native
%   library). JOYBRIDGE launches the small Swift helper in
%   matlab/lib/joybridge/ and receives its axis/button stream over a local
%   UDP socket using plain Java networking (no toolbox).
%
%   j = JoyBridge()                 first HID joystick, helper auto-launched
%   j = JoyBridge('VendorID',0x044F,'ProductID',0x0406)   pick a device
%   j = JoyBridge('Launch',false,'Port',25147)   attach to a running helper
%
%   j.poll()          refresh from the socket; true if a new frame arrived
%   j.axis()          1xN axis vector, each in [0,1] (raw, uncalibrated)
%   j.axis(k)         axis k only
%   j.button()        1xM logical button vector
%   j.AxisUsages      HID Generic-Desktop usage code per axis, bridge order
%                     (48=X 49=Y 50=Z 51=Rx 52=Ry 53=Rz 54=Slider 57=Hat)
%   j.close()         stop the helper and release the socket
%
%   The [0,1] convention is deliberate: centre, sign, dead-zone, span and the
%   channel->axis mapping are all decided by joystick_calibrate.m, not here.
%
%   See also JOYSTICK_CALIBRATE, JOYSTICK_PARAMS.

    properties (SetAccess = private)
        Name       = ''
        VendorID   = 0
        ProductID  = 0
        AxisUsages = []
        NumAxes    = 0
        NumButtons = 0
        Port       = 25147
    end

    properties (Access = private)
        sock            % java.net.DatagramSocket
        proc            % java.lang.Process for the helper, or []
        pkt             % reusable java DatagramPacket
        axesRaw    = []
        buttonsRaw = []
        gotFrame   = false
        gotMeta    = false
    end

    methods
        function obj = JoyBridge(varargin)
            ip = inputParser;
            ip.addParameter('Port', 25147, @(x)isscalar(x) && x > 0);
            ip.addParameter('VendorID',  [], @(x)isempty(x) || isscalar(x));
            ip.addParameter('ProductID', [], @(x)isempty(x) || isscalar(x));
            ip.addParameter('Launch', true, @(x)islogical(x) || ismember(x,[0 1]));
            ip.addParameter('Rate', 60, @(x)isscalar(x) && x > 0);  % ~= model block rate
            ip.addParameter('BinPath', '', @(x)ischar(x) || isstring(x));
            ip.parse(varargin{:});
            a = ip.Results;
            obj.Port = a.Port;

            if a.Launch
                obj.startHelper(char(a.BinPath), a.VendorID, a.ProductID, a.Rate);
            end
            obj.openSocket();

            % wait for a metadata frame (axis layout) plus one data frame
            deadline = tic;
            while toc(deadline) < 5
                obj.poll();
                if obj.gotMeta && obj.gotFrame, break; end
                pause(0.02);
            end
            if ~obj.gotMeta || ~obj.gotFrame
                missing = 'data'; if obj.gotFrame, missing = 'metadata'; end
                obj.close();
                error('JoyBridge:noData', ...
                    ['No %s from joybridge on UDP port %d. Is the helper built ' ...
                     '(matlab/lib/joybridge/build.sh) and a joystick connected?'], ...
                     missing, obj.Port);
            end
        end

        function tf = poll(obj)
        %POLL  Drain the socket, keep only the newest data frame. True if updated.
            tf = false;
            lastD = '';
            for k = 1:400   % bounded drain
                line = obj.recvLine();
                if isempty(line), break; end
                switch line(1)
                    case 'D', lastD = line;                % keep newest only
                    case 'M', obj.parseMeta(line);         % rare (~1 Hz)
                end
            end
            if isempty(lastD), return; end

            % D,seq,nAxes,a0..a(n-1),nButtons,b0..b(m-1)
            v = sscanf(lastD(3:end), '%f,');
            if numel(v) < 3, return; end
            na = v(2);
            if numel(v) < 3 + na, return; end
            obj.axesRaw = v(3:2+na).';
            nb = v(3+na);
            b0 = 4 + na;
            if nb > 0 && numel(v) >= b0+nb-1
                obj.buttonsRaw = logical(v(b0:b0+nb-1)).';
            else
                obj.buttonsRaw = false(1, max(nb, 0));
            end
            obj.NumAxes    = na;
            obj.NumButtons = nb;
            obj.gotFrame   = true;
            tf = true;
        end

        function parseMeta(obj, line)
        %PARSEMETA  M,name,vid,pid,nAxes,u0..u(n-1),nButtons
            parts = strsplit(strtrim(line), ',');
            if numel(parts) < 6, return; end
            na = str2double(parts{5});
            if numel(parts) < 6 + na, return; end
            obj.Name       = parts{2};
            obj.VendorID   = sscanf(parts{3}, '0x%x');
            obj.ProductID  = sscanf(parts{4}, '0x%x');
            obj.NumAxes    = na;
            obj.AxisUsages = str2double(parts(6:5+na));
            obj.NumButtons = str2double(parts{6+na});
            obj.gotMeta    = true;
        end

        function v = axis(obj, idx)
        %AXIS  Last-frame axis vector (or one axis) in [0,1], raw/uncalibrated.
        %   Call poll() first to refresh. (No implicit poll here so a caller
        %   in a simulation loop pays exactly one socket read per step.)
            v = obj.axesRaw;
            if nargin > 1, v = v(idx); end
        end

        function b = button(obj, idx)
        %BUTTON  Last-frame logical button vector (or one button). See axis().
            b = obj.buttonsRaw;
            if nargin > 1, b = b(idx); end
        end

        function close(obj)
        %CLOSE  Stop the helper process and close the socket.
            if ~isempty(obj.sock)
                try, obj.sock.close(); catch, end
                obj.sock = [];
            end
            if ~isempty(obj.proc)
                try, obj.proc.destroyForcibly(); catch, end
                obj.proc = [];
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function startHelper(obj, binPath, vid, pid, rate)
            if isempty(binPath)
                here = fileparts(mfilename('fullpath'));      % matlab/lib
                binPath = fullfile(here, 'joybridge', 'joybridge');
            end
            if ~isfile(binPath)
                error('JoyBridge:noBinary', ...
                    ['joybridge helper not found at\n  %s\n' ...
                     'Build it:  sh "%s"'], binPath, ...
                     fullfile(fileparts(binPath), 'build.sh'));
            end
            args = {binPath, '--port', num2str(obj.Port), '--rate', num2str(rate)};
            if ~isempty(vid), args = [args, {'--vid', sprintf('0x%04X', vid)}]; end
            if ~isempty(pid), args = [args, {'--pid', sprintf('0x%04X', pid)}]; end

            pb = java.lang.ProcessBuilder(args);
            devnull = java.io.File('/dev/null');
            pb.redirectOutput(devnull);
            pb.redirectError(devnull);
            obj.proc = pb.start();
            pause(0.4);   % let it bind and enumerate
        end

        function openSocket(obj)
            import java.net.DatagramSocket java.net.DatagramPacket java.net.InetSocketAddress
            try
                s = DatagramSocket([]);                       % unbound
                s.setReuseAddress(true);
                s.bind(InetSocketAddress('127.0.0.1', obj.Port));
                s.setSoTimeout(int32(1));                     % ms; keep per-step cost tiny
            catch err
                error('JoyBridge:bind', ...
                    ['Cannot bind UDP port %d (%s). A stale helper may be running: ' ...
                     'try  !pkill -f joybridge'], obj.Port, err.message);
            end
            obj.sock = s;
            buf = zeros(1, 4096, 'int8');
            obj.pkt = DatagramPacket(buf, numel(buf));
        end

        function line = recvLine(obj)
            line = '';
            try
                obj.pkt.setLength(4096);   % reset: receive() shrinks it to the last datagram
                obj.sock.receive(obj.pkt);
                n = obj.pkt.getLength();
                % build the string on the Java side - one JNI hop, no
                % per-byte MATLAB conversion (this is the per-step hot path)
                line = char(java.lang.String(obj.pkt.getData(), int32(0), int32(n)));
            catch
                % SocketTimeoutException -> no more packets right now
            end
        end
    end
end
