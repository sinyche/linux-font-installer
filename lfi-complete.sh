#!/bin/bash
# LFI Complete v1.0.0

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
    echo -e "  ${BLUE}⟳${NC} 正在下载 LFI 完整版..."
    # 从Release下载完整版（不受CDN缓存影响）
    if curl -fsSL --connect-timeout 10 --max-time 60 "https://github.com/${REPO}/releases/download/${LFI_RELEASE}/lfi-complete.sh" -o "$SELF" 2>/dev/null; then
        chmod +x "$SELF"
        exec bash "$SELF" "$@"
        exit
    fi
    echo -e "  ${YELLOW}⚠ Release 下载失败，尝试 raw.githubusercontent.com ...${NC}"
    # 回退：从raw下载
    curl -fsSL --connect-timeout 10 --max-time 60 "https://raw.githubusercontent.com/${REPO}/${BRANCH}/lfi.sh" -o "$SELF" 2>/dev/null && {
        chmod +x "$SELF"
        exec bash "$SELF" "$@"
        exit
    }
    echo -e "  ${RED}[✗] 下载失败，请检查网络连接${NC}"
    echo -e "  ${YELLOW}直接运行: bash lfi.sh${NC}"
    exit 1
fi

# NOT using set -e: we do explicit error handling throughout.
# set -e causes silent exits on glob mismatches, grep -q failing to find
# a match, ((count++)) returning 0, and other bash 5.3 edge cases that
# make "正在安装字体文件..." appear to hang.

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
github_raw() { echo "https://raw.githubusercontent.com/${REPO}/${BRANCH}/$1"; }

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

# -------- 内联模块 --------

# >>> compat.sh
# ==============================================================
# LFI 多发行版兼容模块 — 自动适配各Linux发行版
# ==============================================================

# -------- 发行版检测与兼容层 --------
detect_distro() {
    # 已由 lfi.sh 的 detect_system() 设置:
    # $OS, $OS_LIKE, $OS_VERSION, $ARCH, $PKG_MGR
    
    DISTRO_FAMILY=""
    DISTRO_VER_MAJOR=""
    
    # 发行版家族归类
    case "${OS,,}" in
        ubuntu|debian|deepin|uos|kali|linuxmint|elementary|pop|zorin|neon)
            DISTRO_FAMILY="debian"
            ;;
        fedora|rhel|centos|rocky|almalinux|oraclelinux)
            DISTRO_FAMILY="redhat"
            ;;
        opensuse*|suse)
            DISTRO_FAMILY="suse"
            ;;
        arch|manjaro|endeavouros|garuda|artix)
            DISTRO_FAMILY="arch"
            ;;
        alpine)
            DISTRO_FAMILY="alpine"
            ;;
        slackware)
            DISTRO_FAMILY="slackware"
            ;;
        void)
            DISTRO_FAMILY="void"
            ;;
        gentoo|funtoo)
            DISTRO_FAMILY="gentoo"
            ;;
        solus)
            DISTRO_FAMILY="solus"
            ;;
        *)
            # 通过 ID_LIKE 推断
            case "${OS_LIKE,,}" in
                *debian*) DISTRO_FAMILY="debian" ;;
                *fedora*|*rhel*|*centos*) DISTRO_FAMILY="redhat" ;;
                *suse*) DISTRO_FAMILY="suse" ;;
                *arch*) DISTRO_FAMILY="arch" ;;
                *) DISTRO_FAMILY="unknown" ;;
            esac
            ;;
    esac
    
    # 主版本号
    DISTRO_VER_MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)
    
    export DISTRO_FAMILY DISTRO_VER_MAJOR
}

# -------- 包管理器统一的安装命令 --------
pkg_install() {
    local pkg_name="$1"
    local pkg_name_alt="${2:-}"
    
    case "$PKG_MGR" in
        apt)
            sudo apt install -y "$pkg_name" 2>/dev/null && return 0
            [ -n "$pkg_name_alt" ] && sudo apt install -y "$pkg_name_alt" 2>/dev/null && return 0
            return 1
            ;;
        dnf)
            sudo dnf install -y "$pkg_name" 2>/dev/null && return 0
            [ -n "$pkg_name_alt" ] && sudo dnf install -y "$pkg_name_alt" 2>/dev/null && return 0
            return 1
            ;;
        yum)
            sudo yum install -y "$pkg_name" 2>/dev/null && return 0
            [ -n "$pkg_name_alt" ] && sudo yum install -y "$pkg_name_alt" 2>/dev/null && return 0
            return 1
            ;;
        pacman)
            sudo pacman -S --noconfirm "$pkg_name" 2>/dev/null && return 0
            [ -n "$pkg_name_alt" ] && sudo pacman -S --noconfirm "$pkg_name_alt" 2>/dev/null && return 0
            return 1
            ;;
        zypper)
            sudo zypper install -y "$pkg_name" 2>/dev/null && return 0
            [ -n "$pkg_name_alt" ] && sudo zypper install -y "$pkg_name_alt" 2>/dev/null && return 0
            return 1
            ;;
        *)
            log_warn "不支持的包管理器: $PKG_MGR，请手动安装 $pkg_name"
            return 1
            ;;
    esac
}

# -------- 跨发行版字体依赖安装 --------
install_font_deps() {
    log_step "安装系统字体依赖"
    
    local deps=""
    local deps_alt=""
    
    case "$DISTRO_FAMILY" in
        debian)
            deps="fontconfig curl unzip"
            deps_alt=""
            # 可选字体包
            local font_pkgs=(
                "fonts-noto-cjk:fonts-noto-cjk:fonts-noto-cjk-extra"
                "fonts-liberation:fonts-liberation:fonts-liberation"
                "fonts-freefont-ttf:fonts-freefont-ttf:fonts-freefont-ttf"
                "fonts-noto-color-emoji:fonts-noto-color-emoji:fonts-noto-color-emoji"
            )
            ;;
        redhat)
            deps="fontconfig curl unzip"
            deps_alt=""
            local font_pkgs=(
                "google-noto-cjk-fonts:google-noto-cjk-fonts:google-noto-sans-cjk-fonts"
                "liberation-fonts:liberation-fonts:liberation-fonts"
                "gdouros-symbola-fonts:gdouros-symbola-fonts:gdouros-symbola-fonts"
            )
            # CentOS 7 需要启用 EPEL
            if [ "$DISTRO_FAMILY" = "redhat" ] && [ "$DISTRO_VER_MAJOR" -le 7 ] 2>/dev/null; then
                log_warn "CentOS 7 可能需要先启用 EPEL: sudo yum install epel-release"
            fi
            ;;
        arch)
            deps="fontconfig curl unzip"
            deps_alt=""
            local font_pkgs=(
                "noto-fonts-cjk:noto-fonts-cjk:noto-fonts-cjk"
                "ttf-liberation:ttf-liberation:ttf-liberation"
                "noto-fonts-emoji:noto-fonts-emoji:noto-fonts-emoji"
            )
            # AUR 包（不能自动安装，只提示）
            local aur_packages=(
                "ttf-ms-win11-auto:微软雅黑、宋体等"
                "ttf-smiley-sans-bin:得意黑"
                "ttf-lxgw-wenkai:霞鹜文楷"
            )
            ;;
        suse)
            deps="fontconfig curl unzip"
            deps_alt=""
            local font_pkgs=(
                "google-noto-cjk-fonts:google-noto-cjk-fonts:google-noto-sans-cjk-fonts"
                "liberation-fonts:liberation-fonts:liberation-fonts"
            )
            ;;
        alpine)
            deps="fontconfig curl unzip"
            deps_alt=""
            local font_pkgs=(
                "font-noto-cjk:font-noto-cjk:font-noto-cjk"
            )
            ;;
        *)
            deps="fontconfig curl unzip"
            deps_alt=""
            local font_pkgs=()
            ;;
    esac
    
    # 安装基础依赖
    for cmd in "$deps"; do
        local pkg
        pkg=$(echo "$cmd" | cut -d: -f1)
        echo -ne "  ${BLUE}⟳${NC} 安装 $pkg... "
        if pkg_install "$pkg"; then
            echo -e "${GREEN}完成${NC}"
        else
            echo -e "${YELLOW}跳过（手动安装: sudo $PKG_MGR install $pkg）${NC}"
        fi
    done
    
    # 安装可选字体包（失败不中断）
    for entry in "${font_pkgs[@]}"; do
        local pkg
        pkg=$(echo "$entry" | cut -d: -f1)
        local alt
        alt=$(echo "$entry" | cut -d: -f2)
        echo -ne "  ${BLUE}⟳${NC} 安装 $pkg... "
        if pkg_install "$pkg" "$alt"; then
            echo -e "${GREEN}完成${NC}"
        else
            echo -e "${YELLOW}跳过（不影响主功能）${NC}"
        fi
    done
    
    # Arch AUR 提示
    if [ "$DISTRO_FAMILY" = "arch" ]; then
        echo ""
        echo -e "  ${YELLOW}Arch 用户可通过 AUR 安装更多字体:${NC}"
        for entry in "${aur_packages[@]}"; do
        local pkg
        pkg=$(echo "$entry" | cut -d: -f1)
        local desc
        desc=$(echo "$entry" | cut -d: -f2)
            echo -e "    ${WHITE}yay -S $pkg${NC} — $desc"
        done
    fi
    
    log_info "系统字体依赖安装完成"
}

