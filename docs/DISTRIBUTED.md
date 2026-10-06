# Distributed setup (v2): laptop + Jetson

Gazebo, RViz and the joystick run on the laptop. Nav2 runs on the Jetson.
Everything lives in `distributed/` and is run **by path** (no extra colcon
package; see "Why no package" below).

```
distributed/
├── network.env.example     # copy to network.env on BOTH machines (git-ignored)
├── laptop/
│   ├── startup_laptop.sh   # sim + bridges + twist_mux + RViz + joystick
│   ├── laptop.launch.py
│   └── twist_mux.yaml
└── jetson/
    ├── startup_jetson.sh   # Nav2
    ├── jetson.launch.py
    ├── config/nav2_params.yaml
    └── behavior_trees/     # custom outdoor BT XML goes here
```

## Data flow

```
LAPTOP                                              JETSON
Gazebo ─ bridges ─► /clock /odom /tf /joint_states ──────────► Nav2
                    /imu /gps/fix                              (planner, controller,
                    /camera/*/image/compressed                  BT, velocity smoother)
joystick ─► /cmd_vel_teleop ─┐
                             ├─► twist_mux ─► /cmd_vel ─► Gazebo
/cmd_vel_smoothed ◄──────────┘ (from Nav2, priority 10; joystick is 100)
```

The joystick always overrides Nav2. When the joystick stops publishing for
0.5 s, control falls back to Nav2 (so releasing the enable button resumes an
active Nav2 goal).

## One-time setup

**Both machines**
```bash
cp distributed/network.env.example distributed/network.env   # edit IPs / domain
```
`ROS_DOMAIN_ID` and the RMW must be identical on both. Discovery uses the
subnet plus each side's static peer; if it is flaky set
`ROS_AUTOMATIC_DISCOVERY_RANGE=OFF` to use unicast to the static peer only.

**Laptop:** `sudo apt install ros-jazzy-twist-mux` (the sim package must be built).

**Jetson:** Jazzy and Nav2 only; nothing to build. Clone the repo, create
`network.env`. For `--decode-images` also install
`ros-jazzy-image-transport` and `ros-jazzy-compressed-image-transport`.

## Run

```bash
# 1. laptop
./distributed/laptop/startup_laptop.sh
# 2. Jetson (waits for the laptop's /clock, then starts Nav2)
./distributed/jetson/startup_jetson.sh
```

## Compressed images

Two raw 640x480 RGB streams at 20 Hz are about 37 MB/s (~295 Mbit/s), too
much for the link. Keep raw images local to the laptop: only subscribe to
`/camera/{front,rear}/image/compressed` from the Jetson.

`ros_gz_image` normally publishes the compressed topics itself through
`image_transport`. Check on the laptop:
```bash
ros2 topic list | grep compressed
```
If they are missing, run a republisher on the laptop (verify the syntax with
`ros2 run image_transport republish --help`; it differs between releases):
```bash
ros2 run image_transport republish raw compressed --ros-args \
  -r in:=/camera/front/image -r out/compressed:=/camera/front/image/compressed
```
On the Jetson, `startup_jetson.sh --decode-images` decodes both streams to
`/camera/{front,rear}/image_decoded` for perception nodes.

## Verification checklist

1. **Network:** `ping` both ways; `ros2 topic list` on the Jetson shows the
   laptop's topics.
2. **Rates from the Jetson:** `ros2 topic hz /imu` (~200), `/gps/fix` (~10),
   `/odom` (~50). `ros2 topic bw /camera/front/image/compressed` should be
   roughly 1 MB/s, not tens.
3. **TF:** `ros2 run tf2_ros tf2_echo odom base_link` on the Jetson works.
4. **Milestone test:** in RViz (Fixed Frame `odom`) use *2D Goal Pose*. The
   robot should drive there under Jetson control. Grab the joystick mid-drive:
   it must take over immediately.
5. **Record in `docs/test_logs/`:** `/cmd_vel` round-trip latency, Jetson CPU
   load, and the sim's real-time factor with and without the Jetson attached.

## Limitations (current)

- No obstacle sensing: costmaps hold only inflation, so Nav2 will happily
  plan through obstacles. This is a plumbing test.
- No `map` frame or localization: Nav2 works in `odom` with rolling costmaps
  (goals within ~30 m). GPS/IMU/VIO fusion is the next stage.
- No collision monitor: it needs a sensor source. It slots in between
  `/cmd_vel_smoothed` and `twist_mux` once distance estimation exists.
- The default behavior tree is used until the custom outdoor BT is written.

## Why no package

colcon does not search inside a directory that already contains a
`package.xml`. This repo's root is the `ros2_gz_vslam_bot` package, so a ROS
package nested under `distributed/` would never be found. The launch files and
params therefore run by path. When real Jetson-side nodes are written
(perception, VIO), the repo should be restructured into sibling packages
(see the open decision in [ROADMAP](ROADMAP.md#open-decisions)).

## Troubleshooting

| Symptom | Check |
|---|---|
| Jetson never sees `/clock` | Same `ROS_DOMAIN_ID` and RMW on both; IPs in `network.env`; firewall (`sudo ufw status`); try `ROS_AUTOMATIC_DISCOVERY_RANGE=OFF` |
| Topics listed but no data | QoS mismatch (cameras are Best Effort); a very large raw subscription over UDP |
| Nav2 nodes idle / lifecycle waits | `/clock` not arriving, so sim time never advances |
| "Extrapolation" / transform errors | Missing `use_sim_time` on a node; `odom`→`base_link` TF not reaching the Jetson |
| Robot ignores Nav2 | `ros2 topic echo /cmd_vel_smoothed` on the laptop; `twist_mux` running; joystick not holding priority |
| Robot ignores the joystick | Teleop must publish `/cmd_vel_teleop` (remapped), not `/cmd_vel` |
