#!/bin/bash

# docker异常挂起，修复脚本

set -e

echo "==== 停止 Docker & containerd ===="
systemctl stop docker || true
systemctl stop docker.socket || true
systemctl stop containerd || true

echo "==== 清理运行时残留 ===="
rm -rf /run/containerd/* || true
rm -rf /run/docker/* || true

echo "==== 清理异常 shim（容器运行残留） ===="
rm -rf /var/lib/containerd/io.containerd.runtime.v2.task/* || true

echo "==== 重载 systemd ===="
systemctl daemon-reexec
systemctl daemon-reload

echo "==== 启动 containerd ===="
systemctl start containerd

echo "==== 启动 Docker ===="
systemctl start docker

echo "==== 状态检查 ===="
systemctl --no-pager status containerd | head -n 5
systemctl --no-pager status docker | head -n 5

echo "==== 完成 ✅ ===="