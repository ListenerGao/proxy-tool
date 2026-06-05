# proxy-tool

一个轻量的终端代理管理工具，用于在 zsh / bash 中**快速切换** HTTP / HTTPS / SOCKS 代理环境变量。

支持：
- 多套代理配置持久化（跨终端、跨会话生效）
- 一键切换：`proxy mp` / `proxy vn`
- 一键关闭：`proxy off`
- 列表显示并标注当前使用的代理
- zsh Tab 补全

---

## 一、原理

子进程（Python 脚本）**无法**修改父 shell 的环境变量，因此本工具采用 **"Python 主程序 + shell wrapper 函数"** 的方案：

1. Python 程序把要执行的 `export` / `unset` 命令打印到 **stdout**
2. 给人看的提示信息打印到 **stderr**
3. shell 中定义一个 `proxy()` 函数，用 `eval "$(python3 proxy.py ...)"` 把 stdout 的命令在**当前 shell** 里执行

这样环境变量才能真正改到你当前终端里。

---

## 二、安装

### 1. 放置文件

把 `proxy.py` 和 `proxy.sh` 放到任意位置（示例使用 `~/proxy-tool/`）：

```sh
ls ~/proxy-tool/
# proxy.py  proxy.sh
```

### 2. 加入 shell 配置

在 `~/.zshrc`（或 `~/.bashrc`）末尾追加：

```sh
export PROXY_TOOL_BIN="$HOME/proxy-tool/proxy.py"
source "$HOME/proxy-tool/proxy.sh"
```

### 3. 让配置生效

```sh
source ~/.zshrc
```

### 4. 验证

```sh
proxy --help
```

看到命令列表即安装成功。

---

## 三、命令一览

| 命令                          | 作用                                     |
| ----------------------------- | ---------------------------------------- |
| `proxy add <name> '<脚本>'`   | 新增 / 覆盖一个代理配置（不切换）       |
| `proxy list` / `proxy ls`     | 列出所有代理，当前使用的前面带 `*`       |
| `proxy <name>`                | 切换到名为 `<name>` 的代理（简写）       |
| `proxy use <name>`            | 同上，完整写法                           |
| `proxy off` / `proxy unset`   | 关闭代理（unset 所有代理环境变量）       |
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
```

> 同名 `add` 会**覆盖**原有配置。

### 2. 查看列表

```sh
$ proxy list
  * 'mp':
        export https_proxy=http://127.0.0.1:8888;export http_proxy=http://127.0.0.1:8888

    'vn':
        export http_proxy=http://127.0.0.1:10888;export https_proxy=http://127.0.0.1:10888;export all_proxy=socks5://127.0.0.1:10888
```

> `*` 标记的是当前正在使用的代理。

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
# 或
proxy unset

echo $http_proxy   # 应为空
```

### 6. 删除代理

```sh
proxy rm vn
```

---

## 五、Tab 补全（zsh）

输入 `proxy ` 后按 `<Tab>`，会自动列出：
- 内置子命令：`add list ls rm use unset off status`
- 所有已保存的代理名

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
A: "当前使用的代理"会写到配置文件，跨终端共享；但每个终端窗口的环境变量**互相独立**，新开窗口需要再执行一次 `proxy <name>`。如想新开终端自动套用上次代理，可在 `~/.zshrc` 末尾添加：
```sh
proxy "$(python3 "$PROXY_TOOL_BIN" status 2>&1 | awk -F"'" '/当前/{print $2}')" 2>/dev/null
```

**Q: 如何让 git / curl / npm 等使用代理？**
A: 这些工具大多会自动读取 `http_proxy` / `https_proxy` / `all_proxy` 环境变量，`proxy mp` 后即可直接使用。

**Q: 切换代理时旧变量会清干净吗？**
A: 会。每次 `use` / 切换前都会先 `unset` 全部常见代理变量（`http_proxy / https_proxy / all_proxy / no_proxy` 及其大写形式），避免残留。

---

## 八、卸载

```sh
# 1. 从 ~/.zshrc 删除以下两行
export PROXY_TOOL_BIN=...
source .../proxy.sh

# 2. 删除配置文件（可选）
rm -rf ~/.config/proxy-tool

# 3. 删除程序目录
rm -rf ~/proxy-tool
```