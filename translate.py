import sys
import json
import time
import requests
import threading
from queue import Queue
from concurrent.futures import ThreadPoolExecutor, as_completed
from requests.exceptions import Timeout, RequestException
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import os
import google.generativeai as genai
from abc import ABC, abstractmethod

def validate_config(config):
    """
    验证配置文件的完整性和正确性
    
    Args:
        config: 配置字典
        
    Returns:
        tuple: (是否有效, 错误信息)
    """
    required_fields = {
        'api_key': str,
        'url': str,
        'model': str,
        'language': str,
        'max_output_length': int,
        'max_context_length': int,
        'type': str  # 新增服务类型字段
    }
    
    # Gemini 服务不需要 URL 字段
    if config.get('type', '').lower() == 'gemini':
        del required_fields['url']
    
    for field, field_type in required_fields.items():
        if field not in config:
            return False, f"缺少必要配置项：{field}"
        if not isinstance(config[field], field_type):
            return False, f"配置项 {field} 类型错误，应为 {field_type.__name__}"
    
    # 验证 URL 格式（仅对非 Gemini 服务）
    if config.get('type', '').lower() != 'gemini' and not config['url'].startswith(('http://', 'https://')):
        return False, "URL 格式无效"
    
    # 验证数值范围
    if config['max_output_length'] <= 0:
        return False, "max_output_length 必须大于 0"
    if config['max_context_length'] <= 0:
        return False, "max_context_length 必须大于 0"
        
    return True, ""

class ConfigCache:
    """配置文件缓存类"""
    _instance = None
    _config = None
    _last_load_time = 0
    _cache_duration = 300  # 缓存有效期（秒）
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(ConfigCache, cls).__new__(cls)
        return cls._instance

    @classmethod
    def get_config(cls, config_path="config.json", service_name=None, force_reload=False):
        """
        获取配置，如果缓存有效则使用缓存，否则重新加载
        
        Args:
            config_path: 配置文件路径
            service_name: 服务名称
            force_reload: 是否强制重新加载
            
        Returns:
            dict: 配置信息
        """
        current_time = time.time()
        
        with cls._lock:
            # 检查是否需要重新加载配置
            if (cls._config is None or 
                force_reload or 
                current_time - cls._last_load_time > cls._cache_duration):
                try:
                    if not os.path.exists(config_path):
                        raise FileNotFoundError(f"配置文件不存在：{config_path}")
                        
                    with open(config_path, "r", encoding='utf-8') as config_file:
                        cls._config = json.load(config_file)
                    
                    if not isinstance(cls._config, dict):
                        raise ValueError("配置文件格式错误：根对象必须是字典")
                        
                    if 'services' not in cls._config:
                        raise ValueError("配置文件缺少 'services' 部分")
                        
                    cls._last_load_time = current_time
                    print("配置已重新加载", file=sys.stderr)
                except FileNotFoundError as e:
                    print(f"错误：{str(e)}", file=sys.stderr)
                    sys.exit(1)
                except json.JSONDecodeError as e:
                    print(f"配置文件 JSON 格式错误：{str(e)}", file=sys.stderr)
                    sys.exit(1)
                except Exception as e:
                    print(f"加载配置文件时出错：{str(e)}", file=sys.stderr)
                    sys.exit(1)
            
            if not service_name:
                service_name = cls._config.get('default_service')
                if not service_name:
                    raise ValueError("未设置默认服务且未指定服务名称")
            
            service_config = cls._config.get('services', {}).get(service_name)
            if not service_config:
                raise ValueError(f"服务 '{service_name}' 不存在")
                
            # 使用默认值或服务特定值
            defaults = cls._config.get('defaults', {})
            merged_config = defaults.copy()
            merged_config.update(service_config)
            
            # 验证合并后的配置
            is_valid, error_msg = validate_config(merged_config)
            if not is_valid:
                raise ValueError(f"配置验证失败：{error_msg}")
                
            return merged_config

    @classmethod
    def invalidate_cache(cls):
        """清除缓存"""
        with cls._lock:
            cls._config = None
            cls._last_load_time = 0

