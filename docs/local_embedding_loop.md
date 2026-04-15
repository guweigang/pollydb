# Local Embedding Loop

PollyDB now exposes a small embedding boundary for markdown-backed agent memory.
The default storage build does not link an embedding runtime; runtimes such as
llama.cpp should implement `storage.EmbeddingEngine` and consume the targets
emitted by `storage.markdown_embedding_targets(...)`.

## Layers

`MarkdownEmbeddingTarget.scope` has two values:

- `block`: paragraph and code block targets for precise recall.
- `path`: heading section targets for coarse semantic routing.

Each target carries:

- `id`: stable target id namespaced by markdown root and scope.
- `content_id` and `occurrence_id`: links back to the markdown AST/chunk identity.
- `anchor` and `path_hint`: deterministic navigation back into the source document.
- `text`: the normalized text to feed into the embedding model.

## Engine Contract

```v
pub interface EmbeddingEngine {
	model_name() string
	dimensions() int
mut:
	embed(text string) ![]f32
	embed_batch(texts []string) ![][]f32
}
```

A llama.cpp backend should keep model/context state behind this interface and
return one `[]f32` per target text. The caller can then persist vectors in a
USearch sidecar keyed by `MarkdownEmbeddingTarget.id`.

## llama.cpp Backend Shape

The llama.cpp binding is kept out of the default storage build. Compile with
`-d llama_cpp` only when the headers and library are present.

```v
mut engine := storage.new_llama_embedding_engine(storage.LlamaEmbeddingConfig{
	model_path: '/models/bge-small-zh-v1.5.gguf'
	n_ctx: 512
	n_batch: 512
	n_threads: 4
	n_gpu_layers: 999
})!
defer {
	engine.close()
}
```

On macOS the optional binding looks for `llama.h` and `libllama` under
Homebrew-style paths:

```sh
v -d llama_cpp test storage/embedding_test.v
v -d llama_cpp run cmd/bench/llama_embedding_smoke.v /path/to/model.gguf
v -d llama_cpp run cmd/bench/llama_replay_overview_smoke.v /path/to/model.gguf "数据库优化"
```

If llama.cpp is elsewhere, pass extra C flags through `VFLAGS` or adjust
[storage/llama_embedding_d_llama_cpp.c.v](/Users/guweigang/Source/pollytree/storage/llama_embedding_d_llama_cpp.c.v).

The ingestion flow is:

1. Store markdown through `PersistentDatabase.ingest_markdown`.
2. Build targets with `markdown_embedding_targets_from_ref`.
3. Run `engine.embed_batch(markdown_embedding_texts(targets))`.
4. Upsert vectors into PollyDB native vector records using matching target ids.
5. Rebuild or load sidecar indexes such as USearch from PollyDB records.

This keeps PollyDB as the only source of truth. SQLite remains only the FTS5
lexical index; vector indexes are derived, rebuildable, and replaceable.

For the current replay stack, a smoke path now exists that exercises:

1. markdown ingest into a typed table
2. reflective-field indexing
3. reflection persistence
4. structural and semantic link creation
5. replay overview generation

Run:

```sh
v -d llama_cpp run cmd/bench/llama_replay_overview_smoke.v /path/to/model.gguf "数据库优化"
```
