# LOCAL_PATCHES.md — 本地补丁清单

> **这个项目上游已停更**（CJackHwang/AIstudioProxyAPI，最后一次提交 2026-04-22）。
> 当前工作副本是 **v4.1.2 + 本地 10 组补丁**。
> 若执行 `git pull` / 重装依赖 / 重建 venv，**下列补丁会全部丢失**，请按本文件重做。
>
> 所有代码补丁都带有 `[patch 2026-10-29]` 注释标记，可用下面命令一键定位：
> ```bash
> grep -rn "\[patch 2026-10-29\]" --include="*.py" .
> ```
>
> 备份目录（补丁前原件）：项目目录之外的 `credentials_backup/aistudio_*.bak_*`

---

## 一、环境类（`.env`，非代码）

| 键 | 值 | 原值 | 原因 |
|---|---|---|---|
| `QUOTA_SOFT_LIMIT` | `900000000` | `850000` | 自统计 token 桶不按天清零、且是本地估算，会把正常使用误判成"额度耗尽"。放大到 9 亿后该分支永不触发，只保留界面 429 判断 |
| `QUOTA_HARD_LIMIT` | `1000000000` | `950000` | 同上（10 亿） |
| `SUBMIT_BUTTON_ENABLE_TIMEOUT_MS` | `1500` | 未设（默认 5000） | 当前 UI 提交按钮永远不 enabled，等满 5 秒纯浪费 |
| `INCLUDE_THINKING` | `false` | 未设（默认 false） | 思考内容不进正文。见"三、正确性"第 1 条 |
| `DUMP_REQUESTS` | `false` | 未设（默认 false） | 调试用请求转储开关，平时必须关，否则每请求写一个大文件 |

> ⚠️ `FUNCTION_CALLING_MODE` 保持 **`auto`**（原生优先 + 模拟兜底）。
> 曾试过改成 `emulated`（纯模拟），实测效果明显不如原生，已改回。

## 二、依赖类（venv 内，重装即失效）

### `.venv/Lib/site-packages/browserforge/download.py` → `IsDownloaded()`

**问题**：原逻辑要求数据文件「创建时间不超过 5 周」，否则每次启动强制重下。
本机代理对 `github raw` 返回 **502**，下载永远失败 → STREAM proxy 就绪超时 → **服务完全起不来**。

**改法**：改为「文件存在且非空即视为已下载」，不检查时效。

```python
for path in _get_all_paths(**flags):
    if not path.exists() or path.stat().st_size <= 0:
        return False
return True
```

> 另注：Git Bash 的 `cp` 会保留创建时间，**改时间戳无效**（试过）。

---

## 三、正确性修复（代码）

### 1. 思考内容不再混进正文
**文件**：`api_utils/request_processor.py:393`、`api_utils/request_processor.py:564`、
`api_utils/response_generators.py:141/259/468`、`config/settings.py:144`

**问题**：非流式路径把 `reasoning_content` 直接 `+=` 进 `content`，导致返回给客户端的是模型的思考过程。流式路径倒是正确用了 `reasoning_content` 字段 —— **两条路行为不一致**。

**改法**：新增 `INCLUDE_THINKING` 开关（默认 `false`）
- `false`：两条路都不返回思考
- `true`：两条路都只把思考放进 `reasoning_content` 字段，**永不污染 `content`**

**连带**：`usage` 的 `completion_tokens` 不再把思考算进去。

### 2. 参数不带默认值，避免"没传也去调 UI"
**文件**：`browser_utils/page_controller.py:82`（**真正执行的这层**）、
`browser_utils/page_controller_modules/parameters.py:45/79/95`

**问题**：`request_params.get("temperature", DEFAULT_TEMPERATURE)` —— 客户端没传也用默认值去点界面。
而当前 UI 上 temperature / top P 控件藏在「advanced settings」折叠面板里，**未展开不渲染** → 每次白等 2×1.2 秒 + 清缓存。

**改法**：`temperature` / `top_p` 只在请求里带了才调；`stop` 始终调用但默认传 `[]`（清残留、不注入）。

> ⚠️ **`PageController.adjust_parameters` 覆盖了 `ParametersController` 的同名 mixin 方法**，
> 改 `parameters.py` 里那个 `adjust_parameters` 是无效的（shadowed）。改前先用 MRO 确认：
> ```python
> from browser_utils.page_controller import PageController
> print(PageController.adjust_parameters.__module__, PageController.adjust_parameters.__code__.co_firstlineno)
> ```

### 3. 停止序列标签变更
**文件**：`config/selectors.py:79`

```python
# AI Studio 把 "Add stop token" 改成了 "Add stop sequence"
STOP_SEQUENCE_INPUT_SELECTOR = (
    'input[aria-label="Add stop sequence"], '
    'input[aria-label="Add stop token"]'      # 旧标签留作兜底
)
```

### 4. Codex 工具声明无法保存（最关键的一条）
**文件**：`api_utils/utils_ext/function_calling.py`（`SchemaConverter`，4 处）

**问题**：Codex 的 21 个工具经转换后贴进 AI Studio 的 declarations 编辑框，
报红字 `Error in parameters: "enum" must be a list of strings`，**保存不了 → 原生 FC 完全不能用**。

**根因**：`const` → `enum` 转换不看类型：
```python
if "const" in schema:
    cleaned["enum"] = [schema["const"]]     # const: true → enum: [True] ← 雷
```

**改法（4 条 sanitize 规则）**：

