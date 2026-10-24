#!/usr/bin/env python3
"""Record the exact Actions commit and unsigned IPA checksum; never sign an app."""
from pathlib import Path
import hashlib
import json
import os
import plistlib

root = Path(__file__).resolve().parents[1]
ipa = root / 'build/3EQTO-unsigned.ipa'
info_path = root / 'build/DerivedData/Build/Products/Release-iphoneos/3ERoomElectrical.app/Info.plist'
info = plistlib.loads(info_path.read_bytes())
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
metadata = {
    'displayName': info['CFBundleDisplayName'], 'bundleIdentifier': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'commit': os.environ.get('GITHUB_SHA'), 'repository': os.environ.get('GITHUB_REPOSITORY'),
    'runId': os.environ.get('GITHUB_RUN_ID'), 'runAttempt': os.environ.get('GITHUB_RUN_ATTEMPT'),
    'ipa': ipa.name, 'sha256': digest, 'signed': False,
    'installationNote': 'Requires valid re-signing/provisioning before installation on iPhone.'
}
(root / 'build/build-info.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
(root / 'build/3EQTO-unsigned.ipa.sha256').write_text(f'{digest}  {ipa.name}\n', encoding='ascii')
print(json.dumps(metadata, indent=2))
