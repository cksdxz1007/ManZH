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

# 主流程
COMMAND=$1
if [[ -z "$COMMAND" ]]; then
    echo "使用方法: ./translate_man.sh <命令>"
    exit 1
fi

# 修改章节检查逻辑
if [[ "$(uname)" == "Darwin" ]]; then
    # 获取所有可用的章节
    SECTIONS=($(man -w "$COMMAND" 2>/dev/null | grep -o '[0-9]' | sort -u))
    TOTAL_SECTIONS=${#SECTIONS[@]}
else
    # Linux 版本保持不变
    TOTAL_SECTIONS=0
    for SECTION in {1..9}; do
        if man -s "$SECTION" "$COMMAND" > /dev/null 2>&1; then
            TOTAL_SECTIONS=$((TOTAL_SECTIONS + 1))
        fi
    done
fi

if [[ $TOTAL_SECTIONS -eq 0 ]]; then
    echo "未找到 ${COMMAND} 的任何手册页！" | tee -a "$LOG_FILE"
    exit 1
fi

COMPLETED_SECTIONS=0
START_TIME=$(date +%s)

echo "开始翻译 ${COMMAND} 的 ${TOTAL_SECTIONS} 个手册页..."

# 修改主循环
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS 版本的处理逻辑
    if [[ ${#SECTIONS[@]} -eq 0 ]]; then
        echo "未找到 ${COMMAND} 的任何手册页！" | tee -a "$LOG_FILE"
        exit 1
    fi

    COMPLETED_SECTIONS=0
    for SECTION in "${SECTIONS[@]}"; do
        echo "[$((COMPLETED_SECTIONS + 1))/$TOTAL_SECTIONS] 正在处理章节 ${SECTION}..."
        
        if check_translated "$COMMAND" "$SECTION"; then
            echo "章节 ${SECTION} 已经翻译过，跳过..."
            COMPLETED_SECTIONS=$((COMPLETED_SECTIONS + 1))
            show_progress_bar "$COMPLETED_SECTIONS" "$TOTAL_SECTIONS"
            continue
        fi

        echo "正在获取章节 ${SECTION} 的手册内容..."
        MAN_CONTENT=$(get_man_content "$COMMAND" "$SECTION")
        if [[ $? -ne 0 ]]; then
            COMPLETED_SECTIONS=$((COMPLETED_SECTIONS + 1))
            show_progress_bar "$COMPLETED_SECTIONS" "$TOTAL_SECTIONS"
            continue
        fi

        echo "正在检查和格式化内容..."
        PROCESSED_CONTENT=$(preprocess_content "$MAN_CONTENT")

        echo "正在翻译章节 ${SECTION} 的手册内容..."
        START_SECTION_TIME=$(date +%s)
        TRANSLATED_CONTENT=$(translate_content "$PROCESSED_CONTENT")
        END_SECTION_TIME=$(date +%s)

        echo "翻译完成！用时 $((END_SECTION_TIME - START_SECTION_TIME)) 秒。"

        echo "正在保存章节 ${SECTION} 的翻译..."
        save_translated "$TRANSLATED_CONTENT" "$COMMAND" "$SECTION"

        COMPLETED_SECTIONS=$((COMPLETED_SECTIONS + 1))
        show_progress_bar "$COMPLETED_SECTIONS" "$TOTAL_SECTIONS"
    done
else
    # Linux 版本循环逻辑保持不变
    for SECTION in {1..9}; do
        if ! man -s "$SECTION" "$COMMAND" > /dev/null 2>&1; then
            continue
        fi

        if check_translated "$COMMAND" "$SECTION"; then
            COMPLETED_SECTIONS=$((COMPLETED_SECTIONS + 1))
            show_progress_bar "$COMPLETED_SECTIONS" "$TOTAL_SECTIONS"
            continue
        fi

        echo "[$((COMPLETED_SECTIONS + 1))/$TOTAL_SECTIONS] 正在获取章节 ${SECTION} 的手册内容..."
        MAN_CONTENT=$(get_man_content "$COMMAND" "$SECTION")
        if [[ $? -ne 0 ]]; then
            COMPLETED_SECTIONS=$((COMPLETED_SECTIONS + 1))
            show_progress_bar "$COMPLETED_SECTIONS" "$TOTAL_SECTIONS"
            continue
        fi

        echo "[$((COMPLETED_SECTIONS + 1))/$TOTAL_SECTIONS] 正在检查和格式化内容..."
        PROCESSED_CONTENT=$(preprocess_content "$MAN_CONTENT")

        echo "[$((COMPLETED_SECTIONS + 1))/$TOTAL_SECTIONS] 正在翻译章节 ${SECTION} 的手册内容..."
        START_SECTION_TIME=$(date +%s)
        TRANSLATED_CONTENT=$(translate_content "$PROCESSED_CONTENT")
        END_SECTION_TIME=$(date +%s)

        echo "[$((COMPLETED_SECTIONS + 1))/$TOTAL_SECTIONS] 翻译完成！用时 $((END_SECTION_TIME - START_SECTION_TIME)) 秒。"

        echo "[$((COMPLETED_SECTIONS + 1))/$TOTAL_SECTIONS] 正在保存章节 ${SECTION} 的翻译..."
        save_translated "$TRANSLATED_CONTENT" "$COMMAND" "$SECTION"

        COMPLETED_SECTIONS=$((COMPLETED_SECTIONS + 1))
        show_progress_bar "$COMPLETED_SECTIONS" "$TOTAL_SECTIONS"
    done
fi

END_TIME=$(date +%s)

echo
echo "翻译完成！已翻译 ${COMPLETED_SECTIONS}/${TOTAL_SECTIONS} 个章节。"
echo "总用时 $((END_TIME - START_TIME)) 秒。"

if [[ -s "$LOG_FILE" ]]; then
    echo "部分章节翻译失败，详情请查看日志文件：$LOG_FILE"
fi

# 在主流程最后添加
setup_manpath
