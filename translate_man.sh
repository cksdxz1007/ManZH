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
    local translated_content
    
    # 使用管道调用 Python 翻译程序，并捕获返回值
    translated_content=$(echo "$content" | python3 translate.py)
    local exit_code=$?
    
    # 检查翻译是否成功
    if [[ $exit_code -ne 0 ]] || [[ -z "$translated_content" ]]; then
        echo "翻译失败，不保存结果" >&2
        return 1
    fi
    
    echo "$translated_content"
    return 0
}

# 保存翻译后的手册
function save_translated() {
    local content="$1"
    local command="$2"
    local section="${3:-1}"  # 默认保存到 man1
    local man_path="/usr/local/share/man/zh_CN/man${section}"
    
    # 检查内容是否为空
    if [[ -z "$content" ]]; then
        echo "错误：翻译内容为空，不保存结果" >&2
        return 1
    fi
    
    # 创建目录
    mkdir -p "$man_path"
    
    # 保存翻译结果
    echo "$content" > "$man_path/${command}.${section}"
    
    # 设置正确的权限
    chmod 644 "$man_path/${command}.${section}"
    
    echo "翻译后的手册已保存到：$man_path/${command}.${section}"
    return 0
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
    local man_path="/usr/local/share/man/zh_CN/man1"  # 帮助文档默认放在 man1 目录
    
    # 检查内容是否为空
    if [[ -z "$content" ]]; then
        echo "错误：翻译内容为空，不保存结果" >&2
        return 1
    fi
    
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
    return 0
}

# 修改主处理函数
function process_command() {
    local cmd="$1"
    local output=""
    local help_output=""
    local translated_content=""
    
    # 1. 检查命令是否存在
    if ! command -v "$cmd" &> /dev/null; then
        echo "错误：命令 '$cmd' 不存在"
        return 1
    fi
    
    # 2. 尝试获取 man 手册
    output=$(man "$cmd" 2>/dev/null)
    if [[ $? -eq 0 && -n "$output" ]]; then
        echo "正在翻译 man 手册..."
        translated_content=$(echo "$output" | col -b | translate_content)
        if [[ $? -eq 0 && -n "$translated_content" ]]; then
            save_translated "$translated_content" "$cmd" "1"
            return $?
        else
            echo "翻译失败，请检查日志并重试"
            return 1
        fi
    fi
    
    # 3. 如果没有 man 手册，检查 --help 输出
    echo "警告：找不到命令 '$cmd' 的手册页"
    help_output=$(get_command_help "$cmd")
    
    # 4. 检查 --help 输出结果
    if [[ $? -eq 0 && -n "$help_output" ]]; then
        # 5. 有 --help 输出，直接提示并询问
        echo "发现 '$cmd --help' 输出信息"
        read -p "是否使用 --help 输出进行翻译？[Y/n] " use_help
        if [[ "$use_help" != "n" && "$use_help" != "N" ]]; then
            echo "正在翻译 help 信息..."
            translated_content=$(echo "$help_output" | translate_content)
            if [[ $? -eq 0 && -n "$translated_content" ]]; then
                save_help_translated "$translated_content" "$cmd"
                return $?
            else
                echo "翻译失败，请检查日志并重试"
                return 1
            fi
        fi
    else
        # 6. 没有任何帮助信息
        echo "错误：命令 '$cmd' 没有 man 手册也没有 --help 输出"
        echo "可能的原因："
        echo "1. 命令名称输入错误"
        echo "2. 命令未正确安装"
        echo "3. 需要特殊权限才能访问"
        return 1
    fi
    
    return 1
}

# 主程序
if [[ $# -eq 0 ]]; then
    echo "用法: $0 <命令名称>"
    exit 1
fi

process_command "$1"
