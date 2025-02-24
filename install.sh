#!/bin/bash

# 安装目录
INSTALL_DIR="/usr/local/manzh"
BIN_DIR="/usr/local/bin"
VENV_DIR="$INSTALL_DIR/venv"
LOG_FILE="/tmp/manzh_install.log"
BACKUP_FILE="/tmp/manzh_last_backup"
USE_VENV=false

# 日志函数
function log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

function error_log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] 错误: $1" | tee -a "$LOG_FILE" >&2
}

# 错误处理
function handle_error() {
    error_log "$1"
    
    # 检查是否需要回滚
    if [[ -f "$BACKUP_FILE" ]]; then
        local backup_dir=$(cat "$BACKUP_FILE")
        if [[ -d "$backup_dir" ]]; then
            log "正在回滚到备份..."
            if [[ -d "$INSTALL_DIR" ]]; then
                rm -rf "$INSTALL_DIR"
            fi
            mkdir -p "$INSTALL_DIR"
            cp -r "$backup_dir"/* "$INSTALL_DIR/" || error_log "回滚失败"
            log "回滚完成"
        fi
    fi
    
    cleanup
    exit 1
}

# 清理函数
function cleanup() {
    log "执行清理..."
    rm -f /tmp/manzh_*
}

# 确保退出时清理
trap cleanup EXIT

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
    handle_error "需要 root 权限安装\n请使用 sudo 运行此脚本"
fi

# 虚拟环境函数
function setup_venv() {
    log "设置 Python 虚拟环境..."
    
    # 检查现有虚拟环境
    if [[ -d "$VENV_DIR" ]]; then
        log "发现已存在的虚拟环境"
        read -p "是否重新创建虚拟环境？[y/N] " recreate_venv
        if [[ "$recreate_venv" == "y" || "$recreate_venv" == "Y" ]]; then
            log "备份旧的虚拟环境..."
            mv "$VENV_DIR" "${VENV_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
        else
            log "使用现有虚拟环境"
            return 0
        fi
    fi
    
    # 检查 venv 模块
    if ! python3 -c "import venv" &> /dev/null; then
        log "安装 Python venv 模块..."
        if command -v apt &> /dev/null; then
            apt install -y python3-venv || handle_error "安装 python3-venv 失败"
        elif command -v yum &> /dev/null; then
            yum install -y python3-venv || handle_error "安装 python3-venv 失败"
        else
            handle_error "请先安装 python3-venv"
        fi
    fi
    
    # 创建虚拟环境
    log "创建新的虚拟环境..."
    python3 -m venv "$VENV_DIR" || handle_error "创建虚拟环境失败"
    
    # 创建激活脚本的包装器
    log "创建虚拟环境激活脚本..."
    cat > "$BIN_DIR/manzh-activate" << EOF
#!/bin/bash

# 检查虚拟环境是否存在
if [[ ! -d "$VENV_DIR" ]]; then
    echo "错误：虚拟环境不存在"
    echo "请重新运行安装脚本"
    exit 1
fi

# 检查是否已经在虚拟环境中
if [[ -n "\$VIRTUAL_ENV" ]]; then
    if [[ "\$VIRTUAL_ENV" == "$VENV_DIR" ]]; then
        echo "已经在 ManZH 的虚拟环境中"
        return 0
    else
        echo "警告：当前在其他虚拟环境中"
        echo "请先运行 'deactivate' 退出当前环境"
        return 1
    fi
fi

# 激活虚拟环境
source "$VENV_DIR/bin/activate"

# 设置环境变量
export MANZH_VENV=1

echo "Python 虚拟环境已激活！"
echo "现在可以运行 manzh 命令了"
echo "退出虚拟环境请运行: deactivate"

# 启动新的 shell
exec "\$SHELL"
EOF
    
    chmod +x "$BIN_DIR/manzh-activate" || handle_error "设置激活脚本权限失败"
    
    # 修改 manzh 启动脚本以使用虚拟环境
    log "更新主程序脚本..."
    if [[ ! -f "$INSTALL_DIR/manzh.sh" ]]; then
        handle_error "找不到主程序脚本：$INSTALL_DIR/manzh.sh"
    fi
    
    sed -i.bak "2i\\
# 检查虚拟环境\\
if [[ -f '$VENV_DIR/bin/activate' && -z \"\$VIRTUAL_ENV\" ]]; then\\
    echo \"警告：建议在虚拟环境中运行此程序\"\\
    echo \"请先运行: manzh-activate\"\\
    echo \"或者按回车键继续使用系统 Python\"\\
    read -p \"\" response\\
fi" "$INSTALL_DIR/manzh.sh" || handle_error "修改启动脚本失败"
    
    # 激活虚拟环境并安装依赖
    log "安装 Python 依赖..."
    source "$VENV_DIR/bin/activate"
    
    # 更新 pip
    log "更新 pip..."
    pip install --upgrade pip || handle_error "更新 pip 失败"
    
    # 安装依赖
    if [[ -f "requirements.txt" ]]; then
        log "从 requirements.txt 安装依赖..."
        pip install -r requirements.txt || handle_error "安装 Python 依赖失败"
    else
        log "安装必要的 Python 包..."
        pip install requests>=2.31.0 google-generativeai>=0.3.2 || handle_error "安装 Python 依赖失败"
    fi
    
    # 验证安装
    log "验证 Python 包安装..."
    python3 -c "import requests" || handle_error "requests 模块安装失败"
    python3 -c "import google.generativeai" || handle_error "google-generativeai 模块安装失败"
    
    deactivate
    log "虚拟环境设置完成"
}

# 安装系统包
function install_system_packages() {
    local packages=("$@")
    local os_type="$(uname -s)"
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "正在安装系统依赖包..."
    
    case "$os_type" in
        "Darwin")
            # macOS 使用 Homebrew
            if ! command -v brew &> /dev/null; then
                handle_error "请先安装 Homebrew: https://brew.sh"
            fi
            brew install "${packages[@]}" || handle_error "使用 Homebrew 安装依赖失败"
            ;;
            
        "Linux")
            # 检查包管理器
            if command -v apt &> /dev/null; then
                # Debian/Ubuntu
                log "使用 apt 安装依赖..."
                apt update || handle_error "apt update 失败"
                apt install -y "${packages[@]}" || handle_error "使用 apt 安装依赖失败"
            elif command -v dnf &> /dev/null; then
                # 新版 RHEL/CentOS/Fedora
                log "使用 dnf 安装依赖..."
                dnf install -y epel-release || handle_error "安装 EPEL 失败"
                dnf install -y "${packages[@]}" || handle_error "使用 dnf 安装依赖失败"
            elif command -v yum &> /dev/null; then
                # 旧版 RHEL/CentOS
                log "使用 yum 安装依赖..."
                yum install -y epel-release || handle_error "安装 EPEL 失败"
                yum install -y "${packages[@]}" || handle_error "使用 yum 安装依赖失败"
            else
                handle_error "未找到支持的包管理器"
            fi
            ;;
            
        *)
            handle_error "不支持的操作系统类型: $os_type"
            ;;
    esac
    
    log "系统依赖包安装完成"
}

# 检查依赖
function check_dependencies() {
    log "检查依赖..."
    
    # 检查 Python 版本
    local python_version=$(python3 -V 2>&1 | cut -d' ' -f2)
    if [[ "$(printf '%s\n' "3.7" "$python_version" | sort -V | head -n1)" == "3.7" ]]; then
        log "Python 版本检查通过（当前版本：$python_version）"
    else
        handle_error "Python 版本需要 3.7 或更高版本（当前版本：$python_version）"
    fi
    
    local missing_deps=()
    local os_type="$(uname -s)"
    
    # 基础命令检查
    for cmd in python3 jq groff man pip3 curl wget; do
        if ! command -v "$cmd" &> /dev/null; then
            case "$os_type" in
                "Darwin")
                    case "$cmd" in
                        python3) missing_deps+=("python3");;
                        pip3) missing_deps+=("python3");;  # python3 包含 pip3
                        jq) missing_deps+=("jq");;
                        groff) missing_deps+=("groff");;
                        man) missing_deps+=("man-db");;
                        curl) missing_deps+=("curl");;
                        wget) missing_deps+=("wget");;
                    esac
                    ;;
                "Linux")
                    case "$cmd" in
                        python3) missing_deps+=("python3");;
                        pip3) missing_deps+=("python3-pip");;
                        jq) missing_deps+=("jq");;
                        groff) missing_deps+=("groff");;
                        man) missing_deps+=("man-db");;
                        curl) missing_deps+=("curl");;
                        wget) missing_deps+=("wget");;
                    esac
                    ;;
            esac
        fi
    done
    
    # 检查 venv 模块
    if ! python3 -c "import venv" &> /dev/null; then
        if [[ "$os_type" == "Linux" ]]; then
            missing_deps+=("python3-venv")
        fi
    fi
    
    # 如果有缺失的依赖，尝试安装
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "检测到缺失的依赖："
        printf '%s\n' "${missing_deps[@]}"
        echo
        echo "正在自动安装缺失的依赖..."
        install_system_packages "${missing_deps[@]}"
    fi
    
    # 再次验证所有依赖是否已安装
    local verify_failed=false
    for cmd in python3 jq groff man pip3 curl wget; do
        if ! command -v "$cmd" &> /dev/null; then
            error_log "命令 '$cmd' 安装失败"
            verify_failed=true
        fi
    done
    
    if ! python3 -c "import venv" &> /dev/null; then
        error_log "python3-venv 模块安装失败"
        verify_failed=true
    fi
    
    if [[ "$verify_failed" == "true" ]]; then
        handle_error "部分依赖安装失败，请检查系统包管理器状态"
    fi
    
    log "所有依赖检查通过"
}

# 检查系统类型
function check_system() {
    log "检查系统类型..."
    local os_type="$(uname -s)"
    local os_version=""
    
    case "$os_type" in
        "Darwin")
            os_version="$(sw_vers -productVersion)"
            log "检测到 macOS 系统 (版本: $os_version)"
            
            # 检查 Homebrew
            if ! command -v brew &> /dev/null; then
                handle_error "请先安装 Homebrew: https://brew.sh"
            fi
            
            # 检查 macOS 版本兼容性
            if [[ "$(printf '%s\n' "10.15" "$os_version" | sort -V | head -n1)" == "10.15" ]]; then
                handle_error "需要 macOS Catalina (10.15) 或更高版本"
            fi
            
            # 安装依赖
            log "安装系统依赖..."
            brew install jq python3 groff man-db curl wget || handle_error "安装系统依赖失败"
            
            if [[ "$USE_VENV" == "true" ]]; then
                setup_venv
            else
                # 安装 Python 依赖到系统环境
                log "安装 Python 依赖到系统环境..."
                pip3 install --upgrade pip || handle_error "更新 pip 失败"
                if [[ -f "requirements.txt" ]]; then
                    pip3 install -r requirements.txt || handle_error "安装 Python 依赖失败"
                else
                    pip3 install requests>=2.31.0 google-generativeai>=0.3.2 || handle_error "安装 Python 依赖失败"
                fi
            fi
            ;;
            
        "Linux")
            # 获取 Linux 发行版信息
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                os_version="$VERSION_ID"
                log "检测到 $NAME 系统 (版本: $os_version)"
                
                # 检查发行版兼容性
                case "$ID" in
                    "ubuntu"|"debian")
                        if [[ "$(printf '%s\n' "20.04" "$VERSION_ID" | sort -V | head -n1)" == "20.04" ]]; then
                            log "Ubuntu 版本检查通过（当前版本：$VERSION_ID）"
                        else
                            handle_error "需要 Ubuntu 20.04 或更高版本"
                        fi
                        log "使用 apt 安装依赖..."
                        apt update || handle_error "apt update 失败"
                        apt install -y jq python3 python3-pip python3-venv man-db groff curl wget || handle_error "安装系统依赖失败"
                        ;;
                        
                    "centos"|"rhel"|"fedora")
                        if [[ "$(printf '%s\n' "8" "$VERSION_ID" | sort -V | head -n1)" == "8" ]]; then
                            handle_error "需要 CentOS/RHEL 8 或更高版本"
                        fi
                        log "使用 yum/dnf 安装依赖..."
                        if command -v dnf &> /dev/null; then
                            dnf install -y epel-release || handle_error "安装 EPEL 失败"
                            dnf install -y jq python3 python3-pip python3-venv man-db groff curl wget || handle_error "安装系统依赖失败"
                        else
                            yum install -y epel-release || handle_error "安装 EPEL 失败"
                            yum install -y jq python3 python3-pip python3-venv man-db groff curl wget || handle_error "安装系统依赖失败"
                        fi
                        ;;
                        
                    *)
                        handle_error "不支持的 Linux 发行版: $NAME"
                        ;;
                esac
                
                if [[ "$USE_VENV" == "true" ]]; then
                    setup_venv
                else
                    # 安装 Python 依赖到系统环境
                    log "安装 Python 依赖到系统环境..."
                    pip3 install --upgrade pip || handle_error "更新 pip 失败"
                    if [[ -f "requirements.txt" ]]; then
                        pip3 install -r requirements.txt || handle_error "安装 Python 依赖失败"
                    else
                        pip3 install requests>=2.31.0 google-generativeai>=0.3.2 || handle_error "安装 Python 依赖失败"
                    fi
                fi
            else
                handle_error "无法检测 Linux 发行版信息"
            fi
            ;;
            
        *)
            handle_error "不支持的操作系统类型: $os_type"
            ;;
    esac
}

# 检查权限
function check_permissions() {
    log "检查权限..."
    local dirs=("$INSTALL_DIR" "$BIN_DIR" "/usr/local/share/man/zh_CN")
    
    # 检查父目录权限
    for dir in "${dirs[@]}"; do
        local parent_dir="$(dirname "$dir")"
        
        # 检查父目录是否存在
        if [[ ! -d "$parent_dir" ]]; then
            if ! mkdir -p "$parent_dir"; then
                handle_error "无法创建目录: $parent_dir"
            fi
        fi
        
        # 检查父目录权限
        if [[ ! -w "$parent_dir" ]]; then
            handle_error "没有写入权限: $parent_dir"
        fi
        
        # 检查目录是否存在且有写权限
        if [[ -d "$dir" && ! -w "$dir" ]]; then
            handle_error "没有写入权限: $dir"
        fi
        
        # 检查目录的执行权限
        if [[ -d "$dir" && ! -x "$dir" ]]; then
            handle_error "没有执行权限: $dir"
        fi
    done
    
    # 检查特定文件的权限
    local files=("$INSTALL_DIR/manzh.sh" "$INSTALL_DIR/config.json")
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            # 检查文件的读写权限
            if [[ ! -r "$file" ]]; then
                handle_error "没有读取权限: $file"
            fi
            if [[ ! -w "$file" ]]; then
                handle_error "没有写入权限: $file"
            fi
        fi
    done
    
    # 检查日志目录权限
    local log_dir="$(dirname "$LOG_FILE")"
    if [[ ! -w "$log_dir" ]]; then
        handle_error "没有写入权限: $log_dir"
    fi
}

# 备份现有安装
function backup_existing() {
    if [[ -d "$INSTALL_DIR" ]]; then
        local backup_dir="/usr/local/manzh.backup.$(date +%Y%m%d_%H%M%S)"
        log "备份现有安装到: $backup_dir"
        mkdir -p "$backup_dir"
        
        # 特殊处理配置文件
        if [[ -f "$INSTALL_DIR/config.json" ]]; then
            log "备份配置文件..."
            cp "$INSTALL_DIR/config.json" "$backup_dir/config.json.bak"
        fi
        
        # 备份所有文件
        cp -r "$INSTALL_DIR"/* "$backup_dir/" || handle_error "备份失败"
        
        # 保存备份路径
        echo "$backup_dir" > "$BACKUP_FILE"
        
        # 记录备份信息
        cat > "$backup_dir/backup_info.txt" << EOF
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
安装目录: $INSTALL_DIR
Python版本: $(python3 -V 2>&1)
系统信息: $(uname -a)
EOF
    fi
}

# 创建目录
function create_dirs() {
    log "创建必要目录..."
    for dir in "$INSTALL_DIR" "$BIN_DIR" "/usr/local/share/man/zh_CN"; do
        mkdir -p "$dir" || handle_error "创建目录失败: $dir"
    done
}

# 复制文件
function copy_files() {
    log "复制程序文件..."
    local files=(manzh.sh translate_man.sh translate.py config_manager.sh clean.sh)
    
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            handle_error "缺少必要文件: $file"
        fi
        cp "$file" "$INSTALL_DIR/" || handle_error "复制文件失败: $file"
    done
    
    # 创建默认配置文件
    if [[ ! -f "$INSTALL_DIR/config.json" ]]; then
        if [[ -f "config.json.example" ]]; then
            log "使用示例配置文件创建 config.json..."
            cp config.json.example "$INSTALL_DIR/config.json" || handle_error "创建配置文件失败"
        else
            handle_error "缺少配置文件模板: config.json.example"
        fi
    fi
    
    # 创建命令链接
    ln -sf "$INSTALL_DIR/manzh.sh" "$BIN_DIR/manzh" || handle_error "创建命令链接失败"
    
    # 设置权限
    chmod +x "$INSTALL_DIR"/*.sh || handle_error "设置执行权限失败"
    chmod 644 "$INSTALL_DIR/config.json" "$INSTALL_DIR/translate.py" || handle_error "设置文件权限失败"
}

# 验证安装
function verify_installation() {
    log "验证安装..."
    local check_failed=false
    
    # 检查必要文件
    local required_files=(
        "manzh.sh"
        "translate_man.sh"
        "translate.py"
        "config_manager.sh"
        "clean.sh"
        "config.json"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$INSTALL_DIR/$file" ]]; then
            error_log "缺少文件: $file"
            check_failed=true
        fi
    done
    
    # 检查可执行文件权限
    local executables=(
        "manzh.sh"
        "translate_man.sh"
        "config_manager.sh"
        "clean.sh"
    )
    
    for exe in "${executables[@]}"; do
        if [[ ! -x "$INSTALL_DIR/$exe" ]]; then
            error_log "执行权限设置失败: $exe"
            check_failed=true
        fi
    done
    
    # 检查命令链接
    if [[ ! -L "$BIN_DIR/manzh" ]]; then
        error_log "命令链接创建失败"
        check_failed=true
    fi
    
    # 检查虚拟环境（如果启用）
    if [[ "$USE_VENV" == "true" ]]; then
        if [[ ! -d "$VENV_DIR" ]]; then
            error_log "虚拟环境创建失败"
            check_failed=true
        fi
        if [[ ! -f "$BIN_DIR/manzh-activate" ]]; then
            error_log "虚拟环境激活脚本创建失败"
            check_failed=true
        fi
        
        # 在虚拟环境中验证 Python 包
        log "在虚拟环境中验证 Python 包..."
        source "$VENV_DIR/bin/activate"
        
        if ! python3 -c "import requests" &> /dev/null; then
            error_log "Python requests 模块安装失败"
            check_failed=true
        fi
        if ! python3 -c "import google.generativeai" &> /dev/null; then
            error_log "Python google-generativeai 模块安装失败"
            check_failed=true
        fi
        
        deactivate
    else
        # 在系统环境中验证 Python 包
        if ! python3 -c "import requests" &> /dev/null; then
            error_log "Python requests 模块安装失败"
            check_failed=true
        fi
        if ! python3 -c "import google.generativeai" &> /dev/null; then
            error_log "Python google-generativeai 模块安装失败"
            check_failed=true
        fi
    fi
    
    if [[ "$check_failed" == "true" ]]; then
        handle_error "安装验证失败"
    fi
    
    log "安装验证通过"
}

# 创建卸载脚本
function create_uninstall_script() {
    log "创建卸载脚本..."
    
    cat > "$INSTALL_DIR/uninstall.sh" << 'EOF'
#!/bin/bash

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "错误：需要 root 权限卸载"
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

# 设置变量
INSTALL_DIR="/usr/local/manzh"
BIN_DIR="/usr/local/bin"
MAN_DIR="/usr/local/share/man/zh_CN"

# 询问是否保留配置
read -p "是否保留配置文件？[Y/n] " keep_config
if [[ "$keep_config" == "n" || "$keep_config" == "N" ]]; then
    rm -f "$INSTALL_DIR/config.json"
else
    # 备份配置文件
    if [[ -f "$INSTALL_DIR/config.json" ]]; then
        cp "$INSTALL_DIR/config.json" "/tmp/manzh_config.json.bak"
        echo "配置文件已备份到: /tmp/manzh_config.json.bak"
    fi
fi

# 询问是否删除已翻译的手册
read -p "是否删除已翻译的手册？[y/N] " remove_man
if [[ "$remove_man" == "y" || "$remove_man" == "Y" ]]; then
    rm -rf "$MAN_DIR"
    echo "已删除翻译手册"
fi

# 删除安装文件
rm -rf "$INSTALL_DIR"
rm -f "$BIN_DIR/manzh"
rm -f "$BIN_DIR/manzh-activate"

echo "卸载完成！"

# 如果保留了配置，显示恢复说明
if [[ "$keep_config" != "n" && "$keep_config" != "N" && -f "/tmp/manzh_config.json.bak" ]]; then
    echo
    echo "如果您之后重新安装，可以使用以下命令恢复配置："
    echo "sudo cp /tmp/manzh_config.json.bak /usr/local/manzh/config.json"
fi
EOF
    
    chmod +x "$INSTALL_DIR/uninstall.sh"
    log "卸载脚本已创建: $INSTALL_DIR/uninstall.sh"
}

# 设置 MANPATH
function setup_manpath() {
    log "配置 MANPATH 环境变量..."
    
    local manpath_line='export MANPATH="/usr/local/share/man/zh_CN:$MANPATH"'
    local shell_rc=""
    local shell_type=""
    
    # 检测当前用户的默认 shell
    local user_shell=$(basename "$SHELL")
    
    # 获取实际用户（非 root）的主目录
    if [[ $SUDO_USER ]]; then
        local real_user=$SUDO_USER
        if [[ "$(uname)" == "Darwin" ]]; then
            local user_home="/Users/$SUDO_USER"
        else
            local user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        fi
    else
        local real_user=$USER
        local user_home=$HOME
    fi
    
    # 检测系统类型和 shell
    if [[ "$(uname)" == "Darwin" ]]; then
        case "$user_shell" in
            "bash")
                # macOS 的 bash 配置文件优先级
                if [[ -f "$user_home/.bash_profile" ]]; then
                    shell_rc="$user_home/.bash_profile"
                elif [[ -f "$user_home/.profile" ]]; then
                    shell_rc="$user_home/.profile"
                else
                    shell_rc="$user_home/.bash_profile"
                    touch "$shell_rc"
                fi
                shell_type="bash"
                ;;
            "zsh")
                shell_rc="$user_home/.zshrc"
                shell_type="zsh"
                ;;
            *)
                log "警告：未知的 shell 类型：$user_shell"
                echo "请手动将以下行添加到您的 shell 配置文件中："
                echo "$manpath_line"
                return
                ;;
        esac
    else
        # Linux 系统处理
        case "$user_shell" in
            "bash")
                shell_rc="$user_home/.bashrc"
                shell_type="bash"
                ;;
            "zsh")
                shell_rc="$user_home/.zshrc"
                shell_type="zsh"
                ;;
            *)
                log "警告：未知的 shell 类型：$user_shell"
                echo "请手动将以下行添加到您的 shell 配置文件中："
                echo "$manpath_line"
                return
                ;;
        esac
    fi
    
    # 检查是否已经配置
    if grep -q "MANPATH.*\/usr\/local\/share\/man\/zh_CN" "$shell_rc" 2>/dev/null; then
        log "MANPATH 已经配置在 $shell_rc 中"
        return
    fi
    
    # 添加 MANPATH 配置
    echo >> "$shell_rc"
    echo "# ManZH - 中文手册路径" >> "$shell_rc"
    echo "$manpath_line" >> "$shell_rc"
    
    # 修改文件所有权回给实际用户
    chown "$real_user" "$shell_rc"
    
    log "MANPATH 已添加到 $shell_rc"
    echo
    echo "MANPATH 环境变量已配置。要立即生效，请运行："
    echo "source $shell_rc"
    echo
    echo "之后可以直接使用 'man <命令>' 查看中文手册"
    
    # 对于 macOS，添加额外提示
    if [[ "$(uname)" == "Darwin" ]]; then
        echo
        echo "注意：在 macOS 系统上，如果使用 Terminal.app，"
        echo "您可能需要在终端偏好设置中勾选 '使用选项键作为 Meta 键'"
        echo "以确保 man 手册中的中文显示正常。"
    fi
}

# 主安装流程
log "开始安装 Man手册中文翻译工具..."

# 检查依赖和权限
check_dependencies
check_permissions

# 备份现有安装
backup_existing

# 创建目录
create_dirs

# 复制文件
copy_files

# 询问是否使用虚拟环境
echo
echo "Python 环境选择："
echo "1) 使用虚拟环境（推荐）"
echo "2) 使用系统 Python 环境"
echo
echo "虚拟环境的优势："
echo "- 避免依赖冲突"
echo "- 更好的隔离性"
echo "- 更容易管理依赖"
echo "- 不影响系统 Python 环境"
echo
while true; do
    read -p "请选择 [1/2]: " venv_choice
    case $venv_choice in
        1)
            USE_VENV=true
            break
            ;;
        2)
            USE_VENV=false
            break
            ;;
        *)
            echo "请输入 1 或 2"
            ;;
    esac
done

# 检查并安装依赖
check_system

# 验证安装
verify_installation

# 创建卸载脚本
create_uninstall_script

# 配置 MANPATH
setup_manpath

log "安装和初始配置完成！"
echo
echo "使用方法："
if [[ "$USE_VENV" == "true" ]]; then
    echo "1. 首次使用前，请先激活虚拟环境："
    echo "   source manzh-activate"
    echo
    echo "2. 在虚拟环境中使用命令："
    echo "   manzh translate <命令>"
    echo "   manzh config"
    echo "   manzh list"
    echo
    echo "3. 退出虚拟环境："
    echo "   deactivate"
else
    echo "1. 命令行方式："
    echo "   manzh translate <命令>"
    echo "   manzh config"
    echo "   manzh list"
    echo
    echo "2. 交互式方式："
    echo "   manzh"
fi
echo

# 提示配置翻译服务
echo "==============================================="
echo "重要：ManZH 需要至少配置一个可用的翻译服务才能工作"
echo "现在将为您打开配置界面..."
echo "请至少添加一个翻译服务（OpenAI、DeepSeek、Gemini等）"
echo "==============================================="
echo
read -p "按回车键继续配置翻译服务..." 

# 如果使用虚拟环境，需要先激活
if [[ "$USE_VENV" == "true" ]]; then
    echo "正在激活虚拟环境..."
    source "$VENV_DIR/bin/activate"
fi

# 运行配置命令
"$INSTALL_DIR/manzh.sh" config

# 如果使用虚拟环境，完成后退出
if [[ "$USE_VENV" == "true" ]]; then
    deactivate
fi

# 配置 MANPATH
setup_manpath

log "安装和初始配置完成！"
echo
log "安装日志已保存到: $LOG_FILE"

# 根据环境显示下一步提示
if [[ "$USE_VENV" == "true" ]]; then
    echo
    echo "下一步："
    echo "1. 运行 'source manzh-activate' 激活虚拟环境"
    echo "2. 使用 'manzh translate <命令>' 开始翻译"
else
    echo
    echo "下一步："
    echo "直接运行 'manzh translate <命令>' 开始翻译"
fi 