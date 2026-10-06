#!/usr/bin/env bash
#
# startup_laptop.sh — laptop side of the distributed (v2) setup.
#   1. laptop.launch.py : Gazebo + robot_state_publisher + spawn + bridges + twist_mux
#   2. rviz2            (rviz/ros2_gz_vslam_bot.rviz from the installed package)
#   3. joy_node + teleop_twist_joy  (publishes /cmd_vel_teleop, overrides Nav2)
#
# Start this FIRST, then run jetson/startup_jetson.sh on the Jetson.
#
# Usage: ./startup_laptop.sh [--no-rviz] [--no-joy]
# Env:   WS=<workspace>  NETWORK_ENV=<file>  JOY_DEVICE_ID=0
#
# Needs: ros-jazzy-twist-mux, distributed/network.env (copy from network.env.example)

PACKAGE_NAME="ros2_gz_vslam_bot"
ROS_SETUP="/opt/ros/jazzy/setup.bash"
JOY_DEVICE_ID="${JOY_DEVICE_ID:-0}"

AXIS_LINEAR=1
AXIS_ANGULAR=0
SCALE_LINEAR=0.5
SCALE_ANGULAR=1.0
ENABLE_BUTTON=0
SIM_WAIT_TIMEOUT=60

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${NETWORK_ENV:-$DIST_DIR/network.env}"

# Workspace: $WS, else <ws>/src/<repo>/distributed/laptop -> <ws>, else ~/ros2_ws
if [ -z "${WS:-}" ]; then
    candidate="$(cd "$SCRIPT_DIR/../../../.." 2>/dev/null && pwd)"
    if [ -f "$candidate/install/setup.bash" ]; then WS="$candidate"; else WS="$HOME/ros2_ws"; fi
fi

USE_RVIZ=1
USE_JOY=1
for arg in "$@"; do
    case "$arg" in
        --no-rviz) USE_RVIZ=0 ;;
        --no-joy)  USE_JOY=0 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

[ -f "$ROS_SETUP" ] || { echo "ERROR: $ROS_SETUP not found."; exit 1; }
[ -f "$WS/install/setup.bash" ] || { echo "ERROR: $WS/install/setup.bash not found (build first, or set WS=)."; exit 1; }
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found. Copy network.env.example to network.env and edit it."; exit 1; }

set +u
source "$ROS_SETUP"
source "$WS/install/setup.bash"
source "$ENV_FILE"

: "${ROS_DOMAIN_ID:?set ROS_DOMAIN_ID in $ENV_FILE}"
: "${JETSON_IP:?set JETSON_IP in $ENV_FILE}"
export ROS_STATIC_PEERS="$JETSON_IP"

echo "==> Laptop | workspace: $WS | ROS_DOMAIN_ID=$ROS_DOMAIN_ID | RMW=${RMW_IMPLEMENTATION:-default}"
echo "==> Peer (Jetson): $JETSON_IP | discovery range: ${ROS_AUTOMATIC_DISCOVERY_RANGE:-default}"
if ! ping -c1 -W1 "$JETSON_IP" >/dev/null 2>&1; then
    echo "WARNING: cannot ping the Jetson at $JETSON_IP (check cable/IP). Continuing."
fi
ros2 pkg prefix twist_mux >/dev/null 2>&1 || { echo "ERROR: twist_mux missing: sudo apt install ros-jazzy-twist-mux"; exit 1; }
ros2 pkg prefix "$PACKAGE_NAME" >/dev/null 2>&1 || { echo "ERROR: package '$PACKAGE_NAME' not found in workspace."; exit 1; }
RVIZ_CONFIG="$(ros2 pkg prefix --share "$PACKAGE_NAME")/rviz/ros2_gz_vslam_bot.rviz"

PIDS=()
CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - INT TERM EXIT
    echo ""; echo "==> Shutting down..."
    for pid in "${PIDS[@]}"; do kill -INT -- "-$pid" 2>/dev/null; done
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        alive=0
        for pid in "${PIDS[@]}"; do kill -0 "$pid" 2>/dev/null && alive=1; done
        [ "$alive" -eq 0 ] && break
        sleep 0.5
    done
    for pid in "${PIDS[@]}"; do kill -TERM -- "-$pid" 2>/dev/null; done
    wait 2>/dev/null
    echo "==> Done."
}
trap cleanup INT TERM EXIT

echo "==> Launching sim + bridges + twist_mux"
setsid ros2 launch "$SCRIPT_DIR/laptop.launch.py" &
PIDS+=($!)

echo "==> Waiting for the robot (up to ${SIM_WAIT_TIMEOUT}s)..."
if timeout "$SIM_WAIT_TIMEOUT" ros2 topic echo --once /odom >/dev/null 2>&1; then
    echo "    /odom is live."
else
    echo "WARNING: no /odom within ${SIM_WAIT_TIMEOUT}s — check the launch output."
fi

# The Jetson must receive compressed images, never raw ones (~295 Mbit/s).
if ros2 topic list 2>/dev/null | grep -q "/camera/front/image/compressed"; then
    echo "    compressed image topics found."
else
    echo "WARNING: /camera/front/image/compressed not found. See docs/DISTRIBUTED.md"
    echo "         ('Compressed images') for the republish fallback. Do NOT subscribe"
    echo "         to the raw images from the Jetson."
fi

if [ "$USE_RVIZ" -eq 1 ]; then
    echo "==> Launching RViz2"
    if [ -f "$RVIZ_CONFIG" ]; then
        setsid rviz2 -d "$RVIZ_CONFIG" --ros-args -p use_sim_time:=true &
    else
        setsid rviz2 --ros-args -p use_sim_time:=true &
    fi
    PIDS+=($!)
fi

if [ "$USE_JOY" -eq 1 ]; then
    if ls /dev/input/js* >/dev/null 2>&1; then
        echo "==> Launching joystick (publishes /cmd_vel_teleop)"
        setsid ros2 run joy joy_node --ros-args -p device_id:="${JOY_DEVICE_ID}" &
        PIDS+=($!)
        setsid ros2 run teleop_twist_joy teleop_node --ros-args \
            -r cmd_vel:=cmd_vel_teleop \
            -p axis_linear.x:="${AXIS_LINEAR}" \
            -p axis_angular.yaw:="${AXIS_ANGULAR}" \
            -p scale_linear.x:="${SCALE_LINEAR}" \
            -p scale_angular.yaw:="${SCALE_ANGULAR}" \
            -p enable_button:="${ENABLE_BUTTON}" &
        PIDS+=($!)
    else
        echo "WARNING: no joystick at /dev/input/js* — skipping joy + teleop."
    fi
fi

echo ""
echo "==> Laptop side up. Now start distributed/jetson/startup_jetson.sh on the Jetson."
echo "    Ctrl+C stops everything."
wait "${PIDS[0]}"
