#!/bin/bash

# 在文件开头添加对 macOS 的检测和处理
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS 的 man 命令可能需要特殊处理
    function get_man_content() {
        local command=$1
        local section=$2
        local man_file
        
        # 获取手册文件路径
        man_file=$(man -w "${section}" "${command}" 2>/dev/null)
        if [[ -f "$man_file" ]]; then
            # 使用 mandoc 或 groff 直接处理手册文件
            if command -v mandoc >/dev/null 2>&1; then
                mandoc -T ascii "$man_file" | col -b
            else
                groff -mandoc -T ascii "$man_file" | col -b
            fi
            return 0
        else
            echo "未找到手册页: ${command}${section:+ (章节 $section)}" >> "$LOG_FILE"
            return 1
        fi
    }
else
    # 原有的 Linux 版本处理逻辑
    function get_man_content() {
        local command=$1
        local section=$2
        if man -s "$section" "$command" > /dev/null 2>&1; then
            man -s "$section" "$command"
        else
            echo "未找到手册页: ${command}（章节 ${section}）" >> "$LOG_FILE"
            return 1
        fi
    }
fi

# 翻译后的 man 文件目录
TRANSLATED_DIR="/usr/local/share/man/zh_CN"
mkdir -p "$TRANSLATED_DIR"

# 错误日志文件
LOG_FILE="./translate_error.log"
> "$LOG_FILE" # 清空日志文件

# 检查是否已有翻译
function check_translated() {
    local command=$1
    local section=$2
    local man_path="$TRANSLATED_DIR/man${section}/${command}.${section}"
    if [[ -f "$man_path" ]]; then
        return 0
    fi
    return 1
}

# 检查并格式化内容
function preprocess_content() {
    local content="$1"

    # 标记代码块（以4个空格或制表符开头的行）
    echo "$content" | sed -r 's/^([[:space:]]{4,}.*)$/[代码块开始]\n\1\n[代码块结束]/g'
}

# 调用翻译程序
function translate_content() {
    local content="$1"
    echo "$content" | python3 translate.py
}

# 保存翻译后的手册
function save_translated() {
    local content="$1"
    local command=$2
    local section=$3
    local man_path="$TRANSLATED_DIR/man${section}"
    
    # 创建目录
    mkdir -p "$man_path"
    
    # 保存为 nroff 格式
    echo ".\\\" Translated by Man Page Translator" > "$man_path/${command}.${section}"
    echo ".\\\" Original page from $(man -w ${section} ${command})" >> "$man_path/${command}.${section}"
    echo "$content" >> "$man_path/${command}.${section}"
    
    # 设置正确的权限
    chmod 644 "$man_path/${command}.${section}"
}

# 显示进度条
function show_progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local progress=$((current * width / total))
    local bar=""
    for ((i = 0; i < progress; i++)); do
        bar="${bar}#"
    done
    for ((i = progress; i < width; i++)); do
        bar="${bar}-"
    done
    printf "\r[%s] %d/%d 完成" "$bar" "$current" "$total"
}

# 在文件开头添加
function setup_manpath() {
    # 确保翻译目录在 MANPATH 中
    if [[ -z "$MANPATH" ]]; then
        export MANPATH="$TRANSLATED_DIR:$(man -w)"
    else
        export MANPATH="$TRANSLATED_DIR:$MANPATH"
    fi
    
    # 在脚本结束时显示使用说明
    cat << EOF

翻译完成后，您可以通过以下方式查看中文手册：

1. 设置 MANPATH 环境变量：
   export MANPATH="$TRANSLATED_DIR:\$MANPATH"

2. 查看手册：
   man <命令>
   
   例如：
   man ls

注意：您可能需要将 MANPATH 设置添加到 ~/.bashrc 或 ~/.zshrc 中使其永久生效。
EOF
}

# 获取命令帮助信息
function get_command_help() {
    local cmd="$1"
    local help_text=""
    
    # 尝试 --help
    help_text=$($cmd --help 2>/dev/null)
    if [[ $? -eq 0 && -n "$help_text" ]]; then
        echo "$help_text"
        return 0
    fi
    
    # 尝试 -h
    help_text=$($cmd -h 2>/dev/null)
    if [[ $? -eq 0 && -n "$help_text" ]]; then
        echo "$help_text"
        return 0
    fi
    
    # 尝试 help 命令
    help_text=$(help "$cmd" 2>/dev/null)
    if [[ $? -eq 0 && -n "$help_text" ]]; then
        echo "$help_text"
        return 0
    fi
    
    return 1
}

# 检查命令是否存在
function check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        echo "错误：命令 '$cmd' 不存在"
        return 1
    fi
    return 0
}

# 保存翻译后的帮助文档
function save_help_translated() {
    local content="$1"
    local command="$2"
    local man_path="$TRANSLATED_DIR/man1"  # 帮助文档默认放在 man1 目录
    
    # 创建目录
    mkdir -p "$man_path"
    
    # 将 help 输出转换为 man 格式
    cat > "$man_path/${command}.1" << EOF
.TH ${command} 1 "$(date +"%B %Y")" "Help Output" "User Commands"
.SH 名称
${command} \- $(echo "$content" | head -n 1)
.SH 描述
${content}
.SH 注意
本手册页由 ManZH 根据 '${command} --help' 输出自动生成。
EOF
    
    # 设置正确的权限
    chmod 644 "$man_path/${command}.1"
    
    echo "翻译后的帮助文档已保存到：$man_path/${command}.1"
}

# 修改主处理函数
function process_command() {
    local cmd="$1"
    local output=""
    local translated_content=""
    
    # 检查命令是否存在
    if ! check_command "$cmd"; then
        echo "提示：请检查命令名称是否正确，或按 Ctrl+C 取消翻译"
        return 1
    fi
    
    # 首先尝试获取 man 手册
    output=$(man "$cmd" 2>/dev/null)
    if [[ $? -eq 0 && -n "$output" ]]; then
        echo "正在翻译 man 手册..."
        translated_content=$(echo "$output" | col -b | python3 translate.py)
        save_translated "$translated_content" "$cmd" "1"
        return 0
    fi
    
    # 如果没有 man 手册，尝试获取 --help 输出
    echo "注意：未找到 '$cmd' 的 man 手册，尝试翻译 --help 输出..."
    output=$(get_command_help "$cmd")
    if [[ $? -eq 0 && -n "$output" ]]; then
        echo "正在翻译 help 信息..."
        translated_content=$(echo "$output" | python3 translate.py)
        save_help_translated "$translated_content" "$cmd"
        return 0
    fi
    
    # 如果都没有找到
    echo "错误：无法获取 '$cmd' 的帮助信息"
    echo "该命令可能："
    echo "1. 不提供帮助文档"
    echo "2. 需要特殊权限才能访问"
    echo "3. 命令名称输入错误"
    echo
    echo "建议："
    echo "1. 检查命令名称是否正确"
    echo "2. 尝试使用 sudo 运行"
    echo "3. 查看命令的官方文档"
    return 1
}

# 主程序
if [[ $# -eq 0 ]]; then
    echo "用法: $0 <命令名称>"
    exit 1
fi

process_command "$1"
