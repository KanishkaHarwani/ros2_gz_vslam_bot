# Known issues

Last updated after the Jazzy/Harmonic migration and sensor-set change.
Move items to "Resolved" (with the date and test log) when closed.

## Open

| # | Area | Issue | Impact / next step |
|---|---|---|---|
| 1 | Migration | The Harmonic port of the description, world, bridge and launch files has not been validated end-to-end | Run Stage 0 / Test 1 checks from the [roadmap](ROADMAP.md) and log results |
| 2 | Physics | Wheel friction and pivot behavior were tuned on the older Gazebo (ODE-style parameters). Harmonic defaults to DART, which ignores `kp`/`kd` | Re-test in-place rotation for wobble; retune `mu1`/`mu2` if needed |
| 3 | Physics | Wheel collisions are spheres (radius 0.225), while older notes describe cylinders | Confirm which is intended; spheres roll smoothly but have a single contact patch |
| 4 | Physics | Chassis box inertia matches the stated inertial values only to ~8% | Revisit if rotation or pitch behavior looks off |
| 5 | Drive model | `DiffDrive` models two "sides", not four independently driven wheels, so skid-steer slip is not realistic | May distort the odometry baseline (Test 2); revisit if drift looks wrong |
| 6 | Odometry | Wheel odometry and its `odom → base_link` TF are still published by the sim. Whether wheel odometry is an allowed localization input is undecided | If a fused estimate publishes this TF, disable the sim's version |
| 7 | Sensors | Cameras use a plain pinhole model at 130° HFOV (strong edge stretching, no lens distortion) | May matter for VIO and distance estimation; decide on a lens model |
| 8 | Sensors | Camera resolution (640x480) and rate (20 Hz) are below the original 1080p/60 fps target | Deliberate (load); revisit for realism |
| 9 | Sensors | IMU and GPS noise values are generic starting points | Replace with the real hardware's datasheet values |
| 10 | World | GPS origin in `outdoor_flat.world` is a placeholder (0°, 0°, 0 m) | Set to the intended test-site coordinates |
| 11 | World | The ground plane is featureless | Monocular VIO has nothing to track; add texture/feature objects before Test 4 |
| 12 | World | `worlds/flatland.world` is stale: dangling absolute mesh path and a leftover unrelated robot model from a Gazebo-classic export | Clean up or replace before obstacle tests; no rough-terrain world exists yet |
| 13 | RViz | `config/view_bot.rviz` still references the removed lidar/depth/point-cloud displays and the old camera frame names | Update for the new frames, two camera images, IMU and GPS |
| 14 | Packaging | `package.xml` does not list `joy`, `teleop_twist_joy` or `rviz2` as exec dependencies | Add so `rosdep` installs them |
| 15 | Packaging | Repo/package rename to a valid underscore name is only partly done: some files and docs may still use the hyphenated name, and the GitHub repo/remote/LICENSE line may still need updating | Finish the rename pass |
| 16 | Layout | v1/v2 repository split is not yet implemented | See [ARCHITECTURE](ARCHITECTURE.md#6-deployment-variants) |
| 17 | Launch | The spawn node can race `robot_description` on first boot | Re-run, or add a short delay if it becomes a problem |
| 18 | Teleop | Joystick axis/button mapping is controller-specific | Re-check with `ros2 topic echo /joy` when changing controllers |
| 19 | GUI | A Qt/QML segfault was seen once when closing Gazebo, correlated with software rendering | Low priority; does not affect a running sim |

## Environment notes

- If Gazebo falls back to software rendering (look for `libEGL` / `dri2`
  warnings), camera sensors can misbehave. Check
  `glxinfo | grep "direct rendering"` first when sensor output looks wrong.
- Stay on the `ogre2` render engine; the legacy `ogre` engine renders meshes
  incorrectly.
- RViz image displays need Best Effort QoS to receive the bridged images.

## Resolved (history)

These were fixed on the previous stack and are listed because they explain
current model choices.

- **Wheel rocking on in-place rotation:** fixed with anisotropic friction
  (`mu1` 1.0 along the rolling direction, `mu2` 0.3 laterally).
- **Physical pivot offset from odometry:** the single front bumper shifted the
  center of mass ~4.7 cm forward; a mirrored rear bumper brought it under 1 mm.
- **Camera frame corruption while moving:** traced to the combined
  RGB-D camera sensor on `ogre2`
  ([gazebosim/ros_gz#738](https://github.com/gazebosim/ros_gz/issues/738)).
  No longer applicable: depth cameras were removed from the robot.
- **Images missing in ROS:** the image bridge was defined but not added to the
  `LaunchDescription`.
- **Wheel radius and `wheel_separation` mismatches** corrected in `DiffDrive`.
- **Front and rear wheels spinning in opposite directions:** wheel joint axes
  unified.
