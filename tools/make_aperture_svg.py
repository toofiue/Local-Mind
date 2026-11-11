"""Draws the Local Mind app icon: six swirling clay petals around a clay pupil, on cream.
Two colors only. Usage: python3 tools/make_aperture_svg.py Icon/AppIcon.icon/Assets"""
import math, sys, os

CLAY = "#D97757"
C = 512.0
R = 318.0          # outer edge of the petals
INNER = 128.0      # the opening in the middle
SWIRL = 58.0       # how far each petal edge turns, in degrees, from the opening to the rim
GAP = 15.0         # the gap between petals, in pixels, the same width all the way out
PUPIL = 92.0       # the clay pupil
GLINT = 24.0       # the cream catchlight that makes it look alive

def point(radius, degrees):
    a = math.radians(degrees - 90)
    return (C + radius * math.cos(a), C + radius * math.sin(a))

def edge(start, side, steps=32):
    """A petal edge that spirals out from the opening to the rim.
    `side` is +1 or -1: which way to step back from the centre line of the gap."""
    pts = []
    for k in range(steps + 1):
        t = k / steps
        radius = INNER + (R - INNER) * t
        offset = math.degrees(GAP / 2 / radius) * side
        pts.append(point(radius, start + SWIRL * (1 - (1 - t) ** 1.25) + offset))
    return pts

def petal(i):
    left, right = edge(i * 60, 1), edge((i + 1) * 60, -1)
    d = f"M{left[0][0]:.1f} {left[0][1]:.1f} "
    d += " ".join(f"L{x:.1f} {y:.1f}" for x, y in left[1:])
    end = right[-1]
    d += f" A{R:.0f} {R:.0f} 0 0 1 {end[0]:.1f} {end[1]:.1f} "
    d += " ".join(f"L{x:.1f} {y:.1f}" for x, y in reversed(right[:-1]))
    start = left[0]
    d += f" A{INNER:.0f} {INNER:.0f} 0 0 0 {start[0]:.1f} {start[1]:.1f} Z"
    return f'<path fill="{CLAY}" d="{d}"/>'

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n{body}\n</svg>\n'

out = sys.argv[1]
for f in os.listdir(out):
    if f.endswith('.svg'): os.remove(os.path.join(out, f))
open(f'{out}/petals.svg', 'w').write(svg('\n'.join(petal(i) for i in range(6))))
# The pupil, with a catchlight cut out of its upper left, like light caught in an eye.
gx, gy = C - PUPIL * 0.36, C - PUPIL * 0.36
open(f'{out}/pupil.svg', 'w').write(svg(
    f'<path fill="{CLAY}" fill-rule="evenodd" d="M{C-PUPIL} {C}a{PUPIL} {PUPIL} 0 1 0 {2*PUPIL} 0a{PUPIL} {PUPIL} 0 1 0 {-2*PUPIL} 0Z'
    f'M{gx-GLINT} {gy}a{GLINT} {GLINT} 0 1 0 {2*GLINT} 0a{GLINT} {GLINT} 0 1 0 {-2*GLINT} 0Z"/>'))
