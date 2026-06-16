#!/bin/bash
# LFI Fonts Pack Builder v3
# 策略变更：用apt下载，再从系统提取打包

set -e
DIST="dist"
mkdir -p "$DIST"
TMP="/tmp/lfi-fonts-dl"
mkdir -p "$TMP"

log()  { echo -e "\033[0;32m[OK]\033[0m $1"; }
warn() { echo -e "\033[1;33m[!]\033[0m $1"; }

# ===== 1. 中文场景 =====
log "1. 中文场景 - 从GitHub下载"
mkdir -p "$TMP/zh-cn"

# 霞鹜文楷 (直接下载ttf)
curl -fSL --connect-timeout 15 --max-time 180 -L \
  "https://github.com/lxgw/LxgwWenKai/releases/download/v1.330/LXGWWenKai-Regular.ttf" \
  -o "$TMP/zh-cn/LXGWWenKai-Regular.ttf" 2>/dev/null && log "  霞鹜文楷 R (19M)" || warn "  霞鹜文楷 R 失败"

curl -fSL --connect-timeout 15 --max-time 180 -L \
  "https://github.com/lxgw/LxgwWenKai/releases/download/v1.330/LXGWWenKai-Bold.ttf" \
  -o "$TMP/zh-cn/LXGWWenKai-Bold.ttf" 2>/dev/null && log "  霞鹜文楷 B (18M)" || warn "  霞鹜文楷 B 失败"

curl -fSL --connect-timeout 15 --max-time 180 -L \
  "https://github.com/lxgw/LxgwWenKai/releases/download/v1.330/LXGWWenKai-Light.ttf" \
  -o "$TMP/zh-cn/LXGWWenKai-Light.ttf" 2>/dev/null && log "  霞鹜文楷 L (21M)" || warn "  霞鹜文楷 L 失败"

# Noto Sans CJK SC - 从系统包中提取（已安装）
log "  从本地提取 Noto Sans CJK SC..."
cp /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc "$TMP/zh-cn/" 2>/dev/null && log "  NotoSansCJK-Regular.ttc" || warn "  NotoSansCJK 不可用"
cp /usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc "$TMP/zh-cn/" 2>/dev/null && log "  NotoSerifCJK-Regular.ttc" || warn "  NotoSerifCJK 不可用"

# 得意黑 - 尝试下载release assets
REF=$(curl -s "https://api.github.com/repos/atelier-anchor/smiley-sans/releases/latest" 2>/dev/null | grep -o '"browser_download_url": "[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$REF" ]; then
  echo -n "  得意黑 (latest release)... "
  curl -fSL --connect-timeout 15 --max-time 180 -L "$REF" -o "$TMP/zh-cn/SmileySans.zip" 2>/dev/null && {
    sz=$(du -h "$TMP/zh-cn/SmileySans.zip" | cut -f1)
    echo "OK ($sz)"
  } || echo "FAIL"
else
  warn "  得意黑: 无法获取Release信息"
fi

(cd "$TMP/zh-cn" && tar czf "$DIST/lfi-fonts-zh-cn-v1.tar.gz" *.ttf *.ttc *.zip *.otf 2>/dev/null) && \
  log "中文打包完成: $(du -h $DIST/lfi-fonts-zh-cn-v1.tar.gz | cut -f1)"

# ===== 2. 编程场景 =====
log "2. 编程场景 - 从GitHub下载"
mkdir -p "$TMP/coding"

curl -fSL --connect-timeout 15 --max-time 180 -L \
  "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip" \
  -o "$TMP/coding/JetBrainsMono.zip" 2>/dev/null && log "  JetBrains Mono (5.4M)" || warn "  JetBrains Mono 失败"

curl -fSL --connect-timeout 15 --max-time 180 -L \
  "https://github.com/microsoft/cascadia-code/releases/download/v2404.23/CascadiaCode-2404.23.zip" \
  -o "$TMP/coding/CascadiaCode.zip" 2>/dev/null && log "  Cascadia Code (144M)" || warn "  Cascadia Code 失败"

curl -fSL --connect-timeout 15 --max-time 180 -L \
  "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip" \
  -o "$TMP/coding/FiraCode.zip" 2>/dev/null && log "  Fira Code (2.4M)" || warn "  Fira Code 失败"

curl -fSL --connect-timeout 15 --max-time 180 -L \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip" \
  -o "$TMP/coding/JetBrainsMonoNF.zip" 2>/dev/null && log "  JetBrains Mono NF (113M)" || warn "  JetBrains Mono NF 失败"

(cd "$TMP/coding" && tar czf "$DIST/lfi-fonts-coding-v1.tar.gz" *.zip 2>/dev/null) && \
  log "编程打包完成: $(du -h $DIST/lfi-fonts-coding-v1.tar.gz | cut -f1)"

# ===== 3. 办公场景 =====
log "3. 办公场景 - 从本地包管理器安装并提取"

# 安装 liberation 字体
if command -v apt &>/dev/null; then
  sudo apt install -y fonts-liberation fonts-liberation2 2>/dev/null && log "  fonts-liberation 已安装"
fi

# 从系统复制出来
LIB_DIR=$(dpkg -L fonts-liberation 2>/dev/null | grep 'fonts/' | head -1 | xargs dirname 2>/dev/null || echo "/usr/share/fonts/truetype/liberation")
mkdir -p "$TMP/office"
if [ -d "$LIB_DIR" ]; then
  cp "$LIB_DIR"/*.ttf "$TMP/office/" 2>/dev/null && log "  Liberation 系列 ($(ls $TMP/office/*.ttf 2>/dev/null | wc -l)个文件)"
fi

(cd "$TMP/office" && tar czf "$DIST/lfi-fonts-office-v1.tar.gz" *.ttf 2>/dev/null) && \
  log "办公打包完成: $(du -h $DIST/lfi-fonts-office-v1.tar.gz | cut -f1)"

# ===== 4. 设计场景 =====
log "4. 设计场景"
mkdir -p "$TMP/design"

# Noto Sans SC
curl -fSL --connect-timeout 15 --max-time 180 -L \
  "https://github.com/google/fonts/raw/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf" \
  -o "$TMP/design/NotoSansSC.ttf" 2>/dev/null && log "  Noto Sans SC (可变字体)" || warn "  Noto Sans SC 失败"

(cd "$TMP/design" && tar czf "$DIST/lfi-fonts-design-v1.tar.gz" *.ttf 2>/dev/null) && \
  log "设计打包完成: $(du -h $DIST/lfi-fonts-design-v1.tar.gz | cut -f1)"

echo ""
log "全部完成！"
echo ""
ls -lh "$DIST/"*.tar.gz 2>/dev/null
echo ""
echo "未打包的字体（需后续手动添加）："
warn "  得意黑 - 需手动去GitHub Release下载:"
warn "    https://github.com/atelier-anchor/smiley-sans/releases"
warn "  站酷系列 - 需去 zcool.com.cn 下载"
warn "  阿里妈妈数黑体 - 需去官方渠道"
