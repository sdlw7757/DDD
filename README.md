# 全功能DD脚本

一款功能强大的 Linux 系统管理脚本，支持系统重装、面板管理、Docker 管理、系统维护等多种功能。

## ✨ 功能特点

- 🚀 **系统重装**：支持 Ubuntu/Debian/CentOS 全系列版本
- 🎯 **面板管理**：宝塔面板、1Panel 面板一键安装/修复/卸载
- 🐳 **Docker 管理**：Docker 安装/卸载/更新及容器管理
- 🛠️ **基础工具**：网络测试、端口扫描、内核优化、命令行美化等
- ⚡ **GitHub 加速**：自动使用 ghproxy 加速下载

## 📦 一键安装

```bash
# 一键安装并运行脚本
curl -o /usr/local/bin/dd.sh https://raw.githubusercontent.com/sdlw7757/dd-script/refs/heads/main/dd.sh && sed -i 's/\r$//' /usr/local/bin/dd.sh && chmod +x /usr/local/bin/dd.sh && y
```

## 🚀 使用方法

```bash
# 安装后直接运行
dd.sh

# 或使用快捷命令
y
```

## 📋 主菜单功能

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | Ubuntu 全系列版本 DD重装 | 支持 18.04/20.04/22.04/24.04 |
| 2 | Debian 全系列版本 DD重装 | 支持 10/11/12/13 |
| 3 | CentOS 全系列版本 DD重装 | 支持 6/7/8 |
| 4 | 宝塔面板管理 | 安装/修复/清理 |
| 5 | 1Panel 面板管理 | 安装/修复/清理 |
| 6 | Docker 一站式管理 | 安装/卸载/更新/容器管理 |
| 7 | 系统信息查询 | CPU/内存/磁盘/网络等 |
| 8 | 系统更新 | 自动切换国内源并更新 |
| 9 | 系统清理 | 清理缓存和日志 |
| 10 | 基础工具 | 详见下方 |
| 00 | 脚本更新 | 自动检测并更新脚本 |
| 0 | 退出脚本 | 返回命令行 |

## 🛠️ 基础工具菜单

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | 安装常用工具 | curl, wget, git, vim, htop 等 |
| 2 | 网络测试 (ping) | 测试网络连通性 |
| 3 | 端口扫描 (nc) | 扫描指定端口 |
| 4 | 查看磁盘使用情况 | df/du 命令 |
| 5 | 三网线路测试 | 电信/联通/移动测速 |
| 6 | 融合怪测评 ★ | 服务器全面性能测试 |
| 7 | 切换系统更新源 | 更换为国内镜像源 |
| 8 | 查看端口占用状态 | 显示所有监听端口 |
| 9 | 开放所有端口 | 开放 1-65535 端口 |
| 10 | 修改SSH连接端口 | 自定义SSH端口 |
| 11 | Linux系统内核参数优化 ★ | 网络/内存/文件描述符优化 |
| 12 | 命令行美化工具 ★ | Powerline/oh-my-zsh |

## 🔧 高级功能

### GitHub 加速配置

```bash
# 临时配置（仅当前终端有效）
export GITHUB_PROXY="https://ghproxy.com/"
dd.sh
```

### 手动更新脚本

```bash
# 脚本更新命令
curl -o /usr/local/bin/dd.sh https://raw.githubusercontent.com/sdlw7757/dd-script/refs/heads/main/dd.sh && sed -i 's/\r$//' /usr/local/bin/dd.sh && chmod +x /usr/local/bin/dd.sh && y
```

## 📝 更新日志

### v1.0.0
- 初始版本发布
- 支持 Ubuntu/Debian/CentOS 系统重装
- 集成宝塔面板和 1Panel 面板管理
- 添加 Docker 一站式管理功能

### v1.1.0
- 添加三网线路测试功能
- 添加融合怪测评功能
- 添加系统内核参数优化
- 添加命令行美化工具

### v1.2.0
- 添加 GitHub 加速支持
- 添加端口占用状态查看
- 添加开放所有端口功能
- 添加修改 SSH 端口功能

## ⚠️ 注意事项

1. 系统重装功能会格式化磁盘，请确保已备份重要数据
2. 修改 SSH 端口后，请使用新端口连接
3. 部分功能需要 root 权限，请使用 sudo 或切换到 root 用户
4. 建议在执行重要操作前备份系统配置

## 📧 联系方式

如有问题或建议，请提交 Issue 或 Pull Request。

---

## 📄 开源协议

```
MIT License

Copyright (c) 2024 sdlw7757

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
