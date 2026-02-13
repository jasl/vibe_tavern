# Phase 1 — Self-Review

> Date: 2026-02-14
> Reviewer: Claude (self-review)
> Scope: All Phase 1 code, tests, and architecture compliance

## 1. Critical Defects (Must Fix)

### 1.1 Agent#chat 重复消息：用户消息被添加两次

**文件**: `agent.rb` L167-186 + L95-116

`build_prompt` 通过 `SimplePipeline` 已经把 `user_message` 加到了 `prompt.messages` 中，
然后 `Runner#run` 把 `prompt.messages.dup` 作为 conversation，所以 user message 已经在
messages 中了。但 `Agent#chat` 在 L113 又手动 `chat_history.append(user_message)`。

**问题**:
- `SimplePipeline#build_messages` 会遍历 `chat_history` 并追加 `user_message`
- Runner 收到的 messages 已经包含了 user_message
- 但 `Agent#chat` 事后又 append 了一次 user_message 到 history
- 下一次 `chat()` 调用时，`build_prompt` 遍历 history（已含上次的 user msg），
  再追加新的 user_message → **历史中会有正确数量的消息**

**实际影响**: history 是正确的（user + assistant 交替），但设计意图不清晰。
user_message 是在 pipeline 中临时添加的，不会进入 history；Agent 事后统一追加。
这个流程**没有 bug**，但 Runner 内部的 messages 和 history 的关系不直观。

**建议**: 在 `Agent#chat` 中添加注释说明设计意图。或者重构为：
pipeline 不追加 user_message，只组装 history；Agent 统一管理消息的追加。

### 1.2 Agent#build_events 调用了不存在的方法 `events.on(hook)`

**文件**: `agent.rb` L189-200

```ruby
def build_events(events)
  events ||= PromptRunner::Events.new
  if @on_event
    PromptRunner::Events::HOOKS.each do |hook|
      events.on(hook) { |*args| @on_event.call(hook, *args) }  # ← BUG
    end
  end
  events
end
```

`Events` 类通过 `define_method` 生成 `on_turn_start`, `on_turn_end` 等方法，
但没有通用的 `on(hook_name)` 方法。应该用 `events.send(:"on_#{hook}")` 或者
给 `Events` 添加一个 `on(hook, &block)` 方法。

**影响**: 如果用户传入 `on_event` callback，运行时会抛出 `NoMethodError`。
目前测试没有覆盖这个路径。

**修复**: 给 Events 添加 `on(hook, &block)` 方法，或者改用 `send`。

### 1.3 Events#emit 的 rescue 只捕获第一个 callback 的异常

**文件**: `events.rb` L42-49

```ruby
def emit(hook, *args)
  @callbacks.fetch(hook, []).each { |cb| cb.call(*args) }
rescue => e
  if hook != :error && @callbacks[:error].any?
    @callbacks[:error].each { |cb| cb.call(e, true) }
  end
end
```

如果第一个 callback 抛出异常，后续 callbacks 都不会执行。
应该在 each 内部 rescue，让每个 callback 独立失败。

**修复**:
```ruby
def emit(hook, *args)
  @callbacks.fetch(hook, []).each do |cb|
    cb.call(*args)
  rescue => e
    next if hook == :error  # 防止 error handler 的错误无限递归
    @callbacks[:error].each { |ecb| ecb.call(e, true) } if @callbacks[:error].any?
  end
end
```

### 1.4 Runner#run_stream 在没有 MessageComplete 事件时静默失败

**文件**: `runner.rb` L196-199

```ruby
if assistant_msg
  messages << assistant_msg
  all_new_messages << assistant_msg
end
```

如果 provider 的 stream 实现没有发出 `MessageComplete` 事件，`assistant_msg`
会是 nil，导致：
- messages 不更新
- tool call 检查跳过
- 直接返回 nil final_message 的 RunResult

**建议**: 如果 `assistant_msg` 为 nil 且 stream 已结束，应该从收到的 text deltas
重建 Message，或者抛出明确的错误。

## 2. Design Issues (Should Fix)

### 2.1 Provider::Base 缺少 `#models` 方法

**计划** 中定义了 `#models → Array<ModelInfo>`，实现中没有。
不紧急，但应该补上接口定义（可以默认返回空数组）。

### 2.2 ToolResult 的 content 格式混用 String/Symbol key

**文件**: `tool_result.rb` L28-30

