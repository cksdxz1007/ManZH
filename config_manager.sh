#!/bin/bash

CONFIG_FILE="config.json"

# 检查 jq 是否安装
if ! command -v jq &> /dev/null; then
    echo "错误：需要安装 jq 来处理 JSON 文件"
    echo "请运行：brew install jq"
    exit 1
fi

# 读取配置文件
function read_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "{\"services\": {}, \"default_service\": null}" > "$CONFIG_FILE"
    fi
    cat "$CONFIG_FILE"
}

# 保存配置文件
function save_config() {
    echo "$1" | jq '.' > "$CONFIG_FILE"
}

# 交互式添加服务
function interactive_add_service() {
    echo "=== 添加新的翻译服务 ==="
    
    # 输入服务名称
    while true; do
        read -p "请输入服务名称（如 openai, deepseek）: " service_name
        if [[ -z "$service_name" ]]; then
            echo "服务名称不能为空"
            continue
        fi
        
        # 检查服务是否已存在
        if echo "$(read_config)" | jq -e ".services.\"$service_name\"" > /dev/null; then
            echo "服务 '$service_name' 已存在"
            continue
        fi
        break
    done
    
    # 输入 API 密钥
    while true; do
        read -p "请输入 API 密钥: " api_key
        if [[ -z "$api_key" ]]; then
            echo "API 密钥不能为空"
            continue
        fi
        break
    done
    
    # 选择预设 API 地址或自定义
    echo "选择 API 地址："
    echo "1) OpenAI (https://api.openai.com/v1/chat/completions)"
    echo "2) DeepSeek (https://api.deepseek.com/v1/chat/completions)"
    echo "3) 自定义"
    while true; do
        read -p "请选择 [1-3]: " url_choice
        case $url_choice in
            1) url="https://api.openai.com/v1/chat/completions"; break;;
            2) url="https://api.deepseek.com/v1/chat/completions"; break;;
            3) read -p "请输入自定义 API 地址: " url; 
               if [[ -n "$url" ]]; then break; fi;;
            *) echo "请选择有效的选项";;
        esac
    done
    
    # 选择预设模型或自定义
    echo "选择模型："
    echo "1) GPT-4"
    echo "2) GPT-3.5-turbo"
    echo "3) DeepSeek-chat"
    echo "4) 自定义"
    while true; do
        read -p "请选择 [1-4]: " model_choice
        case $model_choice in
            1) model="gpt-4"; break;;
            2) model="gpt-3.5-turbo"; break;;
            3) model="deepseek-chat"; break;;
            4) read -p "请输入自定义模型名称: " model;
               if [[ -n "$model" ]]; then break; fi;;
            *) echo "请选择有效的选项";;
        esac
    done
    
    # 确认信息
    echo
    echo "请确认以下信息："
    echo "服务名称: $service_name"
    echo "API 密钥: $api_key"
    echo "API 地址: $url"
    echo "模型名称: $model"
    
    read -p "是否确认添加？[y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消添加服务"
        return 1
    fi
    
    # 添加服务
    local config=$(read_config)
    config=$(echo "$config" | jq ".services.\"$service_name\" = {
        \"service\": \"$service_name\",
        \"api_key\": \"$api_key\",
        \"url\": \"$url\",
        \"model\": \"$model\",
        \"language\": \"zh-CN\"
    }")
    
    # 如果是第一个服务，设为默认
    if [[ $(echo "$config" | jq '.default_service') == "null" ]]; then
        config=$(echo "$config" | jq ".default_service = \"$service_name\"")
    fi
    
    save_config "$config"
    echo "服务 '$service_name' 添加成功"
    
    # 询问是否设为默认服务
    if [[ $(echo "$config" | jq -r '.default_service') != "$service_name" ]]; then
        read -p "是否将此服务设为默认？[y/N] " set_default
        if [[ "$set_default" == "y" || "$set_default" == "Y" ]]; then
            config=$(echo "$config" | jq ".default_service = \"$service_name\"")
            save_config "$config"
            echo "已将 '$service_name' 设为默认服务"
        fi
    fi
}

