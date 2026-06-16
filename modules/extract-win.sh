#!/bin/bash
# ==============================================================
# LFI Windows字体提取模块
# ==============================================================
# 从Windows双系统/Wine/虚拟机中提取字体并安装到Linux
# 本模块不存储任何字体文件，仅提供提取脚本
# ==============================================================

# -------- Windows字体清单（需要提取的目标） --------
declare -A WIN_FONT_MAP=(
    # 字体显示名 | 文件名(SHA256校验用)
    ["微软雅黑"]="msyh.ttc|msyhbd.ttc|msyhl.ttc"
    ["宋体/新宋体"]="simsun.ttc|simsunb.ttf"
    ["黑体"]="simhei.ttf"
    ["楷体"]="simkai.ttf"
    ["仿宋"]="simfang.ttf"
    ["Arial"]="arial.ttf|arialbd.ttf|arialbi.ttf|ariali.ttf"
    ["Times New Roman"]="times.ttf|timesbd.ttf|timesbi.ttf|timesi.ttf"
    ["Courier New"]="cour.ttf|courbd.ttf|courbi.ttf|couri.ttf"
    ["Verdana"]="verdana.ttf|verdanab.ttf|verdanai.ttf|verdanaz.ttf"
    ["Tahoma"]="tahoma.ttf|tahomabd.ttf"
    ["Segoe UI"]="segoeui.ttf|segoeuib.ttf|segoeuii.ttf|segoeuiz.ttf"
    ["Consolas"]="consola.ttf|consolab.ttf|consolai.ttf|consolaz.ttf"
    ["微软雅黑 Light"]="msyhl.ttc"
)

# -------- 主入口：提取Windows字体 --------
extract_windows_fonts() {
    log_step "从 Windows 提取字体"
    
    # 1. 检测Windows位置
    if ! find_windows_font_dir; then
        return
    fi
    
    # 2. 选择提取策略
    echo ""
    echo -e "  ${BOLD}选择提取方式：${NC}\n"
    echo -e "  ${CYAN}[1]${NC}  ${BOLD}按需提取${NC} — 只提取Linux缺少的Windows字体（推荐）"
    echo -e "  ${CYAN}[2]${NC}  ${BOLD}全部提取${NC} — 提取Windows Fonts目录下所有字体"
    echo -e "  ${CYAN}[3]${NC}  ${BOLD}自定义选择${NC} — 勾选需要的字体"
    echo -e "  ${CYAN}[b]${NC}  返回"
    echo ""
    echo -ne "  ${BOLD}请选择 [1-3/b]: ${NC}"
    read -r ew_choice
    
    case "$ew_choice" in
        1) extract_on_demand ;;
        2) extract_all ;;
        3) extract_custom ;;
        b|B) return ;;
        *) log_warn "无效选项" ;;
    esac
}

