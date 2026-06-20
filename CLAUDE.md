# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

proxy-tool 是一个终端代理管理工具，解决"子进程无法修改父 shell 环境变量"的核心问题。

## 架构核心

**两文件协作模式：**

- `bin/proxy.py` — Python 主程序，处理所有业务逻辑
- `shell/proxy.sh` — Shell wrapper，定义 `proxy()` 函数和 zsh / bash 补全

**stdout/stderr 分工约定（不能打破）：**
- `emit()` → stdout：只输出要被 `eval` 的 shell 命令（`export`、`unset`）
- `log()` → stderr：所有给人看的文字、日志、错误信息

shell wrapper 用 `eval "$(python3 proxy.py ...)"` 执行 stdout 内容，因此任何非 shell 命令进了 stdout 都会导致 eval 报错。

**`proxy <name>` 短语法：** 在 `main()` 中于 argparse 解析前预处理——若 argv[0] 不在已知命令集且存在于配置的 proxies 中，则插入 `use` 前缀转发给 `cmd_use`。

**`__init` 隐藏命令：** 仅由 `proxy.sh` 在 source 时调用（终端启动时自动恢复上次代理）。在 `main()` 入口处提前拦截，完全不经过 argparse，因此不会出现在 `-h` 帮助中。只输出 `export` 脚本，不做 `unset`——新终端只需恢复变量，不应清除其他代理变量。

## 配置文件

```
~/.config/proxy-tool/config.json
```

```json
{
  "current": "mp",
  "proxies": {
    "mp": "export http_proxy=http://127.0.0.1:8888;export https_proxy=http://127.0.0.1:8888"
  }
}
```

## 本地验证

手动测试 Python 脚本（不经过 wrapper，stdout 会打到终端而非 eval）：

```sh
python3 bin/proxy.py list
python3 bin/proxy.py --help
python3 bin/proxy.py add test 'export http_proxy=http://127.0.0.1:9999'
python3 bin/proxy.py use test   # stdout 会显示 export 命令，而非真正设置变量
```

测试完整 wrapper 效果（需先安装或手动 source）：

```sh
# 在已安装的环境里
proxy list
proxy add test 'export http_proxy=http://127.0.0.1:9999'
proxy test
echo $http_proxy
proxy off
```

本地测试安装脚本（不需要网络，会从当前目录复制文件）：

```sh
./install.sh
```

## 发布流程

更新后推送到 GitHub main 分支，install.sh 从 raw.githubusercontent.com 拉取，用户执行：

```sh
curl -fsSL https://raw.githubusercontent.com/ListenerGao/proxy-tool/main/install.sh | bash
```

## 实现细节

**原子写入：** `save_config` 先写 `config.tmp`，再 `Path.replace()` 原子替换为 `config.json`，防止并发写入损坏文件。

**Tab 补全：** zsh（`compdef`）和 bash（`complete -F`）共用 `_proxy_names()`，用 `grep -E '^    "'` + `sed` 直接解析 `config.json`，不启动 Python 子进程。依赖 `json.dump(indent=2)` 产生的固定缩进格式——代理名称条目恰好在 4 空格缩进层。

## 无测试框架

项目无自动化测试。改动后通过上述手动命令验证。修改 `proxy.py` 时重点检查：
1. stdout 有没有混入非 shell 命令的输出
2. `cmd_use` / `cmd_off` / `cmd_rm` 的 `emit()` 调用是否正确
3. `__init` 在 `proxy -h` 中是否仍被隐藏（通过 `main()` 提前拦截实现，与 argparse 无关）