# 交互式删除服务
function interactive_remove_service() {
    echo "=== 删除翻译服务 ==="
    
    # 获取现有服务列表
    local config=$(read_config)
    local services=($(echo "$config" | jq -r '.services | keys[]'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo "当前没有配置任何服务"
        return 1
    fi
    
    # 显示服务列表
    echo "现有服务："
    for i in "${!services[@]}"; do
        echo "$((i+1))) ${services[$i]}"
    done
    
    # 选择要删除的服务
    while true; do
        read -p "请选择要删除的服务 [1-${#services[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#services[@]}" ]]; then
            service_name="${services[$((choice-1))]}"
            break
        fi
        echo "请输入有效的选项"
    done
    
    # 确认删除
    read -p "确定要删除服务 '$service_name' 吗？[y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消删除"
        return 1
    fi
    
    # 删除服务
    if [[ $(echo "$config" | jq -r ".default_service") == "$service_name" ]]; then
        config=$(echo "$config" | jq '.default_service = null')
    fi
    
    config=$(echo "$config" | jq "del(.services.\"$service_name\")")
    save_config "$config"
    echo "服务 '$service_name' 已删除"
}

# 交互式更新服务
function interactive_update_service() {
    echo "=== 更新服务配置 ==="
    
    # 获取现有服务列表
    local config=$(read_config)
    local services=($(echo "$config" | jq -r '.services | keys[]'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo "当前没有配置任何服务"
        return 1
    fi
    
    # 显示服务列表
    echo "选择要更新的服务："
    for i in "${!services[@]}"; do
        echo "$((i+1))) ${services[$i]}"
    done
    
    # 选择服务
    while true; do
        read -p "请选择 [1-${#services[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#services[@]}" ]]; then
            service_name="${services[$((choice-1))]}"
            break
        fi
        echo "请���入有效的选项"
    done
    
    # 选择要更新的字段
    echo "选择要更新的配置项："
    echo "1) API 密钥"
    echo "2) API 地址"
    echo "3) 模型名称"
    echo "4) 语言设置"
    
    while true; do
        read -p "请选择 [1-4]: " field_choice
        case $field_choice in
            1) field="api_key"
               read -p "请输入新的 API 密钥: " value
               ;;
            2) field="url"
               echo "选择 API 地址："
               echo "1) OpenAI (https://api.openai.com/v1/chat/completions)"
               echo "2) DeepSeek (https://api.deepseek.com/v1/chat/completions)"
               echo "3) 自定义"
               while true; do
                   read -p "请选择 [1-3]: " url_choice
                   case $url_choice in
                       1) value="https://api.openai.com/v1/chat/completions"; break;;
                       2) value="https://api.deepseek.com/v1/chat/completions"; break;;
                       3) read -p "请输入自定义 API 地址: " value; 
                          if [[ -n "$value" ]]; then break; fi;;
                       *) echo "请选择有效的选项";;
                   esac
               done
               ;;
            3) field="model"
               echo "���择模型："
               echo "1) GPT-4"
               echo "2) GPT-3.5-turbo"
               echo "3) DeepSeek-chat"
               echo "4) 自定义"
               while true; do
                   read -p "请选择 [1-4]: " model_choice
                   case $model_choice in
                       1) value="gpt-4"; break;;
                       2) value="gpt-3.5-turbo"; break;;
                       3) value="deepseek-chat"; break;;
                       4) read -p "请输入自定义模型名称: " value;
                          if [[ -n "$value" ]]; then break; fi;;
                       *) echo "请选择有效的选项";;
                   esac
               done
               ;;
            4) field="language"
               read -p "请输入语言代码 (默认 zh-CN): " value
               value=${value:-zh-CN}
               ;;
            *) echo "请选择有效的选项"; continue;;
        esac
        break
    done
    
    # 确认更新
    echo
    echo "请确认更新信息："
    echo "服务名称: $service_name"
    echo "更新字段: $field"
    echo "新的值: $value"
    
    read -p "是否确认更新？[y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消更新"
        return 1
    fi
    
    # 更新配置
    config=$(echo "$config" | jq ".services.\"$service_name\".\"$field\" = \"$value\"")
    save_config "$config"
    echo "服务 '$service_name' 的 '$field' 已更新"
}

