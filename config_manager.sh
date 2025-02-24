#!/bin/bash

CONFIG_FILE="config.json"

# 检查 jq 是否安装
if ! command -v jq &> /dev/null; then
    echo "错误：需要安装 jq 来处理 JSON 文件"
    echo "请运行：brew install jq"
    exit 1
fi

# 读取配置文件并处理兼容性
function read_config() {
    local config=""
    
    # 如果配置文件不存在或为空，创建新的
    if [[ ! -f "$CONFIG_FILE" ]] || [[ ! -s "$CONFIG_FILE" ]]; then
        echo "{\"services\": {}, \"default_service\": null, \"defaults\": {\"max_context_length\": 4096, \"max_output_length\": 2048}}" > "$CONFIG_FILE"
    fi
    
    # 检查 JSON 格式是否有效
    if ! jq '.' "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "错误：配置文件格式无效"
        echo "正在重置配置文件..."
        echo "{\"services\": {}, \"default_service\": null, \"defaults\": {\"max_context_length\": 4096, \"max_output_length\": 2048}}" > "$CONFIG_FILE"
    fi
    
    # 读取配置文件
    config=$(cat "$CONFIG_FILE")
    
    # 检查是否需要升级配置
    local needs_upgrade=false
    
    # 检查是否存在 defaults 部分
    if ! echo "$config" | jq -e '.defaults' > /dev/null 2>&1; then
        config=$(echo "$config" | jq '. += {"defaults": {"max_context_length": 4096, "max_output_length": 2048}}')
        needs_upgrade=true
    fi
    
    # 检查每个服务的配置
    if echo "$config" | jq -e '.services' > /dev/null 2>&1; then
        local services=($(echo "$config" | jq -r '.services | keys[]'))
        for service in "${services[@]}"; do
            # 检查是否缺少服务类型
            if ! echo "$config" | jq -e ".services.\"$service\".type" > /dev/null 2>&1; then
                echo "注意：服务 '$service' 缺少类型设置，将设为 chatgpt"
                config=$(echo "$config" | jq ".services.\"$service\".type = \"chatgpt\"")
                needs_upgrade=true
            fi
            
            # 检查是否缺少上下文长度设置
            if ! echo "$config" | jq -e ".services.\"$service\".max_context_length" > /dev/null 2>&1; then
                echo "注意：服务 '$service' 缺少上下文长度设置，将使用默认值"
                config=$(echo "$config" | jq ".services.\"$service\".max_context_length = 4096")
                needs_upgrade=true
            fi
            
            # 检查是否缺少输出长度设置
            if ! echo "$config" | jq -e ".services.\"$service\".max_output_length" > /dev/null 2>&1; then
                echo "注意：服务 '$service' 缺少输出长度设置，将使用默认值"
                config=$(echo "$config" | jq ".services.\"$service\".max_output_length = 2048")
                needs_upgrade=true
            fi
        done
    fi
    
    # 如果配置有更新，保存并提示用户
    if [[ "$needs_upgrade" == "true" ]]; then
        echo "配置文件已更新，添加了缺失的参数设置"
        echo "您可以使用 '更新服务配置' 选项来调整这些参数"
        echo
        save_config "$config"
    fi
    
    echo "$config"
}

# 保存配置文件
function save_config() {
    # 验证 JSON 格式
    if ! echo "$1" | jq '.' > /dev/null 2>&1; then
        echo "错误：无效的配置数据"
        return 1
    fi
    
    # 保存配置
    echo "$1" | jq '.' > "$CONFIG_FILE"
}

