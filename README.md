# ManZH - Man手册中文翻译工具

一个用于将 Linux/Unix man 手册翻译成中文的自动化工具，支持多种翻译服务。

## 功能特点

- 自动获取和翻译命令的 man 手册
- 支持翻译命令的 --help 输出（当没有 man 手册时）
- 支持多个翻译服务（OpenAI、DeepSeek、Ollama 等）
- 支持自定义上下文长度和输出长度
- 智能适配不同翻译服务的参数
- 支持多章节手册的批量翻译
- 保留原始格式和代码块
- 交互式配置界面
- 多线程并行翻译
- 支持断点续传
- 显示翻译进度
- 错误日志记录

## 系统要求

- Linux/Unix 操作系统或 macOS
- Python 3.x
- 以下依赖包（安装脚本会自动安装）：
  - jq
  - python3-requests
  - man
  - col

## 安装

### 推荐方法：使用安装脚本

1. 克隆仓库：
```bash
git clone git@github.com:cksdxz1007/ManZH.git
cd ManZH
```

2. 运行安装脚本：
```bash
sudo ./install.sh
```

安装脚本会自动完成以下操作：
- 检查系统兼容性
- 安装所需依赖
- 设置 Python 环境（系统环境或虚拟环境）
- 创建必要目录
- 配置 MANPATH 环境变量
- 创建命令链接

#### 安装选项

安装脚本会提示您选择 Python 环境：
```bash
Python 环境选择：
1) 使用虚拟环境（推荐）
2) 使用系统 Python 环境
```

选择虚拟环境安装的优势：
- 避免与系统 Python 包冲突
- 更容易管理依赖
- 可以使用 `manzh-activate` 命令激活环境

#### 安装后的验证

安装完成后，可以通过以下方式验证安装：

```bash
# 检查命令是否可用
which manzh

# 检查虚拟环境
ls -la /usr/local/manzh/venv

# 检查配置文件
cat /usr/local/manzh/config.json
```

### 手动安装（高级用户）

如果您不想使用安装脚本，也可以手动安装：

1. 安装依赖：

在 macOS 上：
```bash
brew install jq python3 groff
pip3 install requests
```

在 Linux 上：
```bash
# Ubuntu/Debian
sudo apt install jq python3 python3-requests man-db groff

# CentOS/RHEL
sudo yum install jq python3 python3-requests man-db groff
```

2. 添加执行权限：
```bash
chmod +x manzh.sh config_manager.sh translate_man.sh clean.sh
```

3. 设置 MANPATH（可选）：
```bash
# 添加到 ~/.bashrc 或 ~/.zshrc
export MANPATH="/usr/local/share/man/zh_CN:$MANPATH"

# 使设置生效
source ~/.bashrc  # 或 source ~/.zshrc
```

4. 创建必要目录：
```bash
sudo mkdir -p /usr/local/manzh /usr/local/share/man/zh_CN
```

## 使用方法

### 首次使用配置

安装完成后，首次使用前需要配置至少一个翻译服务：

```bash
manzh config
```

按照提示添加翻译服务（如 OpenAI、DeepSeek、Ollama 等）。

### 交互式界面

直接运行主程序：
```bash
manzh
```

将显示交互式菜单，包含以下选项：
1. 翻译命令手册
2. 配置翻译服务
3. 查看已翻译手册
4. 清理已翻译手册
5. 显示版本信息

### 命令行模式

1. 翻译命令手册：
```bash
manzh translate ls
```

2. 配置翻译服务：
```bash
manzh config
```

3. 查看已翻译手册：
```bash
manzh list
```

4. 清理已翻译手册：
```bash
manzh clean
```

### 虚拟环境使用

如果您在安装时选择了虚拟环境，需要先激活环境：

1. 激活虚拟环境：
   ```bash
   source manzh-activate
   ```

2. 在虚拟环境中使用 ManZH：
   ```bash
   manzh translate ls
   ```

3. 退出虚拟环境：
   ```bash
   deactivate
   ```

虚拟环境的优势：
- 避免依赖冲突
- 更好的隔离性
- 更容易管理依赖
- 不影响系统 Python 环境

## 配置翻译服务

支持多种翻译服务，可以通过配置管理工具进行管理：

```bash
manzh config
```

支持的服务：

### 1. OpenAI 兼容接口类型
- OpenAI (GPT-4, GPT-3.5-turbo)
- DeepSeek
- Ollama (本地模型)
- 任何兼容 OpenAI API 格式的服务

### 2. Google Gemini 类型
- Google Gemini (gemini-2.0-flash-exp 等模型)

