import os

from ament_index_python.packages import get_package_share_directory

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

import xacro


def _setup(context, *args, **kwargs):
    # xacro args must be real strings at process time, so resolve the launch
    # configurations here instead of at LaunchDescription construction.
    use_sim_time = LaunchConfiguration('use_sim_time').perform(context).lower() == 'true'
    enable_gps = LaunchConfiguration('enable_gps').perform(context).lower()
    stereo_mode = LaunchConfiguration('stereo_mode').perform(context).lower()

    if stereo_mode not in ('stereo', 'mono'):
        raise RuntimeError(f"stereo_mode must be 'stereo' or 'mono', got '{stereo_mode}'")

    pkg_path = get_package_share_directory('ros2_gz_vslam_bot')
    xacro_file = os.path.join(pkg_path, 'description', 'robot.urdf.xacro')
    robot_description = xacro.process_file(
        xacro_file,
        mappings={
            'enable_gps': 'true' if enable_gps == 'true' else 'false',
            'enable_right_camera': 'true' if stereo_mode == 'stereo' else 'false',
        },
    ).toxml()

    return [Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        output='screen',
        parameters=[{'robot_description': robot_description,
                     'use_sim_time': use_sim_time}],
    )]


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument(
            'use_sim_time', default_value='false',
            description='Use sim time if true'),
        DeclareLaunchArgument(
            'stereo_mode', default_value='stereo',
            description="'stereo' = left+right cameras, 'mono' = left camera only"),
        DeclareLaunchArgument(
            'enable_gps', default_value='false',
            description='Enable the GPS (NavSat) sensor; only useful in outdoor worlds'),
        OpaqueFunction(function=_setup),
    ])
