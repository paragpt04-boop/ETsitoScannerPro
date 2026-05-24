from PIL import Image
import os

img = Image.open("android-icon/icon.png").convert("RGBA")
sizes = {"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}
for folder,size in sizes.items():
    path = f"android/app/src/main/res/mipmap-{folder}"
    os.makedirs(path, exist_ok=True)
    r = img.resize((size,size), Image.LANCZOS)
    r.save(f"{path}/ic_launcher.png")
    r.save(f"{path}/ic_launcher_round.png")
    print(f"OK {folder} {size}x{size}")
