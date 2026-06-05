#!/usr/bin/env bash
# proxy-tool 一键卸载脚本
#
# 远程使用：
#   curl -fsSL https://raw.githubusercontent.com/ListenerGao/proxy-tool/main/uninstall.sh | bash
#
# 本地使用：
#   ./uninstall.sh
#
# 可选环境变量：
#   PROXY_TOOL_DIR      安装目录（默认: $HOME/.proxy-tool）
#   PROXY_TOOL_SHELL    指定要清理的 rc 文件
#   PROXY_TOOL_PURGE=1  连同配置文件 ~/.config/proxy-tool 一起删除

set -e

if [ -t 1 ]; then
    BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"
    GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; CYAN="\033[36m"
else
    BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
fi

info()  { printf "${CYAN}[proxy-tool]${RESET} %s\n" "$*"; }
ok()    { printf "${GREEN}[proxy-tool]${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}[proxy-tool]${RESET} %s\n" "$*"; }

INSTALL_DIR="${PROXY_TOOL_DIR:-$HOME/.proxy-tool}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/proxy-tool"

BEGIN_MARK="# >>> proxy-tool >>>"
END_MARK="# <<< proxy-tool <<<"

# ---------- 1. 清理 rc 文件中的配置块 ----------
clean_rc() {
    local rc="$1"
    [ -f "$rc" ] || return 0
    if grep -q "$BEGIN_MARK" "$rc"; then
        info "清理 $rc 中的 proxy-tool 配置..."
        local tmp
        tmp="$(mktemp)"
        awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
            BEGIN { skip = 0 }
            $0 == begin { skip = 1; next }
            skip && $0 == end { skip = 0; next }
            !skip { print }
        ' "$rc" > "$tmp"
        mv "$tmp" "$rc"
        ok "已清理 $rc"
    fi
}

if [ -n "$PROXY_TOOL_SHELL" ]; then
    clean_rc "$PROXY_TOOL_SHELL"
else
    # 同时尝试清理 zsh 和 bash 的 rc
    clean_rc "$HOME/.zshrc"
    clean_rc "$HOME/.bashrc"
    clean_rc "$HOME/.bash_profile"
fi

# ---------- 2. 删除安装目录 ----------
if [ -d "$INSTALL_DIR" ]; then
    info "删除安装目录: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    ok "已删除 $INSTALL_DIR"
else
    warn "安装目录不存在: $INSTALL_DIR (跳过)"
fi

# ---------- 3. 可选：删除用户配置 ----------
if [ "${PROXY_TOOL_PURGE:-0}" = "1" ]; then
    if [ -d "$CONFIG_DIR" ]; then
        info "删除用户配置: $CONFIG_DIR"
        rm -rf "$CONFIG_DIR"
        ok "已删除 $CONFIG_DIR"
    fi
else
    if [ -d "$CONFIG_DIR" ]; then
        warn "保留用户配置: $CONFIG_DIR"
        printf "  ${DIM}如需一并删除，可执行: rm -rf %s${RESET}\n" "$CONFIG_DIR"
        printf "  ${DIM}或重跑卸载脚本时设置: PROXY_TOOL_PURGE=1${RESET}\n"
    fi
fi

echo
printf "${BOLD}${GREEN}✔ proxy-tool 已卸载${RESET}\n"
printf "${DIM}请重新打开终端或执行 'source ~/.zshrc' 让 shell 配置生效。${RESET}\n"