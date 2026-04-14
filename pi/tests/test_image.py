from io import BytesIO

from PIL import Image

import image as imageproc


def _png_bytes(w, h, color=128):
    img = Image.new("RGB", (w, h), (color, color, color))
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def test_prepare_resizes_to_576_wide():
    out = imageproc.prepare(_png_bytes(800, 400))
    assert out.width == 576
    assert out.height == 288
    assert out.mode == "1"


def test_prepare_grayscale_input():
    img = Image.new("L", (200, 100), 200)
    buf = BytesIO()
    img.save(buf, format="PNG")
    out = imageproc.prepare(buf.getvalue())
    assert out.mode == "1"
    assert out.width == 576
