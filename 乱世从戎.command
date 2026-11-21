#!/bin/zsh
# 双击启动（macOS）。需要已安装 Godot 4.7+。
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
exec godot --path .