配置示例：
```json
{
  "services": {
    "openai": {
      "service": "openai",
      "api_key": "your-api-key",
      "url": "https://api.openai.com/v1/chat/completions",
      "model": "gpt-4",
      "language": "zh-CN",
      "max_context_length": 8192,
      "max_output_length": 4096
    }
  },
  "default_service": "openai",
  "defaults": {
    "max_context_length": 4096,
    "max_output_length": 2048
  }
}
```

## 配置文件详解

ManZH 的配置文件 `config.json` 包含以下主要部分：

### 服务配置

每个翻译服务的配置包含以下字段：

| 字段 | 说明 | 示例值 |
|------|------|--------|
| type | 服务类型 | "chatgpt" 或 "gemini" |
| service | 服务名称 | "openai", "deepseek", "ollama", "gemini" |
| api_key | API 密钥 | "sk-abcdef123456" |
| url | API 端点 | "https://api.openai.com/v1/chat/completions" |
| model | 模型名称 | "gpt-4", "deepseek-chat", "gemini-2.0-flash-exp" |
| language | 目标语言 | "zh-CN" |
| max_context_length | 上下文最大长度 | 8192 |
| max_output_length | 输出最大长度 | 4096 |

### 本地模型配置 (Ollama)

使用 Ollama 本地模型的配置示例：

```json
"ollama": {
  "type": "chatgpt",
  "service": "ollama",
  "api_key": "123",  // 可以是任意值
  "url": "http://localhost:11434/v1/chat/completions",
  "model": "qwen2.5:7b",  // 使用已下载的模型名称
  "language": "zh-CN",
  "max_context_length": 4096,
  "max_output_length": 2048
}
```

## 翻译结果

翻译后的手册将保存在：
```
/usr/local/share/man/zh_CN/man<章节号>/
```

查看翻译后的手册：
```bash
man -M /usr/local/share/man/zh_CN <命令>
```

例如：
```bash
man -M /usr/local/share/man/zh_CN ls
```

注：对于没有 man 手册的命令（如 conda），ManZH 会自动尝试翻译 --help 输出：
```bash
# 翻译 conda 命令的帮助信息
manzh translate conda

# 查看翻译结果
man -M /usr/local/share/man/zh_CN conda
```

## 目录结构

```
.
├── manzh.sh           # 主控脚本
├── config_manager.sh   # 配置管理脚本
├── translate_man.sh    # 翻译脚本
├── translate.py        # Python 翻译模块
├── clean.sh           # 清理脚本
├── config.json        # 配置文件
└── README.md          # 说明文档
```

## 注意事项

1. 需要 root 权限来安装翻译后的手册
2. 首次使用前请先配置翻译服务
3. 翻译质量取决于所选用的翻译服务
4. 建议在网络稳定的环境下使用
5. 注意 API 使用配额限制

## 常见问题与解决方案

### 翻译失败但仍保存了空文件

**症状**：翻译过程报错，但系统仍然提示翻译结果已保存
**解决方案**：
- 升级到 v1.0.4 或更高版本，此问题已修复
- 手动删除可能存在的空文件：`sudo rm /usr/local/share/man/zh_CN/man1/<命令>.1`

### 虚拟环境兼容性问题

**症状**：使用 `manzh-activate` 激活环境后，运行 `manzh.sh` 提示"当前在其他虚拟环境中"
**解决方案**：
- 升级到 v1.0.4 或更高版本，此问题已修复
- 或使用 `deactivate` 退出当前环境后再运行

### 翻译服务 API 错误

**症状**：翻译过程中出现 API 相关错误，如 "User location is not supported" 或 "Resource has been exhausted"
**解决方案**：
- 检查 API 密钥是否正确
- 尝试切换到其他翻译服务，如 DeepSeek 或 Ollama
- 检查 API 使用配额和区域限制

## 故障排除

1. 如果遇到权限问题：
   - 确保使用 sudo 运行安装脚本和涉及文件系统操作的命令

2. 如果翻译服务无响应：
   - 检查网络连接
   - 验证 API 密钥是否正确
   - 查看 translate_error.log 文件

3. 如果手册格式异常：
   - 尝试清理后重新翻译
   - 检查原始手册格式

## 高级使用技巧

### 批量翻译常用命令

创建一个脚本批量翻译常用命令：

```bash
#!/bin/bash
COMMANDS=(
  "ls" "cd" "grep" "find" "awk" "sed"
  "tar" "cp" "mv" "rm" "mkdir" "chmod"
)

for cmd in "${COMMANDS[@]}"; do
  echo "正在翻译: $cmd"
  manzh translate "$cmd"
  echo "-------------------"
done
```

### 集成到系统 man 命令

