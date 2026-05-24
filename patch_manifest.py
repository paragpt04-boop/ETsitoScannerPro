import re

with open('android/app/src/main/AndroidManifest.xml', 'r') as f:
    content = f.read()

# Permitir trafico HTTP sin restricciones
content = content.replace(
    '<application',
    '<application android:usesCleartextTraffic="true" android:networkSecurityConfig="@xml/network_security_config"',
    1
)

with open('android/app/src/main/AndroidManifest.xml', 'w') as f:
    f.write(content)

# Crear network security config
import os
os.makedirs('android/app/src/main/res/xml', exist_ok=True)
with open('android/app/src/main/res/xml/network_security_config.xml', 'w') as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system"/>
            <certificates src="user"/>
        </trust-anchors>
    </base-config>
</network-security-config>''')

print("OK - Manifest parcheado")