# -------- fontconfig 兼容配置 --------
# 各发行版的 fontconfig 配置路径不同
get_fontconfig_path() {
    if [ "$HAS_ROOT" = true ]; then
        case "$DISTRO_FAMILY" in
            debian|ubuntu)
                echo "/etc/fonts/local.conf"
                ;;
            redhat|fedora|centos|rhel)
                echo "/etc/fonts/local.conf"
                ;;
            arch)
                echo "/etc/fonts/local.conf"
                ;;
            suse)
                echo "/etc/fonts/local.conf"
                ;;
            alpine)
                echo "/etc/fonts/conf.d/99-lfi.conf"
                ;;
            *)
                echo "/etc/fonts/local.conf"
                ;;
        esac
    else
        mkdir -p "$HOME/.config/fontconfig"
        echo "$HOME/.config/fontconfig/fonts.conf"
    fi
}

# -------- sudo 兼容 --------
# 不同发行版 sudo 行为不同
safe_sudo() {
    if [ "$HAS_ROOT" = true ]; then
        # 已经是root，直接执行
        eval "$@"
    else
        if command -v sudo &>/dev/null; then
            sudo "$@"
        else
            log_error "需要 root 权限，但系统未安装 sudo"
            log_warn "请以 root 身份运行: su -c \"$0 $@\""
            return 1
        fi
    fi
}

# -------- 挂载NTFS兼容 --------
mount_ntfs() {
    local device="$1"
    local mount_point="$2"
    
    mkdir -p "$mount_point"
    
    # 按优先级尝试不同的NTFS驱动
    # 1. ntfs3 (内核原生，Linux 5.15+)
    if mount -t ntfs3 "$device" "$mount_point" 2>/dev/null; then
        return 0
    fi
    
    # 2. ntfs-3g (FUSE)
    if mount -t ntfs-3g "$device" "$mount_point" 2>/dev/null; then
        return 0
    fi
    
    # 3. ntfs (旧内核)
    if mount -t ntfs "$device" "$mount_point" 2>/dev/null; then
        return 0
    fi
    
    # 4. 自动检测
    if mount "$device" "$mount_point" 2>/dev/null; then
        return 0
    fi
    
    # 安装 ntfs-3g
    log_warn "NTFS 挂载失败，尝试安装 ntfs-3g..."
    pkg_install "ntfs-3g" && mount -t ntfs-3g "$device" "$mount_point" 2>/dev/null && return 0
    
    return 1
}

# -------- fc-cache 兼容 --------
safe_fc_cache() {
    local force="${1:-false}"
    
    echo -ne "  ${BLUE}⟳${NC} 刷新字体缓存... "
    
    if [ "$force" = true ]; then
        if fc-cache -fv 2>/dev/null | tail -1; then
            echo -e "${GREEN}完成${NC}"
        else
            echo -e "${YELLOW}部分成功${NC}"
        fi
    else
        if fc-cache -f 2>/dev/null; then
            echo -e "${GREEN}完成${NC}"
        else
            echo -e "${YELLOW}警告: fc-cache 执行不完整${NC}"
            log_warn "尝试: fc-cache -fv"
        fi
    fi
}

# -------- 检测缺失的常用命令，按发行版给出安装建议 --------
check_missing_cmd() {
    local cmd="$1"
    local hint="$2"
    
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "  ${YELLOW}缺少命令: ${WHITE}$cmd${NC}"
        echo -e "  ${YELLOW}安装建议:${NC} $hint"
        
        # 自动安装（部分已知命令）
        case "$cmd" in
            unzip)
                pkg_install "unzip" && log_info "unzip 已安装" ;;
            wimtools|wimmountrw)
                pkg_install "wimtools" && log_info "wimtools 已安装" ;;
            ntfs-3g)
                pkg_install "ntfs-3g" && log_info "ntfs-3g 已安装" ;;
        esac
        
        return 1
    fi
    return 0
}

# >>> config.sh
# ==============================================================
# LFI fontconfig配置模块 — WPS乱码修复 / 字体优先级 / 别名映射
# ==============================================================

# -------- 主入口 --------
_configure_fontconfig() {
    log_step "fontconfig 配置"
    
    echo ""
    echo -e "  ${BOLD}请选择要执行的操作:${NC}\n"
    echo -e "  ${CYAN}[1]${NC}  ${BOLD}配置字体优先级${NC}"
    echo -e "      ${WHITE}设置中/英文默认字体排序${NC}\n"
    echo -e "  ${CYAN}[2]${NC}  ${BOLD}修复 WPS 乱码${NC}"
    echo -e "      ${WHITE}配置WPS所需的符号字体别名（wingding/webdings等）${NC}\n"
    echo -e "  ${CYAN}[3]${NC}  ${BOLD}配置开源替代别名${NC}"
    echo -e "      ${WHITE}将Windows字体名映射到开源替代（如 微软雅黑→得意黑）${NC}\n"
    echo -e "  ${CYAN}[4]${NC}  ${BOLD}全部配置（推荐）${NC}\n"
    echo -e "  ${CYAN}[b]${NC}  返回\n"
    echo -ne "  ${BOLD}请选择 [1-4/b]: ${NC}"
    read -r fc_choice
    
    case "$fc_choice" in
        1) configure_font_priority ;;
        2) fix_wps_fonts ;;
        3) configure_fontconfig_alias ;;
        4)
            configure_font_priority
            fix_wps_fonts
            configure_fontconfig_alias
            log_info "全部配置完成！"
            ;;
        b|B) return ;;
        *) log_warn "无效选项" ;;
    esac
    
    refresh_cache
}

# -------- 配置字体优先级 --------
configure_font_priority() {
    log_step "字体优先级配置"
    
    # 检测已安装的质量较好的字体
    local prefer_sans=""
    local prefer_serif=""
    local prefer_mono=""
    
    for f in "Noto Sans CJK SC" "Source Han Sans SC" "Smiley Sans" "Microsoft YaHei" "WenQuanYi Micro Hei" "Noto Sans SC"; do
        fc-list "$f" &>/dev/null && [ -z "$prefer_sans" ] && prefer_sans="$f"
    done
    
    for f in "Noto Serif CJK SC" "Source Han Serif SC" "SimSun" "Noto Serif SC"; do
        fc-list "$f" &>/dev/null && [ -z "$prefer_serif" ] && prefer_serif="$f"
    done
    
    for f in "JetBrains Mono" "Cascadia Code" "Fira Code" "Consolas" "Noto Sans Mono" "DejaVu Sans Mono"; do
        fc-list "$f" &>/dev/null && [ -z "$prefer_mono" ] && prefer_mono="$f"
    done
    
    [ -z "$prefer_sans" ] && prefer_sans="sans-serif"
    [ -z "$prefer_serif" ] && prefer_serif="serif"
    [ -z "$prefer_mono" ] && prefer_mono="monospace"
    
    echo ""
    echo -e "  检测到的最佳字体:"
    echo -e "    ${BLUE}无衬线:${NC} ${prefer_sans}"
    echo -e "    ${BLUE}衬线:${NC}   ${prefer_serif}"
    echo -e "    ${BLUE}等宽:${NC}   ${prefer_mono}"
    echo ""
    
    local config_file
    config_file=$(get_fontconfig_path)
    
    cat > "$config_file" << EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- 字体优先级配置 — 由 LFI 自动生成 -->
  
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>${prefer_sans}</family>
      <family>Noto Sans CJK SC</family>
    </prefer>
  </alias>
  
  <alias>
    <family>serif</family>
    <prefer>
      <family>${prefer_serif}</family>
      <family>Noto Serif CJK SC</family>
    </prefer>
  </alias>
  
  <alias>
    <family>monospace</family>
    <prefer>
      <family>${prefer_mono}</family>
    </prefer>
  </alias>
</fontconfig>
EOF
    
    log_info "字体优先级配置已写入: $config_file"
}