# 交互式设置默认服务
function interactive_set_default() {
    echo "=== 设置默认服务 ==="
    
    # 获取现有服务列表
    local config=$(read_config)
    local services=($(echo "$config" | jq -r '.services | keys[]'))
    local current_default=$(echo "$config" | jq -r '.default_service')
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo "当前没有配置任何服务"
        return 1
    fi
    
    # 显示服务列表
    echo "选择默认服务："
    for i in "${!services[@]}"; do
        if [[ "${services[$i]}" == "$current_default" ]]; then
            echo "$((i+1))) ${services[$i]} (当前默认)"
        else
            echo "$((i+1))) ${services[$i]}"
        fi
    done
    
    # 选择服务
    while true; do
        read -p "请选择 [1-${#services[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#services[@]}" ]]; then
            service_name="${services[$((choice-1))]}"
            break
        fi
        echo "请输入有效的选项"
    done
    
    # ���置默认服务
    config=$(echo "$config" | jq ".default_service = \"$service_name\"")
    save_config "$config"
    echo "已将 '$service_name' 设为默认服务"
}

# 列出所有服务
function list_services() {
    echo "=== 已配置的服务 ==="
    
    local config=$(read_config)
    local default_service=$(echo "$config" | jq -r '.default_service')
    local services=($(echo "$config" | jq -r '.services | keys[]'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo "当前没有配置任何服务"
        return 1
    fi
    
    # 显示服务列表
    for service in "${services[@]}"; do
        local api_key=$(echo "$config" | jq -r ".services.\"$service\".api_key")
        local url=$(echo "$config" | jq -r ".services.\"$service\".url")
        local model=$(echo "$config" | jq -r ".services.\"$service\".model")
        
        if [[ "$service" == "$default_service" ]]; then
            echo "* $service (默认服务)"
        else
            echo "  $service"
        fi
        echo "    API 地址: $url"
        echo "    模型: $model"
        echo "    API 密钥: ${api_key:0:8}..."
        echo
    done
}

# 获取当前默认服务
function get_default_service() {
    echo "=== 当前默认服务 ==="
    
    local config=$(read_config)
    local default_service=$(echo "$config" | jq -r '.default_service')
    
    if [[ "$default_service" == "null" ]]; then
        echo "当前没有设置默认服务"
        return 1
    fi
    
    local service_config=$(echo "$config" | jq -r ".services.\"$default_service\"")
    
    echo "服务名称: $default_service"
    echo "API 地址: $(echo "$service_config" | jq -r '.url')"
    echo "模型: $(echo "$service_config" | jq -r '.model')"
    echo "API 密钥: $(echo "$service_config" | jq -r '.api_key' | cut -c1-8)..."
    echo "语言: $(echo "$service_config" | jq -r '.language')"
}

# 主菜单
function show_menu() {
    while true; do
        echo
        echo "=== 翻译服务配置管理 ==="
        echo "1) 查看所有服务"
        echo "2) 添加新服务"
        echo "3) 删除服务"
        echo "4) 更新服务配置"
        echo "5) 设置默认服务"
        echo "6) 查看当前默认服务"
        echo "0) 退出"
        echo
        
        read -p "请选择操作 [0-6]: " choice
        echo
        
        case $choice in
            1) list_services;;
            2) interactive_add_service;;
            3) interactive_remove_service;;
            4) interactive_update_service;;
            5) interactive_set_default;;
            6) get_default_service;;
            0) exit 0;;
            *) echo "请选择有效的选项";;
        esac
    done
}

# 启动主菜单
show_menu