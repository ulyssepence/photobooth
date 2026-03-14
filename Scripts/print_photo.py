#!/usr/bin/env python3
import sys
import numpy as np
from PIL import Image
from escpos.printer import Usb

VENDOR_ID = 0x0FE6
PRODUCT_ID = 0x811E
HEAD_WIDTH = 576
GAMMA = 1 / 1.8

path = sys.argv[1]
paper_width = int(sys.argv[2]) if len(sys.argv) > 2 else HEAD_WIDTH

img = Image.open(path).convert("L")
w, h = img.size
img = img.resize((paper_width, int(h * paper_width / w)))
arr = np.array(img, dtype=np.float64) / 255.0
arr = np.power(arr, GAMMA) * 255.0
img = Image.fromarray(arr.astype(np.uint8), mode="L").convert("1")

if paper_width < HEAD_WIDTH:
    padded = Image.new("1", (HEAD_WIDTH, img.height), 1)
    padded.paste(img, (0, 0))
    img = padded

p = Usb(VENDOR_ID, PRODUCT_ID)
p.image(img)
p.cut()
