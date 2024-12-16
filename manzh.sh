#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查是否为 root 用户
function check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "错误：需要 root 权限来安装和管理手册"
        echo "请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 检查依赖
function check_dependencies() {
    local missing_deps=()
    
    # 检查必要的命令
    for cmd in jq python3 man col; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # 检查 Python 依赖
    if ! python3 -c "import requests" &> /dev/null; then
        missing_deps+=("python3-requests")
    fi
    
    # 如果有缺失的依赖，显示安装建议
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "错误：缺少以下依赖："
        printf '%s\n' "${missing_deps[@]}"
        echo
        echo "请安装缺失的依赖："
        echo
        if [[ "$(uname)" == "Darwin" ]]; then
            echo "使用 Homebrew 安装："
            echo "brew install jq python3"
            echo "pip3 install requests"
        else
            echo "使用包管理器安装："
            echo "apt install jq python3 python3-requests man-db"
            echo "或"
            echo "yum install jq python3 python3-requests man-db"
        fi
        exit 1
    fi
}

# 列出已翻译的手册
function list_translated() {
    echo "已翻译的手册页："
    echo
    
    local man_dir="/usr/local/share/man/zh_CN"
    if [[ ! -d "$man_dir" ]]; then
        echo "还没有翻译任何手册"
        return
    fi
    
    # 遍历所有章节目录
    for section_dir in "$man_dir"/man*; do
        if [[ -d "$section_dir" ]]; then
            local section=$(basename "$section_dir")
            echo "=== ${section#man} 章节 ==="
            
            # 列出该章节的所有手册
            for man_file in "$section_dir"/*; do
                if [[ -f "$man_file" ]]; then
                    local name=$(basename "$man_file")
                    name=${name%.*}
                    echo "  $name"
                fi
            done
            echo
        fi
    done
    
    # 显示使用说明
    cat << EOF
使用方法：
    man -M /usr/local/share/man/zh_CN <命令>

例如：
    man -M /usr/local/share/man/zh_CN ls

按回车键返回主菜单...
EOF
    read
}

# 交互式翻译
function interactive_translate() {
    echo "=== 翻译命令手册 ==="
    echo
    
    # 输入命令名称
    while true; do
        read -p "请输入要翻译的命令名称（输入 q 返回）: " cmd
        
        if [[ "$cmd" == "q" ]]; then
            return
        fi
        
        if [[ -z "$cmd" ]]; then
            echo "命令名称不能为空"
            continue
        fi
        
        # 检查命令是否存在
        if ! man "$cmd" &> /dev/null; then
            echo "警告：找不到命令 '$cmd' 的手册页"
            read -p "是否继续尝试翻译？[y/N] " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                continue
            fi
        fi
        
        # 执行翻译
        check_root
        "$SCRIPT_DIR/translate_man.sh" "$cmd"
        
        # 询问是否继续翻译其他命令
        echo
        read -p "是否继续翻译其他命令？[y/N] " continue_translate
        if [[ "$continue_translate" != "y" && "$continue_translate" != "Y" ]]; then
            break
        fi
        echo
    done
}

# 显示版本信息
function show_version() {
    echo "Man手册中文翻译工具 v1.0.0"
    echo
    echo "按回车键返回主菜单..."
    read
}

# 清理翻译
function interactive_clean() {
    echo "=== 清理已翻译的手册 ==="
    echo
    
    # 检查是否有翻译
    if [[ ! -d "/usr/local/share/man/zh_CN" ]]; then
        echo "当前没有任何已翻译的手册"
        echo
        echo "按回车键返回主菜单..."
        read
        return
    fi
    
    # 显示当前已翻译的数量
    local count=$(find /usr/local/share/man/zh_CN -type f | wc -l)
    echo "当前已翻译 $count 个手册页"
    echo
    
    # 确认清理
    read -p "确定要清理所有已翻译的手册吗？[y/N] " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        check_root
        "$SCRIPT_DIR/clean.sh"
    else
        echo "已取消清理"
    fi
    
    echo
    echo "按回车键返回主菜单..."
    read
}

# 显示主菜单
function show_menu() {
    while true; do
        clear
        cat << EOF
=== Man手册中文翻译工具 ===

1) 翻译命令手册
2) 配置翻译服务
3) 查看已翻译手册
4) 清理已翻译手册
5) 显示版本信息
0) 退出

EOF
        read -p "请选择操作 [0-5]: " choice
        echo
        
        case $choice in
            1) interactive_translate;;
            2) "$SCRIPT_DIR/config_manager.sh";;
            3) list_translated;;
            4) interactive_clean;;
            5) show_version;;
            0) exit 0;;
            *) 
                echo "无效的选择"
                echo "按回车键继续..."
                read
                ;;
        esac
    done
}

# 主程序
function main() {
    # 检查依赖
    check_dependencies
    
    # 如果有命令行参数，使用命令行模式
    if [[ $# -gt 0 ]]; then
        case "$1" in
            translate)
                shift
                if [[ -z "$1" ]]; then
                    echo "错误：请指定要翻译的命令"
                    echo "用法：$0 translate <命令名>"
                    exit 1
                fi
                check_root
                "$SCRIPT_DIR/translate_man.sh" "$@"
                ;;
            config)
                "$SCRIPT_DIR/config_manager.sh"
                ;;
            clean)
                check_root
                "$SCRIPT_DIR/clean.sh"
                ;;
            list)
                list_translated
                ;;
            version)
                echo "Man手册中文翻译工具 v1.0.0"
                ;;
            help|--help|-h)
                show_help
                ;;
            *)
                echo "错误：未知的命令 '$1'"
                echo "运行 '$0 help' 查看帮助"
                exit 1
                ;;
        esac
    else
        # 没有参数时启动交互式界面
        show_menu
    fi
}

# 运行主程序
main "$@" 