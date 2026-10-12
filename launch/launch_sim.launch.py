import os

from ament_index_python.packages import get_package_share_directory

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, OpaqueFunction
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration

from launch_ros.actions import Node

PACKAGE_NAME = 'ros2_gz_vslam_bot'


def _setup(context, *args, **kwargs):
    pkg_share = get_package_share_directory(PACKAGE_NAME)

    world = LaunchConfiguration('world').perform(context)
    stereo_mode = LaunchConfiguration('stereo_mode').perform(context).lower()
    enable_gps = LaunchConfiguration('enable_gps').perform(context).lower()

    # Accept either a bare name ("empty.world") from worlds/, or a full path.
    world_path = world if os.path.isabs(world) else os.path.join(pkg_share, 'worlds', world)
    if not os.path.isfile(world_path):
        raise RuntimeError(f'World file not found: {world_path}')

    # robot_state_publisher, with the sensor toggles forwarded to xacro.
    rsp = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(pkg_share, 'launch', 'rsp.launch.py')),
        launch_arguments={
            'use_sim_time': 'true',
            'stereo_mode': stereo_mode,
            'enable_gps': enable_gps,
        }.items(),
    )

    # gz-sim server + GUI with the chosen world
    gz_sim = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(get_package_share_directory('ros_gz_sim'),
                         'launch', 'gz_sim.launch.py')),
        launch_arguments={'gz_args': f'-r {world_path}'}.items(),
    )

    # Spawn from /robot_description. base_link is the axle midpoint, so
    # wheel_radius (0.06) of height puts the wheels on the ground; the small
    # extra margin avoids an interpenetrating first physics step.
    spawn_entity = Node(
        package='ros_gz_sim',
        executable='create',
        arguments=['-topic', 'robot_description',
                   '-name', 'vslam_bot',
                   '-z', '0.08'],
        output='screen',
    )

    # General bridge (clock, odom, tf, joint_states, cmd_vel, camera_info, imu, navsat)
    bridge_config = os.path.join(pkg_share, 'config', 'gz_bridge.yaml')
    gz_bridge_node = Node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        parameters=[{'config_file': bridge_config, 'use_sim_time': True}],
        output='screen',
    )

    # Image-specific bridge; only bridge the right image in stereo mode.
    image_topics = ['/camera/left/image']
    if stereo_mode == 'stereo':
        image_topics.append('/camera/right/image')
    ros_gz_image_bridge = Node(
        package='ros_gz_image',
        executable='image_bridge',
        arguments=image_topics,
        output='screen',
    )

    return [rsp, gz_sim, spawn_entity, gz_bridge_node, ros_gz_image_bridge]


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument(
            'world', default_value='empty.world',
            description='World file name in worlds/ (or an absolute path)'),
        DeclareLaunchArgument(
            'stereo_mode', default_value='stereo',
            description="'stereo' = left+right cameras, 'mono' = left camera only"),
        DeclareLaunchArgument(
            'enable_gps', default_value='false',
            description='Enable the GPS sensor (outdoor worlds only)'),
        OpaqueFunction(function=_setup),
    ])
