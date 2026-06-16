#!/bin/bash
# LFI Fonts Pack Builder v3 — 全部开源字体批量打包
set -e
DIST="dist"
mkdir -p "$DIST"
TMP="/tmp/lfi-fonts-dl"
mkdir -p "$TMP"

log()  { echo -e "\033[0;32m[OK]\033[0m $1"; }
warn() { echo -e "\033[1;33m[!]\033[0m $1"; }
dl() {
  local n="$1" u="$2" o="$3"
  echo -n "  $n... "
  if curl -fSL --connect-timeout 15 --max-time 300 -L "$u" -o "$TMP/$o" 2>/dev/null && [ -s "$TMP/$o" ]; then
    local sz=$(du -h "$TMP/$o" | cut -f1)
    echo "OK ($sz)"
    return 0
  else
    echo "FAIL"
    return 1
  fi
}

# ============================
# 1. 中文场景 (zh-cn)
# ============================
log "1. 中文场景"
mkdir -p "$TMP/zh-cn"

# 霞鹜文楷（已有）+ 新增霞鹜文楷Mono
dl "霞鹜文楷 Mono" \
  "https://github.com/lxgw/LxgwWenKai/releases/download/v1.330/LXGWWenKaiMono-Regular.ttf" \
  "zh-cn/LXGWWenKaiMono-Regular.ttf"

# 得意黑（已有）

# 思源系列已有

# 文源圆体 - 跳过（链接不可用）
warn "  文源圆体: 暂无稳定下载链接"

# 打包中文场景（包含已有 + 新增）
# 注意：这里只打包新增字体，最终的tar.gz会合并已有和新字体
(cd "$TMP/zh-cn" && tar czf "$DIST/lfi-fonts-zh-cn-addon-v1.tar.gz" *.ttf 2>/dev/null) && \
  log "中文新增打包: $(du -h $DIST/lfi-fonts-zh-cn-addon-v1.tar.gz | cut -f1)"

# ============================
# 2. 办公场景 (office) — 新增办公字体
# ============================
log "2. 办公场景"
mkdir -p "$TMP/office"

# Liberation已有

# 阿里巴巴普惠体 - 从阿里云OSS（需要特定URL格式）
echo -n "  阿里巴巴普惠体 Regular... "
for url in \
  "https://puhuiti.oss-cn-hangzhou.aliyuncs.com/AlibabaPuHuiTi-3/AlibabaPuHuiTi-3-105-AlibabaPuHuiTi-3-105-Regular.otf" \
  "https://puhuiti.oss-cn-hangzhou.aliyuncs.com/AlibabaPuHuiTi-3.105/AlibabaPuHuiTi-3.105-Regular.otf"; do
  if curl -fSL --connect-timeout 15 --max-time 60 -L "$url" -o /tmp/lfi-alibaba.otf 2>/dev/null && [ -s /tmp/lfi-alibaba.otf ]; then
    mv /tmp/lfi-alibaba.otf "$TMP/office/AlibabaPuHuiTi-Regular.otf"
    sz=$(du -h "$TMP/office/AlibabaPuHuiTi-Regular.otf" | cut -f1)
    echo "OK ($sz)"
    break
  fi
done || echo "FAIL"

# ============================
# 3. 编程场景 (coding) — 新增编程字体
# ============================
log "3. 编程场景"
mkdir -p "$TMP/coding"

# 已有: JetBrains Mono, Cascadia Code, Fira Code, Nerd Fonts
# 新增:
dl "Hack" \
  "https://github.com/source-foundry/Hack/releases/download/v3.003/Hack-v3.003-ttf.zip" \
  "coding/Hack.zip"

dl "Source Code Pro" \
  "https://github.com/adobe-fonts/source-code-pro/releases/download/2.042R-u/1.062R-i/1.026R-vf/TTF-source-code-pro-2.042R-u_1.062R-i.zip" \
  "coding/SourceCodePro.zip"

dl "Iosevka" \
  "https://github.com/be5invis/Iosevka/releases/download/v34.6.3/PkgTTC-Iosevka-34.6.3.zip" \
  "coding/Iosevka.zip"

dl "Maple Mono NF" \
  "https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-NF-unhinted.zip" \
  "coding/MapleMonoNF.zip"

dl "Monaspace" \
  "https://github.com/githubnext/monaspace/releases/download/v1.101/monaspace-v1.101.zip" \
  "coding/Monaspace.zip"

(cd "$TMP/coding" && tar czf "$DIST/lfi-fonts-coding-addon-v1.tar.gz" *.zip 2>/dev/null) && \
  log "编程新增打包: $(du -h $DIST/lfi-fonts-coding-addon-v1.tar.gz | cut -f1)"

# ============================
# 4. 设计场景 (design) — 新增设计字体
# ============================
log "4. 设计场景"
mkdir -p "$TMP/design"

# 已有: 站酷快乐体, 站酷文艺体, 阿里妈妈数黑体, Noto Sans SC
# 以下字体无稳定GitHub直链，从第三方站下载(免费商用授权确认):
# 优设标题黑, 庞门正道标题体, 江西拙楷体, 杨任东竹石体, 仓耳渔阳体
# 这些需要手动下载后补充，见说明

log "设计场景已有字体保持，新增字体暂无稳定直链"
echo "  以下字体需手动下载后补充到 build-fonts-pack.sh:"
echo "  - 优设标题黑 (youzicon/fonts 仓库已404)"
echo "  - 庞门正道标题体 (maoken/fonts 仓库已404)"
echo "  - 江西拙楷体 (只有百度网盘)"
echo "  - 杨任东竹石体 (只有百度网盘)"
echo "  - 仓耳渔阳体 (maoken/fonts 仓库已404)"
echo "  - HarmonyOS Sans (华为官方下载页面)"
echo "  - OPPO Sans (OPPO开放平台下载)"
echo "  - MiSans (小米官网下载)"

echo ""
log "全部完成！"
echo ""
ls -lh "$DIST/"*.tar.gz 2>/dev/null
echo ""
echo "下一步:"
echo "  1. gh release upload 新包到 v1.0.0"
echo "  2. 手动补充字体后重新打包"
