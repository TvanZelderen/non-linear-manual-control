# AE4-311 — Nonlinear and Adaptive Flight Control · Take-Home Assignment 1

Fault-tolerant flight control of a Cessna Citation 550 under an **aileron hardover**
failure, built twice: model-based **ANDI** (adaptive NDI with online RLS aerodynamic
model identification) and sensor-based **INDI**. Deadline **12 Sep 2026**.

Overview / deep dive: <https://claude.ai/code/artifact/47394ee5-776b-4c27-b3f2-3dadb6f44dfa>
Build roadmap: `~/.claude/plans/this-is-a-descently-rustling-bengio.md`
Session state: `~/.claude/handovers/ae4311-andi-indi-assignment/`

## Layout

| Path | Contents |
|---|---|
| `docs/` | The brief + reference PDFs (Embedded MATLAB manuals, Stoica 1977 whiteness test). |
| `model/` | `Citation simulation model 2026_v2.zip` (pristine) and the extracted `Citation simulation model 2026/` — **the live model; we edit `Citation_FlightGear_v2.mdl` in place here.** |
| `reference/` | `demo_Lecture1_NDI.m`, `demo_Lecture2_NDI_MIMO.m`, `LieFx.m` — lecture teaching examples, left untouched. The MIMO demo is the template for the 3×3 `b⁻¹(x)` in step 5. |
| `matlab/` | Our code. `setup/` (build_mex, check_env, joystick_calibrate, patch_model_joystick, add_cockpit_view, **patch_model_failure**, **find_button**), `params/` (aircraft data, joystick_params, **failure_params**), `lib/` (`JoyBridge.m`, `joybridge_open/step/close.m`, **`failure_open/step.m`**, `joybridge/` Swift HID helper), `run/` (**run_experiment**, **validation_matrix**), `test/` (**test_failure**), `analysis/`. `project_startup.m` puts everything on the path. |
| `scripts/` | `runfg.sh` — optional FlightGear visualiser (model runs headless without it). |
| `results/` | Logged sim data and report figures. `run_experiment` writes `results/<timestamp>/`. |
| `archive/` | Superseded v1 model zip (broken trim-file pointer — do not use). |

## Getting started (S1 — get the model running on macOS)

MATLAB R2025a on Apple Silicon. The blockers are Windows binaries, not missing software.

```matlab
run('matlab/project_startup.m')   % add paths
check_env                          % MATLAB build, toolboxes, C compiler, S-functions, joystick
build_mex                          % compile ac_atmos + ac_axes -> .mexmaca64
```

```sh
sh matlab/lib/joybridge/build.sh   % compile the joystick helper (needs Xcode CLT)
```

Then, in the model:

1. Delete the `sfun_rttime` block (Windows-only; the root already has an Aerospace
   Blockset `Simulation Pace` block).
2. Run `initcit`, open `Citation_FlightGear_v2.mdl`, update diagram (**⌘D / Ctrl+D**).
3. Run 60 s with no pilot input. **Gate: the aircraft must hold V ≈ 120 m/s in trim.**
4. Confirm the actual state-vector ordering at the prompt — the brief warns `p,q,r`
   and `δe,δa,δr` ordering is inconsistent across the model.

