"""Read CMU ASF/AMC skeletal motion in its documented axis frames.

Used only by the offline recorded-locomotion asset preparer. R is a world
rest-to-current rotation delta: it acts on each ASF rest direction. Source
length units convert to metres with .0254/.45. Root channels are XYZ position,
then XYZ Euler rotation; all selected CMU sources use this ordering.
"""
from pathlib import Path
import re
import numpy as np
from scipy.spatial.transform import Rotation as R


def between(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    a /= np.linalg.norm(a)
    b /= np.linalg.norm(b)
    q = np.r_[np.cross(a, b), 1. + np.dot(a, b)]
    if np.linalg.norm(q) < 1.e-8:
        axis = np.cross(a, np.eye(3)[np.argmin(np.abs(a))])
        return R.from_rotvec(axis / np.linalg.norm(axis) * np.pi)
    return R.from_quat(q / np.linalg.norm(q))


class Acclaim:
    def __init__(self, asf):
        text = Path(asf).read_text()
        self.bones = {}
        body = text.split(':bonedata')[1].split(':hierarchy')[0]
        for block in re.findall(r'\bbegin\b(.*?)\bend\b', body, re.S):
            fields = {line.strip().split()[0]: line.strip().split()[1:]
                      for line in block.splitlines() if line.strip()}
            name = fields['name'][0]
            axis = R.from_euler('xyz', list(map(float, fields['axis'][:3])), degrees=True)
            self.bones[name] = dict(direction=np.array(fields['direction'], float),
                                    length=float(fields['length'][0]), axis=axis,
                                    dof=fields.get('dof', []))
        self.parents, self.order = {}, ['root']
        hierarchy = text.split(':hierarchy')[1]
        for line in hierarchy.splitlines():
            parts = line.split()
            if len(parts) > 1:
                for child in parts[1:]:
                    self.parents[child] = parts[0]
        def visit(parent):
            for child, p in self.parents.items():
                if p == parent:
                    self.order.append(child)
                    visit(child)
        visit('root')
        assert len(self.order) == len(self.bones) + 1

    def read(self, amc):
        frames = []
        for line in Path(amc).read_text().splitlines():
            parts = line.split()
            if not parts or parts[0].startswith(('#', ':')):
                continue
            if len(parts) == 1 and parts[0].isdigit():
                frames.append({})
            else:
                frames[-1][parts[0]] = np.array(parts[1:], float)
        required = {'root'} | {name for name, b in self.bones.items() if b['dof']}
        assert all(set(frame) == required for frame in frames), 'Incomplete AMC download/frame'
        return frames

    def evaluate(self, frame):
        # Rotations act on rest direction vectors, with C M C^-1 axis frames.
        root = frame.get('root', np.zeros(6))
        rotations = {'root': R.from_euler('xyz', root[3:], degrees=True)}
        starts = {'root': root[:3].copy()}
        ends = {'root': root[:3].copy()}
        for name in self.order[1:]:
            b = self.bones[name]
            parent = self.parents[name]
            angles = dict(zip(b['dof'], frame.get(name, [])))
            motion = R.from_euler('xyz', [angles.get('r' + a, 0.) for a in 'xyz'], degrees=True)
            rotations[name] = rotations[parent] * b['axis'] * motion * b['axis'].inv()
            starts[name] = ends[parent]
            ends[name] = starts[name] + rotations[name].apply(b['direction'] * b['length'])
        return starts, ends, rotations
