import re

with open('android/app/src/main/AndroidManifest.xml', 'r') as f:
    content = f.read()

# Agregar permisos de background
perms = '''    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
'''

content = content.replace(
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.INTERNET"/>\n' + perms
)

# Agregar servicio
service = '''        <service
            android:name=".ScanService"
            android:foregroundServiceType="dataSync"
            android:exported="false"/>
'''

content = content.replace('</application>', service + '</application>')

with open('android/app/src/main/AndroidManifest.xml', 'w') as f:
    f.write(content)

print("Manifest OK")