**Joystick on macOS.** Simulink 3D Animation (the model's `Joystick Input` block) is
not supported on Apple Silicon. We read the sidestick through `matlab/lib/joybridge/`
instead — a small Swift IOKit-HID helper streaming to MATLAB over UDP, wrapped by
`JoyBridge.m`. One-time: `sh matlab/lib/joybridge/build.sh`, then `joystick_calibrate`
(writes `matlab/params/joystick_cal.mat`). Wire it into the model with
`patch_model_joystick` — this replaces the dead `Joystick Input` block with an
Interpreted MATLAB Function reading the bridge, and adds `joybridge_open`/`_close` to
the model Start/StopFcn so the bridge opens once per run. Details:
`matlab/lib/joybridge/README.md`.
If there is no joystick: set the `Pilot` ManualSwitch to *Virtual Joystick*, or comment
the Joystick block with **Ctrl+Shift+U**.

**Visualisation on macOS.** No Simulink 3D Animation needed — it was only ever the
joystick block. Two options, both toolbox-installed:
- `add_cockpit_view` adds a **Cockpit View** block (Aerospace Blockset *MATLAB
  Animation*) — a live 3-D aircraft in a MATLAB figure, no external app.
- **FlightGear** out-the-window: `brew install --cask flightgear`, then
  `./scripts/runfg.sh` (start it, wait for the runway, then run the sim). The model's
  `FlightGear Visualisation` block (Aerospace Blockset `net_fdm`, udp 5502) drives it.
- The `FlightGear Visualisation` subsystem also carries scopes for p/q/r, φ/θ/ψ, h.

## S2 — aileron hardover failure

Brief eq. (1.4): after the servo lag and saturation, `δa,actual = 0.5·δa,cmd − 0.28 rad`.
Spliced into `Cessna Citation 500 / Actuators` on the line `da limits/1 → Mux/2` by an
Interpreted MATLAB Function (`failure_step`) — the node `da limits/1` stays the clean
pre-failure signal that step 3 (RLS) taps. `armed` is logged to `fail_armed`.
Full build plan: <https://claude.ai/code/artifact/1c2efd17-9d59-4fdb-b68a-659a8e98e687>

```matlab
patch_model_joystick        % run FIRST (StartFcn order)
patch_model_failure         % splice the failure; idempotent, writes .prefailure.bak
                            %   patch_model_failure([], '0.02') if Ctrl+D rejects the -1 rate

test_failure                % pure-function checks (safe under -batch)
```

Configure per run with a base-workspace `FAIL` struct (read once at StartFcn):

| `FAIL` field | default | meaning |
|---|---|---|
| `mode` | `'auto'` | `'off'` never · `'on'` from t=0 · `'auto'` schedule + button |
| `t_fail` | `Inf` | scheduled jam time [s] (auto mode); one-way |
| `button` | `2` | sidestick button that jams the aileron **while held** (momentary) — for messing around, not the real workflow. Resolve the real index with `find_button`. |
| `gain` / `offset` | `0.5` / `-0.28` | from `citation_params.p.fail` |
| `verbose` | `true` | print the config line at StartFcn |

`failure_step` is stateless — the arm decision (`t ≥ t_fail` OR button held) is
recomputed every step. Watch the logged `fail_armed` signal for the event, not the
console (`fprintf` from the sim context does not reliably surface).

```matlab
FAIL = struct('mode','auto','t_fail',20);   % jam 20 s in
% ... open the model, initcit, Run (desktop) ...

R = run_experiment(validation_matrix('t_fail',20,'tstop',40));   % batch, desktop
```

**Desktop only** for anything that runs the model — `sim()` / `-batch` segfault this model.

## The eight steps

1. Init model + FlightGear · 2. Failure dynamics + joystick · 3. RLS aero model ID
· 4. Monitoring → covariance-reset trigger · 5. ANDI rate loop `u = b⁻¹(x)[ν − a(x)]`
· 6. Handling-quality comparison (classical vs ANDI, ± failure) · 7. INDI inner loop
(fixed derivatives) · 8. INDI handling-quality comparison.

## Traps (from the brief)

- Re-order `p,q,r` and `δe,δa,δr` to one convention before inverting `b(x)`.
- Tap surface deflections **before** the failure block for identification.
- `yacc` specific forces are in **g**, not m/s² — scale by 9.80665.
- Break RLS algebraic loops with `Memory` blocks.
- Reset PI integrators on any control-mode or failure switch.
- Yaw damper **off**; β feedback on the rudder replaces it.
- First-order prefilters between joystick and the NDI loop.
