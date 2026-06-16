#!/bin/sh
# ==============================================================
# LFI 一键安装器 — 最短的一行命令
# ==============================================================
# 用法:
#   curl -sL https://lfi.run | bash
#   bash <(curl -sL https://lfi.run)
#
# 这个文件专为短域名设计，内容与 lfi.sh 完全相同
# 可以通过任何短URL服务指向此文件
# ==============================================================

exec bash <(curl -fsSL https://raw.githubusercontent.com/sinyche/linux-font-installer/main/lfi.sh) "$@"
