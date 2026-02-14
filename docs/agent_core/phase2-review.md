# Phase 2 — Self-Review

> Date: 2026-02-14
> Reviewer: Claude (self-review)
> Scope: All Phase 2 code (MCP + Skills), tests, and architecture compliance

## 1. Critical Defects (Must Fix)

### 1.1 Client#call_tool re-raises after failed reinitialize

**文件**: `mcp/client.rb`

```ruby
def call_tool(name:, arguments: {}, timeout_s: nil)
  attempt = 0

  begin
    attempt += 1
    result = @rpc.request("tools/call", { "name" => tool_name, "arguments" => args }, timeout_s: timeout_s)
    result.is_a?(Hash) ? result : {}
  rescue AgentCore::MCP::JsonRpcError => e
    raise unless e.code.to_s == "MCP_SESSION_NOT_FOUND"
    raise if attempt > 1

    reinitialize_session!
    retry
  end
end
```

原实现中 `call_tool` 捕获 `MCP_SESSION_NOT_FOUND` 并尝试 `reinitialize_session!`，但**无论重初始化成功与否都会 re-raise 原始 error**。与 `list_tools` 的 `retry` 模式不同：`list_tools` 在 reinitialize 后 retry 请求。

**影响**: 自动重连永远不会成功——它重连 session 后不 retry 请求。

**状态**: ✅ 已修复 — 对齐 `list_tools`：reinitialize 后 retry（限制 1 次），并补充了单测覆盖该分支。

### 1.2 JsonRpcClient#start 在 Mutex 内启动 transport

**文件**: `mcp/json_rpc_client.rb`

```ruby
def start
  @pending_mutex.synchronize do
    # ... state + callback wiring ...
    @starting = true
  end

  wire_transport_callbacks!
  @transport.start  # ← 移到锁外（避免 transport 同步回调导致死锁）

  @pending_mutex.synchronize do
    @started = true
    @starting = false
    @start_cv.broadcast
  end
  self
end
```

原实现中 `@transport.start` 在 `@pending_mutex.synchronize` 内执行。Stdio transport 的 `start` 会 `popen3`
并创建 3 个线程。如果 transport start 阻塞或抛出异常，会持有 `@pending_mutex`，阻塞所有其他操作。

**影响**: 正常情况下 `popen3` 很快返回，不太会真正阻塞。但设计上 transport start
可能涉及网络连接（StreamableHttp 虽然目前也很快），长时间锁持有是潜在问题。

**建议**: 将 transport start 移到锁外（setup callbacks 在锁内，start 在锁外），
或者使用两段式：锁内设状态 + 锁外启动 + 锁内确认。

**状态**: ✅ 已修复 — `start` 采用两段式启动，避免锁内调用 `transport.start`；并添加回归测试覆盖 “transport 在 start 同步 emit stdout” 的死锁场景。

## 2. Design Issues (Should Fix)

### 2.1 StreamableHttp `safe_close_client` 在 close 路径可能被调双次

**文件**: `mcp/transport/streamable_http.rb` L220-256

```ruby
def close(timeout_s: 2.0)
  # ...
  if worker&.alive?
    safe_close_client(stream_client)   # ← 第一次
    safe_close_client(client)          # ← 第一次
    # ... wait worker ...
  elsif session_id && protocol_version
    # ... delete session ...
  end

  safe_close_client(stream_client)     # ← 第二次
  safe_close_client(client)            # ← 第二次
  nil
end
```

worker alive 分支会 close client 两次。虽然 `safe_close_client` 有 rescue，httpx Session 的 `close`
可能不是幂等的（取决于 httpx 版本）。

**建议**: 使用 flag 或 `||=` 追踪是否已经 close。

**状态**: ✅ 已修复 — worker alive 分支 close 后将 local `client/stream_client` 置 nil，避免重复 close；并补充了单测验证 close 只调用一次。

### 2.2 ToolAdapter 只做 name mapping，不做 schema 转换

**文件**: `mcp/tool_adapter.rb`

