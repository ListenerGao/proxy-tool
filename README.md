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

一句话：**Python 不去改环境变量，只负责生成 shell 命令文本，真正的执行交给当前 shell 的 `eval`。**

### 1. 为什么要这么绕

`export` 只影响当前进程和它的子进程。你在终端跑 `python3 proxy.py use mp`，Python 是终端 shell 的**子进程**，它把 `os.environ` 改得天翻地覆，进程一退出也全没了，父 shell 毫无感知。这是 Unix 进程模型的硬约束，绕不过去。

唯一的出路是让**父 shell 自己**执行 `export`。于是分工变成：Python 算出该执行什么，shell 负责执行。

### 2. 通信信道：stdout 传命令，stderr 传人话

这是全项目的地基约定：

- **stdout** —— 只写 `export` / `unset`，给机器 `eval`
- **stderr** —— 所有提示、报错、`list` 的彩色表格，给人看

wrapper 只捕获 stdout，stderr 直接透传到终端：

```sh
shell_cmds="$(python3 "$bin" "$@")"   # $() 只捕获 stdout
local rc=$?
[[ -n "$shell_cmds" ]] && eval "$shell_cmds"
return $rc
```

所以人话原样流到屏幕，命令文本进了 `eval`。**反过来说，stdout 里混进任何一句普通输出，整个工具就会 parse error。**（曾出现过的 bug：argparse 默认把 `--help` 帮助文本打到 stdout，被 `eval` 当成 shell 命令，现已强制改道 stderr。）

另一个关键点：`proxy` 必须是 **shell 函数**，不能是脚本或 alias —— 函数在当前 shell 上下文里运行，`eval` 出来的 `export` 才落在你这个终端上。

### 3. 一次 `proxy mp` 的完整链路

1. 你敲 `proxy mp`，触发 shell 函数
2. 函数调用 `python3 proxy.py mp`
3. 短语法预处理：`mp` 不在内置命令集合里，但存在于配置的 proxies 中 → 参数改写为 `use mp`
4. `cmd_use` 先把 `current = "mp"` **落盘**，再往 stdout 依次输出：
   - `unset http_proxy https_proxy ...`（清掉上一份残留，避免切换时混用）
   - 存储的 export 脚本原文
5. stderr 打一句「已切换到 'mp'」
6. 函数把 stdout 的两行 `eval` 掉，环境变量真正生效

第 4 步「先落盘再输出」是刻意为之：万一写配置失败，程序直接退出，stdout 为空，环境变量原封不动，磁盘状态与 shell 状态不会打架。

### 4. 跨终端恢复：`__init` 隐藏命令

新开的终端是全新进程，环境变量当然是空的。`proxy.sh` 在被 source 时（即每次开终端）自动执行一次 `python3 proxy.py __init`，它读配置里的 `current` 并只输出对应的 export；没有 `current` 就静默不输出。

三个细节：

- `__init` 在程序入口处**提前拦截**，完全不经过 argparse，因此不会出现在 `proxy -h` 里
- 它**只 export、不 unset** —— 新终端本来就干净，多余的 unset 会误伤你手动设置的其他变量
- 它不写 stderr，否则每开一个终端都要被刷一行噪音

### 5. 两个次要机制

**原子写入**：先写 `config.tmp`、`chmod 600`，再用 `Path.replace()` 原子替换。`replace` 在同一文件系统上是原子 rename，避免两个终端同时写把 JSON 写成半截。`600` 是因为代理地址可能带账号密码。

**Tab 补全**：直接 `grep` + `sed` 从 `config.json` 里抠代理名，不启动 Python。补全是高频交互，起一个解释器的 50~100ms 延迟很明显。代价是它依赖 `json.dump(indent=2)` 产生的固定缩进（代理名恰好在 4 空格那一层），序列化参数不能随意改。

### 6. 与 TUN / 全局代理的区别

本质区别：**环境变量是「请应用自觉走代理」，TUN 是「在网络栈层面把流量抢过来」。** 前者是应用层的约定，后者是系统层的强制。

`http_proxy` 这类变量不是内核认的东西，纯粹是约定俗成 —— curl、wget、git、pip、npm 等程序在启动时自己去读它，然后主动把请求发给代理服务器。谁不读，谁就不走代理，内核完全不参与。而 TUN 模式创建一块虚拟网卡并改写路由表，任何进程发出的 IP 包都会被内核路由过去，由代理客户端解析转发，应用毫不知情。

| | 环境变量（本工具） | TUN |
| --- | --- | --- |
| 生效范围 | 只有读该变量的进程，且限于设置了变量的会话 | 全系统所有流量 |
| 支持协议 | 基本只有 HTTP/HTTPS（部分工具支持 `all_proxy` 走 SOCKS） | 任意 IP 流量：UDP、ICMP、游戏、自定义协议 |
| 权限 | 无需 root | 需要管理员权限创建网卡、改路由 |
| 分应用控制 | 天然隔离，这个终端走、那个终端不走 | 需靠代理客户端的进程规则实现，配置复杂 |
| 出问题时 | 最多某个命令连不上 | 路由改错可能整机断网 |
| DNS | 通常仍是本地解析 | 可整个接管，彻底避免 DNS 污染 |
| 痕迹 | 关掉终端就没了 | 系统级持久状态 |

**环境变量方式的典型失效场景：**

- **Docker** —— `docker pull` 由 dockerd 守护进程发起，看不见你终端的变量，需改 daemon 配置
- **GUI 应用** —— 从 Dock / Finder 启动的程序不继承 shell 环境
- **sudo** —— 默认清空环境变量（`env_reset`），`sudo apt update` 不走代理
- **不读变量的程序** —— 如 Java 认的是 `-Dhttp.proxyHost` 而非环境变量
- **UDP / 非 HTTP 协议** —— 完全没辙

**该用哪个？** 不是二选一，取决于场景：终端开发工作（git clone、pip install、curl 调 API、npm）用环境变量更合适 —— 精准、无权限要求、随开随关、不影响其他任何东西，且你能明确知道哪些流量走了代理；全局上网、非 HTTP 协议、管不住的 GUI 程序则只能上 TUN。两者并不冲突，常见做法是 TUN 全局兜底，同时用本工具给特定终端指一个不同的出口。

---

## 项目结构

```
proxy-tool/
├── README.md
├── ROADMAP.md             # 项目进度（当前阶段 / 已完成 / 待办）
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
>
> 代理名不能与内置命令重名（`add / list / ls / rm / use / off / status`），否则短语法 `proxy <name>` 会被内置命令抢占，`add` 时会直接报错。

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

文件权限为 `600`（仅本人可读写），因为代理地址可能包含认证信息（如 `http://user:pass@host:port`）。

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

**Q: 提示「配置文件损坏」怎么办？**
A: 报错信息会给出损坏文件的完整路径和具体原因（通常是手动编辑后 JSON 格式出错）。按提示修复该文件即可；若不想修，删除该文件后用 `proxy add` 重新添加。

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