# AnyTLS Tiny Installer

低内存 NAT 小鸡友好版 AnyTLS-Go 一键安装脚本。

本脚本是为 **64MB / 128MB 内存的小型 NAT VPS、容器小鸡、IPv4 NAT 小鸡** 准备的极简安装脚本。  
相比常见一键脚本，它尽量减少依赖，不使用 `jq`、`python3`，适合资源很小的 Debian / Ubuntu / Alpine 环境。

## 特点

- 支持 Debian / Ubuntu / Alpine
- 支持 systemd 开机自启
- 支持 Alpine OpenRC
- 支持 amd64 / arm64
- 不依赖 jq
- 不依赖 python3
- 默认安装 AnyTLS-Go v0.0.11
- 安装完成后输出 NekoBox 可直接导入的 `anytls://` 节点链接
- 特别适合 NAT 小鸡端口转发场景

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xaceflyer/anytls-tiny-installer/main/anytls.sh)
```

脚本会提示输入监听端口和密码。  
如果留空密码，脚本会自动生成一个随机密码。

## 推荐安装方式

建议直接指定端口和密码，避免交互输入：

```bash
PORT=31918 PASSWORD='your_strong_password' bash <(curl -fsSL https://raw.githubusercontent.com/xaceflyer/anytls-tiny-installer/main/anytls.sh)
```

其中：

- `PORT` 是服务器内部监听端口
- `PASSWORD` 是 AnyTLS 密码

## NAT 小鸡使用说明

AnyTLS-Go 服务端监听的是 **TCP**，不是 UDP。

因此 NAT 面板里必须添加 TCP 端口转发规则。

### 情况一：外部端口和内部端口一致

如果 NAT 面板是：

```text
TCP 外部端口 31918 -> 内部端口 31918
```

则运行：

```bash
PORT=31918 PASSWORD='your_strong_password' bash <(curl -fsSL https://raw.githubusercontent.com/xaceflyer/anytls-tiny-installer/main/anytls.sh)
```

客户端填写：

```text
地址：服务器 IP 或域名
端口：31918
密码：your_strong_password
协议：AnyTLS
```

脚本安装完成后会输出类似：

```text
anytls://your_strong_password@1.2.3.4:31918/?insecure=1
```

可直接复制到 NekoBox 等客户端导入。

### 情况二：外部端口和内部端口不一致

如果 NAT 面板是：

```text
TCP 外部端口 37286 -> 内部端口 31918
```

则运行：

```bash
EXTERNAL_PORT=37286 PORT=31918 PASSWORD='your_strong_password' bash <(curl -fsSL https://raw.githubusercontent.com/xaceflyer/anytls-tiny-installer/main/anytls.sh)
```

其中：

- `PORT=31918`：服务器内部监听端口
- `EXTERNAL_PORT=37286`：客户端实际连接的外部端口

客户端填写：

```text
地址：服务器 IP 或域名
端口：37286
密码：your_strong_password
协议：AnyTLS
```

脚本安装完成后会输出类似：

```text
anytls://your_strong_password@1.2.3.4:37286/?insecure=1
```

## NekoBox 导入

安装完成后，脚本会用红色字体输出一条节点链接：

```text
anytls://password@server-ip:port/?insecure=1
```

复制整行，在 NekoBox / NekoRay / sing-box 类客户端中从剪贴板导入即可。

如果客户端无法连接，请检查客户端是否需要手动开启：

```text
允许不安全
跳过证书验证
insecure
```

## 常用命令

查看服务状态：

```bash
systemctl status anytls --no-pager
```

重启服务：

```bash
systemctl restart anytls
```

查看监听端口：

```bash
ss -lntp | grep anytls
```

或：

```bash
ss -lntp | grep 31918
```

查看日志：

```bash
journalctl -u anytls --no-pager -n 50
```

## 修改端口或密码

编辑 systemd 服务文件：

```bash
nano /etc/systemd/system/anytls.service
```

找到这一行：

```bash
ExecStart=/usr/local/bin/anytls-server -l 0.0.0.0:31918 -p your_strong_password
```

修改端口或密码后执行：

```bash
systemctl daemon-reload
systemctl restart anytls
systemctl status anytls --no-pager
```

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xaceflyer/anytls-tiny-installer/main/anytls.sh) uninstall
```

## 排错

### 1. 客户端连接不上

优先检查 NAT 面板里的端口转发规则。

AnyTLS-Go 使用的是 TCP，因此必须是：

```text
TCP 外部端口 -> 内部端口
```

不要误设成 UDP。

错误示例：

```text
UDP 31918 -> 31918
```

正确示例：

```text
TCP 31918 -> 31918
```

### 2. apt install 被 Killed

这通常是内存太小导致 OOM。  
64MB 内存的小鸡尤其容易出现这个问题。

建议：

- 不要反复 `apt upgrade`
- 尽量使用本脚本的极简依赖安装方式
- 如果服务商允许，先添加 swap
- 如果不允许添加 swap，尽量使用已经预装 `curl` 和 `unzip` 的系统

### 3. reboot 报错

部分容器小鸡执行 `reboot` 时可能出现：

```text
Failed to connect to system scope bus via local transport
```

这通常是容器环境限制。  
建议在服务商面板里点击 Restart / Reboot。

### 4. crontab 不存在

本脚本优先使用 systemd 或 OpenRC 做开机自启，不依赖 crontab。

## 免责声明

本项目仅用于学习和个人网络环境测试。  
请遵守当地法律法规以及服务商使用条款。  
使用本脚本造成的任何后果由使用者自行承担。

## 致谢

本脚本基于实际低内存 NAT VPS 环境排障经验整理而成。  
AnyTLS-Go 项目归其原作者所有。
