module storage

import memory

fn markdown_embedding_targets_from_ref(database &PersistentDatabase, ref MarkdownRef) ![]memory.MarkdownEmbeddingTarget {
	raw := database.load_markdown(ref)!
	return memory.markdown_embedding_targets(raw)
}
