#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo '请在 Apple 芯片 Mac 上运行此脚本。'
    exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo '请先安装 Apple Command Line Tools，再运行此脚本。'
    exit 1
fi
bash test.command
bash build.command
bash package.command
echo '构建完成：应用在 Build 目录，安装压缩包在上一级 deliverables 目录。'
read -r -p '按回车退出…'
