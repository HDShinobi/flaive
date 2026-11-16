"""Render Flaive launcher assets from the plan's 100-unit logo geometry."""

from pathlib import Path

from PIL import Image, ImageDraw


SIZE = 1024
SUPERSAMPLE = 4
ACCENT = "#1DB954"
BACKGROUND = "#0E0F11"
BARS = (
    (24.9, 32.9, 7.4, 30.1),
    (35.6, 23.6, 7.4, 39.4),
    (46.2, 14.2, 7.5, 52.0),
    (56.9, 23.6, 7.4, 39.4),
    (67.6, 32.9, 7.4, 30.1),
)
ARROWHEAD = ((28.5, 66.2), (71.5, 66.2), (50.0, 85.7))
BOUNDS = (24.9, 14.2, 75.0, 85.7)
OUTPUT_DIR = Path(__file__).resolve().parent.parent


def render(filename, color, height_fraction, background=False):
    side = SIZE * SUPERSAMPLE
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    if background:
        draw.rounded_rectangle(
            (0, 0, side - 1, side - 1), radius=side * 0.22, fill=BACKGROUND
        )

    left, top, right, bottom = BOUNDS
    scale = side * height_fraction / (bottom - top)
    center_x, center_y = (left + right) / 2, (top + bottom) / 2

    def point(x, y):
        return (side / 2 + (x - center_x) * scale,
                side / 2 + (y - center_y) * scale)

    for x, y, width, height in BARS:
        draw.rectangle((*point(x, y), *point(x + width, y + height)), fill=color)
    draw.polygon([point(x, y) for x, y in ARROWHEAD], fill=color)
    image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    path = OUTPUT_DIR / filename
    image.save(path)
    print(f"{path.name}: {image.size}, {image.mode}")


if __name__ == "__main__":
    render("flaive-icon-foreground.png", ACCENT, 0.46)
    render("flaive-icon-monochrome.png", "#FFFFFF", 0.46)
    render("flaive-icon-full.png", ACCENT, 0.58, background=True)
