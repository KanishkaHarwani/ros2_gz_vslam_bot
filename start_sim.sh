#!/usr/bin/env bash
#
# start_sim.sh — bring up the full ros2_gz_vslam_bot stack in one shot:
#   1. launch_sim.launch.py   (gz-sim + robot_state_publisher + spawn + bridges)
#   2. rviz2                  (config/view_bot.rviz)
#   3. joy_node               (raw joystick input)
#   4. teleop_twist_joy       (joystick -> /cmd_vel)
#
# Usage:
#   chmod +x start_sim.sh
#   ./start_sim.sh [world] [stereo|mono] [gps|nogps]
#
# Examples:
#   ./start_sim.sh                              # empty.world, stereo, no GPS
#   ./start_sim.sh maze.world mono              # monocular test in the maze
#   ./start_sim.sh yard.world stereo gps        # outdoor world with GPS on
#
# Ctrl+C once will stop everything this script started.

set -u

WORLD="${1:-empty.world}"
STEREO_MODE="${2:-stereo}"
GPS_ARG="${3:-nogps}"

case "$STEREO_MODE" in stereo|mono) ;; *)
    echo "ERROR: second argument must be 'stereo' or 'mono' (got '$STEREO_MODE')"; exit 1 ;;
esac
case "$GPS_ARG" in
    gps)   ENABLE_GPS=true ;;
    nogps) ENABLE_GPS=false ;;
    *) echo "ERROR: third argument must be 'gps' or 'nogps' (got '$GPS_ARG')"; exit 1 ;;
esac

# ---- Adjust these if your setup differs ------------------------------
ROS_DISTRO_SETUP="/opt/ros/humble/setup.bash"
WORKSPACE_SETUP="$HOME/ros2_ws/install/setup.bash"
PACKAGE_NAME="ros2_gz_vslam_bot"

# teleop_twist_joy axis/button mapping — controller-specific, re-check
# with `ros2 topic echo /joy` if you switch controllers
AXIS_LINEAR=1
AXIS_ANGULAR=0
SCALE_LINEAR=0.5     # m/s   (robot limit is 1.0)
SCALE_ANGULAR=1.0    # rad/s (robot limit is 2.0)
ENABLE_BUTTON=0
# ------------------------------------------------------------------------

echo "==> Sourcing ROS 2 environment"
if [ ! -f "$ROS_DISTRO_SETUP" ]; then
    echo "ERROR: $ROS_DISTRO_SETUP not found. Is ROS 2 Humble installed?"
    exit 1
fi
# shellcheck disable=SC1090
source "$ROS_DISTRO_SETUP"

if [ ! -f "$WORKSPACE_SETUP" ]; then
    echo "ERROR: $WORKSPACE_SETUP not found. Build the workspace first:"
    echo "  cd ~/ros2_ws && colcon build --packages-select ${PACKAGE_NAME}"
    exit 1
fi
# shellcheck disable=SC1090
source "$WORKSPACE_SETUP"

# Use the installed copy of the RViz config (no hard-coded source path)
RVIZ_CONFIG="$(ros2 pkg prefix "${PACKAGE_NAME}")/share/${PACKAGE_NAME}/config/view_bot.rviz"

# Track child PIDs so we can clean up on exit
PIDS=()

cleanup() {
    echo ""
    echo "==> Shutting down..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait 2>/dev/null
    echo "==> Done."
}
trap cleanup INT TERM EXIT

echo "==> Launching sim: world=${WORLD} stereo_mode=${STEREO_MODE} enable_gps=${ENABLE_GPS}"
ros2 launch "${PACKAGE_NAME}" launch_sim.launch.py \
    world:="${WORLD}" stereo_mode:="${STEREO_MODE}" enable_gps:="${ENABLE_GPS}" &
PIDS+=($!)

# Give gz-sim + robot_description a few seconds before spawning RViz/teleop
# (a startup race here is normal on first boot)
echo "==> Waiting for sim to come up..."
sleep 8

if [ -f "$RVIZ_CONFIG" ]; then
    echo "==> Launching RViz2"
    rviz2 -d "$RVIZ_CONFIG" &
    PIDS+=($!)
else
    echo "WARNING: RViz config not found at $RVIZ_CONFIG — launching RViz2 with defaults"
    rviz2 &
    PIDS+=($!)
fi

echo "==> Launching joystick node"
ros2 run joy joy_node &
PIDS+=($!)

echo "==> Launching teleop_twist_joy"
ros2 run teleop_twist_joy teleop_node --ros-args \
    -p axis_linear.x:="${AXIS_LINEAR}" \
    -p axis_angular.yaw:="${AXIS_ANGULAR}" \
    -p scale_linear.x:="${SCALE_LINEAR}" \
    -p scale_angular.yaw:="${SCALE_ANGULAR}" \
    -p enable_button:="${ENABLE_BUTTON}" &
PIDS+=($!)

echo ""
echo "==> All nodes launched. Press Ctrl+C to stop everything."
wait
