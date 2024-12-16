#!/bin/bash

# 安装目录
INSTALL_DIR="/usr/local/manzh"
BIN_DIR="/usr/local/bin"

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
    echo "错误：需要 root 权限安装"
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 检查系统类型
function check_system() {
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "检测到 macOS 系统"
        # 检查 Homebrew
        if ! command -v brew &> /dev/null; then
            echo "请先安装 Homebrew: https://brew.sh"
            exit 1
        fi
        # 安装依赖
        brew install jq python3 groff man-db
        pip3 install requests
    else
        echo "检测到 Linux 系统"
        # 检查包管理器
        if command -v apt &> /dev/null; then
            apt update
            apt install -y jq python3 python3-requests man-db groff
        elif command -v yum &> /dev/null; then
            yum install -y jq python3 python3-requests man-db groff
        else
            echo "未知的包管理器，请手动安装依赖"
            exit 1
        fi
    fi
}

# 创建目录
function create_dirs() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "/usr/local/share/man/zh_CN"
}

# 复制文件
function copy_files() {
    cp manzh.sh "$INSTALL_DIR/"
    cp translate_man.sh "$INSTALL_DIR/"
    cp translate.py "$INSTALL_DIR/"
    cp config_manager.sh "$INSTALL_DIR/"
    cp clean.sh "$INSTALL_DIR/"
    
    # 创建默认配置文件
    if [[ ! -f "$INSTALL_DIR/config.json" ]]; then
        cp config.json "$INSTALL_DIR/"
    fi
    
    # 创建命令链接
    ln -sf "$INSTALL_DIR/manzh.sh" "$BIN_DIR/manzh"
    
    # 设置权限
    chmod +x "$INSTALL_DIR"/*.sh
    chmod 644 "$INSTALL_DIR/config.json"
    chmod 644 "$INSTALL_DIR/translate.py"
}

# 主安装流程
echo "开始安装 Man手册中文翻译工具..."

# 检查并安装依赖
check_system

# 创建目录
create_dirs

# 复制文件
copy_files

echo "安装完成！"
echo
echo "使用方法："
echo "1. 命令行方式："
echo "   manzh translate <命令>"
echo "   manzh config"
echo "   manzh list"
echo
echo "2. 交互式方式："
echo "   manzh"
echo
echo "首次使用请先运行 'manzh config' 配置翻译服务" 