```ruby
def text
  content.filter_map { |block|
    block[:text] if block[:type] == "text" || block[:type].to_sym == :text
  }.join("\n")
end
```

`ToolResult.success(text:)` 创建的是 `{ type: "text", text: "..." }` (String key)。
但 MCP 结果可能用 Symbol key。这里的 `||` 处理了两种情况，但不一致。

**建议**: 统一为 Symbol key（gem 内部标准），在 MCP 结果入口处做一次 key 转换。

### 2.3 Message#content 未冻结

`tool_calls` 和 `metadata` 被 freeze 了，但 `content` 没有。
如果 content 是 String，外部可以直接修改（Ruby String 是 mutable 的）。

**建议**: `@content = content.freeze` 或对 String content 调用 `dup.freeze`。

### 2.4 Registry#execute 的 MCP 分支缺少错误处理

**文件**: `registry.rb` L101-115

MCP 的 `client.call_tool` 如果抛出异常（网络错误、超时），
Registry 不会捕获，异常会直接传播到 Runner。

Runner 的 tool execution 中 native Tool 有 rescue（在 Tool#call 里），
但 MCP 路径没有。

**建议**: 在 Registry#execute 的 MCP 分支添加 rescue，返回 ToolResult.error。

### 2.5 Builder#to_config 和 Agent#to_config 序列化内容不一致

`Builder#to_config` 包含 `temperature`, `max_tokens`, `top_p`, `stop_sequences`。
`Agent#to_config` 包含 `llm_options` 嵌套 Hash（来自 `builder.llm_options`）。

`Agent.from_config` 内部调用 `builder.load_config`，`load_config` 处理的是
`temperature`, `max_tokens` 等扁平 key，不处理 `llm_options`。

**影响**: `agent.to_config` → `Agent.from_config` 不会正确恢复 temperature 等参数。

**修复**: 统一序列化格式。Agent#to_config 应该使用 Builder#to_config 的格式。

## 3. 并发安全审查

### 3.1 ✅ ChatHistory::InMemory — 正确

所有读写操作都在 `@mutex.synchronize` 中。`#each` 复制 snapshot 后释放锁。

### 3.2 ✅ Memory::InMemory — 正确

同上。

### 3.3 ✅ Tools::Registry — 正确

所有读写操作都在 `@mutex.synchronize` 中。
`#execute` 在锁外执行工具（避免死锁），但先在锁内获取 tool 引用。

### 3.4 ⚠️ Runner — 非线程安全 by design

Runner 是 stateless 的，每次 `run/run_stream` 使用局部变量。
这是正确的设计：同一个 Runner 实例可以从多个线程安全调用。

但 **Agent** 不是线程安全的：并发调用 `agent.chat()` 会并发修改
`chat_history`（InMemory 有锁，OK）但 prompt 构建和 history 追加之间
存在 TOCTOU 竞争。这是预期的（Agent 对应一个会话），但应该文档化。

### 3.5 ⚠️ Events — 无锁

Events 的 `@callbacks` 在注册和 emit 之间没有锁。
通常 Events 在单线程中使用（注册在 run 之前），但应该注意文档化。

## 4. 边界情况审查

### 4.1 空消息处理

- `Message.new(role: :user, content: "")` → 允许。合理。
- `Message.new(role: :user, content: nil)` → `text` 返回空字符串。可能应该拒绝 nil content。
- `ChatHistory::InMemory.new([])` → OK。

### 4.2 Tool 名称冲突

如果 native tool 和 MCP tool 同名，`Registry#find` 优先返回 native tool（因为先查 `@native_tools`）。
同名 MCP tools 之间会覆盖。这个行为没有文档化。

**建议**: 注册时检查冲突并 warn/raise。

### 4.3 validate_role! 对 nil 的处理

`Message.new(role: nil, content: "x")` → `nil.to_sym` 抛出 `NoMethodError`，
不是 `ArgumentError`。应该先检查 nil。

### 4.4 max_turns = 0

`Runner#run` 中 `turn > max_turns` → turn 1 > 0 → 立即返回 max_turns 结果。
messages 为空，final_message 为 nil。可能应该要求 max_turns >= 1。

### 4.5 Provider 返回 nil message

`response.message` 为 nil 时，`messages << nil`，后续操作会 NPE。
应该验证 response。

## 5. 模块边界与数据流审查

### 5.1 依赖方向 ✅

