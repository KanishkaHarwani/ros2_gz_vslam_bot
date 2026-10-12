# Roadmap

Staged test plan. Each stage lists a goal, prerequisites, and success
criteria so you can tell when it's actually done and not just "ran once."
Log results under `docs/test_logs/`.

**Scope (revised Oct 2026):** small 2-wheel robot (max 50x35x25 cm), one
front stereo camera pair (left-only for monocular runs), IMU, optional GPS,
single laptop. Environments: maze, indoor, warehouse, and more.

## Stage 0 — Robot Description
**Goal:** URDF/xacro for the small robot: 2-wheel diff drive + caster, front
stereo pair, IMU, GPS (toggleable). Fits the 50x35x25 cm budget.
**Success criteria:**
- `scripts/check_envelope.py` reports OK for every toggle combination
  (`stereo_mode` x `enable_gps`)
- Robot spawns in Gazebo without warnings/errors
- `ros2 topic hz /camera/left/image` (and `/camera/right/image` in stereo mode)
  holds near 30 Hz; `/imu` holds near 100 Hz
- `/camera/right/*` is absent in `mono` mode; `/navsat` is absent unless
  `enable_gps:=true`
- `ros2 topic echo /odom` shows sane values driving straight and turning

## Test 1 — Gazebo + Joystick Control
**Goal:** Confirm the robot drives correctly via joystick/teleop in a basic world.
**Prerequisites:** Stage 0 complete.
**Success criteria:**
- Straight-line drive, in-place rotation, and combined motion behave as
  expected: no tipping on the caster, no wobble, no joint errors
- `joy` -> `cmd_vel` -> `DiffDrive` path confirmed end-to-end
- Sim real-time factor logged with stereo + IMU streaming (and with `mono`,
  to quantify what the second camera costs)

## Test 2 — Recording + Pose Comparison
**Goal:** Record odometry, camera and IMU data while driving a known path, and
establish a baseline pose-drift measurement for later VSLAM comparison.
**Prerequisites:** Test 1 passing.
**Success criteria:**
- Bag captures `/odom`, `/tf`, `/camera/left/*`, `/camera/right/*`, `/imu`,
  `/joint_states` at expected rates
- Drift (end-position error vs. known ground truth) is measured and recorded
  as the baseline; ground-truth source is Gazebo's pose publisher (not yet wired up)

## Test 3 — Basic Map Generation (2D or 3D)
**Goal:** Produce a first map from a driven run, validating the mapping pipeline.
**Prerequisites:** Test 1 passing.
**Success criteria:**
- A 2D occupancy grid or 3D point-cloud map is produced from a teleop run
- Map is visually recognizable (features at correct relative positions)

## Test 4 — VSLAM on Flatland with Shapes
**Goal:** First VSLAM run: flat ground, simple high-contrast shapes as visual
features, no obstacles to avoid yet.
**Prerequisites:** VSLAM framework chosen and built; Test 1 passing.
**Success criteria:**
- Pose estimate tracks without losing localization over a full driven loop
- Run in **stereo**, then **mono** (`stereo_mode:=mono`), and with/without IMU
  if the framework supports it; compare each against the Test 2 odometry
  baseline and Gazebo ground truth (ATE/RPE)

## Test 5 — Environment Families (maze / indoor / warehouse)
**Goal:** Check that tracking and mapping hold up in each environment family,
since each stresses VSLAM differently.
**Prerequisites:** Test 4 passing; one world built per family.
**Success criteria:**
- Per family, a full driven run completes with no tracking loss longer than a
  defined threshold, with ATE/RPE recorded:
  - **Maze:** repetitive corridors, loop closure vs. perceptual aliasing
  - **Indoor:** texture-rich vs. texture-poor walls, doorways, lighting
  - **Warehouse:** long aisles, repeated shelving, large open spaces
- GPS stays **off** in all three (no sky view); use `enable_gps:=true` only for
  a deliberate outdoor world

## Test 6 — + Obstacle Detection
**Goal:** Add obstacles to the worlds; detect them (not yet avoid).
**Prerequisites:** Test 5 passing.
**Success criteria:**
- Obstacles appear correctly in the generated map/point cloud
- Detection flags obstacles within a defined range with an acceptable
  false-positive/negative rate on a fixed obstacle set (stereo depth only, no lidar)

## Test 7 — + Path Planning (goal-directed)
**Goal:** Given a goal pose, plan and execute a path around known obstacles.
**Prerequisites:** Test 6 passing; a planner (e.g. Nav2) integrated with the
VSLAM-derived map/costmap.
**Success criteria:**
- Robot reaches a specified goal without collision across several
  goal/obstacle configurations

## Test 8 — + Auto Path Planning (autonomous goal selection)
**Goal:** Robot selects its own goals (e.g. frontier exploration).
**Prerequisites:** Test 7 passing.
**Success criteria:**
- Robot autonomously explores and maps the environment without a
  human-specified goal, terminating when a defined coverage threshold is met

## Test 9 — Full Autonomy, Multiple Environments
**Goal:** Integration test: autonomous exploration and navigation across the
environment families with multiple, varied obstacles.
**Prerequisites:** Tests 4–8 passing individually.
**Success criteria:**
- Robot completes autonomous exploration/navigation without manual
  intervention, with mapping and localization error within the bounds
  established in Test 4

---

## Open Decisions to Log Before Starting
- VSLAM framework choice (see README)
- Ground-truth source for pose error measurement (Gazebo's own pose publisher
  is the simplest option)
- Definition of "sufficient coverage" for Test 8's termination condition
- Whether to keep `<visualize>` off on sensors (now a single flag,
  `sensor_visualize`, in `description/properties.xacro`; default `false`)
- Whether an outdoor world (the only place GPS matters) is in scope
