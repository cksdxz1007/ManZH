#!/bin/bash

# 清理脚本
echo "正在清理已有的翻译结果..."
sudo rm -rf /usr/local/share/man/zh_CN/man*

echo "正在清空错误日志..."
> ./translate_error.log

echo "清理完成！"
echo "现在可以重新运行翻译命令：sudo ./translate_man.sh <命令>" 