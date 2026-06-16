#!/bin/bash
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
        local pkg=$(echo "$cmd" | cut -d: -f1)
        echo -ne "  ${BLUE}⟳${NC} 安装 $pkg... "
        if pkg_install "$pkg"; then
            echo -e "${GREEN}完成${NC}"
        else
            echo -e "${YELLOW}跳过（手动安装: sudo $PKG_MGR install $pkg）${NC}"
        fi
    done
    
    # 安装可选字体包（失败不中断）
    for entry in "${font_pkgs[@]}"; do
        local pkg=$(echo "$entry" | cut -d: -f1)
        local alt=$(echo "$entry" | cut -d: -f2)
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
            local pkg=$(echo "$entry" | cut -d: -f1)
            local desc=$(echo "$entry" | cut -d: -f2)
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
