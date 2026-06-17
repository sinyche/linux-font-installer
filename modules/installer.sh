#!/bin/bash
# ==============================================================
# LFI 安装核心逻辑 — 从自有GitHub Release拉取字体包并安装
# ==============================================================

# -------- 安装一个场景的字体 --------
_install_scenario() {
    local scenario="$1"
    local pack_url="https://github.com/${REPO}/releases/download/${LFI_RELEASE}/lfi-fonts-${scenario}-v1.tar.gz"
    local list_url=$(github_raw "fonts/${scenario}/list.txt")
    
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
        local size=$(du -h "$pack_file" | cut -f1)
        echo -e "${GREEN}${size}${NC}"
        
        echo -ne "  ${BLUE}⟳${NC} 解压中... "
        if tar xzf "$pack_file" -C "$extract_dir" 2>/dev/null; then
            echo -e "${GREEN}完成${NC}"
            
            echo -e "  ${BLUE}⟳${NC} 正在安装字体文件..."
            # 安装所有字体文件 - 最简glob方式
            local count=0
            local skipped=0
            local current=0
            local total=0
            for f in "$extract_dir"/*.ttf "$extract_dir"/*.ttc "$extract_dir"/*.otf "$extract_dir"/*.zip; do
                [ -f "$f" ] && ((total++))
            done
            [ "$total" -eq 0 ] && total=1
            
            for font_file in "$extract_dir"/*.ttf "$extract_dir"/*.ttc "$extract_dir"/*.otf "$extract_dir"/*.zip; do
                [ -f "$font_file" ] || continue
                ((current++))
                local fname
                fname=$(basename "$font_file")
                if [ -f "$FONT_DIR_USER/$fname" ] || ([ "$HAS_ROOT" = true ] && [ -f "$FONT_DIR_SYSTEM/$fname" ]); then
                    ((skipped++))
                    # 显示进度（每5个或最后一个才刷新）
                    if [ $((current % 5)) -eq 0 ] || [ "$current" -eq "$total" ]; then
                        echo -e "\r    检查: ${current}/${total}"
                    fi
                    continue
                fi
                
                # zip文件需要解压
                if [[ "$fname" == *.zip ]]; then
                    local zip_dir="$extract_dir/${fname%.zip}"
                    mkdir -p "$zip_dir"
                    if unzip -q -o "$font_file" -d "$zip_dir" 2>/dev/null; then
                        local zcount=0
                        for inner in "$zip_dir"/*.ttf "$zip_dir"/*.otf; do
                            [ -f "$inner" ] || continue
                            cp "$inner" "$FONT_DIR_USER/" 2>/dev/null
                            [ "$HAS_ROOT" = true ] && sudo cp "$inner" "$FONT_DIR_SYSTEM/" 2>/dev/null
                            ((zcount++))
                        done
                        ((count+=zcount))
                    fi
                else
                    cp "$font_file" "$FONT_DIR_USER/" 2>/dev/null
                    [ "$HAS_ROOT" = true ] && sudo cp "$font_file" "$FONT_DIR_SYSTEM/" 2>/dev/null
                    ((count++))
                fi
                # 显示进度（每5个或最后一个才刷新）
                if [ $((current % 5)) -eq 0 ] || [ "$current" -eq "$total" ]; then
                    echo -e "\r    安装: ${current}/${total}"
                fi
            done
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