```
Agent ──→ PromptBuilder ──→ Resources
  │                            ↑
  └──→ PromptRunner ───────────┘
```

- Agent 依赖所有模块（作为 orchestrator，合理）
- PromptBuilder 依赖 Resources（读取 history, tools, memory）
- PromptRunner 依赖 Resources（执行 tools）和 Message（数据类型）
- Resources 模块之间无循环依赖
- PromptBuilder 和 PromptRunner 之间无直接依赖（通过 BuiltPrompt 传递）

**无循环依赖。✅**

### 5.2 数据流 ✅

```
User Input
  ↓
Agent#chat
  ↓
Agent#build_prompt  →  Memory#search (optional)
  ↓                    ↓
PromptBuilder::Context (数据聚合)
  ↓
Pipeline#build  →  BuiltPrompt (value object, 不可变)
  ↓
Runner#run  →  Provider#chat  →  Response
  ↓                               ↓
  ← tool_calls?  ←────────────────┘
  ↓ yes
Tools::Registry#execute  →  ToolResult
  ↓
  → append to messages → loop back to Provider#chat
  ↓ no (final text)
RunResult (value object)
  ↓
Agent#chat  →  append to ChatHistory
  ↓
Return to caller
```

**单向数据流。✅**

### 5.3 内聚性审查

| 模块 | 内聚等级 | 说明 |
|------|---------|------|
| Message / ContentBlock | ✅ 高 | 纯数据类型，自包含 |
| StreamEvent | ✅ 高 | 纯事件类型 |
| ChatHistory | ✅ 高 | 单一职责：消息存储 |
| Memory | ✅ 高 | 单一职责：长期记忆存储与检索 |
| Provider | ✅ 高 | 单一职责：LLM API 抽象 |
| Tools::Tool | ✅ 高 | 定义 + 执行 |
| Tools::Registry | ✅ 高 | 统一注册 + 查找 + 执行 |
| Tools::Policy | ✅ 高 | 授权决策 |
| PromptBuilder | ✅ 高 | Context→Pipeline→BuiltPrompt，清晰流水线 |
| PromptRunner | ⚠️ 中偏高 | Runner 承担了 tool loop + stream 处理 + policy 检查 |
| Agent | ⚠️ 中 | Orchestrator，正常偏大；需要注意线程安全语义与上下文传递 |

**Runner 内聚改进建议**: 将 `execute_tool_calls` 和 `execute_tool_calls_streaming`
提取为独立的 `ToolExecutor` 类。两个方法高度重复（DRY 违反），也会让 Runner 更精简。

### 5.4 接口清洁度

- `BuiltPrompt` 作为 Builder→Runner 的数据传递对象 ✅
- `RunResult` 作为 Runner→Agent 的数据传递对象 ✅
- `Context` 作为 Agent→Pipeline 的数据传递对象 ✅
- `ToolResult` 作为 Registry→Runner 的数据传递对象 ✅

所有模块间通信使用 value objects，没有直接调用对方内部方法。✅

## 6. 测试覆盖审查

### 6.1 覆盖良好的路径

- ✅ Message 创建、序列化、role 验证
- ✅ ContentBlock 各类型创建与反序列化
- ✅ ChatHistory CRUD + 线程安全 + wrap
- ✅ Memory CRUD + search + metadata filter
- ✅ Registry 注册/查找/执行/格式化
- ✅ Tool 执行 + 错误处理
- ✅ Policy Decision 三种状态
- ✅ Pipeline 基本构建 + memory 注入 + variable 替换 + tool 定义
- ✅ Runner 同步 + tool loop + max_turns + policy deny + streaming
- ✅ Agent build + chat + stream + serialize + reset

### 6.2 未覆盖的路径

- ❌ `Agent#build_events` 的 `@on_event` 路径（建议补测试）
- ❌ `Message.new(content: nil, ...)` 边界
- ❌ Runner 在 provider 抛出异常时的行为
- ❌ Registry MCP 路径（没有 MCP Client mock）
- ❌ Runner streaming 在 MessageComplete 缺失时的行为
- ❌ 空 tool_calls array (`tool_calls: []`)
- ❌ ToolCall arguments 包含嵌套结构的序列化
- ❌ 遗留文件 `test/test_agent_core.rb` 仍存在

## 7. 遗留问题

