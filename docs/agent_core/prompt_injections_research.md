# Prompt 注入 / 上下文管理调研（Codex + OpenClaw + Risuai）与 AgentCore 映射

目标：为 AgentCore 的 `PromptInjections` 基础设施提供一份“对标参考项目”的调研备忘，便于后续在不改底座的前提下，通过定制 source / wrapper / app-side 组装，复刻 Codex/OpenClaw/Risuai 的具体行为。

本报告以当前仓库快照为准（参考实现文档：`docs/agent_core/prompt_injections.md`）。

---

## 0. AgentCore 当前能力（对标基线）

AgentCore 的 Prompt 注入以“生成若干 `Item`”为统一抽象：

- `target: :system_section`：以“可排序 section”追加到 `system_prompt`
- `target: :preamble_message`：以“可排序 message”插入到 chat history 之前（仅允许 `role: :user/:assistant`，不允许 `:system`）
- `prompt_mode: :full/:minimal`：按模式过滤注入（由 `ExecutionContext.attributes[:prompt_mode]` 提供）
- budget/截断：内置策略为 UTF-8 安全的 **Head + Marker + Tail**（按字节）

内置 sources（可组合）：

- `file_set`：读取 workspace 文件集合，注入到 `system_section`
- `repo_docs`：从 `.git` 发现 repo root，收集 root→cwd 层级文档，注入为 1 条 `preamble_message(role: :user)`
- `provided`：APP 在每次调用时通过 `ExecutionContext.attributes` 预置 item
- `text_store`：APP 提供 `fetch(key:)` adapter，source 按 key 拉取文本并生成 item

关键落点：

- items 汇总：`vendor/agent_core/lib/agent_core/context_management/context_manager.rb`
- 组装位置：`vendor/agent_core/lib/agent_core/prompt_builder/simple_pipeline.rb`

---

## 1) Codex（resources/codex）怎么做 user instructions / repo 文档注入

### 1.1 注入位置：preamble 的 user role message

Codex 会把“用户指令（user_instructions）”作为一条 **role=user** 的 message 插入对话（用于让模型把它当作“对用户的额外指令”来遵循）。

相关实现：

- `resources/codex/codex-rs/core/src/codex.rs`：把 `turn_context.user_instructions` 包装成 message（`UserInstructions`）并塞进 items
- `resources/codex/codex-rs/core/src/instructions/user_instructions.rs`：定义了 message 的文本格式

Codex 当前（非 legacy）格式不是简单的 `<user_instructions>...</user_instructions>`，而是：

- `# AGENTS.md instructions for <cwd>`
- `<INSTRUCTIONS> ... </INSTRUCTIONS>`

（同时仍兼容 legacy：以 `<user_instructions>` 开头的消息也会被识别为 user_instructions。）

### 1.2 文档发现：层级 AGENTS.md（含 override 优先）

Codex 的“项目文档”发现规则（简化）：

1. 从 cwd 向上找 `.git`（文件或目录）作为 repo root；不跨越 git root
2. 从 repo root → cwd 的每一层目录，按候选文件名查找并收集
3. **每层只取一个**，并有明确优先级：
   - `AGENTS.override.md` 优先于 `AGENTS.md`
   - 然后才是可配置的 fallback filenames

相关实现：

- `resources/codex/codex-rs/core/src/project_doc.rs`

### 1.3 预算与截断：按 bytes 的“头部截断”

Codex 的 project doc 预算按 `project_doc_max_bytes` 控制：

- 读取时通过 `take(remaining)` 保证不超过剩余预算
- 截断是“只保留前 N bytes”（不是 head+tail）

相关实现：

- `resources/codex/codex-rs/core/src/project_doc.rs`

### 1.4 合并来源：config.user_instructions + project docs + 额外附加段

Codex 的 user instructions 不是“只有 AGENTS.md”，而是多个来源合并：

- `config.user_instructions`（用户显式配置的 instructions）
- project docs（层级 AGENTS.md）
- 可选：某些 feature 会追加一段额外说明（例如 `child_agents_md`）
- 还可能拼上 skills / js repl 等段落

相关实现：

- `resources/codex/codex-rs/core/src/project_doc.rs`（`get_user_instructions`）

---

## 2) OpenClaw（resources/openclaw）怎么做 workspace bootstrap / prompt modes

### 2.1 注入位置：system prompt 的 `# Project Context`

OpenClaw 的“workspace bootstrap 文件注入”发生在 system prompt 内部，并有固定的 `# Project Context` 段落，按文件路径逐个插入：

- 标题：`# Project Context`
- 文件：`## <file.path>` + `file.content`
- 对 `SOUL.md` 会额外提示“按 persona 执行”

相关实现：

- `resources/openclaw/src/agents/system-prompt.ts`

### 2.2 默认 bootstrap 文件集合 + minimal 模式过滤

OpenClaw 把 bootstrap 文件当作“标准集”，例如文档中列出：

- `AGENTS.md`, `SOUL.md`, `TOOLS.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`（新工作区才会有）
- `MEMORY.md`/`memory.md`（可选）

并且 sub-agent（minimal 模式）会默认只注入更小的子集（例如只保留 `AGENTS.md` + `TOOLS.md`）。

相关说明：

- `resources/openclaw/docs/concepts/system-prompt.md`

### 2.3 预算与截断：maxChars + totalMaxChars + head/tail 比例 + 富 marker

OpenClaw 的截断以“字符数（UTF-16）”为单位：