# -------- 修复WPS乱码 --------
fix_wps_fonts() {
    log_step "WPS 字体修复"
    
    local config_file
    config_file=$(get_fontconfig_path)
    
    # 检测WPS是否安装
    local wps_found=false
    for wps_bin in wps wpp et wps-office; do
        command -v "$wps_bin" &>/dev/null && wps_found=true && break
    done
    [ -d "/opt/kingsoft" ] || [ -d "/usr/share/kingsoft" ] && wps_found=true
    
    if [ "$wps_found" = true ]; then
        echo -e "  ${GREEN}检测到 WPS Office${NC}"
    else
        echo -e "  ${YELLOW}未检测到 WPS Office，仅配置符号字体映射${NC}"
    fi
    
    echo ""
    
    # 读取现有配置
    local existing_content=""
    [ -f "$config_file" ] && existing_content=$(cat "$config_file")
    
    # -------- 符号字体检查：Wingdings / Webdings / Symbol --------
    echo -e "  ${BOLD}检查符号字体:${NC}"
    local wps_config=""
    local need_symbol_map=false
    
    for sym_font in "Wingdings" "Webdings" "Symbol"; do
        local sym_found=false
        if fc-list "$sym_font" &>/dev/null; then
            sym_found=true
        fi
        # 也检查通过之前别名是否能找到（比如 FreeSerif 已经映射了）
        
        if [ "$sym_found" = true ]; then
            echo -e "    ${GREEN}✓${NC} ${sym_font} — 已安装"
        else
            echo -e "    ${YELLOW}✗${NC} ${sym_font} — 缺失，需配置别名 → FreeSerif"
            need_symbol_map=true
            wps_config="${wps_config}
  <alias>
    <family>${sym_font}</family>
    <accept><family>FreeSerif</family></accept>
  </alias>"
        fi
    done
    
    # -------- 政务公文专用字体检查 --------
    echo ""
    echo -e "  ${BOLD}检查中文字体:${NC}"
    
    # 公文用到的字体映射表：源字体 → 目标字体
    local doc_fonts=(
        "仿宋_GB2312:FangSong"
        "楷体_GB2312:KaiTi"
        "小标宋:Noto Serif CJK SC Bold"
        "方正小标宋:Noto Serif CJK SC Bold"
        "方正小标宋简体:Noto Serif CJK SC Bold"
        "FZXiaoBiaoSong:Noto Serif CJK SC Bold"
        "黑体:SimHei"
    )
    
    local need_doc_map=false
    
    for entry in "${doc_fonts[@]}"; do
        local src="${entry%%:*}"
        local dst="${entry##*:}"
        
        # 检查源字体是否已存在（直接从系统字体找，不通过别名）
        if fc-list "$src" &>/dev/null; then
            echo -e "    ${GREEN}✓${NC} ${src} — 已安装"
        else
            # 检查替代目标是否已安装
            if fc-list "$dst" &>/dev/null; then
                echo -e "    ${YELLOW}✗${NC} ${src} — 缺失，配置别名 → ${dst}"
                need_doc_map=true
                wps_config="${wps_config}
  <alias>
    <family>${src}</family>
    <accept><family>${dst}</family></accept>
  </alias>"
            else
                echo -e "    ${RED}✗${NC} ${src} — 缺失，且替代字体 ${dst} 也未安装"
            fi
        fi
    done
    
    # -------- 写入配置 --------
    echo ""
    if [ "$need_symbol_map" = false ] && [ "$need_doc_map" = false ]; then
        echo -e "  ${GREEN}所有字体已就绪，无需配置别名${NC}"
        return
    fi
    
    # 包裹配置
    wps_config="
  <!-- WPS符号字体映射（由 LFI 自动检测生成） -->${wps_config}"
    
    if echo "$existing_content" | grep -q "WPS符号字体映射"; then
        log_info "WPS配置已存在，跳过"
    else
        local new_content="${existing_content%</fontconfig>}${wps_config}"$'\n</fontconfig>'
        echo "$new_content" > "$config_file"
        log_info "WPS符号字体映射已配置"
    fi
    
    # 确保FreeSerif已安装（Wingdings/Webdings回退用）
    if [ "$need_symbol_map" = true ]; then
        if ! fc-list "FreeSerif" &>/dev/null; then
            echo ""
            echo -e "  ${YELLOW}需要安装 FreeSerif 字体（Wingdings/Webdings 的回退字体）${NC}"
            echo -ne "  ${YELLOW}是否安装? (Y/n): ${NC}"
            read -r install_fs
            if [ "$install_fs" != "n" ] && [ "$install_fs" != "N" ]; then
                case "$PKG_MGR" in
                    apt)  sudo apt install -y fonts-freefont-ttf 2>/dev/null ;;
                    dnf|yum) sudo dnf install -y freefont 2>/dev/null ;;
                    pacman) sudo pacman -S --noconfirm freefont 2>/dev/null ;;
                    *) log_warn "请手动安装: fonts-freefont-ttf (Debian) / freefont (Fedora)" ;;
                esac
                log_info "FreeSerif 安装完成"
            fi
        fi
    fi
}

# -------- 配置开源替代别名 --------
configure_fontconfig_alias() {
    log_step "开源替代字体别名配置"
    
    local config_file
    config_file=$(get_fontconfig_path)
    
    local existing_content=""
    [ -f "$config_file" ] && existing_content=$(cat "$config_file")
    
    # 映射表：Windows字体 → 开源替代字体
    # 格式：Windows字体名|开源替代1|开源替代2
    local alias_map=(
        "Microsoft YaHei|Smiley Sans|Noto Sans CJK SC"
        "SimSun|Noto Serif CJK SC|"
        "NSimSun|Noto Serif CJK SC|"
        "宋体|Noto Serif CJK SC|"
        "SimHei|Noto Sans CJK SC|"
        "黑体|Noto Sans CJK SC|"
        "KaiTi|LXGW WenKai|"
        "楷体|LXGW WenKai|"
        "FangSong|Noto Serif CJK SC|"
        "仿宋|Noto Serif CJK SC|"
        "方正小标宋|Noto Serif CJK SC Bold|"
        "方正小标宋简体|Noto Serif CJK SC Bold|"
        "小标宋|Noto Serif CJK SC Bold|"
        "FZXiaoBiaoSong|Noto Serif CJK SC Bold|"
    )
    
    echo ""
    echo -e "  ${BOLD}检查字体状态:${NC}"
    echo ""
    
    local alias_config=""
    local has_any_work=false
    
    for entry in "${alias_map[@]}"; do
        local win_font="${entry%%|*}"
        local rest="${entry#*|}"
        local alt1="${rest%%|*}"
        local alt2="${rest##*|}"
        [ "$alt2" = "$alt1" ] && alt2=""
        
        # 检查 Windows 字体是否已经安装
        local win_installed=false
        if fc-list "$win_font" &>/dev/null; then
            win_installed=true
        fi
        
        # 检查开源替代是否已安装
        local alt_installed=false
        local alt_used=""
        if fc-list "$alt1" &>/dev/null; then
            alt_installed=true
            alt_used="$alt1"
        elif [ -n "$alt2" ] && fc-list "$alt2" &>/dev/null; then
            alt_installed=true
            alt_used="$alt2"
        fi
        
        if [ "$win_installed" = true ]; then
            echo -e "    ${GREEN}✓${NC} ${win_font} — 已安装，无需别名"
        elif [ "$alt_installed" = true ]; then
            echo -e "    ${YELLOW}✗${NC} ${win_font} — 缺失，配置别名 → ${alt_used}"
            has_any_work=true
            alias_config="${alias_config}
  <alias>
    <family>${win_font}</family>
    <prefer>
      <family>${alt_used}</family>
    </prefer>
  </alias>"
        else
            echo -e "    ${RED}✗${NC} ${win_font} — 缺失，且替代字体 ${alt1}${alt2:+ / $alt2} 也未安装，跳过"
        fi
    done
    
    echo ""
    if [ "$has_any_work" = false ]; then
        echo -e "  ${GREEN}所有 Windows 字体已就绪，无需配置开源替代别名${NC}"
        return
    fi
    
    alias_config="
  <!-- Windows字体 → 开源替代 映射（由 LFI 自动检测生成） -->${alias_config}"
    
    if echo "$existing_content" | grep -q "开源替代"; then
        log_info "开源替代别名配置已存在，跳过"
    else
        local new_content="${existing_content%</fontconfig>}${alias_config}"$'\n</fontconfig>'
        echo "$new_content" > "$config_file"
        log_info "开源替代字体别名已配置"
    fi
}

# >>> extract-win.sh
# ==============================================================
# LFI Windows字体提取模块 v2 — 多源自动安装
# ==============================================================
# 本模块不存储/分发任何字体文件
# 所有字体来源均为用户自有设备或文件
# ==============================================================

