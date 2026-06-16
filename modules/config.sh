#!/bin/bash
# ==============================================================
# LFI fontconfig配置模块 — WPS乱码修复 / 字体优先级 / 别名映射
# ==============================================================

# -------- 主入口 --------
configure_fontconfig() {
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
    if [ "$HAS_ROOT" = true ]; then
        config_file="/etc/fonts/local.conf"
    else
        mkdir -p "$HOME/.config/fontconfig"
        config_file="$HOME/.config/fontconfig/fonts.conf"
    fi
    
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
    if [ "$HAS_ROOT" = true ]; then
        mkdir -p /etc/fonts
        config_file="/etc/fonts/local.conf"
    else
        mkdir -p "$HOME/.config/fontconfig"
        config_file="$HOME/.config/fontconfig/fonts.conf"
    fi
    
    # 检测WPS是否安装
    local wps_found=false
    for wps_bin in wps wpp et wps-office; do
        command -v "$wps_bin" &>/dev/null && wps_found=true && break
    done
    [ -d "/opt/kingsoft" ] || [ -d "/usr/share/kingsoft" ] && wps_found=true
    
    if [ "$wps_found" = true ]; then
        echo -e "  ${GREEN}检测到 WPS Office${NC}"
    else
        echo -e "  ${YELLOW}未检测到 WPS Office，仍将配置通用符号字体映射${NC}"
    fi
    
    # 读取现有配置
    local existing_content=""
    [ -f "$config_file" ] && existing_content=$(cat "$config_file")
    
    # WPS符号字体映射配置
    local wps_config='

  <!-- WPS符号字体映射（解决WPS显示方框/乱码） -->
  <alias>
    <family>Wingdings</family>
    <accept><family>FreeSerif</family></accept>
  </alias>
  <alias>
    <family>Webdings</family>
    <accept><family>FreeSerif</family></accept>
  </alias>
  <alias>
    <family>Symbol</family>
    <accept><family>FreeSerif</family></accept>
  </alias>
  
  <!-- WPS公文常用字体映射 -->
  <alias>
    <family>仿宋_GB2312</family>
    <accept><family>FangSong</family></accept>
  </alias>
  <alias>
    <family>楷体_GB2312</family>
    <accept><family>KaiTi</family></accept>
  </alias>
  <alias>
    <family>小标宋</family>
    <accept><family>Noto Serif CJK SC Bold</family></accept>
  </alias>
  <alias>
    <family>黑体</family>
    <accept><family>SimHei</family></accept>
  </alias>'
    
    # 插入到 fontconfig 根元素内（</fontconfig>之前）
    if echo "$existing_content" | grep -q "WPS符号字体映射"; then
        log_info "WPS配置已存在，跳过"
    else
        # 简单的插入：在 </fontconfig> 之前插入
        local new_content="${existing_content%</fontconfig>}${wps_config}"$'\n</fontconfig>'
        echo "$new_content" > "$config_file"
        log_info "WPS符号字体映射已配置"
    fi
    
    # 确保FreeSerif已安装（Wingdings/Webdings回退用）
    if ! fc-list "FreeSerif" &>/dev/null; then
        echo ""
        echo -e "  ${YELLOW}建议安装 FreeSerif 字体（Wingdings/Webdings 的回退字体）${NC}"
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
}

# -------- 配置开源替代别名 --------
configure_fontconfig_alias() {
    log_step "开源替代字体别名配置"
    
    local config_file
    if [ "$HAS_ROOT" = true ]; then
        config_file="/etc/fonts/local.conf"
    else
        mkdir -p "$HOME/.config/fontconfig"
        config_file="$HOME/.config/fontconfig/fonts.conf"
    fi
    
    local existing_content=""
    [ -f "$config_file" ] && existing_content=$(cat "$config_file")
    
    local alias_config='

  <!-- Windows字体 → 开源替代 映射（由 LFI 配置） -->
  
  <!-- 微软雅黑 → 得意黑（如果已安装） -->
  <alias>
    <family>Microsoft YaHei</family>
    <prefer>
      <family>Smiley Sans</family>
      <family>Noto Sans CJK SC</family>
    </prefer>
  </alias>
  
  <!-- 宋体 → 思源宋体 -->
  <alias>
    <family>SimSun</family>
    <family>NSimSun</family>
    <family>宋体</family>
    <prefer>
      <family>Noto Serif CJK SC</family>
    </prefer>
  </alias>
  
  <!-- 黑体 → 思源黑体 -->
  <alias>
    <family>SimHei</family>
    <family>黑体</family>
    <prefer>
      <family>Noto Sans CJK SC</family>
    </prefer>
  </alias>
  
  <!-- 楷体 → 霞鹜文楷 -->
  <alias>
    <family>KaiTi</family>
    <family>楷体</family>
    <prefer>
      <family>LXGW WenKai</family>
    </prefer>
  </alias>
  
  <!-- 仿宋 → 思源宋体 -->
  <alias>
    <family>FangSong</family>
    <family>仿宋</family>
    <prefer>
      <family>Noto Serif CJK SC</family>
    </prefer>
  </alias>'
    
    if echo "$existing_content" | grep -q "开源替代"; then
        log_info "开源替代别名配置已存在，跳过"
    else
        local new_content="${existing_content%</fontconfig>}${alias_config}"$'\n</fontconfig>'
        echo "$new_content" > "$config_file"
        log_info "开源替代字体别名已配置"
    fi
}
