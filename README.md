# Gazebo ROS VSLAM (`ros2_gz_vslam_bot`)

A ROS 2 + Gazebo simulation project for developing and validating a
vision-based localization pipeline on an **outdoor ground robot**, stage by
stage: teleop and recording, monocular visual-inertial odometry, monocular
obstacle/distance estimation for **user-controlled driving**, and finally
Nav2-based autonomy.

> **Status:** the robot description and simulation were migrated to
> Ubuntu 24.04 / ROS 2 Jazzy / Gazebo Harmonic and have not yet been validated
> end-to-end on that stack. See [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md).
> The roadmap is a draft; scope is still being decided.

## Robot

| Aspect | Spec |
|---|---|
| Environment | Outdoor |
| Drivetrain | 4-wheel skid-steer, simulated with Gazebo's `DiffDrive` (two joints per side) |
| Cameras | 2x monocular (front + rear), 130° horizontal FOV, 640x480 @ 20 Hz |
| IMU | 1x, 200 Hz |
| GPS | 1x (`navsat`), 10 Hz |
| Other sensors | None. No lidar, no depth camera |

The camera resolution/rate is deliberately below the original 1080p/60 fps
target to keep simulation load manageable.

## Platform

- Ubuntu 24.04, ROS 2 Jazzy, Gazebo Harmonic (`gz-sim`)
- `ros_gz_sim`, `ros_gz_bridge`, `ros_gz_image`
- VSLAM/VIO framework: **not yet chosen** (see [Roadmap](docs/ROADMAP.md))

## Deployment variants (planned)

| Variant | Where things run |
|---|---|
| **v1** | Everything on one laptop: simulation, perception, control |
| **v2** | Laptop runs the simulation; a Jetson runs perception and control |

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the interface between
the two machines.

## Quick start

```bash
cd ~/<your_ws> && colcon build --packages-select ros2_gz_vslam_bot
source install/setup.bash
./src/ros2_gz_vslam_bot/startup.sh        # Gazebo + RViz + joystick teleop
# options: --no-rviz  --no-joy
```

Full setup and verification steps: [`docs/RUNBOOK.md`](docs/RUNBOOK.md).

## Repository layout

```
ros2_gz_vslam_bot/
├── description/     # xacro: links, joints, materials, gazebo_{materials,controls,sensors}
├── launch/          # rsp.launch.py, launch_sim.launch.py
├── config/          # gz_bridge.yaml, view_bot.rviz
├── worlds/          # outdoor_flat.world (+ more per test stage)
├── docs/            # public documentation (this index below)
├── startup.sh       # one-command bring-up
├── package.xml
└── CMakeLists.txt
```

The v1/v2 split is planned but not yet reflected in the layout; the intended
shape is described in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Documentation

| Doc | Contents |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Robot model, frames, topics, launch flow, v1/v2 deployment |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Staged test plan and open decisions (draft) |
| [`docs/RUNBOOK.md`](docs/RUNBOOK.md) | Install, run, verify, troubleshoot |
| [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md) | Open issues, caveats, resolved history |
| `docs/test_logs/` | One dated log per test run |

## References

1. Edge-Deployed 3D Vision and Localization for Autonomous Systems Software — https://github.com/maleehabee22seecs-hue/Edge-Deployed-3D-Vision-and-localization-for-Autonomous-Systems-Software
2. husky-gazebo-image-capture — https://github.com/WikiGenius/husky-gazebo-image-capture
3. Mono-SLAM — https://github.com/engyasin/mono-slam
4. OpenVSLAM — https://github.com/LongruiDong/openvslam
5. Aruco-based Visual SLAM — https://github.com/jim0002/aruco-based-visual-slam
6. VSLAM-Navigation — https://github.com/tranquykien/visual-slam-navigation

> Before pulling code from any of these into the repo, check each one's
> license and confirm compatibility with this project's license (MIT).
