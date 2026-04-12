apt install cifs-utils -y

### 创建密码文件
cat > /etc/samba/pbs-creds << EOF
username=marco
password=Aggie66.com
EOF
chmod 600 /etc/samba/pbs-creds


### 3. 创建挂载点
mkdir -p /mnt/storage_synology

### 4. 写入 fstab
echo "//192.168.2.12/PVEbackup /mnt/storage_synology cifs credentials=/etc/samba/pbs-creds,uid=34,gid=34,file_mode=0770,dir_mode=0770,cache=none,_netdev 0 0" >> /etc/fstab


umount /mnt/storage_synology
mount -a
### 5. 挂载测试
mount -a
su -s /bin/bash backup -c "ls /mnt/storage_synology"

### 6.创建datastore
proxmox-backup-manager datastore create storage-synology /mnt/storage_synology/pbs-datastore --tuning "gc-atime-safety-check=0"

6.PVE Web界面 → 数据中心 → 存储 → 添加 → Proxmox Backup Server
01:59在 PVE Web UI 操作：

数据中心 → 存储 → 添加 → Proxmox Backup Server，填写：
ID：storage-synology
服务器：192.168.2.125（PBS 的 IP）
用户名：root@pam
密码：PBS 的 root 密码
数据存储：选择 storage-synology