# -------- 查找Windows字体目录 --------
find_windows_font_dir() {
    if [ ${#WIN_FONT_DIRS[@]} -eq 0 ]; then
        echo ""
        echo -e "  ${YELLOW}未自动检测到 Windows 字体目录。${NC}"
        echo ""
        echo -e "  常见位置:"
        echo -e "    • ${WHITE}/mnt/Windows/Windows/Fonts${NC} (双系统)"
        echo -e "    • ${WHITE}/run/media/用户名/Windows/Windows/Fonts${NC} (双系统)"
        echo -e "    • ${WHITE}~/.wine/drive_c/windows/Fonts${NC} (Wine)"
        echo -e "    • ${WHITE}$HOME/.local/share/wineprefixes/default/drive_c/windows/Fonts${NC}"
        echo ""
        echo -e "  ${CYAN}[1]${NC} 手动输入路径"
        echo -e "  ${CYAN}[2]${NC} 挂载Windows分区 (需要root)"
        echo -e "  ${CYAN}[b]${NC} 返回"
        echo ""
        echo -ne "  ${BOLD}请选择: ${NC}"
        read -r fw_choice
        
        case "$fw_choice" in
            1)
                echo -ne "  输入字体目录路径: "
                read -r custom_path
                if [ -d "$custom_path" ] && ls "$custom_path"/*.ttf &>/dev/null 2>&1; then
                    WIN_FONT_DIRS=("$custom_path")
                    WIN_AVAILABLE=true
                    echo -e "  ${GREEN}已找到字体: $(ls "$custom_path"/*.{ttf,ttc,otf} 2>/dev/null | wc -l)个${NC}"
                else
                    log_error "路径无效或没有找到字体文件"
                    return 1
                fi
                ;;
            2)
                mount_windows_partition || return 1
                ;;
            b|B) return 1 ;;
            *) log_warn "无效选项"; return 1 ;;
        esac
    else
        echo ""
        echo -e "  ${GREEN}检测到 Windows 字体目录:${NC}"
        local i=1
        for d in "${WIN_FONT_DIRS[@]}"; do
            local count=$(find "$d" -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" 2>/dev/null | wc -l)
            echo -e "  ${CYAN}[$i]${NC} ${WHITE}$d${NC} (${count}个字体文件)"
            ((i++))
        done
        echo ""
        
        # 如果有多个位置，让用户选择
        if [ ${#WIN_FONT_DIRS[@]} -gt 1 ]; then
            echo -ne "  ${BOLD}选择源目录 [1-${#WIN_FONT_DIRS[@]}]: ${NC}"
            read -r idx
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#WIN_FONT_DIRS[@]}" ]; then
                SELECTED_WIN_DIR="${WIN_FONT_DIRS[$((idx-1))]}"
            else
                SELECTED_WIN_DIR="${WIN_FONT_DIRS[0]}"
            fi
        else
            SELECTED_WIN_DIR="${WIN_FONT_DIRS[0]}"
        fi
        
        echo -e "  ${GREEN}使用: ${SELECTED_WIN_DIR}${NC}"
    fi
    
    return 0
}

# -------- 挂载Windows分区 --------
mount_windows_partition() {
    if [ "$HAS_ROOT" = false ]; then
        log_error "挂载分区需要root权限，请使用 sudo lfi.sh"
        return 1
    fi
    
    echo ""
    echo -e "  ${YELLOW}扫描 Windows 分区...${NC}"
    
    # 查找NTFS分区
    local ntfs_parts
    ntfs_parts=$(lsblk -o NAME,FSTYPE,LABEL,SIZE,MOUNTPOINT -p 2>/dev/null | grep -i "ntfs")
    
    if [ -z "$ntfs_parts" ]; then
        log_error "未找到NTFS分区，请确认Windows已正确关机（非休眠状态）"
        return 1
    fi
    
    echo -e "  ${WHITE}找到的NTFS分区:${NC}"
    echo "$ntfs_parts"
    echo ""
    echo -ne "  ${BOLD}输入分区设备名 (如 /dev/sda2): ${NC}"
    read -r part_dev
    
    if [ -z "$part_dev" ] || [ ! -b "$part_dev" ]; then
        log_error "无效的设备名"
        return 1
    fi
    
    local mount_point="/mnt/windows-lfi"
    mkdir -p "$mount_point"
    
    if mount -t ntfs-3g "$part_dev" "$mount_point" 2>/dev/null || mount "$part_dev" "$mount_point" 2>/dev/null; then
        local font_dir="$mount_point/Windows/Fonts"
        if [ -d "$font_dir" ]; then
            WIN_FONT_DIRS=("$font_dir")
            WIN_AVAILABLE=true
            SELECTED_WIN_DIR="$font_dir"
            echo -e "  ${GREEN}已挂载到 ${mount_point}${NC}"
            echo -e "  ${GREEN}找到 $(ls "$font_dir"/*.{ttf,ttc,otf} 2>/dev/null | wc -l) 个字体文件${NC}"
        else
            log_error "挂载成功但未找到 Windows/Fonts 目录"
            umount "$mount_point" 2>/dev/null
            return 1
        fi
    else
        log_error "挂载失败。可能是Windows未完全关机（启用了快速启动）"
        echo -e "  ${YELLOW}解决方法:${NC}"
        echo -e "  1. 在Windows中运行: ${WHITE}powercfg /h off${NC}"
        echo -e "  2. 完全关机后重试"
        return 1
    fi
}

# -------- 按需提取（只提取Linux缺少的） --------
extract_on_demand() {
    log_step "按需提取 Windows 字体"
    echo -e "  ${WHITE}仅提取当前Linux系统中缺少的Windows常用字体${NC}\n"
    
    local extracted=0
    local skipped=0
    local not_found=0
    
    for font_name in "${!WIN_FONT_MAP[@]}"; do
        # 检查Linux是否已有此字体
        local fc_count=$(fc-list "$font_name" 2>/dev/null | wc -l)
        if [ "$fc_count" -gt 0 ]; then
            echo -e "  ${YELLOW}⏭${NC} ${font_name} — 系统中已存在"
            ((skipped++))
            continue
        fi
        
        # 查找Windows中的字体文件
        local files="${WIN_FONT_MAP[$font_name]}"
        local found_file=""
        
        IFS='|' read -ra file_list <<< "$files"
        for f in "${file_list[@]}"; do
            local win_path="$SELECTED_WIN_DIR/$f"
            if [ -f "$win_path" ]; then
                found_file="$win_path"
                break
            fi
        done
        
        if [ -n "$found_file" ]; then
            echo -ne "  ${GREEN}→${NC} ${font_name}... "
            install_single_font "$found_file"
            echo -e "${GREEN}✓${NC}"
            ((extracted++))
        else
            echo -e "  ${RED}✗${NC} ${font_name} — 未在Windows目录中找到"
            ((not_found++))
        fi
    done
    
    echo ""
    log_info "提取完成: ${GREEN}${extracted}${NC} 个安装, ${YELLOW}${skipped}${NC} 个已存在, ${RED}${not_found}${NC} 个未找到"
    refresh_cache
}

# -------- 全部提取 --------
extract_all() {
    log_step "全部提取"
    echo -e "  ${WHITE}提取 Windows Fonts 目录下所有字体${NC}\n"
    
    local total=$(find "$SELECTED_WIN_DIR" \( -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" \) 2>/dev/null | wc -l)
    echo -e "  共发现 ${BLUE}${total}${NC} 个字体文件"
    echo ""
    echo -ne "  ${YELLOW}确认提取全部? (y/N): ${NC}"
    read -r confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "已取消"
        return
    fi
    
    local count=0
    while IFS= read -r -d '' font_file; do
        local fname=$(basename "$font_file")
        # 跳过符号链接字体
        if [ -L "$font_file" ]; then
            continue
        fi
        # 检查是否已安装
        local installed=false
        [ -f "$FONT_DIR_SYSTEM/$fname" ] && installed=true
        [ -f "$FONT_DIR_USER/$fname" ] && installed=true
        
        if [ "$installed" = true ]; then
            continue
        fi
        
        install_single_font "$font_file"
        ((count++))
        
        # 显示进度
        if [ $((count % 20)) -eq 0 ]; then
            echo -ne "  ${BLUE}进度:${NC} ${count}/${total}\r"
        fi
    done < <(find "$SELECTED_WIN_DIR" \( -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" \) -print0 2>/dev/null)
    
    echo ""
    log_info "全部提取完成: 安装了 ${GREEN}${count}${NC} 个字体"
    refresh_cache
}

# -------- 自定义选择 --------
extract_custom() {
    log_step "自定义选择字体"
    
    echo ""
    echo -e "  ${BOLD}可用字体:${NC} (输入数字选择，多个用空格分隔)\n"
    
    # 列出所有Windows字体
    local fonts_list=()
    local i=1
    local font_map_keys=()
    
    for font_name in "${!WIN_FONT_MAP[@]}"; do
        font_map_keys+=("$font_name")
        local files="${WIN_FONT_MAP[$font_name]}"
        local found=""
        
        IFS='|' read -ra file_list <<< "$files"
        for f in "${file_list[@]}"; do
            [ -f "$SELECTED_WIN_DIR/$f" ] && found="$f" && break
        done
        
        local status
        if [ -n "$found" ]; then
            status="${GREEN}可用${NC}"
        else
            status="${RED}未找到${NC}"
        fi
        
        echo -e "  ${CYAN}[$i]${NC} ${font_name} [${status}]"
        fonts_list+=("$found")
        ((i++))
    done
    
    echo ""
    echo -e "  ${CYAN}[a]${NC} 全部选择"
    echo -e "  ${CYAN}[b]${NC} 返回"
    echo ""
    echo -ne "  ${BOLD}请选择: ${NC}"
    read -r custom_sel
    
    if [ "$custom_sel" = "a" ]; then
        for i in "${!font_map_keys[@]}"; do
            local font_name="${font_map_keys[$i]}"
            local files="${WIN_FONT_MAP[$font_name]}"
            IFS='|' read -ra file_list <<< "$files"
            for f in "${file_list[@]}"; do
                [ -f "$SELECTED_WIN_DIR/$f" ] && install_single_font "$SELECTED_WIN_DIR/$f"
            done
        done
        log_info "自定义选择安装完成"
        refresh_cache
    elif [ "$custom_sel" != "b" ]; then
        for idx in $custom_sel; do
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#font_map_keys[@]}" ]; then
                local font_name="${font_map_keys[$((idx-1))]}"
                local files="${WIN_FONT_MAP[$font_name]}"
                IFS='|' read -ra file_list <<< "$files"
                for f in "${file_list[@]}"; do
                    [ -f "$SELECTED_WIN_DIR/$f" ] && install_single_font "$SELECTED_WIN_DIR/$f"
                done
                echo -e "  ${GREEN}✓${NC} ${font_name}"
            fi
        done
        refresh_cache
    fi
}

# -------- 安装单个字体文件 --------
install_single_font() {
    local src="$1"
    local fname=$(basename "$src")
    
    # 系统目录（需要root）
    if [ "$HAS_ROOT" = true ]; then
        cp "$src" "$FONT_DIR_SYSTEM/$fname" 2>/dev/null
    fi
    
    # 用户目录（总是可用）
    mkdir -p "$FONT_DIR_USER"
    cp "$src" "$FONT_DIR_USER/$fname" 2>/dev/null
}

# -------- 提取后自动配置fontconfig别名 --------
# 安装Windows字体后，自动配置字体映射
configure_win_fonts_alias() {
    log_step "配置Windows字体别名"
    
    local config_file
    if [ "$HAS_ROOT" = true ]; then
        config_file="/etc/fonts/local.conf"
    else
        mkdir -p "$HOME/.config/fontconfig"
        config_file="$HOME/.config/fontconfig/fonts.conf"
    fi
    
    cat > "$config_file" << 'FONTCONF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- 字体别名映射：解决程序硬编码字体名的问题 -->
  
  <!-- 西文字体优先（提高英文显示质量） -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Segoe UI</family>
      <family>Microsoft YaHei</family>
      <family>Noto Sans CJK SC</family>
    </prefer>
  </alias>
  
  <alias>
    <family>serif</family>
    <prefer>
      <family>Times New Roman</family>
      <family>SimSun</family>
      <family>Noto Serif CJK SC</family>
    </prefer>
  </alias>
  
  <alias>
    <family>monospace</family>
    <prefer>
      <family>Consolas</family>
      <family>Courier New</family>
      <family>Noto Sans Mono</family>
    </prefer>
  </alias>
  
  <!-- 中文字体映射 -->
  <alias>
    <family>宋体</family>
    <accept><family>SimSun</family></accept>
  </alias>
  
  <alias>
    <family>微软雅黑</family>
    <accept><family>Microsoft YaHei</family></accept>
  </alias>
  
  <alias>
    <family>黑体</family>
    <accept><family>SimHei</family></accept>
  </alias>
  
  <alias>
    <family>楷体</family>
    <accept><family>KaiTi</family></accept>
  </alias>
  
  <alias>
    <family>仿宋</family>
    <accept><family>FangSong</family></accept>
  </alias>
</fontconfig>
FONTCONF
    
    log_info "字体别名配置已写入: $config_file"
    refresh_cache
}
