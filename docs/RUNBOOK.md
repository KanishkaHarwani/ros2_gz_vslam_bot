# Runbook: ros2_gz_vslam_bot (Gazebo Harmonic + ROS 2 Jazzy)

Commands assume Ubuntu 24.04 with ROS 2 Jazzy and Gazebo Harmonic. Replace
`~/ros2_ws` with your workspace.

## 1. One-time setup

### 1.1 Install packages
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

### 1.2 Place the package
```
~/ros2_ws/src/ros2_gz_vslam_bot/{package.xml, CMakeLists.txt, description/, launch/, config/, worlds/}
```
`description/meshes/` must exist with the STL files referenced by `links.xacro`.

### 1.3 Build
```bash
cd ~/ros2_ws
rosdep install --from-paths src --ignore-src -r -y
colcon build --packages-select ros2_gz_vslam_bot
```
Verify the install step copied everything:
```bash
ls install/ros2_gz_vslam_bot/share/ros2_gz_vslam_bot/{worlds,launch,config,description}
```

## 2. Every session

### 2.1 One command
```bash
cd ~/ros2_ws/src/ros2_gz_vslam_bot
./startup.sh              # options: --no-rviz  --no-joy
```
`startup.sh` sources ROS and the workspace (auto-detected, or set `WS=...`),
launches the sim, waits for `/odom`, then starts RViz, `joy_node` and
`teleop_twist_joy`. Ctrl+C stops everything.

### 2.2 Manual
```bash
source /opt/ros/jazzy/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch ros2_gz_vslam_bot launch_sim.launch.py
```
If Gazebo opens without a robot, wait a few seconds: `robot_description` must
be published before the spawn node can use it.

## 3. Verify

Each new terminal needs the environment sourced.

```bash
gz topic -l | grep -E "camera|imu|gps|odom|cmd_vel"   # Gazebo side
ros2 topic list                                        # ROS side
ros2 topic hz /camera/front/image                      # ~20 Hz
ros2 topic hz /imu                                     # ~200 Hz
ros2 topic echo /gps/fix --once
ros2 topic echo /odom --once
```
Expected ROS topics: `/clock /odom /tf /joint_states /camera/{front,rear}/{image,camera_info} /imu /gps/fix`.

## 4. Driving

Joystick (started by `startup.sh`), or a one-off command:
```bash
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.3}, angular: {z: 0.0}}"
```
Keyboard teleop:
```bash
sudo apt install -y ros-jazzy-teleop-twist-keyboard
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```
Joystick axis/button indices are controller-specific. Check with
`ros2 topic echo /joy` and edit the variables at the top of `startup.sh`.

## 5. RViz
```bash
rviz2 -d $(ros2 pkg prefix --share ros2_gz_vslam_bot)/rviz/ros2_gz_vslam_bot.rviz \
  --ros-args -p use_sim_time:=true
```
`use_sim_time:=true` is required when launching RViz by hand (`startup.sh` adds
it); without it, TF and image timestamps (sim time) do not match RViz's wall
clock and displays stay empty. Fixed Frame is `odom`; the view follows
`base_link`. See [KNOWN_ISSUES](KNOWN_ISSUES.md) (#13) regarding the config.

## 6. Troubleshooting

| Symptom | Likely cause / check |
|---|---|
| `startup.sh` can't find `install/setup.bash` | Workspace not built, or set `WS=/path/to/ws` |
| Robot doesn't spawn / mesh load errors | `GZ_SIM_RESOURCE_PATH` must include the parent of the package share dir (set by the launch file); check `ros2 pkg prefix ros2_gz_vslam_bot` and `description/meshes/` |
| World not found | `worlds/outdoor_flat.world` not installed; rebuild and check section 1.3 |
| No image topics in ROS | `image_bridge` not running or not in the `LaunchDescription`; check `gz topic -l` first to separate Gazebo-side from bridge-side |
| No camera/IMU/GPS data at all | Sensor systems missing in the world (`Sensors` with `ogre2`, `Imu`, `NavSat`) |
| No `/gps/fix` | World lacks `<spherical_coordinates>` |
| Robot doesn't move on `/cmd_vel` | Wheel joint names in `gazebo_controls.xacro` must match `joints.xacro`; check `/cmd_vel` is bridged |
| RViz shows nothing under Fixed Frame `odom` | `/tf` not bridged; check `gz_bridge.yaml` and that `odom` appears in `ros2 run tf2_tools view_frames` |
| RViz images blank | Image display QoS must be Best Effort |
| RViz shows no robot / "No transform" errors when started by hand | Missing `use_sim_time:=true`; also check RobotModel durability is Transient Local |
