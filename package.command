#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'PY'
from pathlib import Path
import plistlib, shutil, subprocess, zipfile
source = Path.cwd()
app = source / 'Build/AustinHelpU.app'
with (app / 'Contents/Info.plist').open('rb') as f:
    version = plistlib.load(f)['CFBundleShortVersionString']
output = source.parent / 'deliverables' / ('AustinHelpU-Mac-' + version)
if output.exists():
    raise SystemExit('输出目录已存在，请先检查，不覆盖已有交付')
output.mkdir(parents=True)
shutil.copytree(app, output / 'AustinHelpU.app')
files = ['Main.swift', 'Models.swift', 'Browser.swift', 'Proxy.swift', 'AppModel.swift', 'Views.swift', 'Tests.swift', 'BrowserTests.swift', 'build.command', 'test.command', 'package.command', 'README.md', 'LICENSE', 'NOTICE', 'THIRD_PARTY.md']
resources = ['AppIcon.icns', 'brand.png', 'products.json', 'stores.json']
for name in files + ['Resources/' + name for name in resources]:
    target = output / 'Source' / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / name, target)
for name in ['LICENSE', 'NOTICE', 'THIRD_PARTY.md']:
    shutil.copy2(source / name, output / name)
shutil.copy2(source / 'README.md', output / '使用说明.md')
# Reject all unexpected payloads, including local configuration and browser data.
allowed = {'Source/' + name for name in files + ['Resources/' + n for n in resources]}
allowed |= {'LICENSE', 'NOTICE', 'THIRD_PARTY.md', '使用说明.md', 'AustinHelpU.app/Contents/Info.plist', 'AustinHelpU.app/Contents/MacOS/AustinHelpU', 'AustinHelpU.app/Contents/_CodeSignature/CodeResources'}
allowed |= {'AustinHelpU.app/Contents/Resources/' + name for name in resources + ['LICENSE', 'NOTICE', 'THIRD_PARTY.md']}
actual = {p.relative_to(output).as_posix() for p in output.rglob('*') if p.is_file()}
if actual != allowed:
    raise SystemExit('打包内容与白名单不符: ' + str(actual ^ allowed))
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(output / 'AustinHelpU.app')], check=True)
archive = output.parent / (output.name + '.zip')
# Build from the verified allowlist, without extended attributes or hidden local files.
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for name in sorted(actual):
        z.write(output / name, output.name + '/' + name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist()) == len(allowed)
print('PASS: 签名、压缩包完整性、全部 %d 个文件白名单检查；未打包用户配置' % len(allowed))
print(archive)
PY
