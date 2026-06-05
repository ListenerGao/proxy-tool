#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
proxy: 终端代理管理工具（与 zsh wrapper 配合使用）

配置文件: ~/.config/proxy-tool/config.json
{
  "current": "mp",
  "proxies": {
    "mp": "export https_proxy=http://127.0.0.1:8118;export http_proxy=http://127.0.0.1:8118",
    "vn": "export http_proxy=http://127.0.0.1:10808\\nexport https_proxy=..."
  }
}

约定:
- 所有“需要被 eval 改 shell 环境”的输出，写到 stdout，且只输出 shell 命令。
- 所有给人看的信息(日志/提示/列表)，写到 stderr，避免被 eval。
"""
import argparse
import json
import os
import sys
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "proxy-tool"
CONFIG_FILE = CONFIG_DIR / "config.json"


def log(msg: str = "") -> None:
    """给人看的输出 -> stderr，避免被 wrapper eval。"""
    print(msg, file=sys.stderr)


def emit(shell_cmd: str) -> None:
    """要被 eval 的 shell 命令 -> stdout。"""
    print(shell_cmd)


def load_config() -> dict:
    if not CONFIG_FILE.exists():
        return {"current": None, "proxies": {}}
    try:
        with CONFIG_FILE.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        log(f"[proxy] 配置文件损坏: {e}")
        sys.exit(1)
    data.setdefault("current", None)
    data.setdefault("proxies", {})
    return data


def save_config(cfg: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with CONFIG_FILE.open("w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


# --------- 提取代理脚本里出现过的变量名，用于 unset ---------
PROXY_VARS = [
    "http_proxy", "https_proxy", "all_proxy", "no_proxy",
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
]


def build_unset_cmd(script: str = "") -> str:
    """根据脚本里出现的变量构造 unset；若 script 为空则 unset 全部常见代理变量。"""
    if not script:
        return "unset " + " ".join(PROXY_VARS)
    found = []
    for var in PROXY_VARS:
        if var + "=" in script:
            found.append(var)
    if not found:
        found = PROXY_VARS
    return "unset " + " ".join(found)


# ============ 子命令实现 ============

def cmd_add(args) -> None:
    """proxy add <name> '<script>'  新增/覆盖代理（不切换）。"""
    cfg = load_config()
    script = " ".join(args.script).strip()
    if not script:
        log("[proxy] 用法: proxy add <name> '<export ...>'")
        sys.exit(1)
    cfg["proxies"][args.name] = script
    save_config(cfg)
    log(f"[proxy] 已保存代理 '{args.name}'")


import re
import shutil


# ANSI 颜色：只有 stderr 是 tty 时才上色，避免被重定向时输出乱码
def _supports_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stderr.isatty()


class C:
    if True:  # 占位，下面在运行时按需替换
        pass


def _init_colors():
    on = _supports_color()
    def c(code): return code if on else ""
    C.RESET   = c("\033[0m")
    C.BOLD    = c("\033[1m")
    C.DIM     = c("\033[2m")
    C.GREEN   = c("\033[32m")
    C.CYAN    = c("\033[36m")
    C.YELLOW  = c("\033[33m")
    C.GRAY    = c("\033[90m")
    C.MAGENTA = c("\033[35m")


_init_colors()


_EXPORT_RE = re.compile(r"\s*export\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)")


def _parse_exports(script: str):
    """把 'export A=1;export B=2\\nexport C=3' 解析成 [(KEY, VAL), ...]。
    无法解析的片段以 (None, 原文) 形式返回。"""
    items = []
    # 既支持换行又支持分号分隔
    segments = []
    for line in script.splitlines():
        for seg in line.split(";"):
            seg = seg.strip()
            if seg:
                segments.append(seg)
    for seg in segments:
        m = _EXPORT_RE.match(seg)
        if m:
            items.append((m.group(1), m.group(2).strip().strip("'\"")))
        else:
            items.append((None, seg))
    return items


def cmd_list(args) -> None:
    """proxy list  列出所有代理，并标注当前使用的。"""
    cfg = load_config()
    if not cfg["proxies"]:
        log(f"{C.YELLOW}暂无代理配置{C.RESET}")
        log(f"{C.DIM}可用 'proxy add <name> <export...>' 添加。{C.RESET}")
        return

    current = cfg.get("current")
    term_width = max(40, min(shutil.get_terminal_size((80, 20)).columns, 100))

    # 计算所有 KEY 的最长宽度，便于对齐
    max_key = 0
    parsed_all = {name: _parse_exports(s) for name, s in cfg["proxies"].items()}
    for items in parsed_all.values():
        for k, _ in items:
            if k and len(k) > max_key:
                max_key = len(k)

    # 头部
    title = " PROXY LIST "
    bar = "─" * (term_width - len(title) - 2)
    log(f"{C.BOLD}{C.CYAN}┌─{title}{bar}┐{C.RESET}")

    names = list(cfg["proxies"].keys())
    for idx, name in enumerate(names):
        is_cur = (name == current)
        if is_cur:
            icon = f"{C.GREEN}●{C.RESET}"
            name_str = f"{C.BOLD}{C.GREEN}{name}{C.RESET}"
            tag = f"  {C.GREEN}[current]{C.RESET}"
        else:
            icon = f"{C.GRAY}○{C.RESET}"
            name_str = f"{C.BOLD}{name}{C.RESET}"
            tag = ""

        log(f"{C.CYAN}│{C.RESET} {icon} {name_str}{tag}")

        items = parsed_all[name]
        if not items:
            log(f"{C.CYAN}│{C.RESET}   {C.DIM}(空){C.RESET}")
        else:
            for k, v in items:
                if k is None:
                    log(f"{C.CYAN}│{C.RESET}     {C.DIM}{v}{C.RESET}")
                else:
                    key_pad = k.ljust(max_key)
                    log(f"{C.CYAN}│{C.RESET}     {C.MAGENTA}{key_pad}{C.RESET} {C.DIM}={C.RESET} {C.YELLOW}{v}{C.RESET}")

        # 条目之间留空，最后一项后用底部边框
        if idx < len(names) - 1:
            log(f"{C.CYAN}│{C.RESET}")

    log(f"{C.BOLD}{C.CYAN}└{'─' * (term_width - 1)}┘{C.RESET}")

    if current:
        log(f"{C.DIM}当前使用: {C.RESET}{C.GREEN}{current}{C.RESET}   "
            f"{C.DIM}切换: {C.RESET}proxy <name>   "
            f"{C.DIM}关闭: {C.RESET}proxy off")
    else:
        log(f"{C.DIM}当前未启用代理。切换: {C.RESET}proxy <name>")


def cmd_rm(args) -> None:
    """proxy rm <name>  删除一个代理。"""
    cfg = load_config()
    if args.name not in cfg["proxies"]:
        log(f"[proxy] 不存在: {args.name}")
        sys.exit(1)
    del cfg["proxies"][args.name]
    if cfg.get("current") == args.name:
        cfg["current"] = None
        emit(build_unset_cmd())
    save_config(cfg)
    log(f"[proxy] 已删除 '{args.name}'")


def cmd_use(args) -> None:
    """proxy use <name>  / proxy <name>  切换代理。"""
    cfg = load_config()
    if args.name not in cfg["proxies"]:
        log(f"[proxy] 未找到代理 '{args.name}'。可用 'proxy list' 查看。")
        sys.exit(1)
    script = cfg["proxies"][args.name]
    # 先 unset，避免上一份残留
    emit(build_unset_cmd())
    # 输出新的 export，wrapper 会 eval 它
    emit(script)
    cfg["current"] = args.name
    save_config(cfg)
    log(f"[proxy] 已切换到 '{args.name}'")


def cmd_off(args) -> None:
    """proxy off  关闭代理。"""
    cfg = load_config()
    emit(build_unset_cmd())
    cfg["current"] = None
    save_config(cfg)
    log("[proxy] 已关闭代理")


def cmd_status(args) -> None:
    """proxy status  显示当前代理。"""
    cfg = load_config()
    current = cfg.get("current")
    if not current:
        log("[proxy] 当前未启用代理")
        return
    log(f"[proxy] 当前: '{current}'")
    log(cfg["proxies"].get(current, ""))


# ============ 入口 ============

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="proxy", description="终端代理管理工具")
    sub = p.add_subparsers(dest="cmd")

    sp = sub.add_parser("add", help="新增/覆盖代理：proxy add <name> '<export...>'")
    sp.add_argument("name")
    sp.add_argument("script", nargs=argparse.REMAINDER)
    sp.set_defaults(func=cmd_add)

    sp = sub.add_parser("list", help="列出所有代理")
    sp.set_defaults(func=cmd_list)
    sub.add_parser("ls", help="list 的别名").set_defaults(func=cmd_list)

    sp = sub.add_parser("rm", help="删除代理")
    sp.add_argument("name")
    sp.set_defaults(func=cmd_rm)

    sp = sub.add_parser("use", help="切换代理")
    sp.add_argument("name")
    sp.set_defaults(func=cmd_use)

    sub.add_parser("off", help="关闭代理").set_defaults(func=cmd_off)
    sub.add_parser("status", help="查看当前代理").set_defaults(func=cmd_status)

    return p


def main(argv):
    parser = build_parser()

    # 关键：支持 `proxy mp` 等价于 `proxy use mp`
    known = {"add", "list", "ls", "rm", "use",
             "off", "status", "-h", "--help"}
    if len(argv) >= 1 and argv[0] not in known:
        cfg = load_config()
        if argv[0] in cfg["proxies"]:
            argv = ["use"] + argv

    if not argv:
        parser.print_help(sys.stderr)
        return

    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        parser.print_help(sys.stderr)
        return
    args.func(args)


if __name__ == "__main__":
    main(sys.argv[1:])