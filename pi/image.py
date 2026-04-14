from io import BytesIO

from PIL import Image

# Thermal printer dot widths at 203 dpi (8 dots/mm).
WIDTHS = {58: 384, 80: 576}


def prepare(image_bytes: bytes, width_mm: int = 80) -> Image.Image:
    px = WIDTHS[width_mm]
    img = Image.open(BytesIO(image_bytes))
    img.load()
    if img.mode != "L":
        img = img.convert("L")
    if img.width != px:
        new_h = max(1, round(img.height * px / img.width))
        img = img.resize((px, new_h), Image.LANCZOS)
    return img.convert("1", dither=Image.FLOYDSTEINBERG)
