#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "错误：需要 root 权限卸载"
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 删除安装文件
rm -rf /usr/local/manzh
rm -f /usr/local/bin/manzh

# 询问是否删除翻译后的手册
read -p "是否删除已翻译的手册？[y/N] " remove_man
if [[ "$remove_man" == "y" || "$remove_man" == "Y" ]]; then
    rm -rf /usr/local/share/man/zh_CN
fi

echo "卸载完成！" 