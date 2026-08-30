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
| `matlab/` | Our code. `setup/` (build_mex, check_env), `params/` (aircraft data), `lib/`, `analysis/`. `project_startup.m` puts everything on the path. |
| `scripts/` | `runfg.sh` — optional FlightGear visualiser (model runs headless without it). |
| `results/` | Logged sim data and report figures (later steps). |
| `archive/` | Superseded v1 model zip (broken trim-file pointer — do not use). |

## Getting started (S1 — get the model running on macOS)

MATLAB R2025a on Apple Silicon. The blockers are Windows binaries, not missing software.

```matlab
run('matlab/project_startup.m')   % add paths
check_env                          % MATLAB build, toolboxes, C compiler, S-functions
build_mex                          % compile ac_atmos + ac_axes -> .mexmaca64
```

Then, in the model:

1. Delete the `sfun_rttime` block (Windows-only; the root already has an Aerospace
   Blockset `Simulation Pace` block).
2. Run `initcit`, open `Citation_FlightGear_v2.mdl`, update diagram (**⌘D / Ctrl+D**).
3. Run 60 s with no pilot input. **Gate: the aircraft must hold V ≈ 120 m/s in trim.**
4. Confirm the actual state-vector ordering at the prompt — the brief warns `p,q,r`
   and `δe,δa,δr` ordering is inconsistent across the model.

If there is no joystick: set the `Pilot` ManualSwitch to *Virtual Joystick*, or comment
the Joystick block with **Ctrl+Shift+U**.

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
