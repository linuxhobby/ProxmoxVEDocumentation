# pvetoosl
#在pve中添加計畫任務  
# crontab -e,添加这一行：

```
0 3 * * 3 /usr/local/bin/pvebackup.sh
```


恢复步骤
1. 解压备份  
```
bashtar xzf pve-config-20240101.tar.gz -C /
```
2. 恢复网络配置（重要！先别重启）
检查 /etc/network/interfaces 是否适配新机器的网卡名：
baship link show  # 查看当前网卡名
```
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