`ToolAdapter` 目前只提供 `local_tool_name` 和 `mapping_entry`，但没有 MCP tool JSON schema
到 `AgentCore::Resources::Tools::Tool` 的转换逻辑。计划中提到了 "MCP tool schema → AgentCore::Resources::Tools::Tool"
但实际只实现了 name mapping 部分。

**影响**: App 层需要自己做 schema → Tool 转换。这可能是有意的（gem 不知道具体 Tool API），
但 Phase 2 plan 承诺了 ToolAdapter 完成此转换。

**状态**: ✅ 已澄清 — Phase 2 completion 文档已更正：ToolAdapter 只负责本地 tool name mapping；schema → Tool 转换作为 deferred 项保留在后续阶段（或由 app 层完成）。

### 2.3 FileSystemStore#find_skill_metadata! 每次 load_skill 都 re-scan 全部

**文件**: `resources/skills/file_system_store.rb` L257-263

```ruby
def find_skill_metadata!(name)
  name = name.to_s
  meta = list_skills.find { |m| m.name == name }
  raise ArgumentError, "Unknown skill: #{name}" unless meta
  meta
end
```

每次 `load_skill` 和 `read_skill_file` 都调用 `list_skills` 全量扫描目录。对于大量 skills 的目录，
这个 O(n) 扫描可能影响性能。

**建议**: 添加 `@metadata_cache` 缓存（可选，带 invalidation）。或者接受现状（gem 不做缓存，app 可以缓存）。

### 2.4 SseParser 的 retry 字段解析过于宽松

**文件**: `mcp/sse_parser.rb` L104-106

```ruby
when "retry"
  ms = Integer(value, exception: false)
  @retry_ms = ms if ms && ms >= 0
```

`Integer("  42  ", exception: false)` 在 Ruby 中会返回 `42`（成功解析），但 SSE spec
要求 retry 值是纯数字字符串（"42" 不是 " 42 "）。目前行为更宽松但功能正确。

**影响**: 不太会遇到（server 通常发纯数字），接受现状。

## 3. 并发安全审查

### 3.1 ✅ JsonRpcClient — 正确

所有 pending request 状态在 `@pending_mutex` 中保护。
`PendingRequest` 内部使用独立的 `Mutex + ConditionVariable` 等待响应。
timeout 使用 `CLOCK_MONOTONIC` 避免系统时间跳变。

### 3.2 ✅ Transport::Stdio — 正确

`@mutex` 保护 `@started, @closed, @stdin, @stdout` 等状态。
`send_message` 在锁外写 stdin，并用独立的 `@write_mutex` 串行化 write+newline+flush（避免多线程并发导致 JSON 行 interleave）。
`close` 通过 SIGTERM → SIGKILL 级联，配合 `wait_with_timeout` 轮询。
三个后台线程（stdout reader, stderr reader, monitor）独立运行，不持有共享锁。

### 3.3 ✅ Transport::StreamableHttp — 正确

`@mutex + @cv` 保护 `@queue, @inflight, @closed, @started, @session_id, @protocol_version`。
单 worker 线程顺序处理 queue（避免并发 HTTP 请求）。
`cancel_request` 在新线程中发取消通知（不阻塞调用方）。
Token struct 的 `cancelled` 字段在 mutex 内读写。

### 3.4 ⚠️ Transport::StreamableHttp `resolve_headers_provider!` 在锁外

**文件**: `mcp/transport/streamable_http.rb` L136-137

```ruby
def send_message(hash)
  # ...
  @mutex.synchronize { ... guard checks ... }

  dynamic_headers = resolve_headers_provider!   # ← 锁外

  @mutex.synchronize { ... enqueue ... }
end
```

`resolve_headers_provider!` 调用用户提供的 callback（在锁外），然后再进入锁内 enqueue。
如果两个线程同时 `send_message`，headers_provider 会并发调用。
这是合理设计（provider 应该是线程安全的），但值得文档化。

### 3.5 ⚠️ Skills 模块 — 非线程安全 by design