# -------- Windows字体清单 --------
declare -A WIN_FONT_MAP=(
    ["微软雅黑"]="msyh.ttc|msyhbd.ttc|msyhl.ttc"
    ["宋体/新宋体"]="simsun.ttc|simsunb.ttf"
    ["黑体"]="simhei.ttf"
    ["楷体"]="simkai.ttf"
    ["仿宋"]="simfang.ttf"
    ["方正小标宋"]="fzxbs.ttf|fzxbsj.ttf|fzxiaoBS.ttf|FZXiaoBiaoSong.ttf|FZXiaoBiaoSong-B05S.ttf|FZXBSJW.ttf"
    ["Arial"]="arial.ttf|arialbd.ttf|arialbi.ttf|ariali.ttf"
    ["Times New Roman"]="times.ttf|timesbd.ttf|timesbi.ttf|timesi.ttf"
    ["Courier New"]="cour.ttf|courbd.ttf|courbi.ttf|couri.ttf"
    ["Verdana"]="verdana.ttf|verdanab.ttf|verdanai.ttf|verdanaz.ttf"
    ["Tahoma"]="tahoma.ttf|tahomabd.ttf"
    ["Segoe UI"]="segoeui.ttf|segoeuib.ttf|segoeuii.ttf|segoeuiz.ttf"
    ["Consolas"]="consola.ttf|consolab.ttf|consolai.ttf|consolaz.ttf"
    ["Wingdings"]="wingding.ttf"
    ["Webdings"]="webdings.ttf"
    ["Symbol"]="symbol.ttf"
)

# -------- 主入口 --------
_extract_windows_fonts() {
    log_step "安装 Windows 字体"
    
    echo ""
    echo -e "  ${YELLOW}LFI 不提供 Windows 字体下载。${NC}"
    echo -e "  请选择字体来源（LFI 自动完成安装）："
    echo ""
    echo -e "  ${CYAN}[1]${NC} 从双系统 Windows 分区提取"
    echo -e "  ${CYAN}[2]${NC} 从 Wine 目录提取"
    echo -e "  ${CYAN}[3]${NC} 手动指定字体目录（U盘/移动硬盘等）"
    echo -e "  ${CYAN}[4]${NC} 从 Windows ISO/安装盘提取"
    echo -e "  ${CYAN}[5]${NC} 全盘搜索已有字体文件"
    echo -e "  ${CYAN}[6]${NC} 告诉我怎么获取 Windows 字体"
    echo -e "  ${CYAN}[b]${NC} 返回"
    echo ""
    echo -ne "  ${BOLD}请选择 [1-6/b]: ${NC}"
    read -r src_choice
    
    case "$src_choice" in
        1) extract_from_dual_boot ;;
        2) extract_from_wine ;;
        3) extract_from_user_dir ;;
        4) extract_from_iso ;;
        5) search_globally ;;
        6) show_windows_font_guide ;;
        b|B) return ;;
        *) log_warn "无效选项" ;;
    esac
}

# -------- ① 双系统提取 --------
extract_from_dual_boot() {
    log_step "扫描 Windows 分区"

    # 查找所有NTFS分区
    local ntfs_parts
    ntfs_parts=$(lsblk -o NAME,FSTYPE,LABEL,SIZE -pl 2>/dev/null | grep "ntfs" | grep -v "loop")

    if [ -z "$ntfs_parts" ]; then
        echo ""
        echo -e "  ${YELLOW}未找到 NTFS 分区。${NC}"
        echo ""
        echo -e "  常见原因："
        echo -e "  • Windows 启用了快速启动（需要 ${WHITE}powercfg /h off${NC} 后完全关机）"
        echo -e "  • 硬盘未挂载（可尝试菜单 [3] 手动指定）"
        echo ""
        echo -ne "  ${YELLOW}按回车返回...${NC}"
        read -r
        return
    fi

    # 先尝试挂载每个NTFS分区，检查 /Windows/Fonts 是否存在并统计字体
    local temp_mount="/tmp/lfi-scan-$$"
    mkdir -p "$temp_mount"

    local part_list=()        # 设备名
    local part_labels=()      # 标签/大小信息
    local part_font_info=()   # 字体统计信息
    local part_has_fonts=()   # true/false 是否有Fonts目录
    local best_index=-1       # 字体最多的分区索引

    local max_fonts=0

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local dev
        dev=$(echo "$line" | awk '{print $1}')
        local label
        label=$(echo "$line" | awk '{print $3, $4}')

        part_list+=("$dev")
        part_labels+=("$label")

        # 先检查分区是否已挂载（通过 lsblk 获取挂载点）
        local mnt_point=""
        mnt_point=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -1 | xargs)
        local needs_unmount=false

        if [ -z "$mnt_point" ] || [ "$mnt_point" = "" ]; then
            # 未挂载，临时挂载
            mnt_point="$temp_mount/$$-$(basename "$dev")"
            mkdir -p "$mnt_point"
            if ! mount_ntfs "$dev" "$mnt_point" 2>/dev/null; then
                part_font_info+=("?")
                part_has_fonts+=("false")
                rmdir "$mnt_point" 2>/dev/null || true
                ((idx++))
                continue
            fi
            needs_unmount=true
        fi

        # 查找 Fonts 目录
        local font_dir=""
        for d in "$mnt_point/Windows/Fonts" "$mnt_point"/*/Windows/Fonts; do
            [ -d "$d" ] && font_dir="$d" && break
        done

        if [ -n "$font_dir" ]; then
            local zh_count
            zh_count=$(find "$font_dir" \( -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" \) 2>/dev/null | wc -l)
            zh_count=$(echo "$zh_count" | xargs)
            part_font_info+=("${zh_count}")
            part_has_fonts+=("true")
            if [ "$zh_count" -gt "$max_fonts" ] 2>/dev/null; then
                max_fonts=$zh_count
                best_index=${#part_list[@]}
                best_index=$((best_index - 1))
            fi
        else
            part_font_info+=("0")
            part_has_fonts+=("false")
        fi

        if [ "$needs_unmount" = true ]; then
            umount "$mnt_point" 2>/dev/null || true
            rmdir "$mnt_point" 2>/dev/null || true
        fi
        ((idx++))
    done <<< "$ntfs_parts"

    rmdir "$temp_mount" 2>/dev/null || true

    # 显示分区列表
    echo ""
    echo -e "  ${BOLD}找到以下 NTFS 分区：${NC}"
    echo ""

    local idx=0
    for dev in "${part_list[@]}"; do
        local menu_num="  "
        local marker=""
        if [ "${part_has_fonts[$idx]}" = "true" ]; then
            local fcount="${part_font_info[$idx]}"
            marker=" ${GREEN}✓${NC} ${fcount} 个可用字体"
            if [ "$idx" -eq "$best_index" ]; then
                menu_num="${GREEN}[$((idx+1))]${NC}"
                marker="${marker} ${GREEN}★ 推荐${NC}"
            else
                menu_num=" ${CYAN}[$((idx+1))]${NC}"
            fi
        else
            menu_num=" ${CYAN}[$((idx+1))]${NC}"
            marker=" ${YELLOW}✗${NC} 未找到 Fonts 目录"
        fi
        # 显示简短信息
        local dev_short=$(basename "$dev")
        local label_short="${part_labels[$idx]}"
        echo -e "  ${menu_num} ${BLUE}${dev_short}${NC}  ${label_short}  ${marker}"
        ((idx++))
    done

    echo ""
    echo -e "  ${BOLD}可用字体格式:${NC} .ttf / .ttc / .otf"
    echo ""
    echo -ne "  ${BOLD}请选择 [1-${#part_list[@]}]，回车默认推荐: ${NC}"
    read -r part_choice

    part_dev=""
    if [ -z "$part_choice" ]; then
        # 回车——选推荐分区
        if [ "$best_index" -ge 0 ]; then
            part_dev="${part_list[$best_index]}"
            echo -e "  ${GREEN}自动选择推荐分区: $(basename $part_dev)${NC}"
        else
            part_dev="${part_list[0]}"
            echo -e "  ${YELLOW}未找到含字体的分区，默认选择第一个${NC}"
        fi
    elif [[ "$part_choice" =~ ^[0-9]+$ ]]; then
        # 数字序号
        local num=$((part_choice - 1))
        if [ "$num" -ge 0 ] && [ "$num" -lt "${#part_list[@]}" ]; then
            part_dev="${part_list[$num]}"
            echo -e "  ${GREEN}已选择: $(basename $part_dev)${NC}"
        else
            log_warn "无效序号: $part_choice，默认选择推荐分区"
            if [ "$best_index" -ge 0 ]; then
                part_dev="${part_list[$best_index]}"
            else
                part_dev="${part_list[0]}"
            fi
        fi
    else
        # 可能是设备名直接输入
        part_dev="$part_choice"
        echo -e "  ${GREEN}已选择: $(basename $part_dev)${NC}"
    fi

    # 检查分区是否已挂载
    local mount_point=""
    mount_point=$(lsblk -no MOUNTPOINT "$part_dev" 2>/dev/null | head -1 | xargs)
    local needs_unmount=false

    if [ -z "$mount_point" ] || [ "$mount_point" = "" ]; then
        mount_point="/tmp/lfi-win-$$"
        mkdir -p "$mount_point"
        echo -ne "  ${BLUE}⟳${NC} 挂载中... "
        if ! mount_ntfs "$part_dev" "$mount_point"; then
            echo -e "${RED}失败${NC}"
            log_error "挂载失败。Windows 可能未完全关机（启用了快速启动）"
            echo ""
            echo -e "  ${YELLOW}解决方法:${NC}"
            echo -e "  1. 进入 Windows，以管理员身份运行命令提示符"
            echo -e "  2. 执行: ${WHITE}powercfg /h off${NC}"
            echo -e "  3. 完全关机后再试"
            return
        fi
        echo -e "${GREEN}完成${NC}"
        needs_unmount=true
    else
        echo -e "  ${GREEN}✓ 分区已挂载于: ${mount_point}${NC}"
    fi

    local font_dir=""
    for d in "$mount_point/Windows/Fonts" "$mount_point"/*/Windows/Fonts; do
        [ -d "$d" ] && font_dir="$d" && break
    done

    if [ -n "$font_dir" ]; then
        install_from_dir "$font_dir"
    else
        log_error "未找到 Fonts 目录"
    fi

    if [ "$needs_unmount" = true ]; then
        echo -ne "  ${BLUE}⟳${NC} 卸载分区... "
        umount "$mount_point" 2>/dev/null && echo -e "${GREEN}完成${NC}" || true
        rmdir "$mount_point" 2>/dev/null
    fi
}

