# AgentCore app-side storage adapters

This doc describes a practical Rails approach to persisting the three context
stores that AgentCore expects:

- **ChatHistory**: full, ordered transcript (append-only)
- **ConversationState**: small derived state for context management (summary + cursor)
- **Memory (pgvector)**: semantic store for retrieval (RAG)

AgentCore is a library — it does not prescribe persistence. The app owns IO.

## Why split these stores?

AgentCore uses them differently:

- **ChatHistory** is the canonical record (UI, audit, replay, tool debug). It can
  grow without bounds because it is *not always fully injected into the model*.
- **ConversationState** is the agent-managed “checkpoint” that keeps prompts
  small. It is intentionally tiny so it can be read/written frequently.
- **Memory** is not “the transcript”; it is query-driven retrieval (often across
  many sessions) and can be backed by embeddings + metadata filters.

In AgentCore core:

- context budgeting uses a sliding window first
- when `auto_compact` is enabled, dropped turns are summarized into
  `ConversationState` and injected back as `<conversation_summary>…</conversation_summary>`
- memory search results are injected into the system prompt (and are dropped
  first when the prompt would overflow)

## Data model (recommended)

Use a stable `conversation_id` as the join key.

### Tables

**`agent_conversations`**

- `id` (uuid/bigint)
- `created_at`, `updated_at`

**`agent_messages`** (ChatHistory)

- `id` (uuid/bigint)
- `conversation_id` (FK)
- `position` (integer, monotonically increasing within conversation)
- `role` (string, e.g. `"user"|"assistant"|"tool_result"|"system"`)
- `payload` (jsonb) — store `AgentCore::Message#to_h`
- `created_at`

Indexes:

- unique: `(conversation_id, position)`
- optional: `(conversation_id, created_at)`

**`agent_conversation_states`** (ConversationState, 1 row per conversation)

- `conversation_id` (PK/FK)
- `summary` (text, nullable)
- `cursor` (integer, default `0`, non-null)
- `compaction_count` (integer, default `0`, non-null)
- `lock_version` (integer, default `0`, non-null) for optimistic locking
- `updated_at`

**`agent_memory_entries`** (Memory via pgvector)

- `id` (uuid, PK)
- `conversation_id` (nullable FK; optional scoping)
- `content` (text)
- `metadata` (jsonb)
- `embedding` (`vector(n)`) — dimension depends on your embedding model
- `created_at`, `updated_at`

Indexes:

- `GIN (metadata)` if you filter on metadata keys
- pgvector index on `embedding` (HNSW or IVFFLAT), choose ops by distance metric

### Sample migrations

These are illustrative; adapt naming/PKs to your app.

```ruby
class CreateAgentConversations < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_conversations, id: :uuid do |t|
      t.timestamps
    end
  end
end
```

```ruby
class CreateAgentMessages < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_messages, id: :uuid do |t|
      t.uuid :conversation_id, null: false
      t.integer :position, null: false
      t.string :role, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :agent_messages, %i[conversation_id position], unique: true
    add_index :agent_messages, %i[conversation_id created_at]
    add_foreign_key :agent_messages, :agent_conversations, column: :conversation_id
  end
end
```

```ruby
class CreateAgentConversationStates < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_conversation_states, id: false do |t|
      t.uuid :conversation_id, null: false, primary_key: true
      t.text :summary
      t.integer :cursor, null: false, default: 0
      t.integer :compaction_count, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.datetime :updated_at, null: false
    end

    add_foreign_key :agent_conversation_states, :agent_conversations, column: :conversation_id
  end
end
```

For pgvector, you need the extension + vector column. The cleanest approach is
to add the `pgvector` gem and use its migration helpers. If you do not want a
gem dependency, use `execute` to enable the extension and create the vector
column.

```ruby
class CreateAgentMemoryEntries < ActiveRecord::Migration[8.2]
  def change
    enable_extension "vector"

    create_table :agent_memory_entries, id: :uuid do |t|
      t.uuid :conversation_id
      t.text :content, null: false
      t.jsonb :metadata, null: false, default: {}
      # With pgvector gem: t.vector :embedding, limit: 1536
      t.timestamps
    end

    add_index :agent_memory_entries, :conversation_id
    add_index :agent_memory_entries, :metadata, using: :gin
  end
end
```

Indexing `embedding` depends on the distance operator you choose (cosine/L2/IP).
Example (cosine, HNSW):

```sql
CREATE INDEX index_agent_memory_entries_on_embedding
  ON agent_memory_entries
  USING hnsw (embedding vector_cosine_ops);
```

## Adapter interfaces

### ChatHistory adapter

Implement `AgentCore::Resources::ChatHistory::Base`:

- `#append(message)` stores one `AgentCore::Message`
- `#each` yields messages in chronological order
- `#size`, `#clear`

Recommended payload format:

- store `message.to_h` (jsonb)
- hydrate with `AgentCore::Message.from_h(payload)`

Example skeleton:

```ruby
class ChatHistoryStore < AgentCore::Resources::ChatHistory::Base
  def initialize(conversation_id:)
    @conversation_id = conversation_id
  end

  def append(message)
    AgentMessage.create!(
      conversation_id: @conversation_id,
      position: next_position!,
      role: message.role.to_s,
      payload: message.to_h,
      created_at: Time.current,
    )
    self
  end

  def each
    return enum_for(:each) unless block_given?

    AgentMessage.where(conversation_id: @conversation_id).order(:position).find_each do |row|
      yield AgentCore::Message.from_h(row.payload)
    end
  end

  def size
    AgentMessage.where(conversation_id: @conversation_id).count
  end

  def clear
    AgentMessage.where(conversation_id: @conversation_id).delete_all
    self
  end

  private

  def next_position!
    AgentMessage
      .where(conversation_id: @conversation_id)
      .maximum(:position)
      .to_i + 1
  end
end
```

