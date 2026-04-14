from pathlib import Path
from typing import Protocol

from PIL import Image


class Driver(Protocol):
    def print_bitmap(self, job_id: int, img: Image.Image) -> None: ...


class MockDriver:
    def __init__(self, output_dir: Path):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def print_bitmap(self, job_id: int, img: Image.Image) -> None:
        out = self.output_dir / f"{job_id:06d}.png"
        img.save(out)


class FileDriver:
    """ESC/POS over a character device (e.g. /dev/usb/lp0 for usblp-bridged printers)."""

    def __init__(self, device_path: str):
        from escpos.printer import File

        self._device_path = device_path
        self._File = File

    def print_bitmap(self, job_id: int, img: Image.Image) -> None:
        p = self._File(self._device_path)
        try:
            p.image(img)
            p.cut()
        finally:
            p.close()


class UsbDriver:
    """ESC/POS over libusb (vendor/product id pair)."""

    def __init__(self, vendor_id: int, product_id: int):
        from escpos.printer import Usb

        self._printer = Usb(vendor_id, product_id)

    def print_bitmap(self, job_id: int, img: Image.Image) -> None:
        self._printer.image(img)
        self._printer.cut()


def make(kind: str, *, mock_dir: Path, device: str | None, usb_vid: int | None, usb_pid: int | None) -> Driver:
    if kind == "mock":
        return MockDriver(mock_dir)
    if kind == "file":
        if not device:
            raise ValueError("--device required for file driver")
        return FileDriver(device)
    if kind == "usb":
        if usb_vid is None or usb_pid is None:
            raise ValueError("--usb-vid and --usb-pid required for usb driver")
        return UsbDriver(usb_vid, usb_pid)
    raise ValueError(f"unknown driver: {kind}")
