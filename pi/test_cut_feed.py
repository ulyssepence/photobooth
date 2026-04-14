#!/usr/bin/env python3
"""Print test strips with varying feed values to find the right cut margin.

Each strip: a black bar, numbered lines 1-20, then cut with a specific feed value.
The last visible numbered line tells you where the cutter sits.

Usage:  python3 test_cut_feed.py          # uses /dev/usb/lp0
        python3 test_cut_feed.py /dev/foo  # custom device
"""
import sys
from escpos.printer import File
from PIL import Image, ImageDraw, ImageFont

DEVICE = sys.argv[1] if len(sys.argv) > 1 else "/dev/usb/lp0"
WIDTH = 576
FEEDS = [0, 4, 6, 8, 10, 12]


def make_strip(feed_n: int) -> Image.Image:
    line_h = 32
    lines = 20
    header_h = 60
    img_h = header_h + lines * line_h
    img = Image.new("1", (WIDTH, img_h), 1)
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, WIDTH, header_h - 1], fill=0)
    draw.text((10, 10), f"FEED = {feed_n}", fill=1)
    for i in range(lines):
        y = header_h + i * line_h
        draw.line([(0, y), (WIDTH, y)], fill=0)
        draw.text((10, y + 4), f"line {i + 1}", fill=0)
    draw.line([(0, img_h - 1), (WIDTH, img_h - 1)], fill=0)
    return img


for feed_n in FEEDS:
    p = File(DEVICE)
    try:
        p.image(make_strip(feed_n))
        if feed_n == 0:
            p.cut(feed=False)
        else:
            p.print_and_feed(feed_n)
            p.cut(feed=False)
    finally:
        p.close()
