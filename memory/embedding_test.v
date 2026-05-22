module memory

fn test_markdown_embedding_targets_emit_block_and_path_layers() {
	targets := markdown_embedding_targets('# Intro\n\nHello PollyDB memory.\n\n```v\nprintln("ok")\n```\n\n## Next\n\nShip vectors.\n') or {
		panic(err)
	}

	block_targets := targets.filter(it.scope == .block)
	path_targets := targets.filter(it.scope == .path)

	assert block_targets.len == 3
	assert path_targets.len == 2
	assert block_targets.any(it.kind == 'paragraph' && it.text == 'Hello PollyDB memory.')
	assert block_targets.any(it.kind == 'code_block' && it.text == 'println("ok")')
	assert path_targets.any(it.kind == 'heading_path' && it.text.contains('Intro'))
	assert path_targets.any(it.kind == 'heading_path' && it.text.contains('Ship vectors.'))
}

fn test_markdown_embedding_path_targets_stop_at_next_same_or_higher_heading() {
	targets := markdown_embedding_targets('# A\n\nAlpha.\n\n## A1\n\nNested.\n\n# B\n\nBeta.\n') or {
		panic(err)
	}

	path_targets := targets.filter(it.scope == .path)
	a_target := path_targets.filter(it.text.starts_with('A\n\n'))[0]
	a1_target := path_targets.filter(it.text.starts_with('A1\n\n'))[0]
	b_target := path_targets.filter(it.text.starts_with('B\n\n'))[0]

	assert a_target.anchor == '/h1:a'
	assert a1_target.anchor == '/h1:a/h2:a1'
	assert b_target.anchor == '/h1:b'
	assert a_target.text.contains('Alpha.')
	assert a_target.text.contains('Nested.')
	assert !a_target.text.contains('Beta.')
	assert a1_target.text.contains('Nested.')
	assert !a1_target.text.contains('Beta.')
	assert b_target.text.contains('Beta.')
}

fn test_markdown_embedding_texts_preserve_target_order() {
	targets := [
		MarkdownEmbeddingTarget{
			id:    'a'
			scope: .block
			kind:  'paragraph'
			text:  'first'
		},
		MarkdownEmbeddingTarget{
			id:    'b'
			scope: .path
			kind:  'heading_path'
			text:  'second'
		},
	]

	assert markdown_embedding_texts(targets) == ['first', 'second']
}
