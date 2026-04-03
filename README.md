### 记录各种安装，仅此而已 ###

# Proxmox Virtual Environment 筆記  
## 虛擬機安裝和配置  
1. install-immortalwrt，#安裝immortalwrt 步骤  
   1. setup-v2ray，#v2ray的配置  
2. pvebackup.sh  #PVE 配置文件備份
3. pvetools.sh  #PVE 美化腳本

## pvetoos 配置、备份、恢复  
### 一、备份步骤  
1.在pve中添加計畫任務  
将 *pvebackup.sh* 脚本加入到 */usr/local/bin/* 目录
```
crontab -e #添加下面一行
0 3 * * 4 /usr/local/bin/pve-backup.sh  #每周四3点执行一次
```
  
### 二、恢复步骤
1. 解压备份  
```
bashtar xzf pveconfig-20261212.tar.gz -C / # 根據具體文件名稱
```
2. 恢复网络配置（重要！先别重启）
```
检查 */etc/network/interfaces* 是否适配新机器的网卡名：  
```
baship link show  # 查看当前网卡名  
nano /etc/network/interfaces  # 确认网卡名一致
```  
3. 重启集群服务  
```
bashsystemctl restart pve-cluster  
systemctl restart pvedaemon  
systemctl restart pveproxy  
```
4. 恢复 SSH  
```
bashsystemctl restart ssh  
```
5. 重启宿主机  
```
bashreboot  
```