Skills 的所有类（SkillMetadata, Skill, Frontmatter, Store, FileSystemStore）都不使用锁。
SkillMetadata 和 Skill 是 `Data.define` 不可变值对象，天然线程安全。
FileSystemStore 的 `list_skills / load_skill` 可以并发调用（只读文件系统），
但内部没有缓存，所以没有 race condition。

## 4. 边界情况审查

### 4.1 Stdio transport 空命令

`Stdio.new(command: "  ")` → `start` 时 `raise ArgumentError, "command is required"`。
正确：命令验证在 start 而非构造函数，允许延迟配置。

### 4.2 JsonRpcClient 整数/字符串 ID 不匹配

`alternate_id_lookup` 处理了 MCP server 返回 string ID "1" 而客户端用 integer 1 的情况。
正确：JSON-RPC spec 允许 ID 为 string 或 integer。

### 4.3 SseParser 超大缓冲

`@buffer` 超过 `max_buffer_bytes` 时抛出 `ArgumentError`。
`@event_data_bytes` 超过 `max_event_data_bytes` 时抛出 `EventDataTooLargeError`。
两者都有防护。✅

### 4.4 FileSystemStore 路径穿越

- `normalize_rel_path` 检查 `..` 和 `.` segments
- `safe_join` + `within_dir?` 验证 expand 后的路径
- `ensure_realpath_within_dir!` 用 `File.realpath` 解析符号链接后验证
- 三层防护互补。✅

### 4.5 FileSystemStore 空 dirs

`FileSystemStore.new(dirs: [], strict: true)` → 构造成功，`list_skills` 返回 `[]`。
`FileSystemStore.new(dirs: [], strict: false)` → 同上。合理。

### 4.6 Frontmatter 空 YAML

`"---\n---\nBody"` → strict 模式 `raise ArgumentError`。正确。

### 4.7 ToolAdapter 超长名称

`local_tool_name(server_id: "a"*200, remote_tool_name: "b"*200)` → SHA256 后缀截断到 128 chars。✅

### 4.8 Client protocol version negotiation

Server 返回不支持的协议版本 → `ProtocolVersionNotSupportedError` + close rpc。
Server 不返回协议版本 → 使用客户端请求的版本。合理。

### 4.9 StreamableHttp session DELETE on close

Close 时如果有 session_id，尝试发 HTTP DELETE（限时 0.2s）。如果失败静默忽略。
如果 worker 还活着，先杀 worker 不发 DELETE。合理。

### 4.10 SkillMetadata allowed_tools normalization

- String input: `"tool-a  tool-b"` → split + dedup → `["tool-a", "tool-b"]`
- Array with blanks: `["tool-a", "", "  "]` → strip + reject empty → `["tool-a"]`
- Nil input: → `[]`
- ✅ 全部正确

## 5. 模块边界与数据流审查

### 5.1 依赖方向 ✅

```
MCP::Constants         → 无依赖
MCP::SseParser         → 无依赖
MCP::Transport::Base   → MCP errors
MCP::Transport::Stdio  → Transport::Base, Open3
MCP::Transport::StreamableHttp → Transport::Base, SseParser, httpx (lazy)
MCP::JsonRpcClient     → Transport::Base, Constants, Errors, JSON
MCP::Client            → JsonRpcClient, Constants, Errors
MCP::ServerConfig      → Constants (Data.define)
MCP::ToolAdapter       → Digest

Resources::Skills::SkillMetadata → 无依赖 (Data.define)
Resources::Skills::Skill         → SkillMetadata (Data.define)
Resources::Skills::Frontmatter   → YAML (stdlib)
Resources::Skills::Store         → 无依赖 (abstract)
Resources::Skills::FileSystemStore → Store, Frontmatter, SkillMetadata, Skill
```

**无循环依赖。MCP 和 Skills 完全独立。✅**

### 5.2 数据流 ✅

```
App/Agent
  ↓
MCP::Client.start → Transport.start → 子进程/HTTP
  ↓
Registry.register_mcp_client → Client.list_tools (paginate) → JsonRpcClient.request → Transport.send_message
  ↓                                                                    ↓
  ← tools page ← JsonRpcClient.handle_response ← Transport callback
  ↓
Registry.execute (MCP tool) → Client.call_tool → normalize (content + error) → ToolResult

Skills::FileSystemStore
  ↓
list_skills → scan dirs → parse frontmatter → SkillMetadata[]
  ↓
load_skill → read SKILL.md → parse frontmatter + body → Skill
  ↓
read_skill_file → validate path → read file → String
```