Concurrency note: `next_position!` must be transaction-safe under concurrent
writers. Use one of:

- `SELECT ... FOR UPDATE` on the conversation row (simple)
- store `next_position` on `agent_conversations` and increment atomically
- use a database sequence scoped by conversation (advanced)

### ConversationState adapter

Implement `AgentCore::Resources::ConversationState::Base`:

- `#load` returns `AgentCore::Resources::ConversationState::State`
- `#save(state)` persists `summary/cursor/compaction_count`

Example skeleton:

```ruby
class ConversationStateStore < AgentCore::Resources::ConversationState::Base
  def initialize(conversation_id:)
    @conversation_id = conversation_id
  end

  def load
    row = AgentConversationState.find_by(conversation_id: @conversation_id)
    return AgentCore::Resources::ConversationState::State.new unless row

    AgentCore::Resources::ConversationState::State.new(
      summary: row.summary,
      cursor: row.cursor,
      compaction_count: row.compaction_count,
      updated_at: row.updated_at,
    )
  end

  def save(state)
    AgentConversationState.upsert(
      {
        conversation_id: @conversation_id,
        summary: state.summary,
        cursor: state.cursor,
        compaction_count: state.compaction_count,
        updated_at: Time.current,
      },
      unique_by: :primary_key,
    )
    self
  end
end
```

Concurrency note: when multiple workers may compact the same conversation,
prefer optimistic locking (`lock_version`) or `SELECT ... FOR UPDATE` to avoid
lost updates.

Cursor semantics:

- `cursor` is the number of transcript messages covered by `summary`
- the agent will only iterate messages *after* `cursor` when building prompts
- if your app deletes/prunes old transcript rows, reset conversation state too

### pgvector Memory adapter

Implement `AgentCore::Resources::Memory::Base`. The adapter will typically need
an injected **embedder** (app-owned) because AgentCore does not call embedding
APIs.

Recommended constructor dependencies:

- `conversation_id:` optional scope
- `embedder:` responds to `embed(text) -> Array<Float>`
- `dimensions:` validates embedding size

Search strategy:

1) embed the `query` into a vector
2) SQL `ORDER BY embedding <=> query_vec` (cosine distance) with `LIMIT`
3) apply `metadata_filter` with `metadata @> '{...}'`

Score mapping:

- pgvector returns a *distance* (lower is better). Convert to a score if you
  need one (for example `score = 1.0 / (1.0 + distance)`).

Pseudo-code:

```ruby
class PgvectorMemory < AgentCore::Resources::Memory::Base
  def initialize(embedder:, conversation_id: nil)
    @embedder = embedder
    @conversation_id = conversation_id
  end

  def search(query:, limit: 5, metadata_filter: nil)
    qvec = @embedder.embed(query.to_s)
    vec_literal = "[#{qvec.join(",")}]"
    conn = ActiveRecord::Base.connection
    distance_sql = "embedding <=> #{conn.quote(vec_literal)}::vector"

    rel = AgentMemoryEntry.all
    rel = rel.where(conversation_id: @conversation_id) if @conversation_id
    rel = rel.where("metadata @> ?", metadata_filter.to_json) if metadata_filter

    rel
      .select("id, content, metadata, (#{distance_sql}) AS distance")
      .order(Arel.sql(distance_sql))
      .limit(limit)
      .map do |row|
        distance = row.attributes["distance"].to_f
        score = 1.0 / (1.0 + distance)
        AgentCore::Resources::Memory::Entry.new(
          id: row.id,
          content: row.content,
          metadata: row.metadata,
          score: score,
        )
      end
  end

  def store(content:, metadata: {})
    vec = @embedder.embed(content.to_s)
    vec_literal = "[#{vec.join(",")}]"
    row =
      AgentMemoryEntry.create!(
        conversation_id: @conversation_id,
        content: content.to_s,
        metadata: metadata,
        embedding: vec_literal,
      )
    AgentCore::Resources::Memory::Entry.new(id: row.id, content: row.content, metadata: row.metadata)
  end

  def forget(id:)
    AgentMemoryEntry.where(id: id).delete_all > 0
  end

  def all
    AgentMemoryEntry.all.map do |row|
      AgentCore::Resources::Memory::Entry.new(id: row.id, content: row.content, metadata: row.metadata)
    end
  end

  def size
    AgentMemoryEntry.count
  end

  def clear
    AgentMemoryEntry.delete_all
    self
  end
end
```

## Wiring into AgentCore

Once you have stores, inject them into `AgentCore::Agent`:

```ruby
agent = AgentCore::Agent.build do |b|
  b.provider = provider
  b.model = llm_model.model
  b.system_prompt = system_prompt

  b.chat_history = ChatHistoryStore.new(conversation_id: conversation.id)
  b.conversation_state = ConversationStateStore.new(conversation_id: conversation.id)
  b.memory = PgvectorMemory.new(embedder: embedder, conversation_id: conversation.id)

  b.token_counter = token_counter
  b.context_window = llm_model.context_window_tokens
  b.reserved_output_tokens = effective_llm_options[:max_tokens].to_i

  b.auto_compact = true
  b.memory_search_limit = 5
  b.summary_max_output_tokens = 512
end
```

With this wiring, the agent can:

- keep full transcript in the DB (ChatHistory)
- persist compaction summaries across requests/jobs (ConversationState)
- retrieve relevant long-term context (pgvector Memory)
