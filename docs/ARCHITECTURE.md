# Architecture

How the simulated robot, its interfaces and the (planned) deployment fit
together. Items marked **(planned)** are not implemented yet.

## 1. Layers

```
┌───────────────────────────── Gazebo Harmonic ─────────────────────────────┐
│ world (outdoor_flat.world)   robot model (from URDF)   system plugins     │
│  Physics · Sensors(ogre2) · Imu · NavSat · DiffDrive · JointStatePublisher│
└──────────────┬────────────────────────────────────────────▲───────────────┘
               │ gz-transport                               │ gz-transport
        ┌──────▼───────────────────────────────────────────┴──────┐
        │ ros_gz_bridge (config/gz_bridge.yaml)  +  ros_gz_image   │
        └──────┬───────────────────────────────────────────▲──────┘
               │ ROS 2 topics                              │ /cmd_vel
        ┌──────▼───────────────────────────────────────────┴──────┐
        │ perception / localization / control   (planned)          │
        └──────────────────────────────────────────────────────────┘
```

The simulation side exposes only **sensor topics and `/clock`** and consumes
only **`/cmd_vel`**. Everything on the lower layer is replaceable, which is
what makes the v1/v2 deployment split possible (section 6).

## 2. Robot model (`description/`)

| File | Purpose |
|---|---|
| `robot.urdf.xacro` | Entry point; includes the files below |
| `links.xacro` | Chassis, 4 wheels, front/rear bumpers, cameras (+ optical frames), IMU, GPS |
| `joints.xacro` | Wheel joints (continuous), all other joints fixed |
| `materials.xacro` | URDF colors |
| `gazebo_materials.xacro` | Gazebo colors; wheel friction (`mu1`, `mu2`, `fdir1`) |
| `gazebo_controls.xacro` | `DiffDrive` + `JointStatePublisher` plugins |
| `gazebo_sensors.xacro` | 2x camera, IMU, navsat sensors |

Key parameters: ~185 kg chassis, wheel radius 0.225 m, track width 0.874 m.
Front and rear bumpers are mass-matched so the whole-robot center of mass
sits at `base_link`.

## 3. Frames (TF)

```
odom ──(DiffDrive)──► base_link ──┬─ {l,r}_{f,r}_wheel_link   (joint_states)
                                  ├─ front_bumper_link, rear_bumper_link
                                  ├─ f_camera_link ── f_camera_optical_link
                                  ├─ r_camera_link ── r_camera_optical_link
                                  ├─ imu_link
                                  └─ gps_link
```

