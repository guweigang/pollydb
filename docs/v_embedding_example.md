# V Embedding Example

This is the smallest practical example of using PollyDB directly from V today.

It shows:

- initialize a database
- register a table with a native `markdown_` field
- write one Markdown row
- query it with a Markdown field selector
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
		],
	)!
	db.register_table(spec)!

	cfg := storage.ChunkConfig.default()
	codec := storage.TypedRowCodec.new(spec.table)
	mut seed_row := storage.TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Roadmap')
	seed_row.set('body', storage.MarkdownRef{})
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
- `PersistentDatabase.preview_query_plan_details(...)`

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