在 `~/.bashrc` 或 `~/.zshrc` 中添加以下函数：

```bash
# 优先使用中文手册，如果没有则使用英文手册
function man() {
  LANG=zh_CN command man -M /usr/local/share/man/zh_CN "$@" 2>/dev/null || command man "$@"
}
```

### 自动更新翻译

创建定期更新脚本：

```bash
#!/bin/bash
# 保存为 update-manzh.sh

# 获取已翻译的命令列表
TRANSLATED=$(find /usr/local/share/man/zh_CN -type f -name "*.1" | xargs -n1 basename | sed 's/\.1$//')

# 重新翻译所有命令
for cmd in $TRANSLATED; do
  echo "更新翻译: $cmd"
  manzh translate "$cmd"
done
```

## 性能优化建议

### 翻译大型手册

对于特别大的手册页（如 bash、gcc），可以考虑：

1. 增加配置中的上下文长度和输出长度：
   ```json
   "max_context_length": 16384,
   "max_output_length": 8192
   ```

2. 使用本地模型（如 Ollama）减少网络延迟

3. 分段翻译，使用 `man <命令> | head -n 1000` 等命令分段处理

### 减少 API 使用量

1. 使用 `clean.sh` 定期清理不常用的翻译
2. 优先翻译常用命令
3. 考虑使用本地模型如 Ollama

## 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性支持
3. 提交更改
4. 推送到分支
5. 创建 Pull Request

## 许可证

MIT

## 作者

cynning

## 更新日志

### v1.0.4
- 改进错误处理机制
  - 修复翻译失败时仍保存空文件的问题
  - 添加翻译内容有效性检查
  - 完善翻译失败时的错误提示
- 优化虚拟环境管理
  - 修复 manzh-activate 激活环境后的兼容性问题
  - 改进虚拟环境检测逻辑
  - 优化环境切换提示信息
- 改进 macOS 支持
  - 优化 man 手册处理逻辑
  - 添加 mandoc/groff 自动选择
  - 完善 macOS 下的依赖检查
- 代码结构优化
  - 重构翻译服务抽象层
  - 改进配置文件缓存机制
  - 优化多线程翻译队列
- 翻译服务增强
  - 完善翻译服务错误重试机制
  - 优化翻译缓存策略
  - 改进翻译进度显示

### v1.0.3
- 添加 Google Gemini API 支持
  - 支持 gemini-2.0-flash-exp 模型
  - 优化翻译服务配置结构
  - 添加服务类型验证
- 改进清理功能
  - 添加交互式清理菜单
  - 支持按章节列出已翻译命令
  - 支持删除指定命令的手册
  - 支持清空所有翻译
  - 优化错误日志管理
- 代码优化
  - 添加翻译服务抽象基类
  - 改进配置文件验证
  - 增强错误处理机制
  - 优化进度显示

### v1.0.2
- 修复翻译后的手册无法在列表中显示的问题
- 修复 man 手册和 --help 输出的保存问题
- 改进 --help 翻译的保存格式
- 添加翻译文件保存路径的提示
- 优化命令检查和错误提示逻辑

### v1.0.1
- 添加对 --help 输出的翻译支持
- 优化无 man 手册命令的处理
- 改进翻译提示信息
- 添加上下文长度和输出长度配置
- 优化配置文件兼容性处理

### v1.0.0
- 初始版本发布
- 支持多种翻译服务
- 添加交互式界面
- 支持多线程翻译

## 平台支持

### macOS
- 使用 `man -M` 选项查看翻译后的手册
- 需要安装 groff 以支持手册格式化：`brew install groff`
- 使用 Homebrew 安装依赖

### Linux
- 直接支持 `man -M` 和 `MANPATH` 设置
- 通过包管理器安装依赖
- 支持主流发行版（Ubuntu、Debian、CentOS、RHEL 等）

## 安装依赖

安装脚本会自动安装所需依赖，但如果您选择手动安装，可以参考以下命令：

### macOS
```bash
# 安装基础依赖
brew install jq python3 groff

# 安装 Python 依赖
pip3 install requests

# 可选：安装最新版 man
brew install man-db
```

### Linux
```bash
# Ubuntu/Debian
sudo apt install jq python3 python3-requests man-db groff

# CentOS/RHEL
sudo yum install jq python3 python3-requests man-db groff
```

查看翻译后的手册：

方法一：使用 MANPATH（推荐）
```bash
# 设置过 MANPATH 后可以直接使用
man ls
```

方法二：使用 -M 参数
```bash
man -M /usr/local/share/man/zh_CN <命令>
```

例如：
```bash
man -M /usr/local/share/man/zh_CN ls
```
