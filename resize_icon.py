from PIL import Image, ImageDraw, ImageFont
import os

sizes = {"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}

for folder, size in sizes.items():
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    
    # Fondo degradado oscuro con borde verde
    draw.rectangle([0, 0, size-1, size-1], fill=(5, 15, 5))
    draw.rectangle([0, 0, size-1, size-1], outline=(0, 255, 65), width=max(1, size//24))
    
    # Texto JsIp
    text = "JsIp"
    font_size = size // 4
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
    except:
        font = ImageFont.load_default()
    
    bbox = draw.textbbox((0,0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (size - tw) // 2
    y = (size - th) // 2
    draw.text((x, y), text, fill=(0, 255, 65), font=font)
    
    path = f"android/app/src/main/res/mipmap-{folder}"
    os.makedirs(path, exist_ok=True)
    img.save(f"{path}/ic_launcher.png")
    img.save(f"{path}/ic_launcher_round.png")
    print(f"OK {folder} {size}x{size}")
