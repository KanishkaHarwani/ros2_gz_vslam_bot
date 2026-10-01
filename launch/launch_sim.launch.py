import os

from ament_index_python.packages import get_package_share_directory

from launch import LaunchDescription
from launch.actions import AppendEnvironmentVariable, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource

from launch_ros.actions import Node


def generate_launch_description():

    package_name = 'ros2_gz_vslam_bot'
    pkg_share = get_package_share_directory(package_name)

    # Gazebo Harmonic: GZ_SIM_RESOURCE_PATH (was IGN_GAZEBO_RESOURCE_PATH on
    # Fortress). ros_gz_sim rewrites the URDF's package:// mesh URIs into
    # model://ros2_gz_vslam_bot/..., so Gazebo needs the *parent* of the
    # installed share dir on its path. Appended, so any path the user has
    # already exported is preserved.
    gz_resource_path = AppendEnvironmentVariable(
        'GZ_SIM_RESOURCE_PATH',
        os.path.join(pkg_share, '..')
    )

    # robot_state_publisher (force sim time on)
    rsp = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(pkg_share, 'launch', 'rsp.launch.py')
        ),
        launch_arguments={'use_sim_time': 'true'}.items()
    )

    # gz-sim server + GUI with the outdoor world. -r = start running.
    # on_exit_shutdown: closing Gazebo tears down the whole launch.
    world_path = os.path.join(pkg_share, 'worlds', 'outdoor_flat.world')

    gz_sim = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(get_package_share_directory('ros_gz_sim'),
                         'launch', 'gz_sim.launch.py')
        ),
        launch_arguments={
            'gz_args': f'-r {world_path}',
            'on_exit_shutdown': 'true',
        }.items()
    )

    # Spawn the robot from /robot_description. -z 0.05 leaves a small
    # clearance above the ground so the first physics step doesn't resolve
    # an interpenetrating contact.
    spawn_entity = Node(
        package='ros_gz_sim',
        executable='create',
        arguments=[
            '-topic', 'robot_description',
            '-name', 'my_bot',
            '-z', '0.05',
        ],
        output='screen'
    )

    # General bridge: clock, odom, tf, joint_states, cmd_vel, camera_info,
    # imu, gps/fix (see config/gz_bridge.yaml)
    bridge_config = os.path.join(pkg_share, 'config', 'gz_bridge.yaml')

    gz_bridge_node = Node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        parameters=[{
            'config_file': bridge_config,
            'use_sim_time': True,
        }],
        output='screen'
    )

    # Efficient image-specific bridge for the two mono cameras
    # (no depth images any more).
    ros_gz_image_bridge = Node(
        package='ros_gz_image',
        executable='image_bridge',
        arguments=[
            '/camera/front/image',
            '/camera/rear/image',
        ],
        parameters=[{'use_sim_time': True}],
        output='screen'
    )

    return LaunchDescription([
        gz_resource_path,
        rsp,
        gz_sim,
        spawn_entity,
        gz_bridge_node,
        ros_gz_image_bridge,
    ])