# 修改原有的 load_config 函数
def load_config(config_path="config.json", service_name=None):
    """
    加载配置文件（使用缓存）
    
    Args:
        config_path: 配置文件路径
        service_name: 服务名称
        
    Returns:
        dict: 配置信息
    """
    return ConfigCache.get_config(config_path, service_name)

# 配置重试策略
def create_retry_session(retries=3, backoff_factor=0.3, 
                        status_forcelist=(500, 502, 504)):
    session = requests.Session()
    retry = Retry(
        total=retries,
        read=retries,
        connect=retries,
        backoff_factor=backoff_factor,
        status_forcelist=status_forcelist,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount('http://', adapter)
    session.mount('https://', adapter)
    return session

# 添加翻译队列类
class TranslationQueue:
    def __init__(self, chunk_size=2000, max_retries=3):
        if chunk_size <= 0:
            raise ValueError("chunk_size 必须大于 0")
        if max_retries <= 0:
            raise ValueError("max_retries 必须大于 0")
            
        self.queue = Queue()
        self.results = {}
        self.cache = {}
        self.lock = threading.Lock()
        self.chunk_size = chunk_size
        self.max_retries = max_retries
        self.total_chunks = 0
        self.completed_chunks = 0
        self.failed_chunks = []
        self.progress_lock = threading.Lock()
        self.is_processing = False
        self._error_count = 0
        self.MAX_ERROR_COUNT = 5  # 最大连续错误次数

    def prepare_content(self, content):
        """
        准备内容分块
        
        Args:
            content: 要翻译的完整内容
            
        Returns:
            list: 内容块列表
            
        Raises:
            ValueError: 当内容为空或无效时
        """
        if not content or not isinstance(content, str):
            raise ValueError("无效的输入内容")
            
        content = content.strip()
        if not content:
            raise ValueError("输入内容为空")
            
        # 按段落分割，避免在句子中间断开
        paragraphs = content.split('\n\n')
        chunks = []
        current_chunk = ""
        
        for para in paragraphs:
            if not para.strip():
                continue
                
            if len(current_chunk) + len(para) + 2 <= self.chunk_size:
                current_chunk += (para + '\n\n')
            else:
                if current_chunk:
                    chunks.append(current_chunk.strip())
                current_chunk = para + '\n\n'
        
        if current_chunk:
            chunks.append(current_chunk.strip())
            
        if not chunks:
            raise ValueError("无法生成有效的内容块")
            
        self.total_chunks = len(chunks)
        return chunks

    def add_chunk(self, index, content):
        """
        添加翻译块到队列
        
        Args:
            index: 块索引
            content: 块内容
            
        Raises:
            ValueError: 当索引或内容无效时
        """
        if not isinstance(index, int) or index < 0:
            raise ValueError("无效的块索引")
        if not content or not isinstance(content, str):
            raise ValueError("无效的块内容")
            
        self.queue.put((index, content.strip()))

    def get_chunk(self):
        """
        获取待翻译的块
        
        Returns:
            tuple: (索引, 内容)
            
        Raises:
            Queue.Empty: 当队列为空时
        """
        return self.queue.get(timeout=1)  # 1秒超时

    def add_result(self, index, result):
        """
        添加翻译结果
        
        Args:
            index: 块索引
            result: 翻译结果
            
        Raises:
            ValueError: 当索引或结果无效时
        """
        if not isinstance(index, int) or index < 0:
            raise ValueError("无效的结果索引")
        if not result or not isinstance(result, str):
            raise ValueError("无效的翻译结果")
            
        with self.lock:
            self.results[index] = result.strip()
            with self.progress_lock:
                self.completed_chunks += 1
                self._update_progress()

    def add_failed_chunk(self, index):
        """
        记录失败的块
        
        Args:
            index: 块索引
        """
        with self.lock:
            if index not in self.failed_chunks:
                self.failed_chunks.append(index)
                self._error_count += 1
                
                # 检查连续错误次数
                if self._error_count >= self.MAX_ERROR_COUNT:
                    raise RuntimeError(f"连续失败次数过多（{self._error_count}次），停止处理")

    def get_ordered_results(self):
        """
        获取按顺序排列的翻译结果
        
        Returns:
            list: 翻译结果列表
            
        Raises:
            RuntimeError: 当存在未完成的翻译时
        """
        if len(self.results) != self.total_chunks:
            raise RuntimeError("存在未完成的翻译任务")
            
        return [self.results[i] for i in sorted(self.results.keys())]

    def _update_progress(self):
        """更新翻译进度"""
        progress = (self.completed_chunks / self.total_chunks) * 100
        print(f"\r翻译进度：{progress:.1f}% ({self.completed_chunks}/{self.total_chunks})", 
              end="", file=sys.stderr)
        if self.completed_chunks == self.total_chunks:
            print(file=sys.stderr)  # 换行

    def get_or_cache(self, content, translate_func):
        """
        从缓存获取翻译结果，如果没有则翻译并缓存
        
        Args:
            content: 要翻译的内容
            translate_func: 翻译函数
            
        Returns:
            str: 翻译结果
            
        Raises:
            ValueError: 当内容或函数无效时
            RuntimeError: 当翻译失败时
        """
        if not content or not isinstance(content, str):
            raise ValueError("无效的翻译内容")
        if not callable(translate_func):
            raise ValueError("无效的翻译函数")
            
        # 生成内容的哈希值作为缓存键
        cache_key = hash(content)
        
        with self.lock:
            if cache_key in self.cache:
                return self.cache[cache_key]
            
            result = translate_func(content)
            if not result:
                raise RuntimeError("翻译失败")
                
            self.cache[cache_key] = result.strip()
            return result

class TranslationService(ABC):
    """翻译服务抽象基类"""
    
    @abstractmethod
    def translate(self, content, system_prompt):
        """
        执行翻译
        
        Args:
            content: 要翻译的内容
            system_prompt: 系统提示词
            
        Returns:
            str: 翻译结果
        """
        pass

class ChatGPTService(TranslationService):
    """ChatGPT 翻译服务"""
    
    def __init__(self, config):
        self.config = config
        self.session = create_retry_session()
        
    def translate(self, content, system_prompt):
        headers = {
            "Authorization": f"Bearer {self.config['api_key']}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": self.config["model"],
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"请将以下内容翻译成{self.config['language']}：\n\n{content}"}
            ],
            "temperature": 0.3,
            "max_tokens": self.config["max_output_length"]
        }
        
        try:
            response = self.session.post(
                self.config["url"], 
                headers=headers, 
                json=payload,
                timeout=(10, 120)
            )
            response.raise_for_status()
            
            result = response.json()
            if not isinstance(result, dict):
                raise RuntimeError("API 返回格式错误")
                
            if 'error' in result:
                raise RuntimeError(f"API 错误：{result['error']}")
                
            if 'choices' not in result or not result['choices']:
                raise RuntimeError("API 返回结果格式错误：缺少 choices 字段")
                
            translated_text = result['choices'][0]['message']['content']
            if not translated_text or not isinstance(translated_text, str):
                raise RuntimeError("API 返回的翻译结果无效")
                
            return translated_text.strip()
            
        except Exception as e:
            raise RuntimeError(f"翻译请求失败：{str(e)}")

