#!/bin/bash

# 翻译手册目录
MAN_DIR="/usr/local/share/man/zh_CN"

# 列出所有已翻译的命令
function list_translated_commands() {
    echo "已翻译的命令列表："
    echo "==================="
    
    local total=0
    # 遍历所有章节目录
    for section_dir in "$MAN_DIR"/man*; do
        if [[ -d "$section_dir" ]]; then
            local section=$(basename "$section_dir")
            section_num=${section#man}
            echo
            echo "第 $section_num 章节："
            echo "-------------"
            
            # 列出该章节的所有命令
            local count=0
            for file in "$section_dir"/*; do
                if [[ -f "$file" ]]; then
                    local cmd=$(basename "$file")
                    cmd=${cmd%.*}
                    echo "  $cmd"
                    ((count++))
                    ((total++))
                fi
            done
            
            if [[ $count -eq 0 ]]; then
                echo "  (无)"
            else
                echo "  共 $count 个命令"
            fi
        fi
    done
    
    echo
    echo "总计：$total 个已翻译的命令"
    echo "==================="
}

# 删除指定命令的手册
function delete_command() {
    local cmd="$1"
    local found=false
    
    # 在所有章节中查找并删除
    for section_dir in "$MAN_DIR"/man*; do
        if [[ -d "$section_dir" ]]; then
            local section=$(basename "$section_dir")
            local file="$section_dir/$cmd.*"
            
            # 使用通配符查找文件
            for f in $file; do
                if [[ -f "$f" ]]; then
                    rm -f "$f"
                    echo "已删除：$f"
                    found=true
                fi
            done
        fi
    done
    
    if [[ "$found" == "false" ]]; then
        echo "未找到命令 '$cmd' 的翻译手册"
        return 1
    fi
    
    return 0
}

# 清空所有翻译
function clean_all() {
    echo "警告：这将删除所有已翻译的手册！"
    read -p "确定要继续吗？[y/N] " confirm
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        rm -rf "$MAN_DIR"/man*
        echo "已清空所有翻译结果"
    else
        echo "操作已取消"
        return 1
    fi
    
    return 0
}

# 清空错误日志
function clean_error_log() {
    > ./translate_error.log
    echo "已清空错误日志"
}

# 主菜单
function show_menu() {
    while true; do
        echo
        echo "=== 清理翻译手册 ==="
        echo "1) 列出已翻译的命令"
        echo "2) 删除指定命令的手册"
        echo "3) 清空所有翻译"
        echo "4) 清空错误日志"
        echo "0) 返回主菜单"
        echo
        
        read -p "请选择操作 [0-4]: " choice
        echo
        
        case $choice in
            1)
                list_translated_commands
                ;;
            2)
                list_translated_commands
                echo
                read -p "请输入要删除的命令名称（输入 q 取消）: " cmd
                if [[ "$cmd" != "q" ]]; then
                    delete_command "$cmd"
                fi
                ;;
            3)
                clean_all
                ;;
            4)
                clean_error_log
                ;;
            0)
                return 0
                ;;
            *)
                echo "无效的选择"
                ;;
        esac
        
        echo
        read -p "按回车键继续..."
    done
}

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
    echo "错误：需要 root 权限来清理手册"
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 检查翻译目录是否存在
if [[ ! -d "$MAN_DIR" ]]; then
    echo "翻译目录不存在：$MAN_DIR"
    exit 1
fi

# 启动主菜单
show_menu 