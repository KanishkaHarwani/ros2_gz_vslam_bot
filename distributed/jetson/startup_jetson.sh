#!/usr/bin/env bash
#
# startup_jetson.sh — Jetson side of the distributed (v2) setup: Nav2.
# Start the laptop side (startup_laptop.sh) first.
#
# Usage: ./startup_jetson.sh [--decode-images]
# Env:   NETWORK_ENV=<file>
#
# Needs only ROS 2 Jazzy + Nav2 (no colcon build; this repo is just cloned).
# Needs: distributed/network.env (copy from network.env.example)

ROS_SETUP="/opt/ros/jazzy/setup.bash"
WAIT_TIMEOUT=120

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${NETWORK_ENV:-$DIST_DIR/network.env}"

DECODE=false
for arg in "$@"; do
    case "$arg" in
        --decode-images) DECODE=true ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

[ -f "$ROS_SETUP" ] || { echo "ERROR: $ROS_SETUP not found."; exit 1; }
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found. Copy network.env.example to network.env and edit it."; exit 1; }

set +u
source "$ROS_SETUP"
source "$ENV_FILE"

: "${ROS_DOMAIN_ID:?set ROS_DOMAIN_ID in $ENV_FILE}"
: "${LAPTOP_IP:?set LAPTOP_IP in $ENV_FILE}"
export ROS_STATIC_PEERS="$LAPTOP_IP"

echo "==> Jetson | ROS_DOMAIN_ID=$ROS_DOMAIN_ID | RMW=${RMW_IMPLEMENTATION:-default}"
echo "==> Peer (laptop): $LAPTOP_IP | discovery range: ${ROS_AUTOMATIC_DISCOVERY_RANGE:-default}"
if ! ping -c1 -W1 "$LAPTOP_IP" >/dev/null 2>&1; then
    echo "WARNING: cannot ping the laptop at $LAPTOP_IP (check cable/IP). Continuing."
fi

missing=0
for pkg in nav2_controller nav2_planner nav2_smoother nav2_behaviors nav2_bt_navigator \
           nav2_velocity_smoother nav2_waypoint_follower nav2_lifecycle_manager \
           nav2_regulated_pure_pursuit_controller nav2_navfn_planner; do
    ros2 pkg prefix "$pkg" >/dev/null 2>&1 || { echo "ERROR: missing ROS package: $pkg"; missing=1; }
done
[ "$missing" -eq 0 ] || exit 1
if [ "$DECODE" = true ]; then
    ros2 pkg prefix image_transport >/dev/null 2>&1 || { echo "ERROR: image_transport missing (ros-jazzy-image-transport, ros-jazzy-compressed-image-transport)."; exit 1; }
fi

echo "==> Waiting for the laptop's /clock and /odom (up to ${WAIT_TIMEOUT}s)..."
if timeout "$WAIT_TIMEOUT" ros2 topic echo --once /clock >/dev/null 2>&1; then
    echo "    /clock received."
else
    echo "ERROR: no /clock from the laptop. Check: same ROS_DOMAIN_ID/RMW on both,"
    echo "       network.env IPs, firewall, and that startup_laptop.sh is running."
    exit 1
fi
if timeout 30 ros2 topic echo --once /odom >/dev/null 2>&1; then
    echo "    /odom received."
else
    echo "WARNING: /clock arrives but no /odom — is the robot spawned?"
fi

echo "==> Launching Nav2 (sim time, odom frame, no obstacle sensing yet)"
exec ros2 launch "$SCRIPT_DIR/jetson.launch.py" decode_images:="$DECODE"
