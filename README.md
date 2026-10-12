# Gazebo ROS VSLAM

A ROS 2 + Gazebo (gz-sim) simulation project to develop and progressively
validate a Visual SLAM (VSLAM) pipeline on a **small indoor robot**, moving
from teleop sanity checks through flat-land VSLAM to full autonomy in maze,
indoor and warehouse environments. Everything runs on a single laptop.

## Objective

Build and test a small ground robot capable of visual SLAM-based localization
and mapping in simulation, validated stage-by-stage against odometry, then
extended toward obstacle detection, path planning, and full autonomy. See
[`docs/Roadmap.md`](./docs/Roadmap.md) for the staged test plan.

## Robot Spec

| Aspect | Spec |
|---|---|
| Size budget | **Max 50 (L) x 35 (W) x 25 (H) cm** including wheels, camera, IMU, GPS |
| Actual size | 36.0 x 31.5 x 16.0 cm, 3.7 kg (checked by `scripts/check_envelope.py`) |
| Drivetrain | 2-wheel differential drive + passive front ball caster |
| Camera | Front-facing stereo pair, 12 cm baseline, 640x480 @ 30 Hz, 62.4 deg HFOV |
| IMU | 100 Hz, with noise; at the chassis centre |
| GPS | NavSat, 5 Hz; **toggleable** (outdoor maps only) |
| Lidar / depth | None (pure visual) |
| Compute | Single laptop, no distributed setup |

### Sensor toggles

Both are launch arguments; they switch the *sensor* on or off while the
hardware stays on the robot (so the size budget is always checked with it).

| Argument | Values | Effect |
|---|---|---|
| `stereo_mode` | `stereo` (default) / `mono` | `mono` drops the right camera: no `/camera/right/*` topics, for monocular tests |
| `enable_gps` | `false` (default) / `true` | Adds the `/navsat` topic. Pointless indoors; use for outdoor-style worlds |

```bash
ros2 launch ros2_gz_vslam_bot launch_sim.launch.py world:=empty.world stereo_mode:=mono enable_gps:=false
# or via the helper script: ./start_sim.sh [world] [stereo|mono] [gps|nogps]
```

### Stereo calibration (for the VSLAM config)

Simulated cameras are ideal pinhole: `fx = fy = 528.4`, `cx = 320`, `cy = 240`,
no distortion, baseline `0.12 m` (`bf = 63.4`). Gazebo's right `camera_info`
does **not** carry the baseline, so put it in the VSLAM framework's own config.
Image and `camera_info` headers use the optical frames
(`cam_left_optical_frame`, `cam_right_optical_frame`).

### Changing the geometry

All dimensions live in `description/properties.xacro`. After any edit run:

```bash
python3 scripts/check_envelope.py                                   # defaults
python3 scripts/check_envelope.py enable_gps:=true                  # with toggles
```

It reports the bounding box against the 50x35x25 budget, total mass, CoM, and
whether the CoM stays inside the wheels+caster support triangle.

## Topics

| Topic | Type | Notes |
|---|---|---|
| `/camera/left/image`, `/camera/right/image` | `sensor_msgs/Image` | right only in `stereo` mode |
| `/camera/left/camera_info`, `/camera/right/camera_info` | `sensor_msgs/CameraInfo` | |
| `/imu` | `sensor_msgs/Imu` | |
| `/navsat` | `sensor_msgs/NavSatFix` | only with `enable_gps:=true` |
| `/odom`, `/tf`, `/joint_states`, `/clock` | | from DiffDrive / JointStatePublisher |
| `/cmd_vel` | `geometry_msgs/Twist` | limits: 1.0 m/s, 2.0 rad/s |

## Environments (planned worlds)

| Family | Purpose |
|---|---|
| Maze | Narrow corridors, repetitive structure, loop-closure and perceptual-aliasing stress |
| Indoor | Rooms, doorways, furniture; texture-rich and texture-poor walls |
| Warehouse | Long aisles, shelving, repeated objects, larger open areas |
| More (TBD) | e.g. outdoor yard (the only family where GPS is meaningful), rough terrain |

Only `worlds/empty.world` (flat ground) exists so far. New worlds should copy
its system plugins and `<spherical_coordinates>` block, and are selected with
`world:=<file>`.

## Repository Structure

```
ros2_gz_vslam_bot/
├── description/
│   ├── robot.urdf.xacro        # entry point; declares enable_right_camera / enable_gps args
│   ├── properties.xacro        # all dimensions + inertia macros (single source of truth)
│   ├── links.xacro
│   ├── joints.xacro
│   ├── materials.xacro
│   ├── gazebo_materials.xacro  # colours + wheel/caster friction
│   ├── gazebo_controls.xacro   # DiffDrive + JointStatePublisher
│   └── gazebo_sensors.xacro    # stereo cameras, IMU, GPS (toggled)
├── launch/
│   ├── rsp.launch.py
│   └── launch_sim.launch.py    # args: world, stereo_mode, enable_gps
├── config/
│   ├── gz_bridge.yaml
│   └── view_bot.rviz
├── worlds/
│   └── empty.world             # + maze / indoor / warehouse worlds per test stage
├── scripts/
│   └── check_envelope.py       # size / mass / stability check
├── docs/
│   ├── Roadmap.md
│   ├── Runbook.md
│   └── test_logs/              # one dated log per test run
├── start_sim.sh
├── package.xml
└── CMakeLists.txt
```

(`install(DIRECTORY ...)` in `CMakeLists.txt` is unchanged; it already covers
`config description launch worlds`. There are no mesh files any more.)

## Software Stack (proposed)

- ROS 2 Humble + Gazebo Fortress (`ros_gz_sim`, `ros_gz_bridge`, `ros_gz_image`)
- VSLAM framework — not yet chosen. Candidates for a stereo(+IMU) camera:
  - **ORB-SLAM3** — stereo, mono and visual-inertial modes; maps directly onto
    the `stereo_mode` toggle and the IMU. More integration work.
  - **RTAB-Map** — easiest ROS 2 integration, stereo input, loop closure and
    occupancy-grid output (good fit for the mapping test)
  - **OpenVSLAM** — flexible but less actively maintained
  - Aruco-based VSLAM — useful for early flat-land tests with markers

## References

1. Edge-Deployed 3D Vision and Localization for Autonomous Systems Software — https://github.com/maleehabee22seecs-hue/Edge-Deployed-3D-Vision-and-localization-for-Autonomous-Systems-Software
2. husky-gazebo-image-capture — https://github.com/WikiGenius/husky-gazebo-image-capture
3. Mono-SLAM — https://github.com/engyasin/mono-slam
4. OpenVSLAM — https://github.com/LongruiDong/openvslam
5. Aruco-based Visual SLAM — https://github.com/jim0002/aruco-based-visual-slam
6. VSLAM-Navigation — https://github.com/tranquykien/visual-slam-navigation

> Before pulling code from any of these into the repo, check each one's
> license and confirm compatibility with your intended license for this
> project.
