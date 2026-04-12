# PBS 挂载绿联 NAS（NFS）配置指南

> Proxmox Backup Server + UGREEN NAS NFS 存储配置

---

## 步骤 1：安装 NFS 客户端

在 PBS 服务器上安装 NFS 客户端软件包：

```bash
apt-get install nfs-common
```

---

## 步骤 2：创建挂载点

```bash
mkdir -p /mnt/storage_ugreen
```

---

## 步骤 3：测试手动挂载

```bash
# 手动挂载
mount -t nfs 192.168.2.11:/volume1/storage500GB1 /mnt/storage_ugreen

# 验证挂载
df -h | grep storage_ugreen
ls /mnt/storage_ugreen
```

---

## 步骤 4：配置 systemd 自动挂载

使用 systemd mount/automount 单元实现开机自动挂载。

> 注意：文件名必须与挂载路径严格对应，`/mnt/storage_ugreen` → `mnt-storage_ugreen`

### 4.1 创建 mount 单元

```bash
vi /etc/systemd/system/mnt-storage_ugreen.mount
```

写入以下内容：

```ini
[Unit]
Description=UGREEN NAS NFS Mount
After=network-online.target
Wants=network-online.target

[Mount]
What=192.168.2.11:/volume1/storage500GB1
Where=/mnt/storage_ugreen
Type=nfs
Options=vers=3,tcp,rw,noatime,soft,timeo=30,retrans=3,retry=0,rsize=32768,wsize=32768

[Install]
WantedBy=multi-user.target
```

### 4.2 创建 automount 单元

```bash
vi /etc/systemd/system/mnt-storage_ugreen.automount
```

写入以下内容：

```ini
[Unit]
Description=UGREEN NAS NFS Automount

[Automount]
Where=/mnt/storage_ugreen
TimeoutIdleSec=0

[Install]
WantedBy=multi-user.target
```

### 4.3 创建触发单元

```bash
vi /etc/systemd/system/trigger-ugreen-mount.service
```

写入以下内容：

```ini
[Unit]
Description=Trigger UGREEN NFS Mount
After=mnt-storage_ugreen.automount network-online.target
Wants=mnt-storage_ugreen.automount

[Service]
Type=oneshot
ExecStart=/bin/ls /mnt/storage_ugreen
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

### 4.4 启用并启动

```bash
# 重载 systemd 配置
systemctl daemon-reload

# 启用开机自动挂载
systemctl enable mnt-storage_ugreen.automount

# 启动 automount
systemctl start mnt-storage_ugreen.automount

# 触发一次挂载（访问挂载点即可）
ls /mnt/storage_ugreen
```

### 4.5 验证状态

```bash
systemctl status mnt-storage_ugreen.automount
systemctl status mnt-storage_ugreen.mount
```

### 关键参数说明

| 参数 | 说明 |
|------|------|
| `vers=3` | 使用 NFS v3 协议 |
| `tcp` | 使用 TCP 传输 |
| `soft` | 网络中断时不阻塞，返回错误 |
| `timeo=30` | 超时 30 秒后重试 |
| `retrans=3` | 最多重试 3 次 |
| `retry=0` | 挂载失败不重复尝试 |
| `rsize=32768` | 读块大小 32KB |
| `wsize=32768` | 写块大小 32KB |
| `noatime` | 不更新访问时间，提升性能 |

---

## 步骤 5：创建 PBS Datastore

```bash
# 创建存储目录
mkdir -p /mnt/storage_ugreen/pbs-datastore

# 创建 Datastore
proxmox-backup-manager datastore create storage-ugreen /mnt/storage_ugreen/pbs-datastore

# 设置权限
chown -R backup:backup /mnt/storage_ugreen/pbs-datastore
chmod -R 755 /mnt/storage_ugreen/pbs-datastore
```

### 移除 Datastore（如需）

```bash
proxmox-backup-manager datastore remove storage_ugreen
systemctl restart proxmox-backup
systemctl restart proxmox-backup-proxy
```

---

## 步骤 6：PVE 添加 PBS 存储

路径：**数据中心 → 存储 → 添加 → Proxmox Backup Server**

| 字段 | 填写值 |
|------|--------|
| ID | `nas-backup` |
| 服务器 | PBS 服务器 IP（根据实际情况填写） |
| Datastore | `storage-ugreen` |
| 用户名 | `root@pam`（必须包含 `@pam`） |
| 密码 | PBS 的 root 密码（根据实际情况填写） |
| 指纹 | 根据实际情况填写 |

### 后续配置

- **PBS**：调整精简（Prune）& GC 作业策略
- **PVE**：设置备份计划（Backup Schedule）