# -------- ② Wine提取 --------
extract_from_wine() {
    log_step "从 Wine 提取字体"
    
    local found_dirs=()
    
    # 常见Wine前缀位置
    for d in "$HOME/.wine/drive_c/windows/Fonts" \
             "$HOME/.local/share/wineprefixes/default/drive_c/windows/Fonts" \
             /opt/wine-*/drive_c/windows/Fonts; do
        if [ -d "$d" ] && ls "$d"/*.ttf &>/dev/null 2>&1; then
            found_dirs+=("$d")
        fi
    done
    
    if [ ${#found_dirs[@]} -eq 0 ]; then
        log_error "未找到 Wine 字体目录"
        echo ""
        echo -e "  Wine 未安装或未配置。您可以："
        echo -e "  • ${WHITE}sudo apt install wine${NC} 安装 Wine"
        echo -e "  • 或使用其他菜单项获取字体"
        echo ""
        echo -ne "  ${YELLOW}按回车返回...${NC}"
        read -r
        return
    fi
    
    echo -e "  ${GREEN}找到 Wine 字体目录:${NC}"
    for d in "${found_dirs[@]}"; do
        echo -e "    ${WHITE}$d${NC}"
    done
    
    install_from_dir "${found_dirs[0]}"
}

# -------- ③ 用户指定目录 --------
extract_from_user_dir() {
    log_step "手动指定字体目录"
    echo ""
    echo -e "  请输入字体文件所在目录路径"
    echo -e "  例如: ${WHITE}/media/username/U盘/Fonts${NC}"
    echo -e "  或:   ${WHITE}/home/username/下载/字体${NC}"
    echo ""
    echo -ne "  ${BOLD}路径: ${NC}"
    read -r user_path
    
    # 处理引号和拖拽
    user_path=$(echo "$user_path" | sed "s/^['\"]//;s/['\"]$//" | xargs)
    
    if [ -z "$user_path" ]; then
        log_error "路径不能为空"
        return
    fi
    
    if [ ! -d "$user_path" ]; then
        log_error "目录不存在: $user_path"
        return
    fi
    
    local count
    count=$(find "$user_path" \( -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" \) 2>/dev/null | wc -l)
    if [ "$count" -eq 0 ]; then
        log_error "该目录下没有找到字体文件（.ttf/.ttc/.otf）"
        return
    fi
    
    echo -e "  ${GREEN}找到 ${count} 个字体文件${NC}"
    install_from_dir "$user_path"
}

# -------- ④ 从Windows ISO提取 --------
extract_from_iso() {
    log_step "从 Windows ISO 提取字体"
    echo ""
    echo -e "  请输入 Windows 安装 ISO 或 install.wim 路径"
    echo ""
    echo -ne "  ${BOLD}文件路径: ${NC}"
    read -r iso_path
    
    iso_path=$(echo "$iso_path" | sed "s/^['\"]//;s/['\"]$//" | xargs)
    
    if [ ! -f "$iso_path" ]; then
        log_error "文件不存在: $iso_path"
        return
    fi
    
    local mount_point="/tmp/lfi-win-iso-$$"
    mkdir -p "$mount_point"
    
    local file_ext="${iso_path##*.}"
    file_ext=$(echo "$file_ext" | tr '[:upper:]' '[:lower:]')
    
    case "$file_ext" in
        iso)
            echo -ne "  ${BLUE}⟳${NC} 挂载 ISO... "
            if mount -o loop,ro "$iso_path" "$mount_point" 2>/dev/null; then
                echo -e "${GREEN}完成${NC}"
                find_fonts_in_mounted_iso "$mount_point"
                umount "$mount_point" 2>/dev/null
            else
                echo -e "${RED}失败${NC}"
                log_error "挂载 ISO 失败（可能需要安装 fuseiso: sudo apt install fuseiso）"
            fi
            ;;
        wim)
            echo -ne "  ${BLUE}⟳${NC} 挂载 WIM... "
            if command -v wimmountrw &>/dev/null; then
                wimmountrw "$iso_path" "$mount_point" 2>/dev/null && {
                    echo -e "${GREEN}完成${NC}"
                    find_fonts_in_mounted_iso "$mount_point"
                    wimumount "$mount_point" 2>/dev/null
                } || echo -e "${RED}失败${NC}"
            elif command -v mount &>/dev/null && modprobe ntfs3 2>/dev/null; then
                mount -t ntfs3 -o loop "$iso_path" "$mount_point" 2>/dev/null && {
                    echo -e "${GREEN}完成${NC}"
                    find_fonts_in_mounted_iso "$mount_point"
                    umount "$mount_point" 2>/dev/null
                } || echo -e "${RED}失败${NC}"
            else
                echo -e "${RED}需要安装 wimtools${NC}"
                log_warn "请安装: sudo apt install wimtools"
            fi
            ;;
        esd)
            log_warn "ESD 格式暂不支持，请先转换为 ISO"
            ;;
        *)
            log_error "不支持的文件格式: $file_ext（支持 iso/wim）"
            ;;
    esac
    
    rmdir "$mount_point" 2>/dev/null || true
}

find_fonts_in_mounted_iso() {
    local mnt="$1"
    
    echo -e "  ${BLUE}⟳${NC} 搜索字体文件..."
    
    local temp_dir="/tmp/lfi-iso-fonts-$$"
    mkdir -p "$temp_dir"
    
    local found=0
    while IFS= read -r -d '' f; do
        local fname
        fname=$(basename "$f")
        # 只提取我们需要的字体
        local matched=false
        for key in "${!WIN_FONT_MAP[@]}"; do
            local files="${WIN_FONT_MAP[$key]}"
            IFS='|' read -ra file_list <<< "$files"
            for tf in "${file_list[@]}"; do
                if [ "${fname,,}" = "${tf,,}" ]; then
                    install_single_font "$f"
                    ((found++))
                    echo -ne "\r  已找到: ${found} 个字体文件"
                    matched=true
                    break
                fi
            done
            [ "$matched" = true ] && break
        done
    done < <(find "$mnt" \( -name "*.ttf" -o -name "*.ttc" \) -print0 2>/dev/null)
    
    echo ""
    if [ "$found" -gt 0 ]; then
        echo -e "  ${GREEN}✓ 从 ISO 中提取了 ${found} 个字体${NC}"
        refresh_cache
    else
        echo -e "  ${YELLOW}ISO 中未找到所需字体${NC}"
    fi
    
    rm -rf "$temp_dir"
}

# -------- ⑤ 全盘搜索 --------
search_globally() {
    log_step "全盘搜索 Windows 字体"
    echo ""
    echo -e "  ${YELLOW}正在扫描全盘，这可能需要几分钟...${NC}"
    echo -e "  （仅搜索常见 Windows 字体文件名）"
    echo ""
    
    # 构建目标文件列表
    local targets=()
    for key in "${!WIN_FONT_MAP[@]}"; do
        local files="${WIN_FONT_MAP[$key]}"
        IFS='|' read -ra file_list <<< "$files"
        for f in "${file_list[@]}"; do
            targets+=("$f")
        done
    done
    
    # 去重
    targets=($(printf "%s\n" "${targets[@]}" | sort -u))
    
    local total=0
    for target in "${targets[@]}"; do
        echo -ne "  ${BLUE}⟳${NC} 搜索 ${target}... \r"
        
        local found_path
        found_path=$(find / -maxdepth 6 -name "$target" -type f 2>/dev/null | head -1)
        
        if [ -n "$found_path" ]; then
            local size
            size=$(du -h "$found_path" | cut -f1)
            echo -e "  ${GREEN}✓${NC} ${target}  (${size})  ${WHITE}$found_path${NC}"
            install_single_font "$found_path"
            ((total++))
        fi
    done
    
    echo ""
    if [ "$total" -gt 0 ]; then
        echo -e "  ${GREEN}✓ 共安装 ${total} 个字体文件${NC}"
        refresh_cache
    else
        echo -e "  ${YELLOW}未找到任何 Windows 字体文件${NC}"
        echo ""
        echo -e "  建议："
        echo -e "  • 如果双系统，选择菜单 [1] 自动提取"
        echo -e "  • 如果有安装盘，选择菜单 [4] 从 ISO 提取"
        echo -e "  • 或者选菜单 [7] 安装开源替代方案"
    fi
}

# -------- 从目录安装字体 --------
install_from_dir() {
    local src_dir="$1"
    
    if [ ! -d "$src_dir" ]; then
        log_error "目录不存在: $src_dir"
        return
    fi
    
    echo ""
    echo -e "  ${BOLD}可用 Windows 字体:${NC}\n"
    
    local found_count=0
    local installed_count=0
    
    for key in "${!WIN_FONT_MAP[@]}"; do
        local files="${WIN_FONT_MAP[$key]}"
        local installed=false
        
        IFS='|' read -ra file_list <<< "$files"
        for f in "${file_list[@]}"; do
            local full_path="$src_dir/$f"
            if [ -f "$full_path" ]; then
                if [ "$installed" = false ]; then
                    echo -ne "  ${GREEN}→${NC} ${key}... "
                    installed=true
                fi
                install_single_font "$full_path"
                ((found_count++))
            fi
        done
        
        if [ "$installed" = true ]; then
            echo -e "${GREEN}已安装${NC}"
            ((installed_count++))
        fi
    done
    
    echo ""
    if [ "$installed_count" -gt 0 ]; then
        echo -e "  ${GREEN}✓ 共安装 ${found_count} 个文件（${installed_count} 种字体）${NC}"
        refresh_cache
    else
        echo -e "  ${YELLOW}未找到 Windows 字体文件${NC}"
    fi
}

# -------- 安装单个字体文件 --------
install_single_font() {
    local src="$1"
    local fname
    fname=$(basename "$src")
    
    # 跳过已安装的
    [ -f "$FONT_DIR_USER/$fname" ] && return
    [ "$HAS_ROOT" = true ] && [ -f "$FONT_DIR_SYSTEM/$fname" ] && return
    
    mkdir -p "$FONT_DIR_USER"
    cp "$src" "$FONT_DIR_USER/$fname" 2>/dev/null
    
    if [ "$HAS_ROOT" = true ]; then
        mkdir -p "$FONT_DIR_SYSTEM"
        cp "$src" "$FONT_DIR_SYSTEM/$fname" 2>/dev/null
    fi
}

# -------- 引导用户获取字体 --------
show_windows_font_guide() {
    log_step "如何获取 Windows 字体"
    
    echo ""
    echo -e "  ${YELLOW}Windows 字体（微软雅黑、宋体等）受版权保护，${NC}"
    echo -e "  ${YELLOW}LFI 无法直接提供下载。${NC}"
    echo ""
    echo -e "  ${BOLD}合法获取方式：${NC}\n"
    echo -e "  ${CYAN}①${NC} ${BOLD}如果你有 Windows 电脑${NC}"
    echo -e "     把 U 盘插到 Windows 电脑，复制"
    echo -e "     ${WHITE}C:\\Windows\\Fonts${NC} 文件夹里的 .ttf/.ttc 文件"
    echo -e "     然后插回本机，选择菜单 [3] 手动指定目录\n"
    echo -e "  ${CYAN}②${NC} ${BOLD}如果你有 Windows 安装 ISO${NC}"
    echo -e "     选择菜单 [4]，输入 ISO 文件路径"
    echo -e "     LFI 自动挂载并提取所需字体\n"
    echo -e "  ${CYAN}③${NC} ${BOLD}如果你有双系统${NC}"
    echo -e "     选择菜单 [1]，LFI 自动从 Windows 分区提取\n"
    echo -e "  ${CYAN}④${NC} ${BOLD}如果你都没有${NC}"
    echo -e "     选择菜单 [7] 安装开源替代方案"
    echo -e "     ${WHITE}得意黑${NC} → 代替微软雅黑"
    echo -e "     ${WHITE}霞鹜文楷${NC} → 代替楷体"
    echo -e "     ${WHITE}思源宋体${NC} → 代替宋体"
    echo -e "     ${WHITE}Liberation${NC} 系列 → 代替 Arial/Times\n"
    echo -e "  ${YELLOW}开源替代方案已经完全够日常使用了！${NC}"
    echo ""
    echo -ne "  ${YELLOW}按回车返回...${NC}"
    read -r
}

# >>> installer.sh
# ==============================================================
# LFI 安装核心逻辑 — 从自有GitHub Release拉取字体包并安装
# ==============================================================

# -------- 安装一个场景的字体 --------
_install_scenario() {
    local scenario="$1"
    local pack_url="https://github.com/${REPO}/releases/download/${LFI_RELEASE}/lfi-fonts-${scenario}-v1.tar.gz"
    local list_url
    list_url=$(github_raw "fonts/${scenario}/list.txt")
    
    # 载入兼容模块（使用distro专用函数）
    detect_distro 2>/dev/null || true
    
    log_step "安装 ${scenario} 场景字体"
    
    # 创建字体目录
    if [ "$HAS_ROOT" = true ]; then
        sudo mkdir -p "$FONT_DIR_SYSTEM"
    fi
    mkdir -p "$FONT_DIR_USER"
    
    local pack_file="$DOWNLOAD_DIR/lfi-fonts-${scenario}-v1.tar.gz"
    local extract_dir="$DOWNLOAD_DIR/${scenario}_extract"
    mkdir -p "$extract_dir"
    
    echo ""
    echo -ne "  ${BLUE}↓${NC} 下载字体包 (${scenario})... "
    
    # 从 Release 下载打包好的字体
    if curl -fSL --connect-timeout 15 --max-time 300 "$pack_url" -o "$pack_file" 2>/dev/null; then
        local size
        size=$(du -h "$pack_file" | cut -f1)
        echo -e "${GREEN}${size}${NC}"
        
        echo -ne "  ${BLUE}⟳${NC} 解压中... "
        if tar xzf "$pack_file" -C "$extract_dir" 2>/dev/null; then
            echo -e "${GREEN}完成${NC}"
            
            echo -e "  ${BLUE}⟳${NC} 正在安装字体文件..."
            # 安装所有字体文件 - 使用find代替glob（bash 5.3兼容）
            local count=0
            local skipped=0
            local current=0
            local item_count=0

            # 第一步：解压所有zip包
            while IFS= read -r -d '' zip_file; do
                local zname
                zname=$(basename "$zip_file")
                local zdir="$extract_dir/${zname%.zip}"
                mkdir -p "$zdir"
                unzip -q -o "$zip_file" -d "$zdir" 2>/dev/null || true
            done < <(find "$extract_dir" -maxdepth 1 -name "*.zip" -print0 2>/dev/null)

            # 第二步：统计所有实际字体文件数（含zip解压后的）
            while IFS= read -r -d '' f; do
                ((item_count++))
            done < <(find "$extract_dir" \( -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" \) -print0 2>/dev/null)
            [ "$item_count" -eq 0 ] && item_count=1

            # 第三步：安装所有字体文件，显示真实进度
            local progress_label="安装"
            while IFS= read -r -d '' font_file; do
                ((current++))
                local fname
                fname=$(basename "$font_file")
                if [ -f "$FONT_DIR_USER/$fname" ] || ([ "$HAS_ROOT" = true ] && [ -f "$FONT_DIR_SYSTEM/$fname" ]); then
                    ((skipped++))
                    progress_label="检查"
                else
                    cp "$font_file" "$FONT_DIR_USER/" 2>/dev/null || true
                    [ "$HAS_ROOT" = true ] && sudo cp "$font_file" "$FONT_DIR_SYSTEM/" 2>/dev/null || true
                    ((count++))
                    progress_label="安装"
                fi
                # 显示进度（每5个或最后一个才刷新）
                if [ $((current % 5)) -eq 0 ] || [ "$current" -eq "$item_count" ]; then
                    echo -e "\\r    ${progress_label}: ${current}/${item_count}"
                fi
            done < <(find "$extract_dir" \( -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" \) -print0 2>/dev/null)
            echo ""
            
            local result="安装了 ${BLUE}${count}${NC} 个"
            [ "$skipped" -gt 0 ] && result="${result}（${YELLOW}${skipped}${NC} 个已存在跳过）"
            echo -e "  ${GREEN}✓${NC} ${result}"
        else
            echo -e "${RED}解压失败${NC}"
        fi
    else
        echo -e "${RED}下载失败${NC}"
        echo -e "  ${YELLOW}尝试直接安装...${NC}"
        # 回退：逐一下载（兼容旧的list.txt格式）
        install_scenario_fallback "$scenario" "$list_url"
    fi
    
    refresh_cache
}

# -------- 回退方案：逐一下载 --------
install_scenario_fallback() {
    local scenario="$1"
    local list_url="$2"
    
    local list_content
    list_content=$(curl -fsSL "$list_url" 2>/dev/null) || {
        log_warn "场景 '$scenario' 字体清单不可用"
        return
    }
    
    local downloaded=0
    local skipped=0
    
    while IFS='|' read -r name path license; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [ -z "$name" ] && continue
        
        name=$(echo "$name" | xargs)
        path=$(echo "$path" | xargs)
        local fname
        fname=$(basename "$path")
        
        # 检查是否已存在
        if [ -f "$FONT_DIR_USER/$fname" ] || ([ "$HAS_ROOT" = true ] && [ -f "$FONT_DIR_SYSTEM/$fname" ]); then
            echo -e "  ${YELLOW}⏭${NC} ${name} — 已存在"
            ((skipped++))
            continue
        fi
        
        echo -ne "  ${BLUE}↓${NC} ${name}... "
        log_warn "回退模式不支持单文件下载，跳过"
    done <<< "$list_content"
}

# -------- 安装全部场景 --------
install_all() {
    log_step "全部安装"
    for scene in zh-cn office coding design; do
        install_scenario "$scene"
    done
    log_info "全部场景安装完成！"
}

# -------- 刷新字体缓存 --------
refresh_cache() {
    echo ""
    echo -ne "  ${BLUE}⟳${NC} 刷新字体缓存... "
    if fc-cache -f 2>/dev/null; then
        echo -e "${GREEN}完成${NC}"
    else
        echo -e "${RED}失败${NC}"
        log_warn "尝试: sudo fc-cache -fv"
    fi
}

# -------- 检查安装结果 --------
verify_installation() {
    local font_name="$1"
    local count
    count=$(fc-list "$font_name" 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} ${font_name} 已安装 (${count}个变体)"
        return 0
    else
        echo -e "  ${RED}✗${NC} ${font_name} 未安装"
        return 1
    fi
}

# >>> menu.sh
# ==============================================================
# LFI 菜单系统 — 场景选择 + 操作入口
# ==============================================================

# 被 lfi.sh source 加载，变量和函数已继承

# -------- 渲染标题块 --------
print_header() {
    local title="$1"
    local color="${2:-$BLUE}"
    local width=56
    local pad
    pad=$(( (width - ${#title} - 2) / 2 ))
    
    echo ""
    echo -e "${color}   ╔$(printf '═%.0s' $(seq 1 $((width-2))))╗${NC}"
    echo -e "${color}   ║$(printf ' %.0s' $(seq 1 $pad)) ${BOLD}${WHITE}${title}${NC}${color}$(printf ' %.0s' $(seq 1 $((width - pad - ${#title} - 2))))║${NC}"
    echo -e "${color}   ╚$(printf '═%.0s' $(seq 1 $((width-2))))╝${NC}"
    echo ""
}

# -------- 系统状态栏 --------
print_status_bar() {
    echo -e " ${BLUE}系统:${NC} ${OS:-unknown} ${DISTRO_FAMILY:+($DISTRO_FAMILY)} | ${BLUE}架构:${NC} ${ARCH} | ${BLUE}包管理器:${NC} ${PKG_MGR}"
    if [ "$WIN_AVAILABLE" = true ]; then
        echo -e " ${BLUE}Windows字体:${NC} ${GREEN}已检测到${NC} (${#WIN_FONT_DIRS[@]}个位置)"
    else
        echo -e " ${BLUE}Windows字体:${NC} ${YELLOW}未检测到${NC}"
    fi
    if [ "$HAS_ROOT" = true ]; then
        echo -e " ${BLUE}权限:${NC} ${GREEN}root${NC}"
    else
        echo -e " ${BLUE}权限:${NC} ${YELLOW}普通用户${NC} (字体安装到 ~/.local/share/fonts)"
    fi
    echo ""
}

# -------- 场景菜单 --------
show_main_menu() {
    print_header "选择使用场景" "$BLUE"
    print_status_bar
    
    echo -e "  ${BOLD}请选择使用场景：${NC}\n"
    echo -e "  ${CYAN}[1]${NC}  🀄  ${BOLD}中文用户必备${NC}"
    echo -e "      ${WHITE}开源中文字体 + 办公文档配置${NC}\n"
    echo -e "  ${CYAN}[2]${NC}  💻  ${BOLD}编程开发${NC}"
    echo -e "      ${WHITE}JetBrains Mono / Fira Code / Cascadia Code / Nerd Fonts${NC}\n"
    echo -e "  ${CYAN}[3]${NC}  🎨  ${BOLD}设计师 / 创意场景${NC}"
    echo -e "      ${WHITE}免费可商用字体合集${NC}\n"
    echo -e "  ${CYAN}[4]${NC}  📦  ${BOLD}全部安装（推荐）${NC}\n"
    echo -e "  ${YELLOW}━━━━ 补充功能 ━━━━${NC}\n"
    echo -e "  ${CYAN}[5]${NC}  🪟  ${BOLD}安装 Windows 字体${NC}"
    echo -e "      ${WHITE}从双系统/Wine/ISO/U盘提取，或全盘搜索${NC}\n"
    echo -e "  ${CYAN}[6]${NC}  ⚡  ${BOLD}仅安装开源替代方案${NC}"
    echo -e "      ${WHITE}用开源字体替代Windows商业字体，无需Windows也可用${NC}\n"
    echo -e "  ${CYAN}[7]${NC}  🔧  ${BOLD}配置 fontconfig 映射${NC}"
    echo -e "      ${WHITE}修复WPS乱码 / 设置字体优先级 / 配置别名${NC}\n"
    echo -e "  ${YELLOW}━━━━ 工具 ━━━━${NC}\n"
    echo -e "  ${CYAN}[8]${NC}  🔍  ${BOLD}查看已安装字体${NC}"
    echo -e "  ${CYAN}[9]${NC}  🗑️   ${BOLD}卸载 / 重置字体${NC}"
    echo -e "  ${CYAN}[i]${NC}  ℹ️   ${BOLD}关于 / 许可说明${NC}"
    echo -e "  ${CYAN}[q]${NC}  ❌  ${BOLD}退出${NC}"
    echo ""
    echo -ne "  ${BOLD}请输入选项 [1-9/0/i/q]: ${NC}"
}

# -------- 菜单循环 --------
menu_loop() {
    while true; do
        show_main_menu
        read -r choice
        
        case "$choice" in
            1)
                install_scenario "zh-cn"
                install_scenario "office"
                ;;
            2) install_scenario "coding" ;;
            3) install_scenario "design" ;;
            4) install_all ;;
            5) extract_windows_fonts ;;
            6) install_opensource_alternative ;;
            7) configure_fontconfig ;;
            8) show_installed_fonts ;;
            9) uninstall_fonts ;;
            i|I) show_about ;;
            q|Q) 
                echo -e "\n${GREEN}感谢使用 LFI！${NC}"
                # 清理临时文件
                [ -d "$LFI_ROOT" ] && rm -rf "$LFI_ROOT" 2>/dev/null
                exit 0
                ;;
            *) 
                echo -e "\n${RED}无效选项: $choice${NC}"
                sleep 1
                ;;
        esac
        
        # 安装完成后停留，让用户选择返回或退出
        if [[ "$choice" =~ ^[0-9]$ ]] || [[ "$choice" =~ ^[iI]$ ]]; then
            echo ""
            echo -ne "${YELLOW}按回车返回主菜单，或输入 q 退出: ${NC}"
            read -r back
            [ "$back" = "q" ] || [ "$back" = "Q" ] && {
                echo -e "\n${GREEN}感谢使用 LFI！${NC}"
                [ -d "$LFI_ROOT" ] && rm -rf "$LFI_ROOT" 2>/dev/null
                exit 0
            }
        fi
    done
}

# -------- 安装场景（代理函数，转发到模块的真实实现） --------
install_scenario() {
    if declare -f _install_scenario > /dev/null 2>&1; then
        _install_scenario "$@"
    else
        log_error "内部错误: installer.sh 未加载"
    fi
}

# -------- 政务公文配置 --------
configure_office_fonts() {
    log_step "政务公文配置"
    
    echo ""
    echo -e "  ${BOLD}本功能自动完成以下操作：${NC}"
    echo -e "  ${CYAN}①${NC} 从 Windows 分区提取公文字体（方正小标宋、仿宋、楷体、黑体）"
    echo -e "  ${CYAN}②${NC} 配置 fontconfig 别名（WPS 乱码修复 + 字体优先级 + 开源替代）"
    echo ""
    
    # 检查是否有已挂载的 Windows 分区
    local win_found=false
    local ntfs_parts
    ntfs_parts=$(lsblk -o NAME,FSTYPE,LABEL,SIZE -pl 2>/dev/null | grep "ntfs" | grep -v "loop")
    
    if [ -n "$ntfs_parts" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local dev
            dev=$(echo "$line" | awk '{print $1}')
            local mnt
            mnt=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -1 | xargs)
            
            if [ -n "$mnt" ] && [ "$mnt" != "" ]; then
                local font_dir=""
                for d in "$mnt/Windows/Fonts" "$mnt"/*/Windows/Fonts; do
                    [ -d "$d" ] && font_dir="$d" && break
                done
                if [ -n "$font_dir" ]; then
                    win_found=true
                    echo -e "  ${GREEN}✓${NC} 检测到 Windows 分区: ${dev}"
                    
                    echo ""
                    echo -e "  ${BOLD}提取公文字体...${NC}"
                    local gov_count=0
                    for target in "fzxbs.ttf" "fzxbsj.ttf" "FZXiaoBiaoSong.ttf" "FZXiaoBiaoSong-B05S.ttf" "FZXBSJW.ttf" "simfang.ttf" "simkai.ttf" "simhei.ttf" "simsun.ttc" "msyh.ttc"; do
                        local found_file
                        found_file=$(find "$font_dir" -maxdepth 1 -name "$target" -type f 2>/dev/null | head -1)
                        if [ -n "$found_file" ]; then
                            cp "$found_file" "$FONT_DIR_USER/" 2>/dev/null || true
                            [ "$HAS_ROOT" = true ] && sudo cp "$found_file" "$FONT_DIR_SYSTEM/" 2>/dev/null || true
                            echo -e "    ${GREEN}✓${NC} $(basename $found_file)"
                            ((gov_count++))
                        fi
                    done
                    echo -e "  ${GREEN}已提取 ${gov_count} 个公文字体文件${NC}"
                    break
                fi
            fi
        done <<< "$ntfs_parts"
    fi
    
    if [ "$win_found" = false ]; then
        echo -e "  ${YELLOW}⚠${NC} 未检测到 Windows 分区，跳过字体提取"
        echo -e "  ${YELLOW}⚠${NC} fontconfig 配置将仅使用已安装的开源字体"
    fi
    
    # 配置三部曲
    echo ""
    echo -e "  ${BOLD}配置 fontconfig 映射...${NC}"
    echo ""
    configure_font_priority
    fix_wps_fonts
    configure_fontconfig_alias
    
    refresh_cache
    log_info "政务公文配置完成！"
}

