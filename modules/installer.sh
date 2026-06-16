#!/bin/bash
# ==============================================================
# LFI 安装核心逻辑 — 从GitHub拉取开源字体并安装
# ==============================================================

# -------- 安装一个场景的字体 --------
install_scenario() {
    local scenario="$1"
    local list_url=$(github_raw "fonts/${scenario}/list.txt")
    
    log_step "安装 ${scenario} 场景字体"
    
    # 下载字体清单
    local list_content
    list_content=$(curl -fsSL "$list_url" 2>/dev/null) || {
        log_warn "场景 '$scenario' 字体清单暂不可用"
        return
    }
    
    # 创建字体目录
    if [ "$HAS_ROOT" = true ]; then
        mkdir -p "$FONT_DIR_SYSTEM"
    fi
    mkdir -p "$FONT_DIR_USER"
    
    local downloaded=0
    local skipped=0
    
    echo -e "${YELLOW}"
    echo "    下载中... 请耐心等待"
    echo -e "${NC}"
    
    # 逐行解析清单
    # 格式: 名称 | 下载URL | 文件名 | 许可证(可选)
    while IFS='|' read -r name url file license; do
        # 跳过注释和空行
        [[ "$name" =~ ^#.*$ ]] && continue
        [ -z "$name" ] && [ -z "$url" ] && continue
        
        # 去除首尾空格
        name=$(echo "$name" | xargs)
        url=$(echo "$url" | xargs)
        file=$(echo "$file" | xargs)
        
        # 目标路径
        local user_target="$FONT_DIR_USER/$file"
        local sys_target="$FONT_DIR_SYSTEM/$file"
        
        # 检查文件是否已存在
        if [ -f "$sys_target" ] || [ -f "$user_target" ]; then
            echo -e "  ${YELLOW}⏭${NC} ${name} — 已存在，跳过"
            ((skipped++))
            continue
        fi
        
        echo -ne "  ${BLUE}↓${NC} ${name}... "
        
        # 下载（支持zip和ttf/otf）
        local tmp_file="$DOWNLOAD_DIR/$file"
        if curl -fSL --connect-timeout 15 --max-time 120 "$url" -o "$tmp_file" 2>/dev/null; then
            # 如果是zip，解压
            if [[ "$file" == *.zip ]]; then
                unzip -q -o "$tmp_file" -d "$DOWNLOAD_DIR/${file%.zip}" 2>/dev/null
                # 复制所有.ttf/.otf文件
                if [ "$HAS_ROOT" = true ]; then
                    cp "$DOWNLOAD_DIR/${file%.zip}"/*.ttf "$FONT_DIR_SYSTEM/" 2>/dev/null
                    cp "$DOWNLOAD_DIR/${file%.zip}"/*.otf "$FONT_DIR_SYSTEM/" 2>/dev/null
                fi
                cp "$DOWNLOAD_DIR/${file%.zip}"/*.ttf "$FONT_DIR_USER/" 2>/dev/null
                cp "$DOWNLOAD_DIR/${file%.zip}"/*.otf "$FONT_DIR_USER/" 2>/dev/null
                echo -e "${GREEN}完成${NC}"
            else
                if [ "$HAS_ROOT" = true ]; then
                    cp "$tmp_file" "$sys_target"
                fi
                cp "$tmp_file" "$user_target"
                echo -e "${GREEN}完成${NC}"
            fi
            ((downloaded++))
        else
            echo -e "${RED}失败${NC}"
            log_warn "下载失败: $url"
        fi
        
    done <<< "$list_content"
    
    echo ""
    log_info "场景 '${scenario}': ${GREEN}${downloaded}${NC} 个安装, ${YELLOW}${skipped}${NC} 个已存在"
    
    # 刷新缓存
    refresh_cache
}

# -------- 安装开源替代方案（7号菜单） --------
install_opensource_alternative() {
    log_step "开源替代方案说明"
    echo ""
    echo -e "  ${WHITE}本模式安装以下开源字体，替代Windows商业字体：${NC}"
    echo ""
    echo -e "  ${BLUE}Windows 原版${NC}    → ${GREEN}开源替代${NC}"
    echo -e "  ─────────────────────────────"
    echo -e "  微软雅黑          → ${GREEN}得意黑 Smiley Sans${NC}"
    echo -e "  宋体              → ${GREEN}思源宋体 Noto Serif CJK SC${NC}"
    echo -e "  黑体              → ${GREEN}思源黑体 Noto Sans CJK SC${NC}"
    echo -e "  楷体              → ${GREEN}霞鹜文楷 LXGW WenKai${NC}"
    echo -e "  Arial             → ${GREEN}Liberation Sans${NC}"
    echo -e "  Times New Roman   → ${GREEN}Liberation Serif${NC}"
    echo -e "  Courier New       → ${GREEN}Liberation Mono${NC}"
    echo -e "  Consolas          → ${GREEN}JetBrains Mono / Cascadia Code${NC}"
    echo ""
    echo -ne "  ${YELLOW}是否继续安装? (Y/n): ${NC}"
    read -r confirm
    if [ "$confirm" != "n" ] && [ "$confirm" != "N" ]; then
        install_scenario "zh-cn"
        install_scenario "coding"
        # fontconfig映射自动配置
        configure_fontconfig_alias
        log_info "开源替代方案安装完成！"
    else
        log_info "已取消"
    fi
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
