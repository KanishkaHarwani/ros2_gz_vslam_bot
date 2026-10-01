#!/usr/bin/env bash
#
# startup.sh — bring up the ros2_gz_vslam_bot stack (ROS 2 Jazzy + Gazebo Harmonic):
#   1. launch_sim.launch.py  (Gazebo + robot_state_publisher + spawn + bridges)
#   2. rviz2                 (config/view_bot.rviz from the installed package)
#   3. joy_node              (raw joystick input)
#   4. teleop_twist_joy      (joystick -> /cmd_vel)
#
# Usage:
#   ./startup.sh [--no-rviz] [--no-joy]
#
# Environment overrides:
#   WS=~/ros2_ws        workspace containing install/setup.bash
#   JOY_DEVICE_ID=0     joystick index for joy_node
#
# Ctrl+C once stops everything this script started.

# NOTE: no `set -u` here — ROS setup scripts reference unset variables.

# ---- Adjust these if your setup differs ------------------------------
PACKAGE_NAME="ros2_gz_vslam_bot"
ROS_SETUP="/opt/ros/jazzy/setup.bash"
WS="${WS:-$HOME/learn_ws}"
JOY_DEVICE_ID="${JOY_DEVICE_ID:-0}"

# teleop_twist_joy mapping — controller-specific; re-check with
# `ros2 topic echo /joy` if you switch controllers.
AXIS_LINEAR=1
AXIS_ANGULAR=0
SCALE_LINEAR=0.5
SCALE_ANGULAR=1.0
ENABLE_BUTTON=0

SIM_WAIT_TIMEOUT=60   # seconds to wait for the robot's /odom before continuing
# ------------------------------------------------------------------------

USE_RVIZ=1
USE_JOY=1
for arg in "$@"; do
    case "$arg" in
        --no-rviz) USE_RVIZ=0 ;;
        --no-joy)  USE_JOY=0 ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

echo "==> Sourcing ROS 2 environment"
if [ ! -f "$ROS_SETUP" ]; then
    echo "ERROR: $ROS_SETUP not found. Is ROS 2 Jazzy installed?"
    exit 1
fi
if [ ! -f "$WS/install/setup.bash" ]; then
    echo "ERROR: $WS/install/setup.bash not found. Build first:"
    echo "  cd $WS && colcon build --packages-select ${PACKAGE_NAME}"
    exit 1
fi
set +u
source "$ROS_SETUP"
source "$WS/install/setup.bash"

if ! ros2 pkg prefix "$PACKAGE_NAME" >/dev/null 2>&1; then
    echo "ERROR: package '$PACKAGE_NAME' not found in the sourced workspace."
    exit 1
fi
RVIZ_CONFIG="$(ros2 pkg prefix --share "$PACKAGE_NAME")/config/view_bot.rviz"

# Each long-running process gets its own session (setsid) so cleanup can
# signal the whole process tree, including gz-sim children of `ros2 launch`.
PIDS=()
CLEANED=0

cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - INT TERM EXIT
    echo ""
    echo "==> Shutting down..."
    for pid in "${PIDS[@]}"; do
        kill -INT -- "-$pid" 2>/dev/null
    done
    # grace period, then force-terminate anything still alive
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        alive=0
        for pid in "${PIDS[@]}"; do
            kill -0 "$pid" 2>/dev/null && alive=1
        done
        [ "$alive" -eq 0 ] && break
        sleep 0.5
    done
    for pid in "${PIDS[@]}"; do
        kill -TERM -- "-$pid" 2>/dev/null
    done
    wait 2>/dev/null
    echo "==> Done."
}
trap cleanup INT TERM EXIT

echo "==> Launching Gazebo + robot_state_publisher + spawn + bridges"
setsid ros2 launch "$PACKAGE_NAME" launch_sim.launch.py &
PIDS+=($!)

echo "==> Waiting for the robot to come up (up to ${SIM_WAIT_TIMEOUT}s)..."
if timeout "$SIM_WAIT_TIMEOUT" ros2 topic echo --once /odom >/dev/null 2>&1; then
    echo "    /odom is live."
else
    echo "WARNING: no /odom within ${SIM_WAIT_TIMEOUT}s — continuing anyway."
    echo "         Check the launch output above (spawn / bridge errors)."
fi

if [ "$USE_RVIZ" -eq 1 ]; then
    if [ -f "$RVIZ_CONFIG" ]; then
        echo "==> Launching RViz2"
        setsid rviz2 -d "$RVIZ_CONFIG" --ros-args -p use_sim_time:=true &
    else
        echo "WARNING: $RVIZ_CONFIG not found — launching RViz2 with defaults"
        setsid rviz2 --ros-args -p use_sim_time:=true &
    fi
    PIDS+=($!)
fi

if [ "$USE_JOY" -eq 1 ]; then
    if ls /dev/input/js* >/dev/null 2>&1; then
        echo "==> Launching joystick node (device_id=${JOY_DEVICE_ID})"
        setsid ros2 run joy joy_node --ros-args -p device_id:="${JOY_DEVICE_ID}" &
        PIDS+=($!)

        echo "==> Launching teleop_twist_joy"
        setsid ros2 run teleop_twist_joy teleop_node --ros-args \
            -p axis_linear.x:="${AXIS_LINEAR}" \
            -p axis_angular.yaw:="${AXIS_ANGULAR}" \
            -p scale_linear.x:="${SCALE_LINEAR}" \
            -p scale_angular.yaw:="${SCALE_ANGULAR}" \
            -p enable_button:="${ENABLE_BUTTON}" &
        PIDS+=($!)
    else
        echo "WARNING: no joystick found at /dev/input/js* — skipping joy + teleop."
    fi
fi

echo ""
echo "==> All nodes launched. Press Ctrl+C to stop everything."
# Exit (and clean up) as soon as the sim launch ends, e.g. Gazebo window closed.
wait "${PIDS[0]}"