class GeminiService(TranslationService):
    """Google Gemini 翻译服务"""
    
    def __init__(self, config):
        self.config = config
        genai.configure(api_key=config['api_key'])
        self.model = genai.GenerativeModel(config['model'])
        
    def translate(self, content, system_prompt):
        try:
            prompt = f"{system_prompt}\n\n请将以下内容翻译成{self.config['language']}：\n\n{content}"
            
            response = self.model.generate_content(
                prompt,
                generation_config={
                    'temperature': 0.3,
                    'top_p': 1,
                    'top_k': 32,
                    'max_output_tokens': self.config['max_output_length']
                }
            )
            
            if not response.text:
                raise RuntimeError("未获取到翻译结果")
                
            return response.text.strip()
            
        except Exception as e:
            raise RuntimeError(f"Gemini 翻译失败：{str(e)}")

def create_translation_service(config):
    """
    创建翻译服务实例
    
    Args:
        config: 服务配置
        
    Returns:
        TranslationService: 翻译服务实例
    """
    service_type = config.get('type', 'chatgpt').lower()
    
    if service_type == 'gemini':
        return GeminiService(config)
    else:
        return ChatGPTService(config)

def translate_worker(chunk_data, config, translation_queue):
    """
    翻译工作函数
    
    Args:
        chunk_data: (索引, 内容)元组
        config: 配置信息
        translation_queue: 翻译队列实例
        
    Returns:
        bool: 是否翻译成功
        
    Raises:
        ValueError: 当参数无效时
        RuntimeError: 当翻译过程出错时
    """
    if not isinstance(chunk_data, tuple) or len(chunk_data) != 2:
        raise ValueError("无效的块数据格式")
        
    index, content = chunk_data
    if not isinstance(index, int) or index < 0:
        raise ValueError("无效的块索引")
    if not content or not isinstance(content, str):
        raise ValueError("无效的块内容")
        
    retry_count = 0
    last_error = None
    
    # 检测内容类型（man手册还是help输出）
    is_man_page = bool(".SH" in content or ".TH" in content)
    
    system_prompt = """你是一位专业的技术文档翻译专家，特别擅长将英文命令行文档翻译成中文。请遵循以下规则：

1. 保持专业术语的准确性，必要时保留英文原文，采用"中文（英文）"的格式
2. 对于 man 手册：
   - 严格保持所有 nroff/troff 格式标记
   - 保持命令语法和参数格式不变
3. 对于 help 输出：
   - 保持选项格式（如 --help, -h）不变
   - 保持示例命令和路径不变
4. 命令行选项说明采用："选项名称 - 中文说明"的格式
5. 确保翻译准确、专业、通俗易懂
6. 保持所有空格、缩进和换行格式"""

    # 添加内容类型提示
    if not is_man_page:
        system_prompt += "\n注意：这是命令的 help 输出，不是 man 手册，请保持命令行格式和示例的原样显示。"

    # 创建翻译服务实例
    translation_service = create_translation_service(config)

    # 使用缓存机制翻译
    while retry_count < translation_queue.max_retries:
        try:
            translated_content = translation_queue.get_or_cache(
                content,
                lambda x: translation_service.translate(x, system_prompt)
            )
            if translated_content:
                translation_queue.add_result(index, translated_content)
                return True
        except Exception as e:
            last_error = str(e)
            print(f"块 {index + 1} 第 {retry_count + 1} 次尝试失败：{last_error}", 
                  file=sys.stderr)
            retry_count += 1
            if retry_count < translation_queue.max_retries:
                print(f"正在重试...", file=sys.stderr)
                time.sleep(min(retry_count * 2, 10))
            continue
    
    print(f"块 {index + 1} 翻译失败，最后一次错误：{last_error}", file=sys.stderr)
    translation_queue.add_failed_chunk(index)
    return False