**单向数据流。✅**

### 5.3 接口一致性

| 模块 | 公共接口 | 风格一致 |
|------|---------|---------|
| Transport::Base | start, send_message, close, callbacks | ✅ 统一 |
| JsonRpcClient | start, request, notify, close | ✅ 统一 |
| Client | start, list_tools, call_tool, close | ✅ 统一 |
| Store | list_skills, load_skill, read_skill_file | ✅ keyword args |
| FileSystemStore | 同 Store | ✅ |

所有公共方法使用 keyword arguments。✅

### 5.4 Key 一致性

- MCP wire protocol: string keys (`"jsonrpc"`, `"id"`, `"method"`, `"params"`)
- MCP client return values: string keys（直接返回 JSON parse 结果）
- SseParser events: symbol keys (`{ id:, event:, data:, retry_ms: }`)
- Skills metadata: symbol keys（Frontmatter 返回 symbol hash）
- SkillMetadata/Skill: Ruby attributes（Data.define members）

**Wire protocol 统一 string keys，gem 内部统一 symbol keys。✅**

## 6. 测试覆盖审查

### 6.1 覆盖良好的路径

- ✅ MCP Constants 全覆盖（版本号、error codes、headers）
- ✅ SseParser 正常解析、多行 data、comments、retry、buffer limits、data limits
- ✅ Transport::Base abstract 方法 + callback accessors
- ✅ Transport::Stdio start/send/close + process lifecycle + error handling
- ✅ StreamableHttp 构造验证 + send/close/cancel + session management
- ✅ JsonRpcClient request/notify/close + timeout + correlation + transport close
- ✅ Client initialize/list_tools/call_tool + protocol negotiation + reconnect
- ✅ ServerConfig 构造 + coerce + validation + transport-specific checks
- ✅ ToolAdapter name mapping + overflow + sanitization
- ✅ SkillMetadata normalization + coercion + edge cases
- ✅ Skill construction + files_index + truncation + type validation
- ✅ Frontmatter strict/lenient + validation + key conversion
- ✅ Store abstract methods
- ✅ FileSystemStore list/load/read + path security + progressive disclosure

### 6.2 未覆盖或薄弱的路径

- ✅ StreamableHttp 本地集成测试（httpx + WEBrick，本地 SSE/JSON server，全链路覆盖 JSON/SSE/GET 重连）
- ✅ Client `call_tool` 的 `MCP_SESSION_NOT_FOUND` 重连路径（1 次 retry）已修复并测试覆盖
- ✅ JsonRpcClient 并发请求基础覆盖（多线程 request + out-of-order response），仍建议补更强压力测试
- ⚠️ FileSystemStore 符号链接攻击测试 — 有 realpath 保护但测试中用了真实 fixture（非 symlink）
- ⚠️ Stdio transport 进程崩溃时的 on_close callback 触发 — 有实现但难以在 CI 中稳定测试

### 6.3 测试数据统计

```
Total: 585 runs, 1239 assertions, 0 failures, 0 errors
```

Phase 2 新增测试覆盖：

| 模块 | 测试文件数 | 说明 |
|------|-----------|------|
| MCP | 9 | 全部新建 |
| Skills | 5 | 全部新建（Resources 命名空间） |
| Phase 1 覆盖扩展 | 9 | 新建 + 扩展 |
| 合计 | 23 | |

## 7. Wire Protocol 审查

### 7.1 JSON-RPC 2.0 合规

- ✅ `"jsonrpc": "2.0"` 在所有请求中
- ✅ `"id"` 为递增整数（合规：spec 允许 string/integer/null）
- ✅ `"params"` 可选（notification 不含 id）
- ✅ error 响应结构 `{ code, message, data }`
- ✅ 取消通知使用 `notifications/cancelled`

### 7.2 MCP 协议合规