- `bootstrapMaxChars`：单文件最大 chars
- `bootstrapTotalMaxChars`：所有 bootstrap 文件注入总 chars
- head/tail 比例：`BOOTSTRAP_HEAD_RATIO = 0.7`，`BOOTSTRAP_TAIL_RATIO = 0.2`
- marker 会显式提示“去读哪个文件”以及“截断统计”

相关实现：

- `resources/openclaw/src/agents/pi-embedded-helpers/bootstrap.ts`

### 2.4 promptMode：full / minimal / none

OpenClaw 的 system prompt 可以按 `promptMode` 渲染：

- `full`：完整段落
- `minimal`：省略 Skills/Heartbeats/Silent Replies 等
- `none`：只返回非常小的 base identity line

相关说明：

- `resources/openclaw/docs/concepts/system-prompt.md`

此外，OpenClaw 还会把 `extraSystemPrompt` 作为一个独立段插到系统提示词中，并按 minimal/full 切换标题：

- minimal：`## Subagent Context`
- full：`## Group Chat Context`

相关实现：

- `resources/openclaw/src/agents/system-prompt.ts`

### 2.5 可观测性：/context report（注入体积与 token 构成）

OpenClaw 支持输出 context 报告（例如 project context 占用、tool schema chars 等），方便调参。

可参考：

- `resources/openclaw/src/agents/system-prompt-report.ts`

---

## 3) Risuai（resources/Risuai）怎么做长对话压缩与“记忆卡片”

Risuai 更偏“聊天应用”，它的“记忆/上下文管理”主要体现在：

- 维护 token 预算（maxContextTokens）
- 当超预算时先滑窗丢弃旧消息
- 可选启用 SupaMemory/HypaMemory v2/v3，对旧对话进行压缩/摘要并以“特殊 chat item”形态插入或替换

相关线索：

- 入口流程（决定什么时候做 memory 压缩、怎么丢弃消息）：`resources/Risuai/src/ts/process/index.svelte.ts`
- SupaMemory（把历史压缩到 room.supaMemoryData，并影响最终发送 chats）：`resources/Risuai/src/ts/process/memory/supaMemory.ts`

这类系统的共同点是：把“可持续的历史信息”从 transcript 中抽离成一个更紧凑的 memory block，并在 prompt 组装时给它预留预算（甚至按比例分配）。

---

## 4) 与 AgentCore 映射：目前能复刻到什么程度？

### 4.1 Codex user instructions（可近似）

AgentCore 对应能力：

- 用 `repo_docs` 产生 1 条 `preamble_message(role: :user)`
- 通过 `wrapper_template` 自定义文本格式

但要“完全一致”，目前缺：

- per-directory “只取一个文件”的优先级语义（`AGENTS.override.md` > `AGENTS.md`）
- 把 `config.user_instructions` 与 project docs 组装为同一条 message 的内置逻辑（目前建议 APP 侧拼好，用 `provided` 注入）
- Codex 的“只截断头部 bytes”策略（AgentCore 目前默认 head+tail）

### 4.2 OpenClaw bootstrap files（可近似）

AgentCore 对应能力：

- 用 `file_set` 注入一组文件为 `# Project Context`（可配置 header/title）
- per-file `max_bytes` + total `total_max_bytes`
- `prompt_mode :minimal` 过滤（靠 `files[].prompt_modes`）

但要“完全一致”，目前缺：

- OpenClaw 的 head/tail 比例与富 marker（我们是 50/50 + 简单 marker，可配置 marker 但不支持比例/统计）
- “默认 bootstrap 文件集合”与“sub-agent 默认过滤”这种开箱即用策略（目前要在 config 里显式列出）
- /context report 这种可观测性
- prompt_mode `:none`

### 4.3 Risuai 类（上下文压缩 + 记忆卡片）

AgentCore 已有：

- sliding window + auto-compaction（ConversationState summary）

但 Risuai 类系统常见的能力，AgentCore 目前不包含：

- 记忆块预算占比（memoryTokensRatio）与更复杂的“多阶段压缩算法”
- 将摘要/记忆作为“可选择插入的专门消息类型/卡片”并在 UI 层可视化（AgentCore 更偏引擎）

---

## 5) 建议的后续定制点（不改底座也能做）

优先推荐“APP 侧组装 + provided/text_store 注入”，把“精确复刻”变成纯业务层：

1. Codex 精确复刻
   - APP 实现“按层优先级只取一个”的 AGENTS.md 合并（参考 `project_doc.rs`）
   - APP 把 `config.user_instructions + AGENTS.* + skills/js repl 等` 拼成一条字符串
   - 用 `provided` 注入 1 条 `preamble_message(role: :user)`，格式用 `# AGENTS.md instructions for ...` + `<INSTRUCTIONS>`
2. OpenClaw 精确复刻
   - APP 用 OpenClaw 的 head/tail 比例与 marker 规则预裁剪文本（参考 `bootstrap.ts`）
   - 用 `provided` 注入 1 条 `system_section`，内容自己排版成 `# Project Context` + `## path`
   - minimal/full 的标题切换也在 APP 完成（或在多个 items 上按 prompt_modes 分流）

如果希望未来在 AgentCore 内置，也可以做 source 的 v2 版本：

- `repo_docs` v2：per-dir 单文件优先级 + 可配置 separator + 可选“无文件也注入默认说明”
- `file_set` v2：支持 head/tail 比例、marker 模板（含 file name/统计）、以及流式读取避免大文件内存峰值
- 注入可观测性：统一 emit “注入体积/来源/是否截断”事件，方便做类似 OpenClaw 的 /context 报告

