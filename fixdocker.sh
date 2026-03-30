#!/bin/bash
set -e

echo "==== 停止 Docker & containerd ===="
systemctl stop docker.service || true
systemctl stop docker.socket || true
systemctl stop containerd.service || true

echo "==== 强制杀掉残留进程 ===="
pkill -9 dockerd || true
pkill -9 containerd || true

echo "==== 处理残留 network namespace ===="
for ns in $(ip netns list | awk '{print $1}'); do
    echo "Deleting network namespace: $ns"
    ip netns delete $ns || true
done

echo "==== 清理运行时残留 ===="
rm -rf /run/docker/netns/* || true
rm -rf /run/docker/* || true
rm -rf /run/containerd/* || true
rm -rf /var/lib/containerd/io.containerd.runtime.v2.task/* || true

echo "==== 清理 Docker 虚拟网桥（可选，但推荐） ===="
for br in $(ip link show | grep 'docker' | awk -F: '{print $2}' | tr -d ' '); do
    echo "Deleting bridge: $br"
    ip link delete $br || true
done

echo "==== 修复 systemd 假死状态 ===="
systemctl daemon-reexec
systemctl daemon-reload
systemctl reset-failed

echo "==== 启动 containerd & Docker ===="
systemctl start containerd
systemctl start docker

echo "==== 状态检查 ===="
systemctl --no-pager status containerd | head -n 5
systemctl --no-pager status docker | head -n 5

echo "==== 完成 ✅ ===="