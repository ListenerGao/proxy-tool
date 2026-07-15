# ROADMAP

> 本文件是项目真实进度源，记录当前阶段、已完成、进行中、待办、阻塞与最近验证。
> 项目介绍与使用方式见 README.md。

## 当前阶段

稳定维护期：核心功能（多代理配置、一键切换、跨终端自动恢复、Tab 补全、一键安装/卸载）已全部完成并上线，当前只做缺陷修复与小幅健壮性优化。

## 已完成

- 2026-06-05 核心功能上线：Python 主程序 + shell wrapper 双文件架构，add/list/rm/use/off/status 全套命令，一键安装/卸载脚本
- 2026-06-07 跨终端自动恢复上次代理（source 时调用 `__init`），并在 `-h` 帮助中隐藏该内部命令
- 2026-06-18 修复 6 处代码质量和健壮性问题；添加 CLAUDE.md 记录架构约定
- 2026-06-20 清理死代码、补齐 bash 补全；`proxy list` 支持「单 export 多赋值」写法的逐行显示；同步更新 README
- 2026-07-15 四处健壮性修复：config.json 权限收紧至 600、`add` 拒绝内置命令名、配置损坏报错附文件路径、`use` 先落盘再输出 shell 命令（已推送）
- 2026-07-15 新增本 ROADMAP.md（接入 projects 看板自动提取）；README 同步补充命令名限制、600 权限说明与配置损坏 FAQ
- 2026-07-15 修复历史 bug：`proxy --help` / 子命令 `-h` 的 argparse 帮助文本默认打到 stdout 被 wrapper eval 导致 parse error，现强制走 stderr（`_StderrHelpParser`）

## 进行中

- 无

## 待办

- 无

## 阻塞

- 无

## 最近验证

- 2026-07-15 用隔离的 `XDG_CONFIG_HOME` 手动验证：四处修复全部符合预期；回归通过——`proxy <name>` 短语法、`list` 逐行对齐显示、`__init` 正常输出且不出现在 `--help`、stdout 仅含 shell 命令
