"""Jetson side of the distributed (v2) setup: Nav2 only (for now).

Runs on sim time (the /clock comes from the laptop). Only the Nav2 servers
needed for goal-directed driving are started: no map server, no AMCL, no
collision monitor, no docking/route servers. Nav2 works in the `odom` frame
with rolling costmaps and has no obstacle sensing yet.

Velocity chain:  controller/behaviors -> /cmd_vel_nav
                 -> velocity_smoother -> /cmd_vel_smoothed
                 -> (laptop) twist_mux -> /cmd_vel -> Gazebo

Run by path (no build needed):
    ros2 launch distributed/jetson/jetson.launch.py [decode_images:=true]
"""
import os

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, GroupAction
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration

from launch_ros.actions import Node, SetParameter
from launch_ros.parameter_descriptions import ParameterFile


LIFECYCLE_NODES = [
    'controller_server',
    'smoother_server',
    'planner_server',
    'behavior_server',
    'velocity_smoother',
    'bt_navigator',
    'waypoint_follower',
]


def generate_launch_description():
    here = os.path.dirname(os.path.realpath(__file__))

    use_sim_time = LaunchConfiguration('use_sim_time')
    autostart = LaunchConfiguration('autostart')
    params_file = ParameterFile(LaunchConfiguration('params_file'))

    args = [
        DeclareLaunchArgument('use_sim_time', default_value='true'),
        DeclareLaunchArgument('autostart', default_value='true'),
        DeclareLaunchArgument(
            'params_file',
            default_value=os.path.join(here, 'config', 'nav2_params.yaml')),
        DeclareLaunchArgument(
            'decode_images', default_value='false',
            description='Decode the laptop\'s compressed camera images to raw '
                        'on the Jetson (for VIO / perception nodes).'),
    ]

    def nav2_node(package, executable, name, remappings=None):
        return Node(
            package=package,
            executable=executable,
            name=name,
            output='screen',
            parameters=[params_file],
            remappings=remappings or [],
        )

    nav2 = GroupAction([
        SetParameter('use_sim_time', use_sim_time),

        nav2_node('nav2_controller', 'controller_server', 'controller_server',
                  [('cmd_vel', 'cmd_vel_nav')]),
        nav2_node('nav2_smoother', 'smoother_server', 'smoother_server'),
        nav2_node('nav2_planner', 'planner_server', 'planner_server'),
        nav2_node('nav2_behaviors', 'behavior_server', 'behavior_server',
                  [('cmd_vel', 'cmd_vel_nav')]),
        nav2_node('nav2_velocity_smoother', 'velocity_smoother',
                  'velocity_smoother', [('cmd_vel', 'cmd_vel_nav')]),
        nav2_node('nav2_bt_navigator', 'bt_navigator', 'bt_navigator'),
        nav2_node('nav2_waypoint_follower', 'waypoint_follower',
                  'waypoint_follower'),

        Node(
            package='nav2_lifecycle_manager',
            executable='lifecycle_manager',
            name='lifecycle_manager_navigation',
            output='screen',
            parameters=[{'autostart': autostart,
                         'node_names': LIFECYCLE_NODES}],
        ),
    ])

    # Optional: decode compressed images published by the laptop. Nothing on
    # the Jetson subscribes to the raw image topics, so raw frames are never
    # sent over the network.
    decoders = [
        Node(
            package='image_transport',
            executable='republish',
            name=f'decode_{side}',
            arguments=['compressed', 'raw'],
            remappings=[
                ('in/compressed', f'/camera/{side}/image/compressed'),
                ('out', f'/camera/{side}/image_decoded'),
            ],
            parameters=[{'use_sim_time': True}],
            condition=IfCondition(LaunchConfiguration('decode_images')),
            output='screen',
        )
        for side in ('front', 'rear')
    ]

    return LaunchDescription(args + [nav2] + decoders)
