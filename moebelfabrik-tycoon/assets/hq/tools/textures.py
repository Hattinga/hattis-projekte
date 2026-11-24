"""HQ texture library for Moebelfabrik Tycoon (tileable PBR maps).

Run with a normal Python 3 that has numpy + Pillow:
    python assets/hq/tools/textures.py

Every map is generated from a fixed seed, so a rebuild is byte-identical.
All maps tile seamlessly: the noise is built in the frequency domain
(periodic by construction) and every sine uses integer frequencies.

Convention: U (image x) runs ALONG the wood grain. One texture tile spans
TILE_M metres in the model (see hqlib.TILE_M), so grain scale stays the
same across every asset of the series.
"""
from pathlib import Path
import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "textures"
OUT.mkdir(parents=True, exist_ok=True)
# 512 px per 0.5 m tile = ~1000 px/m, about Roblox's own material density.
# Mobile budget: a quarter of the memory of 1024 maps, no visible loss at game distance.
N = 512


def srgb(hexcode):
    return np.array([int(hexcode[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def periodic_noise(n, seed, fu, fv, power=2.0):
    """Tileable noise. fu/fv = rough cut-off frequency (cycles per tile) in u/v.
    Anisotropic cut-offs stretch the noise (e.g. low fu = streaks along u)."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((n, n))
    ky = np.fft.fftfreq(n) * n  # cycles per tile (v / rows)
    kx = np.fft.fftfreq(n) * n  # cycles per tile (u / cols)
    KX, KY = np.meshgrid(kx, ky)
    r = np.sqrt((KX / fu) ** 2 + (KY / fv) ** 2)
    filt = 1.0 / (1.0 + r ** power)
    filt[0, 0] = 0
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
    out -= out.mean()
    return out / (out.std() + 1e-9)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(h)  # OpenGL (+Y up), Roblox/Blender
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


def save_rgb(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(OUT / f"{name}.png", optimize=True)


def save_gray(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(OUT / f"{name}.png", optimize=True)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def grid(n=N):
    v, u = np.mgrid[0:n, 0:n] / n
    return u, v


# --------------------------------------------------------------------------- wood
def wood(name, seed, light, mid, late, rings, rough_base, rough_var, contrast, pores, normal_strength):
    """Flat-sawn hardwood. Annual rings run along u (grain direction) and are
    distorted by low-frequency periodic noise, which yields the gentle
    'cathedral' drift of real boards."""
    u, v = grid()
    # Warp must change slowly across the board (fv ~1) or the rings fold into
    # closed loops (burl look). Along the grain it drifts gently (fu ~1.5).
    warp = periodic_noise(N, seed, 1.0, 0.9, power=3.0) * 1.3 + periodic_noise(N, seed + 1, 4, 1.5, power=3.0) * 0.07
    phase = v * rings + warp
    f = phase - np.floor(phase)
    # earlywood -> latewood: soft rise, short drop. Kept narrow and soft so the
    # grain reads as wood, not as contour lines, at game distance.
    latewood = smoothstep(0.50, 0.93, f) ** 2.2 * (1 - smoothstep(0.93, 1.0, f))
    # fine streaks along the grain (fibres / rays), very stretched in u
    streak = periodic_noise(N, seed + 2, 3, 260, power=1.5)
    pore = periodic_noise(N, seed + 3, 40, 420, power=1.3)
    broad = periodic_noise(N, seed + 4, 1.5, 2.5)  # board-to-board tone drift

    t = np.clip(latewood * contrast + streak * 0.09 + broad * 0.06, 0, 1)
    col = (1 - t)[..., None] * srgb(light) + t[..., None] * srgb(mid)
    col = col * (1 - pores * np.clip(pore, 0, 3)[..., None] * 0.035)
    col = col * (1 - 0.22 * latewood[..., None] * contrast) + 0.22 * latewood[..., None] * contrast * srgb(late)
    col = col * (1 + broad[..., None] * 0.035)
    save_rgb(f"{name}_Color", col)

    height = -latewood * 0.6 - np.clip(pore, 0, 3) * pores * 0.35 + streak * 0.15
    save_rgb(f"{name}_Normal", normal_from_height(height, normal_strength))

    rough = rough_base + rough_var * (latewood * 0.6 + np.clip(pore, 0, 3) * 0.15) + broad * 0.02
    save_gray(f"{name}_Roughness", rough)


# ---------------------------------------------------------------------- cardboard
def cardboard(name, seed):
    u, v = grid()
    fib = periodic_noise(N, seed, 90, 140, power=1.4)
    blot = periodic_noise(N, seed + 1, 3, 3)
    speck = periodic_noise(N, seed + 2, 400, 400, power=0.8)
    flute = 0.5 + 0.5 * np.sin(2 * np.pi * v * 128)  # corrugation barely shows through the liner
    base = srgb("B98C5B")
    col = base * (1 + fib[..., None] * 0.045 + blot[..., None] * 0.02)
    dark = (speck > 2.6)[..., None] * 0.18
    col = col * (1 - dark)
    save_rgb(f"{name}_Color", col)
    save_rgb(f"{name}_Normal", normal_from_height(fib * 0.25 + flute * 0.35 + blot * 0.1, 0.9))
    save_gray(f"{name}_Roughness", 0.86 + fib * 0.03)


# ------------------------------------------------------------------- rubber belt
def rubber(name, seed):
    """Conveyor belt top: fine cross ribs every 1/64 tile along v."""
    u, v = grid()
    ribs = smoothstep(0.35, 0.5, np.abs(((v * 64) % 1) - 0.5))
    wear = periodic_noise(N, seed, 3, 40)
    grit = periodic_noise(N, seed + 1, 300, 300, power=1.0)
    col = srgb("2B2D2F") * (1 + wear[..., None] * 0.06 + grit[..., None] * 0.03) * (1 - ribs[..., None] * 0.2)
    save_rgb(f"{name}_Color", col)
    save_rgb(f"{name}_Normal", normal_from_height(-ribs * 1.0 + grit * 0.05, 2.0))
    save_gray(f"{name}_Roughness", 0.78 + wear * 0.04 - ribs * 0.08)


# ------------------------------------------------------------------ painted steel
def paint(name, seed, hexcode):
    """Powder-coat: faint orange-peel in the normal map, colour is tinted in
    the material so one height/roughness set serves every paint colour."""
    peel = periodic_noise(N, seed, 60, 60, power=2.0)
    fine = periodic_noise(N, seed + 1, 300, 300, power=1.0)
    blot = periodic_noise(N, seed + 2, 2, 2)
    col = srgb(hexcode) * (1 + blot[..., None] * 0.02 + fine[..., None] * 0.008)
    save_rgb(f"{name}_Color", col)
    save_rgb(f"{name}_Normal", normal_from_height(peel * 0.4 + fine * 0.05, 0.6))
    save_gray(f"{name}_Roughness", 0.52 + peel * 0.03 + blot * 0.02)


if __name__ == "__main__":
    # Raw: pale, matte, soft grain (sanded beech / spruce feel)
    wood("WoodRaw", 11, light="DEBD8F", mid="CDA778", late="AD8052", rings=52,
         rough_base=0.74, rough_var=0.10, contrast=0.6, pores=1.0, normal_strength=1.2)
    # Finish: warm honey oil finish (P03 HJ3), deeper grain contrast, satin
    wood("WoodFinish", 23, light="C48D5B", mid="A86F40", late="7A4824", rings=52,
         rough_base=0.38, rough_var=0.12, contrast=0.62, pores=1.0, normal_strength=0.8)
    # Bench top: oiled beech butcher block, a touch paler/greyer than the product
    wood("WoodBench", 37, light="D6B48A", mid="BE9A6D", late="9C7550", rings=60,
         rough_base=0.55, rough_var=0.10, contrast=0.55, pores=0.8, normal_strength=1.0)
    cardboard("Cardboard", 51)
    rubber("Rubber", 61)
    # Painted steel deliberately has NO texture maps: on the target phone a
    # flat MeshPart colour is cheaper and reads the same at game distance.
    print("textures ->", OUT)
