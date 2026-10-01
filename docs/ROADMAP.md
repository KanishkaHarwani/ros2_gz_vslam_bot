# Roadmap (draft)

Staged test plan. Each stage lists a goal, prerequisites and success criteria
so it is clear when a stage is actually done and not just "ran once". Log
results under `docs/test_logs/` (one dated file per run).

> **Draft:** sensor set (2x mono camera, IMU, GPS) and the end goal
> (obstacle avoidance + distance estimation for user control) are settled;
> later stages may change as scope is decided.

## Stage 0: Robot description and simulation
**Goal:** Robot model and world run on Ubuntu 24.04 / Jazzy / Harmonic.
**Success criteria:**
- Robot spawns without warnings or errors
- `/camera/{front,rear}/image` hold ~20 Hz, `/imu` ~200 Hz, `/gps/fix` ~10 Hz
- `/odom` is sane while driving straight and while turning
- GPS fixes match the world's `spherical_coordinates` origin

## Test 1: Gazebo + joystick control
**Prerequisites:** Stage 0.
**Success criteria:**
- Straight-line drive, in-place rotation and combined motion behave cleanly
  (no wobble, jitter or joint errors)
- `joy` → `cmd_vel` → `DiffDrive` confirmed end-to-end
- Real-time factor logged with both cameras, IMU and GPS running

## Test 2: Recording + ground-truth baseline
**Goal:** Record data on a known path and measure baseline drift.
**Prerequisites:** Test 1.
**Success criteria:**
- Bag captures `/odom`, `/tf`, `/joint_states`, both camera image/camera_info
  topics, `/imu`, `/gps/fix` at expected rates
- A ground-truth pose source is wired up (Gazebo's own pose publisher is the
  simplest option)
- Wheel-odometry drift (end-position error vs. ground truth) is recorded as
  the baseline number

## Test 3: IMU + GPS state estimation
**Goal:** An outdoor global estimate from IMU and GPS (optionally wheel odometry).
**Prerequisites:** Test 2.
**Success criteria:**
- Estimator output tracks ground truth; error metrics recorded
- Behavior under GPS noise is characterized

## Test 4: Monocular visual-inertial odometry
**Goal:** First VIO run: flat ground with high-contrast features, front camera + IMU.
**Prerequisites:** VIO framework chosen and built; Test 2.
**Success criteria:**
- Tracks without losing localization over a full driven loop
- Metric scale is recovered (from the IMU)
- ATE/RPE vs. ground truth recorded and compared with the Test 2 and Test 3 baselines
- Decision logged on how to use the second (rear) camera

## Test 5: Monocular obstacle distance estimation
**Goal:** Estimate distance to obstacles from camera images.
**Prerequisites:** Test 4 (or at least calibrated camera model).
**Success criteria:**
- Distance error vs. ground truth measured over a fixed obstacle set and range sweep
- Usable range and failure cases (lighting, texture, 130° edge distortion) documented

## Test 6: User-controlled driving with obstacle avoidance
**Goal:** The operator drives by joystick; the system shows obstacle distance
and slows/stops the robot to prevent collisions.
**Prerequisites:** Test 5.
**Success criteria:**
- Distance information is presented to the operator
- Zero collisions across a defined set of runs and obstacle configurations
- Safety layer does not trigger on obstacle-free ground (false-stop rate recorded)

## Test 7: Laptop + Jetson deployment (v2)
**Goal:** Repeat the key tests with simulation on the laptop and perception/control on the Jetson.
**Prerequisites:** Tests 4 to 6 passing in v1.
**Success criteria:**
- Same results as v1 within defined tolerances
- Latency, bandwidth and Jetson CPU/GPU load logged
- `cmd_vel` round-trip latency does not break Test 6

## Test 8: Nav2 autonomy with outdoor behavior tree
**Goal:** Autonomous goal-directed driving (e.g. GPS waypoints) using a
robot-specific Nav2 behavior tree.
**Prerequisites:** Test 6.
**Success criteria:**
- Reaches specified goals without collision across several goal/obstacle configurations

## Test 9: Rough terrain integration
**Goal:** Combine everything on non-flat terrain with multiple obstacles.
**Prerequisites:** Tests 4 to 8.
**Success criteria:**
- Completes runs without manual intervention; localization error within the
  bounds established in Test 4

---

## Open decisions
- VIO/VSLAM framework (mono-inertial candidates, e.g. ORB-SLAM3, OpenVINS, VINS-Fusion; to be evaluated)
- Whether wheel odometry/joint encoders are an allowed input to localization
- How the second camera is used (independent tracker vs. multi-camera system)
- Camera lens model: keep pinhole, or model distortion/fisheye for 130°
- Distance-estimation approach (learned monocular depth vs. ground-plane geometry vs. both)
- Ground-truth pose source and export format
- Localization stack for outdoor use (e.g. EKF fusion of IMU/GPS/VO)
- Repository structure for v1/v2 (shared package(s) + per-variant bringup)
- Jetson software environment (native vs. container)
- Terrain world design for Test 9
