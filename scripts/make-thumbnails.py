#!/usr/bin/env python3
"""Frame native --thumbnail-test renders for the chooser (development only)."""
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent
for character in ['arcanine', 'mewtwo', 'pikachu', 'charizard']:
    image = Image.open(ROOT/f'dist/thumbnail-source-{character}.png').convert('RGBA')
    bounds = image.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    assert bounds and bounds[3]-bounds[1] > 100, 'Native model must be visible'
    image = image.crop(bounds)
    image.thumbnail((288, 288), Image.Resampling.LANCZOS)
    framed = Image.new('RGBA', (320, 320))
    framed.alpha_composite(image, ((320-image.width)//2, (320-image.height)//2))
    framed.save(ROOT/f'Assets/preview-{character}.png')
    print(character, bounds, image.size)