| 规则 | 处理 | 位置 |
|---|---|---|
| 非字符串 `const` | 不转 enum，改成描述提示 `(must be true)` | `:789` |
| `enum` 里非字符串项 | 过滤；全空则删键 | `:854` |
| `required: []` | 跳过不输出 | `:863` |
| `properties: {}` | 跳过不输出 | `:824` |
| description 超长 | 截断到 1000 字符 | `:677` |

**验证方式**：拿真实请求的 `tools` 数组跑 `convert_openai_tools_to_gemini()`，
检查生成结果里四类问题均为 0，再贴进 UI 手工确认能保存。

---

## 四、性能优化（代码）

### 1. 参数元素等待 5000ms → 1200ms
`browser_utils/page_controller_modules/parameters.py`：temperature / max_tokens / stop / top_p 四处 `to_be_visible`

### 2. 提交按钮超时改为读配置
`browser_utils/page_controller.py:184` —— 原来是**硬编码 10000ms**，不读 `SUBMIT_BUTTON_ENABLE_TIMEOUT_MS`

### 3. Ctrl+Enter 优先（**两层都要改**）
- `browser_utils/page_controller.py:224` ← **真正生效的一层**
- `browser_utils/page_controller_modules/input.py:169`（内层，同样改保持一致）

**原因**：当前 UI 上纯回车提交的验证几乎必失败（约 5 秒），Ctrl+Enter 实测 100% 成功。

> ⚠️ 同一个坑踩过两次：**这个项目多处逻辑有 mixin + override 两层实现**，改前务必确认哪层在跑。

### 4. 不再写错误快照
`browser_utils/page_controller_modules/parameters.py:221/476/537`、`input.py:125`、`api_utils/queue_worker.py:365`

**原因**：那三类"元素不存在"是良性的，但每请求写 4 组 png+html → `errors_py/` 涨到 **597 个文件 / 308 MB**。
现在只留 debug 日志；`submit_button_click_fail` / `input_submit_error` 这类真故障仍保留快照。

### 效果

```
单请求耗时：38~50 秒 → 8~9 秒
```

---

## 五、运维/工具类

### 1. 跳过启动时的交互提示
**文件**：`launcher/runner.py:192`

**问题**：`input_with_timeout()` 超时后**僵尸读线程仍阻塞在 stdin**，会吞掉下一个提示的输入
（现象：输入数字没反应、等 30 秒超时）。

**改法**：命令行已给 `--auto-save-auth` + `--save-auth-as` 时，直接跳过两个提示。

```bash
python launch_camoufox.py --debug --auto-save-auth --save-auth-as main3
```

### 2. 请求转储（调试用）
**文件**：`api_utils/routers/chat.py:43`，开关 `DUMP_REQUESTS`

开启后把原始请求体写到 `logs/requests/req_<时间>_<reqid>.json`。
**平时必须关**，Codex 的请求体 100 KB+。

### 3. BAT 脚本体系（全 ASCII，纯 cmd，无中文）

| 脚本 | 用途 |
|---|---|
| `start-debug.bat` | 账号 1（main.json） |
| `start-account2.bat` | 账号 2（main2.json） |
| `start-account3.bat` | 账号 3（main3.json） |
| `start-account.bat` | 通用：输名字启动任意账号 |
| `add-account.bat` | 加新账号（cmd 的 `set /p` 收名字，避开僵尸线程 bug） |
| `start-watchdog.bat` | 外部看门狗（health 巡检 + 自动重启） |
| `stop-all.bat` | 安全停止（只杀 camoufox 相关，不碰其他 python） |

**两个踩过的坑**：
- **BAT 里不能写中文** —— cmd 用 GBK 解析 UTF-8 文件会撕碎命令行
- **echo 行里不能出现 `->`** —— `>` 会被当重定向符，生成 `y` / `n` / `main2` 这种垃圾文件

### 4. 登录态
```
auth_profiles/saved/  main.json ｜ main2.json ｜ main3.json
```

- 启动用 `--active-auth-json` 才免登录，**且只有这种启动方式才会把 cookie 刷新回写 json**
- 不带该参数启动 → `current_auth_profile_path = None` → 刷新器不写文件、也不按账号记账
- **不要用 `.pwcli/profiles/...` 那些 Chromium profile** —— camoufox 是 Firefox 内核，格式不兼容

---

## 六、已知但**未修复**的问题

### 1. 内建 Quota Watchdog 的两个缺陷
`server.py:25` `quota_watchdog()`

- **轮换失败也强行复位**：`if IS_QUOTA_EXCEEDED: reset_quota_status()` → 下个请求继续冲撞 Google，可能诱发 403
- **`IS_RECOVERING` 无超时**：`perform_auth_rotation` 卡住时该标志永久为 True，
  而 `stream.py:399` 里 `if IS_RECOVERING: empty_count = 0` → **所有请求无限空等、队列锁死**

**目前策略**：不修，靠手动换号。

### 2. temperature / Top P 在 UI 上已不可达
控件在「Expand or collapse advanced settings」折叠面板内，项目没有先展开的逻辑。
**目前策略**：不调（请求没带就跳过），保持界面默认 1.0 / 0.95。

### 3. 服务无自愈
页面 / 浏览器 / worker 任一死掉 → 后续请求全部 503，**只能重启**。
**目前策略**：外部 `watchdog.py` 兜底（health + 日志信标双探测）。

### 4. 页面可能被导到错误页
网络抖动时代理断开 → 页面停在 `https://aistudio.google.com/520` → 启动失败。
**这不是账号问题也不是代码问题**（不带 cookie 也连不上），换节点或重试即可。
