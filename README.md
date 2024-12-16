# ManZH - Man手册中文翻译工具

一个用于将 Linux/Unix man 手册翻译成中文的自动化工具，支持多种翻译服务。

## 功能特点

- 自动获取和翻译命令的 man 手册
- 支持翻译命令的 --help 输出（当没有 man 手册时）
- 支持多个翻译服务（OpenAI、DeepSeek、Ollama 等）
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
- 以下依赖包：
  - jq
  - python3-requests
  - man
  - col

## 安装

1. 克隆仓库：
```bash
git clone git@github.com:cksdxz1007/ManZH.git
cd ManZH
```

2. 安装依赖：

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

3. 添加执行权限：
```bash
chmod +x manzh.sh config_manager.sh translate_man.sh clean.sh
```

### 方法一：使用安装脚本

1. 下载并解压发布包：
```bash
wget https://github.com/cksdxz1007/ManZH/releases/download/v1.0.0/manzh-1.0.0.tar.gz
tar xzf manzh-1.0.0.tar.gz
cd manzh-1.0.0
```

## 使用方法

### 交互式界面

直接运行主程序：
```bash
sudo ./manzh.sh
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
sudo ./manzh.sh translate ls
```

2. 配置翻译服务：
```bash
./manzh.sh config
```

3. 查看已翻译手册：
```bash
./manzh.sh list
```

4. 清理已翻译手册：
```bash
sudo ./manzh.sh clean
```

## 配置翻译服务

支持多种翻译服务，可以通过配置管理工具进行管理：

```bash
./manzh.sh config
```

支持的服务：
- OpenAI (GPT-4, GPT-3.5-turbo)
- DeepSeek
- Ollama (本地模型)
- 其他兼容的服务

配置示例：
```json
{
  "services": {
    "openai": {
      "service": "openai",
      "api_key": "your-api-key",
      "url": "https://api.openai.com/v1/chat/completions",
      "model": "gpt-4",
      "language": "zh-CN"
    }
  },
  "default_service": "openai"
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

注意：对于没有 man 手册的命令（如 conda），ManZH 会自动尝试翻译 --help 输出：
```bash
# 翻译 conda 命令的帮助信息
sudo ./manzh.sh translate conda

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

## 故障排除

1. 如果遇到权限问题：
   - 确保使用 sudo 运行涉及文件系统操作的命令

2. 如果翻译服务无响应：
   - 检查网络连接
   - 验证 API 密钥是否正确
   - 查看 translate_error.log 文件

3. 如果手册格式异常：
   - 尝试清理后重新翻译
   - 检查原始手册格式

## 贡献指南 man conda
No manual entry for conda

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支
3. 提交更改
4. 推送到分支
5. 创建 Pull Request

## 许可证

MIT

## 作者

[Your Name]

## 更新日志

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