# V Embedding Example

This is the smallest practical example of using PollyDB directly from V today.

It shows:

- initialize a database
- register a table with a native `markdown_` field
- write one Markdown row
- query it with a Markdown field selector
- query it with lightweight FTS
- inspect planner preview metadata

## Minimal Example

```v
module main

import os
import storage

fn main() ! {
	root_dir := os.join_path(os.vtmp_dir(), 'pollydb-v-embed-demo')
	os.rmdir_all(root_dir) or {}

	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	defer {
		db.close() or {}
	}

	spec := storage.TypedTableSpec.new(
		storage.TableDef.new('notes', [
			storage.ColumnDef.new('id', .string_, false)!,
			storage.ColumnDef.new('title', .string_, false)!,
			storage.ColumnDef.new('body', .markdown_, false)!,
		], ['id'])!,
		[
			storage.SchemaIndexDef.markdown_value('body_heading_text_idx', 'body', 'heading_text:2')!,
			storage.SchemaIndexDef.markdown_value('body_link_host_idx', 'body', 'link_host')!,
			storage.SchemaIndexDef.markdown_value('body_fts_any_idx', 'body', 'fts')!,
		],
	)!
	db.register_table(spec)!

	cfg := storage.ChunkConfig.default()
	codec := storage.TypedRowCodec.new(spec.table)
	mut seed_row := storage.TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Roadmap')
	seed_row.set('body', storage.MarkdownRef{
		doc_root_id: 'seed-note-1'
		source_hash: 'seed-note-1'
		source_len: 0
	})
	seed_tree := storage.Tree.build([
		storage.KVPair{
			key: storage.TableView.new(storage.Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg)!
	_ = db.commit_to_branch('main', seed_tree, storage.CommitMeta{
		author: 'gwg'
		message: 'seed notes table'
		timestamp: 1
	})!

	session := db.open_session('main')!
	_ = session.put_markdown(
		mut db,
		'notes',
		'note-1'.bytes(),
		'body',
		'# Intro\n\nSee [docs](https://docs.example.com).\n\n## Roadmap\n\nShip it.\n',
		cfg,
		storage.CommitMeta{
			author: 'gwg'
			message: 'write markdown body'
			timestamp: 2
		},
	)!

	page := session.query_page(mut db, storage.QueryRequest{
		table_name: 'notes'
		filters: [
			storage.QueryFilter.field_prefix('body', 'markdown', 'heading_text:2', 'Road')
		]
		select_columns: ['title']
		limit: 10
	})!

	println('rows=${page.rows.len}')
	println('strategy=${page.plan.strategy}')
	println('index=${page.plan.index_name}')

	fts := session.query_fts(mut db, storage.FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		kind: .all
		terms: ['pollydb', 'roadmap']
		select_columns: ['title']
		limit: 10
	})!

	println('fts_rows=${fts.rows.len}')
	println('fts_strategy=${fts.plan.strategy}')
	println('fts_index=${fts.plan.index_name}')

	preview := db.preview_query_plan_details(storage.QueryRequest{
		table_name: 'notes'
		filters: [
			storage.QueryFilter.field_prefix('body', 'markdown', 'heading_text:2', 'Road')
			storage.QueryFilter.eq('title', 'Roadmap')
		]
		select_columns: ['title']
		limit: 10
	})!

	println('preview_strategy=${preview.plan.strategy}')
	println('preview_notes=${preview.notes}')
	println('preview_warnings=${preview.warnings}')
}
```

## What This Example Uses

The most important APIs are:

- `PersistentDatabase.init(...)`
- `TypedTableSpec.new(...)`
- `SchemaIndexDef.markdown_value(...)`
- `DatabaseSession.put_markdown(...)`
- `DatabaseSession.query_page(...)`
- `DatabaseSession.query_fts(...)`
- `PersistentDatabase.preview_query_plan_details(...)`

## Lightweight FTS Example

The same Markdown row can also be queried through the lightweight lexical FTS layer:

```v
preview := session.preview_fts_query_details(storage.FtsQuery{
	table_name: 'notes'
	column_name: 'body'
	scope: .any
	kind: .any
	terms: ['agent', 'sync']
	limit: 20
})!

println(preview.plan.strategy)
println(preview.notes)

result := session.query_fts(mut db, storage.FtsQuery{
	table_name: 'notes'
	column_name: 'body'
	scope: .heading
	kind: .term
	terms: ['roadmap']
	select_columns: ['title']
	limit: 20
})!
```

Supported lightweight FTS kinds today:

- `term`
- `prefix`
- `all`
- `any`

Supported Markdown FTS scopes today:

- `any`
- `heading`
- `paragraph`
- `code_block`
- `list_item`

## Simpler Query Construction Options

If you do not want to build `QueryRequest` directly, PollyDB now also exposes
two intermediate lowering layers:

- `SqlFilterFragment`
- `NormalizedQueryPredicate`

Those are intended for future `vsql`, but they are also usable directly from V
if you want a more builder-like query construction path.

## When This Is Enough

Direct V embedding is already a good fit when:

- you want typed storage without waiting for `vsql`
- you are comfortable defining table specs in code
- your query needs fit the current single-table filter model
- you want planner introspection without adding SQL parsing first

If you want SQL syntax, that is the next layer.
If you want storage/query behavior from V today, this is already enough.
