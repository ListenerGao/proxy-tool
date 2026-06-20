# proxy-tool

一个轻量的终端代理管理工具，用于在 zsh / bash 中**快速切换** HTTP / HTTPS / SOCKS 代理环境变量。

支持：
- 多套代理配置持久化（跨终端、跨会话生效）
- 一键切换：`proxy mp` / `proxy vn`
- 一键关闭：`proxy off`
- 列表显示并标注当前使用的代理
- zsh / bash Tab 补全

---

## 一、原理

子进程（Python 脚本）**无法**修改父 shell 的环境变量，因此本工具采用 **"Python 主程序 + shell wrapper 函数"** 的方案：

1. Python 程序把要执行的 `export` / `unset` 命令打印到 **stdout**
2. 给人看的提示信息打印到 **stderr**
3. shell 中定义一个 `proxy()` 函数，用 `eval "$(python3 proxy.py ...)"` 把 stdout 的命令在**当前 shell** 里执行

这样环境变量才能真正改到你当前终端里。

---

## 项目结构

```
proxy-tool/
├── README.md
├── LICENSE
├── install.sh             # 一键安装入口
├── uninstall.sh           # 一键卸载入口
├── bin/
│   └── proxy.py           # Python 主程序
├── shell/
│   └── proxy.sh           # shell wrapper / zsh / bash 补全
└── docs/                  # 文档与截图（预留）
```

---

## 二、安装

### 方式 A：一键安装（推荐）

```sh
curl -fsSL https://raw.githubusercontent.com/ListenerGao/proxy-tool/main/install.sh | bash
```

或使用 `wget`：

```sh
wget -qO- https://raw.githubusercontent.com/ListenerGao/proxy-tool/main/install.sh | bash
```

脚本会自动完成：
1. 把 `proxy.py` / `proxy.sh` 安装到 `~/.proxy-tool/`
2. 自动检测 `zsh` / `bash`，把配置追加到对应的 `~/.zshrc` 或 `~/.bashrc`（带 `# >>> proxy-tool >>>` 标记，幂等，不会重复）
3. 提示 `source` 命令使其立即生效

安装完成后执行：

```sh
source ~/.zshrc      # 或 source ~/.bashrc
proxy --help
```

可选环境变量（安装前 `export` 即可）：

| 变量 | 作用 | 默认 |
| --- | --- | --- |
| `PROXY_TOOL_DIR`   | 安装目录                  | `$HOME/.proxy-tool` |
| `PROXY_TOOL_REPO`  | 仓库 raw 前缀（自定义 fork） | `https://raw.githubusercontent.com/ListenerGao/proxy-tool/main` |
| `PROXY_TOOL_SHELL` | 指定写入的 rc 文件          | 自动检测 |

### 方式 B：手动安装

#### 1. 放置文件

把仓库中的 `bin/proxy.py` 和 `shell/proxy.sh` 放到任意位置（示例使用 `~/proxy-tool/`）：

```sh
mkdir -p ~/proxy-tool
cp bin/proxy.py   ~/proxy-tool/
cp shell/proxy.sh ~/proxy-tool/

ls ~/proxy-tool/
# proxy.py  proxy.sh
```

#### 2. 加入 shell 配置

在 `~/.zshrc`（或 `~/.bashrc`）末尾追加：

```sh
export PROXY_TOOL_BIN="$HOME/proxy-tool/proxy.py"
source "$HOME/proxy-tool/proxy.sh"
```

#### 3. 让配置生效

```sh
source ~/.zshrc
```

#### 4. 验证

```sh
proxy --help
```

看到命令列表即安装成功。

---

## 三、命令一览

| 命令                          | 作用                                     |
| ----------------------------- | ---------------------------------------- |
| `proxy add <name> '<脚本>'`   | 新增 / 覆盖一个代理配置（不切换）       |
| `proxy list` / `proxy ls`     | 列出所有代理，当前使用的标 `●` + `[current]` |
| `proxy <name>`                | 切换到名为 `<name>` 的代理（简写）       |
| `proxy use <name>`            | 同上，完整写法                           |
| `proxy off`                   | 关闭代理（unset 所有代理环境变量）       |
| `proxy status`                | 查看当前正在使用哪个代理                 |
| `proxy rm <name>`             | 删除一个代理配置                         |

---

## 四、使用示例

### 1. 添加代理

```sh
# 单条规则
proxy add mp 'export https_proxy=http://127.0.0.1:8888;export http_proxy=http://127.0.0.1:8888'

# 多条规则（用 ; 拼接成一行，整体用单引号包住）
proxy add vn 'export http_proxy=http://127.0.0.1:10888;export https_proxy=http://127.0.0.1:10888;export all_proxy=socks5://127.0.0.1:10888'

# 也可以一个 export 带多个变量（值不含空格时合法），效果与上面等价
proxy add cv 'export https_proxy=http://127.0.0.1:7888 http_proxy=http://127.0.0.1:7888 all_proxy=socks5://127.0.0.1:7888'
```

