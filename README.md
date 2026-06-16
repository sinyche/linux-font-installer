# Linux Font Installer (LFI)

> **一行命令，搞定 Linux 字体问题**

```bash
bash <(curl -sL https://raw.githubusercontent.com/sinyche/linux-font-installer/main/lfi.sh)
```

> 推荐复制上面这一行粘贴到终端运行。

## 解决的问题

Linux 桌面用户最常见的痛点之一就是字体问题：
- 浏览器/文档显示方块乱码
- WPS 缺少字体无法正常排版
- 开发工具中文字体模糊
- 缺少好看的编程字体
- 双系统下不能用 Windows 的字体

LFI 的目标是用一个交互式菜单，让你按场景选择，自动搞定所有字体问题。

## 功能菜单

```
  [1] 🀄  中文用户必备       — 霞鹜文楷 / 得意黑 / 思源系列
  [2] 📄  办公文档/WPS       — 仿宋/楷体替代 / WPS乱码修复
  [3] 💻  编程开发           — JetBrains Mono / Fira Code / Nerd Fonts
  [4] 🎨  设计师场景         — 免费可商用字体
  [5] 📦  全部安装（推荐）
  [6] 🪟  从Windows提取字体  — 双系统/虚拟机/Wine
  [7] ⚡   开源替代方案       — 无Windows也能用
  [8] 🔧  配置fontconfig映射 — 修复WPS乱码/字体优先级
  [9] 🔍  查看已安装字体
  [0] 🗑️   卸载/重置字体
```

## 工作原理

### 字体来源

| 类别 | 来源 | 许可 |
|------|------|------|
| **开源字体** | GitHub Release 直接下载 | OFL/MIT，自由分发 |
| **Windows 字体** | 从用户本机提取（双系统/Wine） | 用户自有授权，不存储不分发 |
| **商业字体** | 官方购买链接引导 | 请购买正版 |

### 结构

```
lfi.sh                    ← 一键运行入口
modules/
├── menu.sh               ← 交互菜单
├── installer.sh          ← 开源字体安装
├── extract-win.sh        ← Windows字体提取
└── config.sh             ← fontconfig配置
fonts/
├── zh-cn/list.txt        ← 中文字体清单
├── office/list.txt       ← 办公字体清单
├── coding/list.txt       ← 编程字体清单
├── design/list.txt       ← 设计字体清单
└── windows/list.txt      ← Windows提取清单
```

## 开发计划

- [x] 项目架构设计
- [x] 主入口脚本
- [x] 菜单系统
- [x] 安装核心逻辑
- [x] Windows提取模块
- [x] fontconfig配置模块
- [x] 各场景字体清单
- [ ] 字体清单补全（更多开源字体）
- [ ] 网络断点续传
- [ ] 字体预览功能
- [ ] 代理支持

## 许可

- **本工具代码** — MIT
- **分发的开源字体** — 各自许可证（OFL / MIT）
- **Windows提取功能** — 仅提供提取脚本，不包含字体文件

## 致谢

- [霞鹜文楷](https://github.com/lxgw/LxgwWenKai) (OFL)
- [得意黑 Smiley Sans](https://github.com/atelier-anchor/smiley-sans) (OFL)
- [思源系列](https://github.com/adobe-fonts) (OFL)
- [JetBrains Mono](https://www.jetbrains.com/lp/mono/) (OFL)
- [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) (MIT)
