# Runbook — ros2_gz_vslam_bot (Gazebo Harmonic + ROS 2 Jazzy)

Commands assume ROS 2 Jazzy and Gazebo Harmonic (gz-sim 8) are installed system-wide
and your workspace is at `~/ros2_ws` (adjust paths as needed).

---

## 1. One-time setup

### 1.1 Install required packages
```bash
sudo apt update
sudo apt install -y \
  ros-jazzy-ros-gz \
  ros-jazzy-ros-gz-sim \
  ros-jazzy-ros-gz-bridge \
  ros-jazzy-ros-gz-image \
  ros-jazzy-robot-state-publisher \
  ros-jazzy-xacro \
  ros-jazzy-rviz2 \
  ros-jazzy-joy \
  ros-jazzy-teleop-twist-joy
```

### 1.2 Place the package and build
```bash
cd ~/ros2_ws/src
# ros2_gz_vslam_bot/{package.xml, CMakeLists.txt, description/, launch/, config/, worlds/, scripts/}
cd ~/ros2_ws
rosdep install --from-paths src --ignore-src -r -y
colcon build --packages-select ros2_gz_vslam_bot
```
There are no mesh files; no `description/meshes/` folder is needed.

---

## 2. Every-session boot sequence

### 2.1 Source your environment (every new terminal)
```bash
source /opt/ros/jazzy/setup.bash
source ~/ros2_ws/install/setup.bash
```

### 2.2 Launch the full sim stack
```bash
ros2 launch ros2_gz_vslam_bot launch_sim.launch.py \
  world:=empty.world stereo_mode:=stereo enable_gps:=false
```
Or everything (sim + RViz + joystick teleop) in one go:
```bash
./start_sim.sh [world] [stereo|mono] [gps|nogps]
```

| Argument | Values | Effect |
|---|---|---|
| `world` | file in `worlds/`, or an absolute path | default `empty.world` |
| `stereo_mode` | `stereo` / `mono` | `mono` removes the right camera |
| `enable_gps` | `false` / `true` | `true` adds `/navsat` (outdoor worlds only) |

If gz-sim opens with an empty world and no robot, wait a few seconds:
`robot_description` must publish before the `create` node can spawn.

---

## 3. Verifying it's working

### 3.1 Gazebo-side topics
Harmonic uses the `gz` command (there is no `ign`):
```bash
gz topic -l | grep -E "camera|imu|navsat|odom|cmd_vel"
```

### 3.2 ROS-side topics and rates
```bash
ros2 topic list
ros2 topic hz /camera/left/image      # ~30 Hz
ros2 topic hz /camera/right/image     # ~30 Hz (stereo mode only)
ros2 topic hz /imu                    # ~100 Hz
ros2 topic echo /odom --once
ros2 topic echo /navsat --once        # only with enable_gps:=true
```

### 3.3 Check the toggles took effect
```bash
ros2 topic list | grep camera/right   # empty in mono mode
ros2 topic list | grep navsat         # empty unless enable_gps:=true
```
(`/navsat` or `/camera/right/*` can appear in the topic list as an empty
bridge endpoint; `ros2 topic hz` showing no data is the real test.)

---

## 4. Driving the robot

```bash
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist \
  "{linear: {x: 0.3}, angular: {z: 0.0}}"

sudo apt install -y ros-jazzy-teleop-twist-keyboard   # one-time
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```
Robot limits: 1.0 m/s linear, 2.0 rad/s angular.

---

## 5. Visualizing in RViz2

```bash
rviz2 -d ~/ros2_ws/install/ros2_gz_vslam_bot/share/ros2_gz_vslam_bot/config/view_bot.rviz
```
Fixed Frame is `odom`. Shows the robot model, TF, and both camera images
(the right image panel stays empty in mono mode).

---

## 6. Checking the robot's size budget

After editing `description/properties.xacro`:
```bash
python3 scripts/check_envelope.py
python3 scripts/check_envelope.py enable_gps:=true enable_right_camera:=false
```
Fails (exit 1) if the robot exceeds 50x35x25 cm or the CoM leaves the
wheels+caster support triangle.

---

## 7. Known open items

- **Worlds:** only `worlds/empty.world` exists. Maze, indoor and warehouse
  worlds are still to be built (copy its system plugins).
- **Ground truth:** Gazebo pose publisher not yet wired up (needed for Test 2).
- **Not yet run in Gazebo:** this description was validated with xacro and a
  geometric check, not yet launched. First launch may need friction/damping
  tuning of the caster and wheels.

---

## 8. Troubleshooting quick reference

| Symptom | Likely cause |
|---|---|
| No camera data | Sensors plugin missing `ogre2` in the world, or `image_bridge` not running; check `gz topic -l` first to separate Gazebo-side from bridge-side |
| No `/imu` data | World is missing the `gz::sim::systems::Imu` plugin (`gz-sim-imu-system`) |
| No `/navsat` data | `enable_gps:=true` not set, or world lacks the NavSat plugin / `<spherical_coordinates>` |
| Robot doesn't move on `/cmd_vel` | Joint names in `gazebo_controls.xacro` (`l_wheel_joint`, `r_wheel_joint`) must match `joints.xacro` |
| Robot tips forward/back or drags | Check caster friction (`gazebo_materials.xacro`) and that `check_envelope.py` reports CoM inside the support triangle |
| RViz shows nothing under Fixed Frame `odom` | `/tf` not bridging; check `gz_bridge.yaml` has the `tf` entry |
