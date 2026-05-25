from PIL import Image
import shutil, os

img = Image.open('android-icon/icon.png').convert('RGBA')
sizes = [16, 32, 48, 64, 128, 256]
img.save('windows/runner/resources/app_icon.ico', format='ICO', sizes=[(s,s) for s in sizes])
shutil.copy('android-icon/icon.png', 'assets/icon.png')
print("Icons OK")
