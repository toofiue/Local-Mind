"""Draws the Iris app icon's layers: six aperture blades, the rim, and the glowing core.
Usage: python3 tools/make_aperture_svg.py Icon/AppIcon.icon/Assets"""
import math, sys, os

C, R, RIM, H, GAP = 512.0, 300.0, 34.0, 118.0, 16.0
ROT = math.radians(-90)

def vertex(i, h):
    a = ROT + math.radians(60 * i)
    return (C + h * math.cos(a), C + h * math.sin(a))

def line_of_edge(i, h):
    """Edge from vertex i to i+1: unit normal pointing away from the centre, and offset."""
    a = ROT + math.radians(60 * i + 30)
    n = (math.cos(a), math.sin(a))
    return n, h * math.cos(math.radians(30))

def meet(n1, c1, n2, c2):
    det = n1[0] * n2[1] - n1[1] * n2[0]
    x = (c1 * n2[1] - c2 * n1[1]) / det
    y = (n1[0] * c2 - n2[0] * c1) / det
    return (C + x, C + y)

def on_circle(n, c, direction):
    """Where the line n.x = c meets the blade circle, heading in `direction`."""
    foot = (n[0] * c, n[1] * c)
    t = math.sqrt(max(R * R - c * c, 0))
    p1 = (foot[0] + direction[0] * t, foot[1] + direction[1] * t)
    return (C + p1[0], C + p1[1])

def blade(j):
    n1, c1 = line_of_edge(j, H)        # blade lies outside this line
    n0, c0 = line_of_edge(j - 1, H)    # and inside this one
    a1, a0 = c1 + GAP / 2, c0 - GAP / 2
    corner = meet(n1, a1, n0, a0)
    d1 = (-n1[1], n1[0])               # along edge j, toward vertex j+1
    d0 = (-n0[1], n0[0])
    p1 = on_circle(n1, a1, d1)
    p0 = on_circle(n0, a0, d0)
    return (f'<path fill="#FFFFFF" d="M{corner[0]:.1f} {corner[1]:.1f} L{p1[0]:.1f} {p1[1]:.1f} '
            f'A{R:.0f} {R:.0f} 0 0 0 {p0[0]:.1f} {p0[1]:.1f} Z"/>')

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n{body}\n</svg>\n'

out = sys.argv[1]
for f in os.listdir(out):
    if f.endswith('.svg'): os.remove(os.path.join(out, f))
open(f'{out}/blades.svg', 'w').write(svg('\n'.join(blade(j) for j in range(6))))
open(f'{out}/rim.svg', 'w').write(svg(
    f'<path fill="#FFFFFF" fill-rule="evenodd" d="M{C-R-RIM} {C}a{R+RIM} {R+RIM} 0 1 0 {2*(R+RIM)} 0a{R+RIM} {R+RIM} 0 1 0 {-2*(R+RIM)} 0Z'
    f'M{C-R+6} {C}a{R-6} {R-6} 0 1 0 {2*(R-6)} 0a{R-6} {R-6} 0 1 0 {-2*(R-6)} 0Z"/>'))
open(f'{out}/core.svg', 'w').write(svg(f'<circle fill="#3FE3D2" cx="{C}" cy="{C}" r="{H*1.25:.0f}"/>'))
