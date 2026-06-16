#!/bin/bash
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
extract_windows_fonts() {
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
    ntfs_parts=$(lsblk -o NAME,FSTYPE,LABEL,SIZE -p 2>/dev/null | grep "ntfs" | grep -v "loop")
    
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
    
    echo ""
    echo -e "  ${GREEN}找到以下 NTFS 分区：${NC}"
    echo "$ntfs_parts"
    echo ""
    echo -ne "  ${BOLD}输入分区设备名（如 /dev/sda2）或回车自动选择第一个: ${NC}"
    read -r part_dev
    
    if [ -z "$part_dev" ]; then
        part_dev=$(echo "$ntfs_parts" | head -1 | awk '{print $1}')
    fi
    
    local mount_point="/mnt/lfi-win-$$"
    mkdir -p "$mount_point"
    
    echo -ne "  ${BLUE}⟳${NC} 挂载中... "
    if mount -t ntfs-3g "$part_dev" "$mount_point" 2>/dev/null || mount "$part_dev" "$mount_point" 2>/dev/null; then
        echo -e "${GREEN}完成${NC}"
        
        local font_dir="$mount_point/Windows/Fonts"
        if [ -d "$font_dir" ]; then
            install_from_dir "$font_dir"
        else
            # 尝试其他常见路径
            for d in "$mount_point"/*/Windows/Fonts "$mount_point"/Windows/Fonts; do
                [ -d "$d" ] && font_dir="$d" && break
            done
            [ -d "$font_dir" ] && install_from_dir "$font_dir" || log_error "未找到 Fonts 目录"
        fi
        
        echo -ne "  ${BLUE}⟳${NC} 卸载分区... "
        umount "$mount_point" 2>/dev/null && echo -e "${GREEN}完成${NC}" || true
        rmdir "$mount_point" 2>/dev/null
    else
        log_error "挂载失败。Windows 可能未完全关机（启用了快速启动）"
        echo ""
        echo -e "  ${YELLOW}解决方法:${NC}"
        echo -e "  1. 进入 Windows，以管理员身份运行命令提示符"
        echo -e "  2. 执行: ${WHITE}powercfg /h off${NC}"
        echo -e "  3. 完全关机后再试"
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
    
    local count=$(find "$user_path" \( -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" \) 2>/dev/null | wc -l)
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
                log_error "挂载 ISO 失败，需要 root 权限"
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
        local fname=$(basename "$f")
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
            local size=$(du -h "$found_path" | cut -f1)
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
    local fname=$(basename "$src")
    
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
