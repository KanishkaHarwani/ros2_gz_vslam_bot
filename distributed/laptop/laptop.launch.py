"""Laptop side of the distributed (v2) setup.

Starts the existing simulation stack (Gazebo, robot_state_publisher, spawn,
bridges) from the ros2_gz_vslam_bot package, plus twist_mux which merges the
joystick (/cmd_vel_teleop) and Nav2 (/cmd_vel_smoothed) into /cmd_vel.

Run by path (no build needed):
    ros2 launch distributed/laptop/laptop.launch.py
"""
import os

from ament_index_python.packages import get_package_share_directory

from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource

from launch_ros.actions import Node


def generate_launch_description():
    here = os.path.dirname(os.path.realpath(__file__))

    sim = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(
            get_package_share_directory('ros2_gz_vslam_bot'),
            'launch', 'launch_sim.launch.py'))
    )

    twist_mux = Node(
        package='twist_mux',
        executable='twist_mux',
        output='screen',
        parameters=[os.path.join(here, 'twist_mux.yaml'),
                    {'use_sim_time': True}],
        remappings=[('cmd_vel_out', 'cmd_vel')],
    )

    return LaunchDescription([sim, twist_mux])