1. `test/test_agent_core.rb` 目前保留为空文件（避免 `rake test` 默认加载时报错）；后续可考虑移除该入口或改为 require 真实测试
2. gemspec 的 `required_ruby_version` 是 `>= 3.3.0`，但项目 `.ruby-version` 是 `4.0.1`
3. MCP error namespace (`AgentCore::MCP::Error`) 在 Phase 1 定义但 Phase 2 才用

## 8. 修复优先级与状态

> 全部修复完成于 2026-02-14。修复后测试: 98 runs, 196 assertions, 0 failures, 0 errors。

### P0（必须修复，阻塞后续工作）

1. ✅ **Agent#build_events 的 `events.on(hook)` NoMethodError** — 添加了 `Events#on(hook, &block)` 通用方法
2. ✅ **Builder/Agent to_config 不一致** — Agent#to_config 改为使用 Builder 扁平 key 格式

### P1（应尽快修复）

3. ✅ **Events#emit rescue 范围过大** — 改为 per-callback rescue，每个 callback 独立失败
4. ✅ **Runner stream 无 MessageComplete 时返回 nil** — 返回 error RunResult + stream ErrorEvent
5. ✅ **Registry MCP 执行缺少 rescue** — MCP call_tool 异常返回 ToolResult.error
6. ✅ **execute_tool_calls / execute_tool_calls_streaming 重复代码** — 统一为 `execute_tool_calls(stream_block:)` 参数

### P2（改进，不阻塞）

7. ✅ Message content freeze — `@content = content.freeze`
8. ✅ validate_role! nil 检查 — 添加 nil guard，抛出 ArgumentError
9. ✅ Tool 名称冲突检测 — 注册时 warn 冲突
10. ✅ max_turns 最小值校验 — `raise ArgumentError if max_turns < 1`
11. ✅ Provider::Base#models 接口 — 添加默认返回 `[]` 的 `#models` 方法
12. ✅ ToolResult content key 统一 — `#text` 方法兼容 String/Symbol key
13. ✅ Runner 对 nil response.message 的防御 — 返回 error RunResult
14. ✅ 删除 test/test_agent_core.rb — 清空为空文件（保留以避免 load 错误）

### 新增测试覆盖

- `test_nil_role_raises_argument_error` — Message nil role 边界
- `test_content_is_frozen` — Message 内容不可变
- `test_empty_content_blocks_text` — 空 content blocks
- `test_max_turns_zero_raises` — max_turns=0 校验
- `test_max_turns_negative_raises` — max_turns 负数校验
- `test_nil_response_message_returns_error` — provider nil message 防御
- `test_generic_on_method` — Events#on 通用注册
- `test_generic_on_unknown_hook_raises` — Events#on 未知 hook 校验
- `test_per_callback_rescue_continues_to_next` — 回调独立失败
- `test_system_prompt_is_sent_as_system_message` — Runner 确保 system_prompt 进入 messages
- `test_unknown_tool_call_does_not_raise` — tool hallucination 时不会直接抛异常
- `test_memory_injected_into_system_message` — memory 注入确实进入 system message
- `test_symbolize_keys_*` — `AgentCore::Utils.symbolize_keys` key 归一化规则（Symbol 优先）

### 补充修复（Phase 1 之后发现）

- ✅ `Runner` 没有把 `BuiltPrompt#system_prompt` 发给 Provider，导致 system prompt / memory 注入实际未生效
- ✅ streaming 模式补齐 `Events`：`llm_request`、`stream_delta`、`llm_response`
- ✅ tool call 指向未注册 tool 时，`Runner` 捕获 `ToolNotFoundError` 并返回 `ToolResult.error`（不中断整次 run）
- ✅ 将 `Runner#normalized_options` 抽取为 `AgentCore::Utils.symbolize_keys`，作为公共 Hash key 归一化工具

## 9. 仍建议关注（Phase 2 / Rails 整合前）

1. **执行上下文（context）贯穿**：目前 `ToolPolicy#authorize` / `Tools::Registry#execute` 未接收执行上下文（user/session/permissions），限制了鉴权与审计能力；建议在 `Agent#chat/chat_stream` 增加 `context:` 并向下传递（含 policy + tool 执行）。
2. **确认流（Decision.confirm）**：`Decision.confirm` 当前会被当作 deny（非 allowed）处理，但没有“需要用户确认”的交互式通道；建议定义 Runner 的行为（例如 emit 事件并中断、或返回可恢复的结果）。