- `odom → base_link` currently comes from the simulated wheel odometry. Whether
  that stays, or is replaced by a fused estimate, is an open decision
  ([ROADMAP](ROADMAP.md#open-decisions)).
- Image and `camera_info` messages are stamped with the **optical** frames
  (z forward, x right, y down, per REP-103).
- The rear camera is yawed 180° relative to `base_link`.

## 4. Interfaces

| ROS topic | Type | Direction | Rate | Source |
|---|---|---|---|---|
| `/clock` | `rosgraph_msgs/Clock` | sim → ROS | – | Gazebo |
| `/cmd_vel` | `geometry_msgs/Twist` | ROS → sim | – | `DiffDrive` |
| `/odom` | `nav_msgs/Odometry` | sim → ROS | 50 Hz | `DiffDrive` (wheel odometry) |
| `/tf` | `tf2_msgs/TFMessage` | sim → ROS | – | `DiffDrive` |
| `/joint_states` | `sensor_msgs/JointState` | sim → ROS | – | `JointStatePublisher` |
| `/camera/front/image` | `sensor_msgs/Image` | sim → ROS | 20 Hz | camera (via `ros_gz_image`) |
| `/camera/front/camera_info` | `sensor_msgs/CameraInfo` | sim → ROS | 20 Hz | camera |
| `/camera/rear/image` | `sensor_msgs/Image` | sim → ROS | 20 Hz | camera (via `ros_gz_image`) |
| `/camera/rear/camera_info` | `sensor_msgs/CameraInfo` | sim → ROS | 20 Hz | camera |
| `/imu` | `sensor_msgs/Imu` | sim → ROS | 200 Hz | IMU |
| `/gps/fix` | `sensor_msgs/NavSatFix` | sim → ROS | 10 Hz | navsat |
| `/cmd_vel_teleop` | `geometry_msgs/Twist` | joystick → mux | – | `teleop_twist_joy` (v2 only) |
| `/cmd_vel_smoothed` | `geometry_msgs/Twist` | Jetson → mux | – | Nav2 `velocity_smoother` (v2 only) |

In v2, `twist_mux` on the laptop merges the two command topics into `/cmd_vel`
(joystick has priority). In v1 the joystick publishes `/cmd_vel` directly.

Images use `ros_gz_image` rather than the generic bridge for efficiency; all
other topics are listed in `config/gz_bridge.yaml`.

## 5. Launch flow

`startup.sh` → `launch_sim.launch.py`, which starts:

1. `robot_state_publisher` (via `rsp.launch.py`, sim time on)
2. `gz sim` with `worlds/outdoor_flat.world`
3. `ros_gz_sim create` (spawns the robot from `/robot_description`)
4. `ros_gz_bridge parameter_bridge` (`config/gz_bridge.yaml`)
5. `ros_gz_image image_bridge` (the two camera images)

`startup.sh` then waits for `/odom`, and starts RViz, `joy_node` and
`teleop_twist_joy`.

Gazebo resolves the model's mesh URIs through `GZ_SIM_RESOURCE_PATH`, which the
launch file extends with the parent of the installed package share directory.

## 6. Deployment variants

### v1: single machine **(planned layout)**
Simulation and all ROS nodes on one laptop. Default for development.

### v2: laptop + Jetson **(scaffolded, unverified; see [DISTRIBUTED](DISTRIBUTED.md))**

| Machine | Runs |
|---|---|
| Laptop | Gazebo, bridges, RViz |
| Jetson | Localization/VIO, perception, controller (and Nav2 for autonomy mode) |

The boundary is the interface in section 4: sensors and `/clock` flow to the
Jetson, `/cmd_vel` flows back. Points to settle for v2:

- **Bandwidth:** two 640x480 @ 20 Hz streams are significant over Wi-Fi.
  Prefer wired Ethernet and/or compressed image transport.
- **Discovery/QoS:** shared `ROS_DOMAIN_ID` and an explicit DDS configuration.
- **Sim time:** the Jetson nodes must run with `use_sim_time:=true`.
- **OS/ROS on the Jetson:** the supported JetPack/Ubuntu version determines
  whether Jazzy runs natively or in a container. To be verified against current
  JetPack support.
- **Package split:** the same nodes must run in both variants; only the
  launch/deployment differs, so the code should not be duplicated between
  `v1` and `v2`. Because colcon rejects duplicate package names, shared code
  lives in common package(s) and each variant adds only bringup/config.

## 7. Planned perception and control stack **(planned, undecided)**

Intended end goal: **obstacle avoidance and distance estimation for
user-controlled driving**, with Nav2 autonomy as a parallel mode.

- Sensing is limited to monocular cameras, IMU and GPS, so obstacle distance
  must come from monocular estimation (learned depth and/or ground-plane
  geometry using the known camera height and pitch).
- A safety layer between the joystick and `/cmd_vel` (for example
  `nav2_collision_monitor`) would slow or stop the robot, and distance
  information would be shown to the operator.
- Outdoor localization would fuse IMU, GPS and visual odometry (and possibly
  wheel odometry); autonomy mode uses a robot-specific Nav2 behavior tree.

Framework and algorithm choices are tracked in [ROADMAP](ROADMAP.md#open-decisions).

## 8. Design decisions

| Decision | Rationale |
|---|---|
| Sensors limited to 2 mono cameras, IMU, GPS | Matches the intended real-robot sensor set |
| Optical frames as separate links | Correct camera axes for VSLAM without distorting the body-frame mounting |
| Camera sensors use plain rectilinear projection | Simplest start; a 130° lens model is deferred until the VSLAM framework is chosen |
| `DiffDrive` for a 4-wheel robot | Simple and adequate for early tests; true skid-steer slip is not modeled |
| Anisotropic wheel friction (low lateral `mu2`) | Lets the chassis pivot without stick-slip |
| Rear bumper mirrors front bumper | Keeps the center of mass at `base_link` so physical and odometric pivot agree |
