#!/usr/bin/env python3
"""Check the robot against its size budget and report mass / centre of mass.

Processes description/robot.urdf.xacro (with the toggles you pass), walks the
joint tree from base_link, and computes the axis-aligned bounding box of every
visual and collision shape in the robot frame, with the ground taken as the
lowest point (the wheel/caster contact).

Usage:
    python3 scripts/check_envelope.py
    python3 scripts/check_envelope.py enable_gps:=true enable_right_camera:=false

Exit code is 1 if the envelope or the stability check fails.
"""
import math
import os
import sys
import xml.etree.ElementTree as ET

import xacro

LIMIT_L, LIMIT_W, LIMIT_H = 0.50, 0.35, 0.25  # metres


def rpy_matrix(r, p, y):
    cr, sr, cp, sp, cy, sy = (math.cos(r), math.sin(r), math.cos(p),
                              math.sin(p), math.cos(y), math.sin(y))
    return [[cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr],
            [sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr],
            [-sp, cp * sr, cp * cr]]


def mat_vec(m, v):
    return [sum(m[i][j] * v[j] for j in range(3)) for i in range(3)]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def floats(s, n=3, default=0.0):
    if s is None:
        return [default] * n
    return [float(x) for x in s.split()]


def origin(el):
    o = el.find('origin') if el is not None else None
    if o is None:
        return [0, 0, 0], [0, 0, 0]
    return floats(o.get('xyz')), floats(o.get('rpy'))


def shape_points(geom):
    """Points (local frame) whose bounding box equals the shape's."""
    box, cyl, sph = geom.find('box'), geom.find('cylinder'), geom.find('sphere')
    if box is not None:
        x, y, z = [v / 2 for v in floats(box.get('size'))]
        return [[sx * x, sy * y, sz * z] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    if cyl is not None:
        r, h = float(cyl.get('radius')), float(cyl.get('length')) / 2
        return [[r * math.cos(a), r * math.sin(a), sz * h]
                for a in [i * math.pi / 18 for i in range(36)] for sz in (-1, 1)]
    if sph is not None:
        r = float(sph.get('radius'))
        return [[sx * r, sy * r, sz * r] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)] + \
               [[r, 0, 0], [-r, 0, 0], [0, r, 0], [0, -r, 0], [0, 0, r], [0, 0, -r]]
    return []


def main():
    mappings = dict(a.split(':=', 1) for a in sys.argv[1:] if ':=' in a)
    pkg = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    doc = xacro.process_file(os.path.join(pkg, 'description', 'robot.urdf.xacro'),
                             mappings=mappings)
    root = ET.fromstring(doc.toxml())
    links = {l.get('name'): l for l in root.findall('link')}

    # Link poses in base_link frame
    pose = {'base_link': ([0, 0, 0], [[1, 0, 0], [0, 1, 0], [0, 0, 1]])}
    pending = list(root.findall('joint'))
    while pending:
        progressed = False
        for j in list(pending):
            parent, child = j.find('parent').get('link'), j.find('child').get('link')
            if parent in pose:
                p0, r0 = pose[parent]
                xyz, rpy = origin(j)
                r1 = mat_mul(r0, rpy_matrix(*rpy))
                p1 = [a + b for a, b in zip(p0, mat_vec(r0, xyz))]
                pose[child] = (p1, r1)
                pending.remove(j)
                progressed = True
        if not progressed:
            sys.exit('ERROR: disconnected joint tree: ' + ', '.join(
                j.get('name') for j in pending))

    lo, hi = [1e9] * 3, [-1e9] * 3
    mass, com = 0.0, [0.0, 0.0, 0.0]
    for name, link in links.items():
        p, r = pose[name]
        for tag in ('visual', 'collision'):
            for el in link.findall(tag):
                xyz, rpy = origin(el)
                rr = mat_mul(r, rpy_matrix(*rpy))
                base = [a + b for a, b in zip(p, mat_vec(r, xyz))]
                for pt in shape_points(el.find('geometry')):
                    w = [a + b for a, b in zip(base, mat_vec(rr, pt))]
                    lo = [min(a, b) for a, b in zip(lo, w)]
                    hi = [max(a, b) for a, b in zip(hi, w)]
        inertial = link.find('inertial')
        if inertial is not None:
            m = float(inertial.find('mass').get('value'))
            xyz, _ = origin(inertial)
            c = [a + b for a, b in zip(p, mat_vec(r, xyz))]
            mass += m
            com = [a + m * b for a, b in zip(com, c)]
    com = [c / mass for c in com]

    L, W, H = hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]
    ok = L <= LIMIT_L and W <= LIMIT_W and H <= LIMIT_H
    print('config: %s' % (mappings or 'defaults'))
    print('envelope  L %.3f / %.2f   W %.3f / %.2f   H %.3f / %.2f   -> %s'
          % (L, LIMIT_L, W, LIMIT_W, H, LIMIT_H, 'OK' if ok else 'OVER BUDGET'))
    print('  x: %.3f .. %.3f   y: %.3f .. %.3f   z: %.3f .. %.3f (ground at z=%.3f)'
          % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], lo[2]))
    print('mass %.2f kg   CoM (base_link frame): x=%.3f y=%.3f z=%.3f'
          % (mass, *com))

    # Static stability: CoM must be inside the support triangle (wheels + caster)
    def contact(name):
        return pose[name][0][:2]
    a, b, c = contact('l_wheel_link'), contact('r_wheel_link'), contact('caster_link')

    def sign(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    d1, d2, d3 = sign(com[:2], a, b), sign(com[:2], b, c), sign(com[:2], c, a)
    inside = not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
    share = (com[0] - a[0]) / (c[0] - a[0]) if c[0] != a[0] else 0
    print('support triangle: CoM %s; ~%.0f%% of weight on caster'
          % ('inside' if inside else 'OUTSIDE (will tip)', 100 * share))
    sys.exit(0 if ok and inside else 1)


if __name__ == '__main__':
    main()
