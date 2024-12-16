import sys
import json
import requests
import threading
from queue import Queue
from concurrent.futures import ThreadPoolExecutor, as_completed
from requests.exceptions import Timeout, RequestException
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# 加载配置
def load_config(config_path="config.json", service_name=None):
    try:
        with open(config_path, "r") as config_file:
            config = json.load(config_file)
            
        if not service_name:
            service_name = config.get('default_service')
            if not service_name:
                raise Exception("ManZH：未设置默认服务")
        
        service_config = config.get('services', {}).get(service_name)
        if not service_config:
            raise Exception(f"ManZH：服务 '{service_name}' 不存在")
            
        return service_config
        
    except FileNotFoundError:
        print("配置文件未找到，请检查 config.json 是否存在！")
        sys.exit(1)
    except json.JSONDecodeError:
        print("配置文件格式错误，请确保 config.json 是有效��� JSON 文件！")
        sys.exit(1)

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
    def __init__(self):
        self.queue = Queue()
        self.results = {}
        self.lock = threading.Lock()

    def add_chunk(self, index, content):
        self.queue.put((index, content))

    def get_chunk(self):
        return self.queue.get()

    def add_result(self, index, result):
        with self.lock:
            self.results[index] = result

    def get_ordered_results(self):
        return [self.results[i] for i in sorted(self.results.keys())]

# 改翻译函数为线程工作函数
def translate_worker(chunk_data, config, translation_queue):
    index, content = chunk_data
    
    # 检测内容类型（man手册还是help输出）
    is_man_page = ".SH" in content or ".TH" in content
    
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

    headers = {
        "Authorization": f"Bearer {config['api_key']}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "model": config["model"],
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"请将以下man手册内容翻译成{config['language']}：\n\n{content}"}
        ],
        "temperature": 0.3,
        "max_tokens": 4000
    }

    session = create_retry_session()
    
    try:
        response = session.post(
            config["url"], 
            headers=headers, 
            json=payload,
            timeout=(10, 120)
        )
        response.raise_for_status()
        result = response.json()
        
        if 'choices' not in result or not result['choices']:
            raise Exception("API 返回结果格式错误")
            
        translated_content = result['choices'][0]['message']['content']
        translation_queue.add_result(index, translated_content)
        print(f"块 {index + 1} 翻译完成", file=sys.stderr)
        return True
        
    except Timeout:
        print(f"块 {index + 1} 翻译超时，正在重试...", file=sys.stderr)
        try:
            response = session.post(
                config["url"], 
                headers=headers, 
                json=payload,
                timeout=(10, 180)
            )
            response.raise_for_status()
            result = response.json()
            translated_content = result['choices'][0]['message']['content']
            translation_queue.add_result(index, translated_content)
            print(f"块 {index + 1} 重试成功", file=sys.stderr)
            return True
        except Exception as e:
            print(f"块 {index + 1} 重试失败：{str(e)}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"块 {index + 1} 翻译错误：{str(e)}", file=sys.stderr)
        return False

if __name__ == "__main__":
    config = load_config()

    try:
        man_content = sys.stdin.read()
        if not man_content.strip():
            print("未接收到 man 手册内容！")
            sys.exit(1)

        # 分块
        chunk_size = 2000
        content_chunks = [man_content[i:i+chunk_size] 
                        for i in range(0, len(man_content), chunk_size)]
        
        # 创建翻译队列
        translation_queue = TranslationQueue()
        
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
            failed_chunks = []
            for i, future in enumerate(as_completed(futures)):
                if not future.result():
                    failed_chunks.append(i + 1)
            
            # 检查失败的块
            if failed_chunks:
                print(f"警告：以下块翻译失败：{failed_chunks}", file=sys.stderr)
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
