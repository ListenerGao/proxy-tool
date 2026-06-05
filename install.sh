#!/usr/bin/env bash
# proxy-tool 一键安装脚本
#
# 远程使用：
#   curl -fsSL https://raw.githubusercontent.com/ListenerGao/proxy-tool/main/install.sh | bash
#
# 本地使用：
#   ./install.sh
#
# 可选环境变量：
#   PROXY_TOOL_DIR    安装目录（默认: $HOME/.proxy-tool）
#   PROXY_TOOL_REPO   仓库 raw 前缀（默认: https://raw.githubusercontent.com/ListenerGao/proxy-tool/main）
#   PROXY_TOOL_SHELL  指定要写入的 rc 文件（默认: 自动检测 zsh/bash）

set -e

# ---------- 颜色 ----------
if [ -t 1 ]; then
    BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"
    GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; CYAN="\033[36m"
else
    BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
fi

info()  { printf "${CYAN}[proxy-tool]${RESET} %s\n" "$*"; }
ok()    { printf "${GREEN}[proxy-tool]${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}[proxy-tool]${RESET} %s\n" "$*"; }
error() { printf "${RED}[proxy-tool]${RESET} %s\n" "$*" >&2; }

# ---------- 配置 ----------
INSTALL_DIR="${PROXY_TOOL_DIR:-$HOME/.proxy-tool}"
REPO_RAW="${PROXY_TOOL_REPO:-https://raw.githubusercontent.com/ListenerGao/proxy-tool/main}"
FILES=("proxy.py" "proxy.sh")

# ---------- 1. 检查依赖 ----------
info "检查依赖..."
if ! command -v python3 >/dev/null 2>&1; then
    error "未找到 python3，请先安装 Python 3。"
    exit 1
fi

if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
else
    error "需要 curl 或 wget 之一，请先安装。"
    exit 1
fi
ok "依赖检查通过（python3 / $DOWNLOADER）"

# ---------- 2. 下载文件 ----------
info "准备安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# 如果当前就在源码目录（本地直接运行），直接复制
if [ -f "./proxy.py" ] && [ -f "./proxy.sh" ]; then
    info "检测到本地源码，直接复制..."
    cp -f ./proxy.py "$INSTALL_DIR/proxy.py"
    cp -f ./proxy.sh "$INSTALL_DIR/proxy.sh"
else
    info "从远程下载: $REPO_RAW"
    for f in "${FILES[@]}"; do
        url="$REPO_RAW/$f"
        dest="$INSTALL_DIR/$f"
        info "  下载 $f ..."
        if [ "$DOWNLOADER" = "curl" ]; then
            if ! curl -fsSL "$url" -o "$dest"; then
                error "下载失败: $url"
                exit 1
            fi
        else
            if ! wget -q "$url" -O "$dest"; then
                error "下载失败: $url"
                exit 1
            fi
        fi
    done
fi

chmod +x "$INSTALL_DIR/proxy.py"
ok "文件已就位: $INSTALL_DIR"

# ---------- 3. 检测 shell rc 文件 ----------
detect_rc() {
    if [ -n "$PROXY_TOOL_SHELL" ]; then
        echo "$PROXY_TOOL_SHELL"
        return
    fi
    # 优先看当前 SHELL 环境变量
    case "${SHELL##*/}" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            else
                echo "$HOME/.bash_profile"
            fi
            ;;
        *)
            # 兜底：哪个存在用哪个
            if [ -f "$HOME/.zshrc" ]; then
                echo "$HOME/.zshrc"
            elif [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            else
                echo "$HOME/.zshrc"
            fi
            ;;
    esac
}

RC_FILE="$(detect_rc)"
info "目标 shell 配置: $RC_FILE"

# ---------- 4. 写入 shell 配置（幂等） ----------
BEGIN_MARK="# >>> proxy-tool >>>"
END_MARK="# <<< proxy-tool <<<"

BLOCK="$BEGIN_MARK
export PROXY_TOOL_BIN=\"$INSTALL_DIR/proxy.py\"
[ -f \"$INSTALL_DIR/proxy.sh\" ] && source \"$INSTALL_DIR/proxy.sh\"
$END_MARK"

touch "$RC_FILE"

if grep -q "$BEGIN_MARK" "$RC_FILE"; then
    info "检测到旧的 proxy-tool 配置，更新中..."
    # 用 awk 替换两个 mark 之间的块
    tmp="$(mktemp)"
    awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v block="$BLOCK" '
        BEGIN { skip = 0 }
        $0 == begin { print block; skip = 1; next }
        skip && $0 == end { skip = 0; next }
        !skip { print }
    ' "$RC_FILE" > "$tmp"
    mv "$tmp" "$RC_FILE"
    ok "已更新 $RC_FILE 中的 proxy-tool 配置"
else
    {
        echo ""
        echo "$BLOCK"
    } >> "$RC_FILE"
    ok "已追加配置到 $RC_FILE"
fi

# ---------- 5. 完成提示 ----------
echo
printf "${BOLD}${GREEN}✔ proxy-tool 安装完成！${RESET}\n"
echo
printf "${BOLD}下一步：${RESET}\n"
printf "  ${DIM}# 让配置立即生效${RESET}\n"
printf "  source %s\n" "$RC_FILE"
echo
printf "${BOLD}快速上手：${RESET}\n"
printf "  proxy add mp 'export http_proxy=http://127.0.0.1:8888;export https_proxy=http://127.0.0.1:8888'\n"
printf "  proxy list\n"
printf "  proxy mp        ${DIM}# 切换${RESET}\n"
printf "  proxy off       ${DIM}# 关闭${RESET}\n"
echo
printf "${DIM}卸载：curl -fsSL %s/uninstall.sh | bash${RESET}\n" "$REPO_RAW"