- ✅ `initialize` 握手交换 protocolVersion + clientInfo + capabilities
- ✅ `notifications/initialized` 在 initialize 成功后发送
- ✅ `Mcp-Protocol-Version` header 在初始化后的请求中
- ✅ `Mcp-Session-Id` header 在 session 建立后的请求中
- ✅ 404 → MCP_SESSION_NOT_FOUND 映射
- ✅ session DELETE on close

### 7.3 camelCase 使用审查

MCP 协议中的 camelCase（`protocolVersion`, `clientInfo`, `serverInfo`）只出现在
JSON wire protocol 中（string keys in hashes），不作为 Ruby 方法名或 instance variables。

唯一的 Ruby 代码中 camelCase 问题: `ServerConfig` 中的 `Data.define` 字段名。
检查: ServerConfig 使用 snake_case 字段（`protocol_version`, `client_info`），仅在
`#to_json_params` 中转换为 camelCase wire format。✅

## 8. 安全审查

### 8.1 FileSystemStore 路径安全 ✅

三层防护：
1. **路径规范化**: `REL_PATH_PATTERN` 只允许 `scripts/|references/|assets/` + 单层文件名
2. **路径展开**: `File.expand_path` + `within_dir?` 前缀检查
3. **Realpath 解析**: `File.realpath` 解析符号链接后再次验证

### 8.2 YAML 安全 ✅

`Frontmatter.parse` 使用 `YAML.safe_load`（隐含在标准 parse 中），
不允许自定义类实例化。metadata values 强制为 string。

### 8.3 进程安全 (Stdio) ✅

- `env` 参数规范化（string keys/values only）
- `command + args` 通过 `Open3.popen3` 传递（不走 shell 展开）
- 关闭时 SIGTERM → SIGKILL 级联（不会留下僵尸进程）

### 8.4 HTTP 安全 (StreamableHttp)

- ✅ max_response_bytes 限制响应大小
- ✅ sse_max_reconnects 限制重连次数
- ⚠️ 无 URL 白名单/黑名单 — app 层负责

## 9. 修复优先级

### P0（必须修复，阻塞后续工作）

1. ✅ **Client#call_tool 重连后不 retry** (1.1) — 已对齐 list_tools 的 retry 模式（限制 1 次）

### P1（应尽快修复）

2. ✅ **JsonRpcClient#start 在锁内启动 transport** (1.2) — 已采用两段式启动并补充回归测试
3. ✅ **ToolAdapter 缺少 schema 转换** (2.2) — 已在文档中明确该功能为 deferred（ToolAdapter 仅负责 name mapping）

### P2（改进，不阻塞）

4. ✅ StreamableHttp close 路径双重 close (2.1) — 已避免重复 close，并补充单测覆盖
5. FileSystemStore find_skill_metadata! 无缓存 (2.3) — app 可缓存，gem 无需
6. resolve_headers_provider! 并发安全文档化 (3.4) — 添加注释

## 10. 仍建议关注（Phase 3 / Rails 整合前）

1. **MCP Client 生命周期管理**: 目前 Client/Transport 的 close 是手动调用。在 Rails 中需要确保 MCP 连接随请求/进程生命周期正确关闭（leaking subprocess 或 HTTP connection）。建议在 Agent 层添加 `ensure close` 或 `at_exit` 钩子。

2. **Skills 热加载**: FileSystemStore 每次 `list_skills` 全量扫描。对于开发环境需要考虑文件监控 + 增量更新（已在 deferred list 中）。

3. **MCP 错误转换**: MCP server 返回的 error 直接以 `JsonRpcError` 传播。Agent/Runner 层可能需要将 MCP errors 映射为标准 `ToolResult.error`，目前 Phase 1 review 中已提到 Registry 添加了 rescue，但还需确认 Phase 2 的 error types 都被覆盖。

4. **StreamableHttp 的 httpx 版本依赖**: 代码中 `HTTPX::Request` 动态添加 `stream` accessor（L263-267），这依赖 httpx 的内部结构。httpx 升级可能 break。建议添加版本约束或 feature detection。
