#!/bin/bash
# ==============================================================
# LFI 菜单系统 — 场景选择 + 操作入口
# ==============================================================

# 被 lfi.sh source 加载，变量和函数已继承

# -------- 渲染标题块 --------
print_header() {
    local title="$1"
    local color="${2:-$BLUE}"
    local width=56
    local pad=$(( (width - ${#title} - 2) / 2 ))
    
    echo ""
    echo -e "${color}   ╔$(printf '═%.0s' $(seq 1 $((width-2))))╗${NC}"
    echo -e "${color}   ║$(printf ' %.0s' $(seq 1 $pad)) ${BOLD}${WHITE}${title}${NC}${color}$(printf ' %.0s' $(seq 1 $((width - pad - ${#title} - 2))))║${NC}"
    echo -e "${color}   ╚$(printf '═%.0s' $(seq 1 $((width-2))))╝${NC}"
    echo ""
}

# -------- 系统状态栏 --------
print_status_bar() {
    echo -e " ${BLUE}系统:${NC} ${OS:-unknown} | ${BLUE}架构:${NC} ${ARCH} | ${BLUE}包管理器:${NC} ${PKG_MGR}"
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
    echo -e "      ${WHITE}霞鹜文楷 / 得意黑 / 思源系列 / 开源中文字体${NC}\n"
    echo -e "  ${CYAN}[2]${NC}  📄  ${BOLD}办公文档（WPS / 政务公文）${NC}"
    echo -e "      ${WHITE}仿宋/楷体开源替代 / WPS符号字体修复 / fontconfig映射${NC}\n"
    echo -e "  ${CYAN}[3]${NC}  💻  ${BOLD}编程开发${NC}"
    echo -e "      ${WHITE}JetBrains Mono / Fira Code / Cascadia Code / Nerd Fonts${NC}\n"
    echo -e "  ${CYAN}[4]${NC}  🎨  ${BOLD}设计师 / 创意场景${NC}"
    echo -e "      ${WHITE}免费可商用字体合集${NC}\n"
    echo -e "  ${CYAN}[5]${NC}  📦  ${BOLD}全部安装（推荐）${NC}\n"
    echo -e "  ${YELLOW}━━━━ 补充功能 ━━━━${NC}\n"
    echo -e "  ${CYAN}[6]${NC}  🪟  ${BOLD}从 Windows 提取字体${NC}"
    echo -e "      ${WHITE}从双系统/虚拟机/Wine中提取微软字体到本机${NC}\n"
    echo -e "  ${CYAN}[7]${NC}  ⚡  ${BOLD}仅安装开源替代方案${NC}"
    echo -e "      ${WHITE}用开源字体替代Windows商业字体，无需Windows也可用${NC}\n"
    echo -e "  ${CYAN}[8]${NC}  🔧  ${BOLD}配置 fontconfig 映射${NC}"
    echo -e "      ${WHITE}修复WPS乱码 / 设置字体优先级 / 配置别名${NC}\n"
    echo -e "  ${YELLOW}━━━━ 工具 ━━━━${NC}\n"
    echo -e "  ${CYAN}[9]${NC}  🔍  ${BOLD}查看已安装字体${NC}"
    echo -e "  ${CYAN}[0]${NC}  🗑️   ${BOLD}卸载 / 重置字体${NC}"
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
            1) install_scenario "zh-cn" ;;
            2) install_scenario "office" ;;
            3) install_scenario "coding" ;;
            4) install_scenario "design" ;;
            5) install_all ;;
            6) extract_windows_fonts ;;
            7) install_opensource_alternative ;;
            8) configure_fontconfig ;;
            9) show_installed_fonts ;;
            0) uninstall_fonts ;;
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

# -------- 安装场景（占位，由installer.sh覆盖） --------
install_scenario() {
    # 实际实现在 installer.sh 中
    log_error "内部错误: installer.sh 未加载"
}

install_all() {
    log_step "全部安装"
    install_scenario "zh-cn"
    install_scenario "office"
    install_scenario "coding"
    install_scenario "design"
    log_info "全部场景安装完成！"
}

extract_windows_fonts() {
    log_error "内部错误: extract-win.sh 未加载"
}

install_opensource_alternative() {
    log_step "安装开源替代方案"
    install_scenario "zh-cn"
    install_scenario "coding"
    install_scenario "design"
    log_info "开源替代安装完成！"
}

configure_fontconfig() {
    log_error "内部错误: config.sh 未加载"
}

show_installed_fonts() {
    log_step "已安装字体"
    echo ""
    
    # 统计
    local total=$(fc-list | wc -l)
    local zh=$(fc-list :lang=zh 2>/dev/null | wc -l)
    
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