# 交互式添加服务
function interactive_add_service() {
    echo "=== 添加新的翻译服务 ==="
    
    # 输入服务名称
    while true; do
        read -p "请输入服务名称（如 openai, deepseek, gemini）: " service_name
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
    
    # 选择服务类型
    echo "选择服务类型："
    echo "1) ChatGPT 兼容接口（OpenAI/DeepSeek/Ollama等）"
    echo "2) Google Gemini"
    while true; do
        read -p "请选择 [1-2]: " type_choice
        case $type_choice in
            1) service_type="chatgpt"; break;;
            2) service_type="gemini"; break;;
            *) echo "请选择有效的选项";;
        esac
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
    if [[ "$service_type" == "chatgpt" ]]; then
        echo "选择 API 地址："
        echo "1) OpenAI (api.openai.com)"
        echo "2) DeepSeek (api.deepseek.com)"
        echo "3) 自定义"
        while true; do
            read -p "请选择 [1-3]: " url_choice
            case $url_choice in
                1) url="https://api.openai.com"; break;;
                2) url="https://api.deepseek.com"; break;;
                3) read -p "请输入 API 域名（如 api.example.com）: " domain
                   echo
                   echo "说明：对于 ChatGPT 兼容接口，您只需要输入 API 域名部分。"
                   echo "系统会自动添加 'https://' 前缀和 '/v1/chat/completions' 路径。"
                   echo
                   echo "示例："
                   echo "✓ api.openai.com"
                   echo "✓ api.deepseek.com"
                   echo "✓ api.moonshot.cn"
                   echo "✗ https://api.openai.com/v1/chat/completions"
                   echo "✗ http://localhost:11434"
                   echo
                   read -p "请输入 API 域名: " domain
                   if [[ -n "$domain" ]]; then
                       # 移除可能的协议前缀和尾部斜杠
                       domain=$(echo "$domain" | sed -E 's#^(https?://)?##' | sed 's#/$##')
                       url="https://$domain"
                       break
                   fi;;
                *) echo "请选择有效的选项";;
            esac
        done
        # 添加统一的路径
        url="${url}/v1/chat/completions"
    fi
    
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
    
    # 添加上下文长度设置
    echo "设置上下文长度（字符数）："
    echo "1) 4K  (4096)"
    echo "2) 8K  (8192)"
    echo "3) 32K (32768)"
    echo "4) 64K (65536)"
    echo "5) 自定义"
    
    while true; do
        read -p "请选择 [1-5]: " length_choice
        case $length_choice in
            1) context_length=4096; break;;
            2) context_length=8192; break;;
            3) context_length=32768; break;;
            4) context_length=65536; break;;
            5) read -p "请输入自定义长度: " context_length
               if [[ "$context_length" =~ ^[0-9]+$ ]]; then break; fi
               echo "请输入有效的数字";;
            *) echo "请选择有效的选项";;
        esac
    done
    
    # 添加输出长度设置
    echo "设置最大输出长度（字符数）："
    echo "1) 2K  (2048)"
    echo "2) 4K  (4096)"
    echo "3) 8K  (8192)"
    echo "4) 自定义"
    
    while true; do
        read -p "请选择 [1-4]: " output_choice
        case $output_choice in
            1) output_length=2048; break;;
            2) output_length=4096; break;;
            3) output_length=8192; break;;
            4) read -p "请输入自定义长度: " output_length
               if [[ "$output_length" =~ ^[0-9]+$ ]]; then break; fi
               echo "请输入有效的数字";;
            *) echo "请选择有效的选项";;
        esac
    done
    
    # 更新确认信息显示
    echo
    echo "请确认以下信息："
    echo "服务名称: $service_name"
    echo "服务类型: $service_type"
    echo "API 密钥: $api_key"
    if [[ "$service_type" != "gemini" ]]; then
        echo "API 地址: $url"
    fi
    echo "模型名称: $model"
    echo "上下文长度: $context_length"
    echo "输出长度: $output_length"
    
    read -p "是否确认添加？[y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消添加服务"
        return 1
    fi
    
    # 更新配置保存
    local config=$(read_config)
    
    # 根据服务类型创建不同的配置
    if [[ "$service_type" == "gemini" ]]; then
        config=$(echo "$config" | jq ".services.\"$service_name\" = {
            \"type\": \"gemini\",
            \"service\": \"$service_name\",
            \"api_key\": \"$api_key\",
            \"model\": \"$model\",
            \"language\": \"zh-CN\",
            \"max_context_length\": $context_length,
            \"max_output_length\": $output_length
        }")
    else
        config=$(echo "$config" | jq ".services.\"$service_name\" = {
            \"type\": \"chatgpt\",
            \"service\": \"$service_name\",
            \"api_key\": \"$api_key\",
            \"url\": \"$url\",
            \"model\": \"$model\",
            \"language\": \"zh-CN\",
            \"max_context_length\": $context_length,
            \"max_output_length\": $output_length
        }")
    fi
    
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
        local service_type=$(echo "$config" | jq -r ".services.\"${services[$i]}\".type")
        echo "$((i+1))) ${services[$i]} ($service_type)"
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
    
    # 获取当前服务类型
    current_type=$(echo "$config" | jq -r ".services.\"$service_name\".type")
    
    # 选择要更新的字段
    echo "选择要更新的配置项："
    echo "1) 服务类型"
    echo "2) API 密钥"
    if [[ "$current_type" != "gemini" ]]; then
        echo "3) API 地址"
    fi
    echo "4) 模型名称"
    echo "5) 语言设置"
    echo "6) 上下文长度"
    echo "7) 输出长度"
    
    while true; do
        read -p "请选择 [1-7]: " field_choice
        case $field_choice in
            1) field="type"
               echo "选择服务类型："
               echo "1) ChatGPT 兼容接口"
               echo "2) Google Gemini"
               while true; do
                   read -p "请选择 [1-2]: " type_choice
                   case $type_choice in
                       1) value="chatgpt"
                          # 如果从 Gemini 切换到 ChatGPT，需要添加 URL
                          if [[ "$current_type" == "gemini" ]]; then
                              echo "选择 API 地址："
                              echo "1) OpenAI (api.openai.com)"
                              echo "2) DeepSeek (api.deepseek.com)"
                              echo "3) 自定义"
                              while true; do
                                  read -p "请选择 [1-3]: " url_choice
                                  case $url_choice in
                                      1) url="https://api.openai.com"; break;;
                                      2) url="https://api.deepseek.com"; break;;
                                      3) read -p "请输入 API 域名（如 api.example.com）: " domain
                                         echo
                                         echo "说明：对于 ChatGPT 兼容接口，您只需要输入 API 域名部分。"
                                         echo "系统会自动添加 'https://' 前缀和 '/v1/chat/completions' 路径。"
                                         echo
                                         echo "示例："
                                         echo "✓ api.openai.com"
                                         echo "✓ api.deepseek.com"
                                         echo "✓ api.moonshot.cn"
                                         echo "✗ https://api.openai.com/v1/chat/completions"
                                         echo "✗ http://localhost:11434"
                                         echo
                                         read -p "请输入 API 域名: " domain
                                         if [[ -n "$domain" ]]; then
                                             # 移除可能的协议前缀和尾部斜杠
                                             domain=$(echo "$domain" | sed -E 's#^(https?://)?##' | sed 's#/$##')
                                             url="https://$domain"
                                             break
                                         fi;;
                                      *) echo "请选择有效的选项";;
                                  esac
                              done
                              # 添加统一的路径
                              url="${url}/v1/chat/completions"
                          fi
                          break;;
                       2) value="gemini"
                          # 如果从 ChatGPT 切换到 Gemini，需要删除 URL
                          if [[ "$current_type" != "gemini" ]]; then
                              config=$(echo "$config" | jq "del(.services.\"$service_name\".url)")
                          fi
                          break;;
                       *) echo "请选择有效的选项";;
                   esac
               done
               ;;
            2) field="api_key"
               read -p "请输入新的 API 密钥: " value
               ;;
            3) if [[ "$current_type" != "gemini" ]]; then
                   field="url"
                   echo "选择 API 地址："
                   echo "1) OpenAI (api.openai.com)"
                   echo "2) DeepSeek (api.deepseek.com)"
                   echo "3) 自定义"
                   while true; do
                       read -p "请选择 [1-3]: " url_choice
                       case $url_choice in
                           1) value="https://api.openai.com"; break;;
                           2) value="https://api.deepseek.com"; break;;
                           3) read -p "请输入 API 域名（如 api.example.com）: " domain
                              echo
                              echo "说明：对于 ChatGPT 兼容接口，您只需要输入 API 域名部分。"
                              echo "系统会自动添加 'https://' 前缀和 '/v1/chat/completions' 路径。"
                              echo
                              echo "示例："
                              echo "✓ api.openai.com"
                              echo "✓ api.deepseek.com"
                              echo "✓ api.moonshot.cn"
                              echo "✗ https://api.openai.com/v1/chat/completions"
                              echo "✗ http://localhost:11434"
                              echo
                              read -p "请输入 API 域名: " domain
                              if [[ -n "$domain" ]]; then
                                  # 移除可能的协议前缀和尾部斜杠
                                  domain=$(echo "$domain" | sed -E 's#^(https?://)?##' | sed 's#/$##')
                                  value="https://$domain"
                                  break
                              fi;;
                           *) echo "请选择有效的选项";;
                       esac
                   done
                   # 添加统一的路径
                   value="${value}/v1/chat/completions"
               else
                   echo "Gemini 服务不需要 API 地址"
                   continue
               fi
               ;;
            4) field="model"
               if [[ "$current_type" == "gemini" ]]; then
                   echo "选择 Gemini 模型："
                   echo "1) gemini-pro"
                   echo "2) gemini-2.0-flash-exp"
                   echo "3) 自定义"
                   while true; do
                       read -p "请选择 [1-3]: " model_choice
                       case $model_choice in
                           1) value="gemini-pro"; break;;
                           2) value="gemini-2.0-flash-exp"; break;;
                           3) read -p "请输入自定义模型名称: " value;
                              if [[ -n "$value" ]]; then break; fi;;
                           *) echo "请选择有效的选项";;
                       esac
                   done
               else
                   echo "选择模型："
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
               fi
               ;;
            5) field="language"
               read -p "请输入语言代码 (默认 zh-CN): " value
               value=${value:-zh-CN}
               ;;
            6) field="max_context_length"
               echo "设置上下文长度（字符数）："
               echo "1) 4K  (4096)"
               echo "2) 8K  (8192)"
               echo "3) 32K (32768)"
               echo "4) 64K (65536)"
               echo "5) 自定义"
               while true; do
                   read -p "请选择 [1-5]: " length_choice
                   case $length_choice in
                       1) value=4096; break;;
                       2) value=8192; break;;
                       3) value=32768; break;;
                       4) value=65536; break;;
                       5) read -p "请输入自定义长度: " value
                          if [[ "$value" =~ ^[0-9]+$ ]]; then break; fi
                          echo "请输入有效的数字";;
                       *) echo "请选择有效的选项";;
                   esac
               done
               ;;
            7) field="max_output_length"
               echo "设置最大输出长度（字符数）："
               echo "1) 2K  (2048)"
               echo "2) 4K  (4096)"
               echo "3) 8K  (8192)"
               echo "4) 自定义"
               while true; do
                   read -p "请选择 [1-4]: " output_choice
                   case $output_choice in
                       1) value=2048; break;;
                       2) value=4096; break;;
                       3) value=8192; break;;
                       4) read -p "请输入自定义长度: " value
                          if [[ "$value" =~ ^[0-9]+$ ]]; then break; fi
                          echo "请输入有效的数字";;
                       *) echo "请选择有效的选项";;
                   esac
               done
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
    if [[ "$field" == "max_context_length" || "$field" == "max_output_length" ]]; then
        config=$(echo "$config" | jq ".services.\"$service_name\".\"$field\" = $value")
    else
        config=$(echo "$config" | jq ".services.\"$service_name\".\"$field\" = \"$value\"")
    fi
    
    # 如果更新了类型为 chatgpt 并且需要添加 URL
    if [[ "$field" == "type" && "$value" == "chatgpt" && -n "$url" ]]; then
        config=$(echo "$config" | jq ".services.\"$service_name\".url = \"$url\"")
    fi
    
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
    
    # 设置默认服务
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
        local service_type=$(echo "$config" | jq -r ".services.\"$service\".type")
        local api_key=$(echo "$config" | jq -r ".services.\"$service\".api_key")
        local model=$(echo "$config" | jq -r ".services.\"$service\".model")
        local context_length=$(echo "$config" | jq -r ".services.\"$service\".max_context_length")
        local output_length=$(echo "$config" | jq -r ".services.\"$service\".max_output_length")
        
        if [[ "$service" == "$default_service" ]]; then
            echo "* $service (默认服务)"
        else
            echo "  $service"
        fi
        echo "    服务类型: $service_type"
        if [[ "$service_type" != "gemini" ]]; then
            local url=$(echo "$config" | jq -r ".services.\"$service\".url")
            echo "    API 地址: $url"
        fi
        echo "    模型: $model"
        echo "    API 密钥: ${api_key:0:8}..."
        echo "    上下文长度: $context_length"
        echo "    输出长度: $output_length"
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
    local service_type=$(echo "$service_config" | jq -r '.type')
    
    echo "服务名称: $default_service"
    echo "服务类型: $service_type"
    if [[ "$service_type" != "gemini" ]]; then
        echo "API 地址: $(echo "$service_config" | jq -r '.url')"
    fi
    echo "模型: $(echo "$service_config" | jq -r '.model')"
    echo "API 密钥: $(echo "$service_config" | jq -r '.api_key' | cut -c1-8)..."
    echo "语言: $(echo "$service_config" | jq -r '.language')"
    echo "上下文长度: $(echo "$service_config" | jq -r '.max_context_length')"
    echo "输出长度: $(echo "$service_config" | jq -r '.max_output_length')"
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