if __name__ == "__main__":
    config = load_config()

    try:
        man_content = sys.stdin.read()
        if not man_content.strip():
            print("未接收到内容！", file=sys.stderr)
            sys.exit(1)

        # 创建翻译队列
        translation_queue = TranslationQueue(chunk_size=2000, max_retries=3)
        
        # 准备内容分块
        content_chunks = translation_queue.prepare_content(man_content)
        
        # 设置线程池
        max_workers = min(4, len(content_chunks))  # 最多4个线程
        print(f"使用 {max_workers} 个线程进行翻译...", file=sys.stderr)
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # 提交所有翻译任务
            futures = []
            for i, chunk in enumerate(content_chunks):
                translation_queue.add_chunk(i, chunk)
                future = executor.submit(
                    translate_worker, 
                    (i, chunk), 
                    config, 
                    translation_queue
                )
                futures.append(future)
            
            # 等待所有任务完成
            for future in as_completed(futures):
                future.result()
            
            # 检查失败的块
            if translation_queue.failed_chunks:
                print(f"\n警告：以下块翻译失败：{translation_queue.failed_chunks}", 
                      file=sys.stderr)
                sys.exit(1)
            
            # 按顺序合并结果
            translated_content = "".join(translation_queue.get_ordered_results())
            print(translated_content)
        
    except KeyboardInterrupt:
        print("\n翻译被用户中断", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"处理过程出错：{str(e)}", file=sys.stderr)
        sys.exit(1)