install_all() {
    log_step "全部安装"
    install_scenario "zh-cn"
    install_scenario "coding"
    install_scenario "design"
    log_info "全部场景安装完成！"
}

extract_windows_fonts() {
    if declare -f _extract_windows_fonts > /dev/null 2>&1; then
        _extract_windows_fonts
    else
        log_error "内部错误: extract-win.sh 未加载"
    fi
}

install_opensource_alternative() {
    log_step "安装开源替代方案"
    install_scenario "zh-cn"
    install_scenario "coding"
    install_scenario "design"
    log_info "开源替代安装完成！"
}

configure_fontconfig() {
    if declare -f _configure_fontconfig > /dev/null 2>&1; then
        _configure_fontconfig
    else
        log_error "内部错误: config.sh 未加载"
    fi
}

show_installed_fonts() {
    log_step "已安装字体"
    echo ""
    
    # 统计
    local total
    total=$(fc-list | wc -l)
    local zh
    zh=$(fc-list :lang=zh 2>/dev/null | wc -l)
    
    echo -e "  ${BLUE}系统字体总数:${NC} ${BOLD}${total}${NC}"
    echo -e "  ${BLUE}中文字体数量:${NC} ${BOLD}${zh}${NC}"
    echo ""
    
    echo -e "  ${BOLD}常用字体清单:${NC}"
    echo ""
    
    # 显示中文字体分组
    echo -e "  ${BLUE}■ 中文字体:${NC}"
    fc-list :lang=zh -f "    %{file}\n" 2>/dev/null | sort -u | while read f; do
        name=$(fc-list "$f" -f "%{family[0]}\n" 2>/dev/null | head -1)
        [ -n "$name" ] && echo -e "    ${WHITE}$name${NC}"
    done | sort -u | head -20
    
    echo ""
    echo -e "  ${BLUE}■ 等宽/编程字体:${NC}"
    for font in "JetBrains Mono" "Fira Code" "Cascadia Code" "Source Code Pro" "Monaco" "Consolas" "Hack" "DejaVu Sans Mono"; do
        count=$(fc-list "$font" 2>/dev/null | wc -l)
        [ "$count" -gt 0 ] && echo -e "    ${GREEN}✓${NC} ${font}" || echo -e "    ${RED}✗${NC} ${font}"
    done
    
    echo ""
    echo -e "  ${YELLOW}提示: 使用 fc-list 查看全部字体${NC}"
}

