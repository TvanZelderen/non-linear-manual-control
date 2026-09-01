# joybridge — HID joystick → UDP for MATLAB on Apple Silicon

The Citation model reads the pilot sidestick through a Simulink 3D Animation
`Joystick Input` block. That toolbox **is not supported on macOS**, and the
usual fallbacks don't work here either:

| Option | Why it fails on this Mac |
|---|---|
| Simulink 3D Animation `vrjoystick` / `Joystick Input` | Toolbox unsupported on macOS (Windows/Linux only) |
| Aerospace Blockset `Pilot Joystick` | Windows-only (DirectInput) |
| HebiJoystick (Java/JInput) | Ships `ppc/i386/x86_64` native libs only; MATLAB's JVM here is `aarch64` |
| `udpport` in a MATLAB Function block | Needs Instrument Control Toolbox (not licensed) |

`joybridge` is a ~200-line Swift helper that reads the stick via the native
**IOKit HID** API and streams its axes/buttons as UDP datagrams to
`127.0.0.1`. MATLAB receives them with plain `java.net.DatagramSocket` — no
toolbox. `JoyBridge.m` wraps both ends; `joystick_calibrate.m` turns raw axes
into calibrated `[roll pitch yaw throttle]`.

## Build

```sh
sh build.sh          # needs only the Xcode Command Line Tools (swiftc)
```

Produces `./joybridge` (git-ignored — rebuild per machine).

## Use

```sh
./joybridge --list                       # enumerate HID joysticks/gamepads
./joybridge --vid 0x044F --pid 0x0406     # stream the T.A320 sidestick
./joybridge --port 25147 --rate 100       # defaults
```

From MATLAB you normally don't run it directly — `JoyBridge` launches it:

```matlab
j = JoyBridge('VendorID', hex2dec('044F'), 'ProductID', hex2dec('0406'));
j.poll();  j.axis()    % 1xN in [0,1];  j.button() -> logical
j.close()
```

## Wire format

ASCII, one `\n`-terminated datagram per line.

```
M,<name>,<vid>,<pid>,<nAxes>,<usage0>,..,<nButtons>      metadata, ~1 Hz (burst at start)
D,<seq>,<nAxes>,<a0..aN-1>,<nButtons>,<b0..bM-1>         data, at --rate Hz
```

`<usageK>` is the HID Generic-Desktop usage code of axis K: 48=X 49=Y 50=Z
51=Rx 52=Ry 53=Rz 54=Slider 55=Dial 56=Wheel 57=Hat. Axes are ordered by
ascending usage code. `aK` is normalised to `[0,1]` from the element's logical
range; `bK` is 0/1. The helper is deliberately policy-free — centre, sign,
dead-zone and channel mapping live in `joystick_calibrate.m`.

## Thrustmaster T.A320 sidestick (measured)

`vid=0x044F pid=0x0406`, 5 axes `[X Y Rz Slider Hat]` (usages `48 49 53 54 57`),
17 buttons. X = roll, Y = pitch, Rz = yaw/rudder, Slider = base throttle lever
(unipolar, rests at 0), Hat = 8-way POV (ignored by calibration).
