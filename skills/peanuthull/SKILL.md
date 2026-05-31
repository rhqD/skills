---
name: peanuthull
description: 管理花生壳内网穿透映射，包含映射增删改查、连通性测试、域名列表、端口检测、账号信息
allowed-tools: [Read, Write, Bash, Grep, Glob]
---

# 花生壳映射管理

## 触发条件

- 当用户提到花生壳、内网穿透、映射管理、hsk 时触发
- 当用户需要查看/创建/修改/删除花生壳映射时触发
- 当用户需要测试映射连通性时触发

## Instructions

所有操作通过 `skills/peanuthull/scripts/hsk.sh` 脚本完成。使用前需确保已设置 API Key（支持命令行、环境变量、配置文件三层 fallback）。

### 映射管理

| 操作 | 命令 | 说明 |
|------|------|------|
| 查看映射列表 | `hsk.sh mapping list` | 调用云端 API 列出所有映射 |
| 创建映射 | `hsk.sh mapping create <参数>` | 创建新的内网穿透映射 |
| 更新映射 | `hsk.sh mapping update <domain> <port> <fwtype> <JSON>` | 更新已有映射配置 |
| 删除映射 | `hsk.sh mapping delete <domain> <port> <fwtype>` | 删除指定映射 |
| 启停映射 | `hsk.sh mapping toggle <domain> <port> <fwtype> <on\|off>` | 启用或禁用指定映射 |

**创建映射参数说明**：
- `--domain <域名>` — 外网访问域名
- `--port <端口>` — 映射端口
- `--fwtype <协议>` — 协议类型（1=TCP, 2=HTTP, 3=HTTPS, 4=UDP）
- `--inner-host <内网地址>` — 内网目标主机
- `--inner-port <内网端口>` — 内网目标端口
- `--memo <名称>` — 备注名称（可选）

### 连通性测试

```bash
hsk.sh test <domain> <port>
```

通过 DNS 解析 → TCP 连接 → HTTP 响应三步检测外网映射是否可达。

### 域名与端口

| 操作 | 命令 | 说明 |
|------|------|------|
| 域名列表 | `hsk.sh domain list` | 查询可用域名 |
| 端口检测 | `hsk.sh port check <port>` | 检查端口是否可用 |

### 账号信息

```bash
hsk.sh account info
```

查看用户 ID、映射用量、带宽、流量、到期时间等账号信息。

## Guidelines

- 脚本依赖 `jq` 解析 JSON，首次运行会自动检测并提示安装
- 操作失败时分析错误响应并给出可操作的提示，不要盲目重试
- 删除映射前应向用户确认，因为该操作不可逆
- 列表输出使用表格格式，状态用颜色区分（绿色=正常运行/已启用，红色=已禁用）

## Examples

### 查看所有映射

**输入**: 帮我看看花生壳有哪些映射
**输出**: 执行 `hsk.sh mapping list`，以表格展示所有映射及其状态

### 创建新映射

**输入**: 帮我在花生壳上创建一个映射，把本地的 8080 端口通过 test.example.com 的 80 端口暴露出去
**输出**: 收集必要参数后执行 `hsk.sh mapping create --domain test.example.com --port 80 --fwtype HTTP --inner-host 127.0.0.1 --inner-port 8080`

### 更新映射内网地址

**输入**: 把「我的映射」的内网地址改成 192.168.1.100
**输出**: 执行 `hsk.sh mapping update test.example.com 80 2 '{"servicehost":"192.168.1.100"}'`

### 测试连通性

**输入**: 测试一下 test.example.com:80 能不能通
**输出**: 执行 `hsk.sh test test.example.com 80`，报告 TCP 连通性结果
