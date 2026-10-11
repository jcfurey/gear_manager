#!/usr/bin/env python3
"""
Generates the Shutter Manager app icon.

Design: a six-blade aperture iris on a deep blue-to-teal gradient, with warm light showing through
the opening. Full-bleed (no baked-in rounded-rect bezel; iOS masks the corners), flat with a soft
shadow under the lens ring. Deterministic: re-run to regenerate.

Writes one 1024×1024 PNG, the single-size icon Xcode 14+ scales for every device.

Usage: python3 Tools/generate_app_icon.py   (needs Pillow)
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # supersample master, LANCZOS-downscaled to 1024
OUT = os.path.join(os.path.dirname(__file__), "..",
                   "ShutterManager", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")

# Palette
BG_TOP = (14, 26, 43)        # deep navy, top-left
BG_BOTTOM = (22, 74, 86)     # teal, bottom-right
RING = (196, 204, 212)       # lens ring
RING_SHADE = (120, 130, 142)
BLADE_LIGHT = (58, 66, 78)
BLADE_DARK = (38, 44, 54)
LIGHT_CENTER = (255, 214, 140)  # warm light through the opening
LIGHT_EDGE = (232, 120, 52)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def diagonal_gradient(c1, c2, size):
    """Smooth diagonal gradient: build small, upscale (a linear ramp stays clean)."""
    g = Image.new("RGB", (64, 64))
    px = g.load()
    for y in range(64):
        for x in range(64):
            px[x, y] = lerp(c1, c2, (x + y) / (2 * 63))
    return g.resize((size, size), Image.BICUBIC)


def radial_gradient(c_inner, c_outer, size):
    g = Image.new("RGB", (128, 128))
    px = g.load()
    for y in range(128):
        for x in range(128):
            d = math.hypot(x - 63.5, y - 63.5) / 63.5
            px[x, y] = lerp(c_inner, c_outer, min(1.0, d))
    return g.resize((size, size), Image.BICUBIC)


def ray_circle(origin, direction, radius):
    """First intersection beyond `origin` of the ray origin + t·direction (t > 0) with the circle
    of `radius` centred on (0, 0)."""
    ox, oy = origin
    dx, dy = direction
    a = dx * dx + dy * dy
    b = 2 * (ox * dx + oy * dy)
    c = ox * ox + oy * oy - radius * radius
    t = (-b + math.sqrt(b * b - 4 * a * c)) / (2 * a)
    return (ox + t * dx, oy + t * dy)


def arc_points(p_from, p_to, radius, steps=48):
    a0 = math.atan2(p_from[1], p_from[0])
    a1 = math.atan2(p_to[1], p_to[0])
    while a1 < a0:
        a1 += 2 * math.pi
    return [(radius * math.cos(a0 + (a1 - a0) * i / steps),
             radius * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]


def main():
    img = diagonal_gradient(BG_TOP, BG_BOTTOM, S).convert("RGBA")
    cx = cy = S / 2
    ring_outer = S * 0.40
    ring_inner = S * 0.345
    opening = S * 0.14
    blades = 6
    rotation = math.radians(12)

    # Soft shadow under the lens ring.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        [cx - ring_outer, cy - ring_outer + S * 0.02, cx + ring_outer, cy + ring_outer + S * 0.02],
        fill=(0, 0, 0, 120))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(S * 0.03)))

    # Lens ring: a light-to-dark diagonal sheen.
    ring = diagonal_gradient(RING, RING_SHADE, S).convert("RGBA")
    ring_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ring_mask).ellipse([cx - ring_outer, cy - ring_outer, cx + ring_outer, cy + ring_outer], fill=255)
    img.paste(ring, (0, 0), ring_mask)

    # Warm light behind the iris, visible through the opening.
    light = radial_gradient(LIGHT_CENTER, LIGHT_EDGE, int(ring_inner * 2)).convert("RGBA")
    light_mask = Image.new("L", light.size, 0)
    ImageDraw.Draw(light_mask).ellipse([0, 0, light.size[0] - 1, light.size[1] - 1], fill=255)
    img.paste(light, (int(cx - ring_inner), int(cy - ring_inner)), light_mask)

    # Blades: each is bounded by one edge of the hexagonal opening, the extensions of that edge's
    # neighbours out to the ring, and the arc between them.
    hexagon = [(opening * math.cos(rotation + 2 * math.pi * k / blades),
                opening * math.sin(rotation + 2 * math.pi * k / blades)) for k in range(blades)]
    tips = []
    for k in range(blades):
        a, b = hexagon[k], hexagon[(k + 1) % blades]
        tips.append(ray_circle(b, (b[0] - a[0], b[1] - a[1]), ring_inner))
    draw = ImageDraw.Draw(img)
    for k in range(blades):
        v1 = hexagon[(k + 1) % blades]
        v2 = hexagon[(k + 2) % blades]
        polygon = [v1] + arc_points(tips[k], tips[(k + 1) % blades], ring_inner) + [v2]
        shade = BLADE_LIGHT if k % 2 == 0 else BLADE_DARK
        draw.polygon([(cx + x, cy + y) for x, y in polygon], fill=shade + (255,))
    # Blade edges, so neighbouring blades read as separate leaves.
    for k in range(blades):
        b = hexagon[(k + 1) % blades]
        draw.line([(cx + b[0], cy + b[1]), (cx + tips[k][0], cy + tips[k][1])],
                  fill=(24, 28, 34, 255), width=int(S * 0.006))

    # Thin highlight on the inside of the ring.
    draw.ellipse([cx - ring_inner, cy - ring_inner, cx + ring_inner, cy + ring_inner],
                 outline=(235, 240, 245, 255), width=int(S * 0.008))

    img.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(OUT, "PNG", optimize=True)
    print(f"Wrote {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
