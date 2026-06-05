# proxy: 终端代理管理 wrapper（适用于 zsh / bash）
#
# 安装：把这段加到 ~/.zshrc 或 ~/.bashrc：
#   export PROXY_TOOL_BIN="$HOME/proxy-tool/proxy.py"
#   source "$HOME/proxy-tool/proxy.sh"
#
# 原理：
#   Python 脚本无法修改父 shell 的环境变量。
#   所以让 Python 把 export/unset 命令打印到 stdout，
#   wrapper 函数用 eval 在当前 shell 中执行，从而真正生效。
#   人类可读信息走 stderr，不会被 eval。

proxy() {
    local bin="${PROXY_TOOL_BIN:-$HOME/proxy-tool/proxy.py}"
    if [[ ! -f "$bin" ]]; then
        echo "[proxy] 找不到主程序: $bin" >&2
        echo "[proxy] 请设置 PROXY_TOOL_BIN 环境变量指向 proxy.py" >&2
        return 1
    fi

    # 捕获 stdout（要被 eval 的 shell 命令），stderr 原样透传给用户
    local shell_cmds
    shell_cmds="$(python3 "$bin" "$@")"
    local rc=$?

    if [[ -n "$shell_cmds" ]]; then
        eval "$shell_cmds"
    fi

    return $rc
}

# zsh 补全：让 `proxy <Tab>` 列出已保存的代理名
if [[ -n "$ZSH_VERSION" ]]; then
    _proxy_complete() {
        local bin="${PROXY_TOOL_BIN:-$HOME/proxy-tool/proxy.py}"
        local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/proxy-tool/config.json"
        local builtins=(add list ls rm use unset off status)
        local names=()
        if [[ -f "$cfg" ]]; then
            names=(${(f)"$(python3 -c "import json,sys;d=json.load(open('$cfg'));print('\n'.join(d.get('proxies',{}).keys()))" 2>/dev/null)"})
        fi
        compadd -- "${builtins[@]}" "${names[@]}"
    }
    compdef _proxy_complete proxy 2>/dev/null
fi