> 同名 `add` 会**覆盖**原有配置。以上三种写法（`;` 分隔、换行分隔、单 `export` 多赋值）都合法，`proxy list` 均会逐行对齐显示。

### 2. 查看列表

```text
$ proxy list
┌─ PROXY LIST ─────────────────────────────────────────────────────────────────┐
│ ● mp  [current]
│     https_proxy = http://127.0.0.1:8888
│     http_proxy  = http://127.0.0.1:8888
│
│ ○ vn
│     http_proxy  = http://127.0.0.1:10888
│     https_proxy = http://127.0.0.1:10888
│     all_proxy   = socks5://127.0.0.1:10888
└──────────────────────────────────────────────────────────────────────────────┘
当前使用: mp   切换: proxy <name>   关闭: proxy off
```

> `●` + `[current]`（绿色高亮）标记的是当前正在使用的代理，`○` 为未启用。实际输出带 ANSI 配色；设置 `NO_COLOR=1` 可关闭颜色。

### 3. 切换代理

```sh
proxy mp           # 简写
proxy use vn       # 完整写法

# 验证
echo $http_proxy
# http://127.0.0.1:10888
```

### 4. 查看当前状态

```sh
$ proxy status
[proxy] 当前: 'vn'
export http_proxy=http://127.0.0.1:10888;export https_proxy=http://127.0.0.1:10888;export all_proxy=socks5://127.0.0.1:10888
```

### 5. 关闭代理

```sh
proxy off

echo $http_proxy   # 应为空
```

### 6. 删除代理

```sh
proxy rm vn
```

---

## 五、Tab 补全（zsh / bash）

输入 `proxy ` 后按 `<Tab>`，会自动列出：
- 内置子命令：`add list ls rm use off status`
- 所有已保存的代理名

zsh 用 `compdef`、bash 用 `complete -F`，两者共用同一套解析逻辑，直接读 `config.json`，不会启动 Python 子进程。

---

## 六、配置文件位置

```
~/.config/proxy-tool/config.json
```

格式：

```json
{
  "current": "mp",
  "proxies": {
    "mp": "export https_proxy=http://127.0.0.1:8888;export http_proxy=http://127.0.0.1:8888",
    "vn": "export http_proxy=http://127.0.0.1:10888;export https_proxy=http://127.0.0.1:10888;export all_proxy=socks5://127.0.0.1:10888"
  }
}
```

可以直接手动编辑（编辑后立即生效，不需要重启 shell；切换时才会重新读取）。

---

## 七、常见问题

**Q: 为什么 `proxy mp` 之后 `echo $http_proxy` 没有内容？**
A: 请确认你**已经 `source proxy.sh`** 并通过 `proxy` 这个 wrapper 函数调用，而不是直接执行 `python3 proxy.py mp`。直接调用 Python 脚本是无法改父 shell 环境变量的。

**Q: 多个终端窗口的代理状态会同步吗？**
A: 会。"当前使用的代理"会写到配置文件，跨终端共享。每次新开终端 `source ~/.zshrc` 时，wrapper 会自动调用一次 `proxy.py __init`，把上次的代理 `export` 在新 shell 里 eval 一遍，因此 **`proxy status` 显示的代理与 `$http_proxy` 等环境变量保持一致**，无需手动再执行 `proxy <name>`。

如果不想要这个自动恢复行为，在 `source proxy.sh` **之前**设置：
```sh
export PROXY_TOOL_AUTOLOAD=0
```

**Q: 如何让 git / curl / npm 等使用代理？**
A: 这些工具大多会自动读取 `http_proxy` / `https_proxy` / `all_proxy` 环境变量，`proxy mp` 后即可直接使用。

**Q: 切换代理时旧变量会清干净吗？**
A: 会。每次 `use` / 切换前都会先 `unset` 全部常见代理变量（`http_proxy / https_proxy / all_proxy / no_proxy` 及其大写形式），避免残留。

---

## 八、卸载

### 方式 A：一键卸载（推荐）

```sh
curl -fsSL https://raw.githubusercontent.com/ListenerGao/proxy-tool/main/uninstall.sh | bash
```

如需连同 `~/.config/proxy-tool` 用户配置一起删除：

```sh
PROXY_TOOL_PURGE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/ListenerGao/proxy-tool/main/uninstall.sh)"
```

### 方式 B：手动卸载

```sh
# 1. 从 ~/.zshrc 删除 # >>> proxy-tool >>> 与 # <<< proxy-tool <<< 之间的整段配置
#    （手动安装时则删除以下两行）
# export PROXY_TOOL_BIN=...
# source .../proxy.sh

# 2. 删除配置文件（可选）
rm -rf ~/.config/proxy-tool

# 3. 删除程序目录
rm -rf ~/.proxy-tool       # 或手动安装时的目录，如 ~/proxy-tool
```