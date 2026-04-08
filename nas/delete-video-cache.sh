#!/bin/bash

PATHS=(
  /volume4/@video_web
  /volume4/@video
  /volume3/@video_web
  /volume3/@video
  /volume2/@video_web
  /volume2/@video
  /volume1/@video_web
  /volume1/@video
)

for dir in "${PATHS[@]}"; do
  echo "------------------------------------"
  echo "正在处理目录: $dir"

  if [ -d "$dir" ]; then
    echo "目录存在，开始清理..."
    /bin/rm -rf "$dir"/*
    echo "清理完成: $dir"
  else
    echo "目录不存在，跳过: $dir"
  fi

  echo "等待 30 秒后继续..."
  sleep 30
done

echo "所有任务执行完成"