uninstall_fonts() {
    log_step "卸载字体"
    echo ""
    echo -e "  ${YELLOW}此操作将删除 LFI 安装的自定义字体${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} 删除系统字体目录: ${FONT_DIR_SYSTEM}"
    echo -e "  ${CYAN}[2]${NC} 删除用户字体目录: ${FONT_DIR_USER}"
    echo -e "  ${CYAN}[3]${NC} 重置 fontconfig 配置"
    echo -e "  ${CYAN}[4]${NC} 全部清理"
    echo -e "  ${CYAN}[b]${NC} 返回"
    echo ""
    echo -ne "  ${BOLD}请选择: ${NC}"
    read -r uc
    
    case "$uc" in
        1|2|3|4)
            [ "$HAS_ROOT" = false ] && echo -e "  ${YELLOW}需要root权限执行部分操作${NC}"
            echo -ne "  ${RED}确认? (y/N): ${NC}"
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                [ "$uc" = "1" ] || [ "$uc" = "4" ] && [ "$HAS_ROOT" = true ] && {
                    rm -rf "$FONT_DIR_SYSTEM" 2>/dev/null
                    log_info "已删除: $FONT_DIR_SYSTEM"
                }
                [ "$uc" = "1" ] || [ "$uc" = "4" ] && [ "$HAS_ROOT" = false ] && {
                    log_warn "跳过系统目录（需要root）"
                }
                [ "$uc" = "2" ] || [ "$uc" = "4" ] && {
                    rm -rf "$FONT_DIR_USER" 2>/dev/null
                    log_info "已删除: $FONT_DIR_USER"
                }
                [ "$uc" = "3" ] || [ "$uc" = "4" ] && {
                    rm -f /etc/fonts/local.conf.lfi 2>/dev/null
                    rm -rf "$FONT_CACHE_DIR" 2>/dev/null
                    log_info "已重置 fontconfig 缓存"
                }
                fc-cache -f 2>/dev/null
                log_info "字体缓存已刷新"
            else
                log_info "已取消"
            fi
            ;;
        b|B) return ;;
        *) log_warn "无效选项" ;;
    esac
}

