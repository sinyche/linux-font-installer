#!/bin/bash
# ==============================================================
# Linux Font Installer (LFI) — 一行命令搞定Linux字体问题
# ==============================================================
# 用法:
#   一行命令:
#     bash <(curl -sL https://raw.githubusercontent.com/sinyche/linux-font-installer/main/lfi.sh)
# ==============================================================

# -------- 配置 --------
REPO="sinyche/linux-font-installer"
BRANCH="main"
LFI_VERSION="1.0.0"
LFI_RELEASE="v1.0.0"

# -------- 自举：如果是管道运行，先下载完整版再执行 --------
if [ ! -f "$0" ] || [[ "$0" == /dev/fd/* ]] || [[ "$0" == /proc/self/fd/* ]]; then
    SELF="/tmp/lfi-self-$$.sh"
    echo "  ⟳ 正在下载 LFI 完整版..."
    # 从Release下载完整版（不受CDN缓存影响）
    if curl -fsSL --connect-timeout 10 --max-time 60 "https://github.com/${REPO}/releases/download/${LFI_RELEASE}/lfi-complete.sh" -o "$SELF" 2>/dev/null; then
        chmod +x "$SELF"
        exec bash "$SELF" "$@"
        exit
    fi
    echo "  ⚠ Release 下载失败，尝试 raw.githubusercontent.com ..."
    # 回退：从raw下载
    curl -fsSL --connect-timeout 10 --max-time 60 "https://raw.githubusercontent.com/${REPO}/${BRANCH}/lfi.sh" -o "$SELF" 2>/dev/null && {
        chmod +x "$SELF"
        exec bash "$SELF" "$@"
        exit
    }
    echo "  [✗] 下载失败，请检查网络连接"
    echo "  直接运行: bash lfi.sh"
    exit 1
fi

# NOT using set -e: causes silent exit on glob mismatch, grep -q with no match,
# and other bash 5.3 edge cases. We use explicit error handling throughout.

# -------- 颜色 --------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# -------- 路径 --------
LFI_ROOT="${LFI_ROOT:-/tmp/lfi-$$}"
FONT_DIR_SYSTEM="/usr/local/share/fonts/custom"
FONT_DIR_USER="${HOME}/.local/share/fonts"
FONT_CACHE_DIR="${HOME}/.cache/fontconfig"
MODULE_DIR="${LFI_ROOT}/modules"
FONTLIST_DIR="${LFI_ROOT}/fonts"
DOWNLOAD_DIR="${LFI_ROOT}/downloads"

# -------- 工具函数 --------
log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
log_title() { echo -e "\n${BOLD}${WHITE}$1${NC}\n"; }

# -------- URL读取 + 模块加载 --------
github_raw() {
    echo "https://raw.githubusercontent.com/${REPO}/${BRANCH}/$1"
}

dl_module() {
    local name="$1"
    local target="$MODULE_DIR/$name"
    
    mkdir -p "$MODULE_DIR"
    # 如果目录中没有，从完整版中提取
    # 优先从本地临时文件加载
    # 下载完整版
    local complete_url="https://github.com/${REPO}/releases/download/${LFI_RELEASE}/lfi-complete.sh"
    curl -fsSL "$complete_url" -o "$MODULE_DIR/lfi-complete.sh" 2>/dev/null || {
        # 回退：单独下载模块
        local url=$(github_raw "modules/$name")
        curl -fsSL "$url" -o "$target" 2>/dev/null || {
            log_error "下载模块失败: $name"
            exit 1
        }
        source "$target" 2>/dev/null || {
            log_error "加载模块失败: $name"
            exit 1
        }
        return
    }
}

# -------- 系统检测 --------
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="${ID}"
        OS_LIKE="${ID_LIKE:-}"
        OS_VERSION="${VERSION_ID:-}"
    else
        OS="unknown"
    fi
    
    ARCH=$(uname -m)
    
    # 检测是否有root权限
    if [ "$(id -u)" -eq 0 ]; then
        HAS_ROOT=true
    else
        HAS_ROOT=false
    fi
    
    # 检测包管理器
    if command -v apt &>/dev/null; then
        PKG_MGR="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MGR="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MGR="yum"
    elif command -v pacman &>/dev/null; then
        PKG_MGR="pacman"
    elif command -v zypper &>/dev/null; then
        PKG_MGR="zypper"
    else
        PKG_MGR="unknown"
    fi
    
    # 检测Windows挂载
    detect_windows
}

# -------- Windows检测 --------
detect_windows() {
    WIN_FONT_DIRS=()
    
    # 常见挂载点
    for d in /mnt/Windows /mnt/windows /media/*/Windows /media/*/windows /run/media/*/Windows /run/media/*/windows /mnt/*/Windows /mnt/*/windows; do
        [ -d "$d/Fonts" ] && WIN_FONT_DIRS+=("$d/Fonts")
        [ -d "$d/Fonts" ] && [ -d "$d/System32" ] && WIN_FOUND=true || true
    done
    
    # Wine
    for w in "$HOME/.wine/drive_c/windows/Fonts" "$HOME/.local/share/wineprefixes/default/drive_c/windows/Fonts" /opt/wine-*/drive_c/windows/Fonts; do
        [ -d "$w" ] && WIN_FONT_DIRS+=("$w")
    done
    
    # 检测Windows版本（从注册表或文件）
    WIN_VERSION=""
    for d in /mnt/Windows /mnt/windows; do
        if [ -f "$d/System32/config/SOFTWARE" ]; then
            WIN_VERSION="windows-unknown"
        fi
    done
    
    if [ ${#WIN_FONT_DIRS[@]} -gt 0 ]; then
        WIN_AVAILABLE=true
    else
        WIN_AVAILABLE=false
    fi
}

# -------- 预备环境 --------
prepare_env() {
    mkdir -p "$MODULE_DIR" "$FONTLIST_DIR" "$DOWNLOAD_DIR"
    
    # 检查依赖
    local missing=()
    for cmd in curl fc-list fc-cache; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "缺少依赖: ${missing[*]}"
        echo -e "  ${YELLOW}建议:${NC} sudo apt install curl fontconfig (Debian/Ubuntu)"
        echo -e "  ${YELLOW}建议:${NC} sudo dnf install curl fontconfig (Fedora)"
        read -p "按回车继续，或 Ctrl+C 退出..."
    fi
    
    # 提示root
    if [ "$HAS_ROOT" = false ]; then
        log_warn "非root运行，字体将安装到用户目录: ${FONT_DIR_USER}"
        log_warn "部分系统级配置需要 sudo lfi.sh"
        echo ""
    fi
}

# -------- 主菜单（加载模块） --------
main() {
    echo -e "\033[2J\033[H"  # 清屏
    echo ""
    echo -e "${BOLD}${BLUE}   ╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}   ║     Linux Font Installer ${LFI_VERSION}           ║${NC}"
    echo -e "${BOLD}${BLUE}   ║     一行命令，搞定 Linux 字体问题        ║${NC}"
    echo -e "${BOLD}${BLUE}   ╚═══════════════════════════════════════════╝${NC}"
    echo ""
    
    detect_system
    prepare_env
    
    # 加载所有核心模块
    for mod in menu.sh installer.sh extract-win.sh config.sh compat.sh; do
        dl_module "$mod"
    done

    # 检测发行版
    detect_distro
    
    # 进入菜单循环
    menu_loop
}

main "$@"