show_about() {
    print_header "关于 LFI" "$PURPLE"
    echo ""
    echo -e "  ${BOLD}Linux Font Installer${NC} v${LFI_VERSION}"
    echo ""
    echo -e "  ${BLUE}项目地址:${NC} https://github.com/${REPO}"
    echo -e "  ${BLUE}作者:${NC} sinyche"
    echo ""
    log_step "许可说明"
    echo ""
    echo -e "  ${WHITE}本工具自身使用 MIT 许可开源。${NC}"
    echo ""
    echo -e "  本工具安装的字体分为三类："
    echo ""
    echo -e "  ${GREEN}① 开源字体${NC}"
    echo -e "     霞鹜文楷 (OFL) / 得意黑 (OFL)"
    echo -e "     思源系列 (OFL) / JetBrains Mono (OFL)"
    echo -e "     Fira Code (OFL) / Nerd Fonts (MIT)"
    echo -e "     → 可自由使用和分发"
    echo ""
    echo -e "  ${YELLOW}② Windows 提取字体${NC}"
    echo -e "     微软雅黑 / 宋体 / 黑体 等"
    echo -e "     → 从您已有的 Windows 系统提取"
    echo -e "     → 仅限您个人设备使用"
    echo -e "     → 本工具只提供提取脚本，不分发字体文件"
    echo ""
    echo -e "  ${YELLOW}③ 商业字体引导${NC}"
    echo -e "     方正字库 / 华文字库 等"
    echo -e "     → 仅提供官方购买链接引导"
    echo -e "     → 请购买正版授权后使用"
    echo ""
    log_step "致谢"
    echo ""
    echo -e "  感谢所有开源字体的作者和贡献者！"
    echo ""
}

# -------- 主函数 --------
main() {
    echo -e "\033[2J\033[H"
    echo ""
    echo -e "${BOLD}${BLUE}   ╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}   ║     Linux Font Installer ${LFI_VERSION}           ║${NC}"
    echo -e "${BOLD}${BLUE}   ║     一行命令，搞定 Linux 字体问题        ║${NC}"
    echo -e "${BOLD}${BLUE}   ╚═══════════════════════════════════════════╝${NC}"
    echo ""
    detect_system
    prepare_env
    detect_distro
    menu_loop
}
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ ! -f "$0" ] || [[ "$0" == /dev/fd/* ]]; then
    main "$@"
fi
