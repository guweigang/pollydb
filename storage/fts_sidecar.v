module storage

import os
import vmarkdown

$if windows {
	#flag windows -lsqlite3
} $else {
	#flag -lsqlite3
	#include "sqlite3.h"
}

const fts_sidecar_schema_version = 'v1'
const sqlite_ok_code = 0
const sqlite_row_code = 100
const sqlite_done_code = 101

struct C.sqlite3 {}

struct C.sqlite3_stmt {}

fn C.sqlite3_open(&char, &&C.sqlite3) int

fn C.sqlite3_close(&C.sqlite3) int

fn C.sqlite3_busy_timeout(&C.sqlite3, int) int

fn C.sqlite3_exec(&C.sqlite3, &char, voidptr, voidptr, &&char) int

fn C.sqlite3_prepare_v2(&C.sqlite3, &char, int, &&C.sqlite3_stmt, &&char) int

fn C.sqlite3_step(&C.sqlite3_stmt) int

fn C.sqlite3_finalize(&C.sqlite3_stmt) int

fn C.sqlite3_column_int(&C.sqlite3_stmt, int) int

fn C.sqlite3_column_text(&C.sqlite3_stmt, int) &u8

fn C.sqlite3_column_bytes(&C.sqlite3_stmt, int) int

fn C.sqlite3_column_double(&C.sqlite3_stmt, int) f64

fn C.sqlite3_errmsg(&C.sqlite3) &char

fn C.sqlite3_free(voidptr)

@[heap]
struct FtsSqliteDb {
mut:
	conn &C.sqlite3 = unsafe { nil }
}

pub struct FtsSidecarHit {
pub:
	row_pk_hex string
	score      f64
}

fn fts_sidecar_dir(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'fts')
}

fn fts_sidecar_path(root_dir string) string {
	return os.join_path(fts_sidecar_dir(root_dir), 'fts.db')
}

fn ensure_fts_sidecar_layout(root_dir string) ! {
	os.mkdir_all(fts_sidecar_dir(root_dir))!
}

fn open_fts_sidecar(root_dir string) !FtsSqliteDb {
	ensure_fts_sidecar_layout(root_dir)!
	mut conn := &C.sqlite3(unsafe { nil })
	path := fts_sidecar_path(root_dir)
	code := C.sqlite3_open(&char(path.str), &conn)
	if code != sqlite_ok_code {
		if conn != unsafe { nil } {
			return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(conn))) })
		}
		return error('failed to open FTS sidecar sqlite database')
	}
	mut db := FtsSqliteDb{
		conn: conn
	}
	_ = C.sqlite3_busy_timeout(db.conn, 5000)
	db.exec_none('pragma journal_mode = WAL;') or {}
	db.exec_none('pragma synchronous = NORMAL;') or {}
	return db
}

fn (mut db FtsSqliteDb) close() ! {
	if db.conn == unsafe { nil } {
		return
	}
	code := C.sqlite3_close(db.conn)
	if code != sqlite_ok_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
	db.conn = unsafe { nil }
}

fn (db &FtsSqliteDb) exec_none(query string) ! {
	mut err_msg := &char(unsafe { nil })
	code := C.sqlite3_exec(db.conn, &char(query.str), unsafe { nil }, unsafe { nil },
		&err_msg)
	if code == sqlite_ok_code {
		return
	}
	if err_msg != unsafe { nil } {
		msg := unsafe { cstring_to_vstring(err_msg) }
		C.sqlite3_free(err_msg)
		return error(msg)
	}
	return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
}

fn (db &FtsSqliteDb) q_int(query string) !int {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	pres := C.sqlite3_prepare_v2(db.conn, &char(query.str), -1, &stmt, 0)
	if pres != sqlite_ok_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	code := C.sqlite3_step(stmt)
	if code != sqlite_row_code {
		return error('failed to fetch integer result')
	}
	value := C.sqlite3_column_int(stmt, 0)
	finish := C.sqlite3_step(stmt)
	if finish != sqlite_done_code {
		return error('unexpected trailing rows in scalar query')
	}
	return value
}

fn (db &FtsSqliteDb) q_strings(query string) ![]string {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	pres := C.sqlite3_prepare_v2(db.conn, &char(query.str), -1, &stmt, 0)
	if pres != sqlite_ok_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	mut out := []string{}
	for {
		code := C.sqlite3_step(stmt)
		if code == sqlite_done_code {
			break
		}
		if code != sqlite_row_code {
			return error('failed to fetch string rows')
		}
		value := C.sqlite3_column_text(stmt, 0)
		if value == unsafe { nil } {
			out << ''
			continue
		}
		out << unsafe { (&char(value)).vstring() }
	}
	return out
}

fn sqlite_stmt_text(stmt &C.sqlite3_stmt, idx int) string {
	value := C.sqlite3_column_text(stmt, idx)
	if value == unsafe { nil } {
		return ''
	}
	value_len := C.sqlite3_column_bytes(stmt, idx)
	if value_len <= 0 {
		return ''
	}
	return unsafe { (&char(value)).vstring_with_len(value_len).clone() }
}

fn (db &FtsSqliteDb) q_f64(query string) !f64 {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	pres := C.sqlite3_prepare_v2(db.conn, &char(query.str), -1, &stmt, 0)
	if pres != sqlite_ok_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	code := C.sqlite3_step(stmt)
	if code != sqlite_row_code {
		return error('failed to fetch float result')
	}
	value := C.sqlite3_column_double(stmt, 0)
	finish := C.sqlite3_step(stmt)
	if finish != sqlite_done_code {
		return error('unexpected trailing rows in float query')
	}
	return value
}

fn ensure_fts_sidecar_base(mut sidecar FtsSqliteDb) ! {
	sidecar.exec_none('create table if not exists pollydb_fts_meta (name text primary key, value text not null)')!
	sidecar.exec_none("insert or replace into pollydb_fts_meta(name, value) values ('schema_version', '${fts_sidecar_schema_version}')")!
	sidecar.exec_none('create table if not exists pollydb_fts_indexes (table_name text not null, index_name text primary key, column_name text not null, source_plugin text not null, text_mode text not null, tokenizer text not null, prefix_lengths text not null)')!
}

fn ensure_fts_sidecar_for_specs(mut database PersistentDatabase, specs []TypedTableSpec) ! {
	if specs.len == 0 {
		return
	}
	mut sidecar := open_fts_sidecar(database.root_dir)!
	defer {
		sidecar.close() or {}
	}
	ensure_fts_sidecar_base(mut sidecar)!
	for spec in specs {
		for index in spec.indexes {
			if !index.is_fts() {
				continue
			}
			ensure_fts_sidecar_index_table(mut sidecar, spec, index)!
		}
	}
}

fn ensure_fts_sidecar_index_table(mut sidecar FtsSqliteDb, spec TypedTableSpec, index SchemaIndexDef) ! {
	table_name := fts_sidecar_table_name(spec.table.name, index.name)
	mut create_query := 'create virtual table if not exists ${sqlite_ident(table_name)} using fts5(branch_name UNINDEXED, row_pk UNINDEXED, body'
	tokenizer := index.fts_tokenizer.trim_space()
	if tokenizer.len > 0 {
		create_query += ', tokenize=${sqlite_text(tokenizer)}'
	}
	if index.fts_prefix_lengths.len > 0 {
		create_query += ', prefix=${sqlite_text(index.fts_prefix_lengths.map(it.str()).join(' '))}'
	}
	create_query += ');'
	sidecar.exec_none(create_query)!
	meta_sql := 'insert or replace into pollydb_fts_indexes(table_name, index_name, column_name, source_plugin, text_mode, tokenizer, prefix_lengths) values (${sqlite_text(spec.table.name)}, ${sqlite_text(index.name)}, ${sqlite_text(index.column)}, ${sqlite_text(index.fts_source_plugin)}, ${sqlite_text(index.fts_text_mode)}, ${sqlite_text(index.fts_tokenizer)}, ${sqlite_text(index.fts_prefix_lengths.map(it.str()).join(','))})'
	sidecar.exec_none(meta_sql)!
}

fn spec_fts_indexes(spec TypedTableSpec) []SchemaIndexDef {
	return spec.indexes.filter(it.is_fts())
}

fn fts_text_for_row_data(database &PersistentDatabase, table TableDef, row TypedRowData, index SchemaIndexDef) !string {
	column := table.column(index.column)!
	value := row.get(index.column)!
	return match column.typ {
		.string_ {
			match value {
				string { value.clone() }
				NullValue { '' }
				else { return error('fts string column requires string payload: ${index.column}') }
			}
		}
		.markdown_ {
			match value {
				MarkdownRef {
					raw := database.load_markdown(value)!
					(extract_markdown_fts_text(raw, index.fts_text_mode)!).clone()
				}
				NullValue {
					''
				}
				else {
					return error('fts markdown column requires MarkdownRef payload: ${index.column}')
				}
			}
		}
		else {
			return error('unsupported FTS column type: ${column.typ.str()}')
		}
	}
}

fn fts_sidecar_delete_row_for_indexes(mut sidecar FtsSqliteDb, branch_name string, spec TypedTableSpec, indexes []SchemaIndexDef, primary_key []u8) ! {
	row_pk_hex := primary_key.hex()
	for index in indexes {
		table_name := fts_sidecar_table_name(spec.table.name, index.name)
		sidecar.exec_none('delete from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)} and row_pk = ${sqlite_text(row_pk_hex)}')!
	}
}

fn fts_sidecar_upsert_row(mut sidecar FtsSqliteDb, database &PersistentDatabase, branch_name string, spec TypedTableSpec, indexes []SchemaIndexDef, primary_key []u8, row TypedRowData) ! {
	row_pk_hex := primary_key.hex()
	for index in indexes {
		ensure_fts_sidecar_index_table(mut sidecar, spec, index)!
		table_name := fts_sidecar_table_name(spec.table.name, index.name)
		sidecar.exec_none('delete from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)} and row_pk = ${sqlite_text(row_pk_hex)}')!
		text := (fts_text_for_row_data(database, spec.table, row, index) or { continue }).clone()
		if text.len == 0 || text.trim_space().len == 0 {
			continue
		}
		insert_sql := 'insert into ${sqlite_ident(table_name)}(branch_name, row_pk, body) values (${sqlite_text(branch_name)}, ${sqlite_text(row_pk_hex)}, ${sqlite_text(text)})'
		sidecar.exec_none(insert_sql)!
	}
}

pub fn (mut database PersistentDatabase) apply_fts_write_set(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet) ! {
	if write_set.len() == 0 {
		return
	}
	mut spec_by_name := map[string]TypedTableSpec{}
	for spec in specs {
		if !spec.indexes.any(it.is_fts()) {
			continue
		}
		spec_by_name[spec.table.name] = spec
	}
	if spec_by_name.len == 0 {
		return
	}
	ensure_fts_sidecar_for_specs(mut database, spec_by_name.values())!
	mut sidecar := open_fts_sidecar(database.root_dir)!
	defer {
		sidecar.close() or {}
	}
	ensure_fts_sidecar_base(mut sidecar)!
	for op in write_set.operations() {
		spec := spec_by_name[op.table_name] or { continue }
		indexes := spec_fts_indexes(spec)
		if indexes.len == 0 {
			continue
		}
		if op.delete {
			fts_sidecar_delete_row_for_indexes(mut sidecar, branch_name, spec, indexes,
				op.primary_key)!
			continue
		}
		fts_sidecar_upsert_row(mut sidecar, database, branch_name, spec, indexes, op.primary_key,
			op.row)!
	}
}

pub fn (mut database PersistentDatabase) rebuild_fts_indexes_at_branch(branch_name string, table_names []string) ! {
	mut specs := []TypedTableSpec{}
	for spec in database.registered_specs() {
		if table_names.len > 0 && spec.table.name !in table_names {
			continue
		}
		if !spec.indexes.any(it.is_fts()) {
			continue
		}
		specs << spec
	}
	if specs.len == 0 {
		return
	}
	ensure_fts_sidecar_for_specs(mut database, specs)!
	mut sidecar := open_fts_sidecar(database.root_dir)!
	defer {
		sidecar.close() or {}
	}
	ensure_fts_sidecar_base(mut sidecar)!
	session := database.begin_session(SessionOptions.for_branch(branch_name))!
	for spec in specs {
		rows := session.scan_table(mut database, spec.table.name, 0) or { []TypedSchemaRow{} }
		for index in spec.indexes {
			if !index.is_fts() {
				continue
			}
			ensure_fts_sidecar_index_table(mut sidecar, spec, index)!
			table_name := fts_sidecar_table_name(spec.table.name, index.name)
			sidecar.exec_none('delete from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)}')!
			for row in rows {
				text := (fts_sidecar_document_text(database, spec.table, row, index) or { continue }).clone()
				if text.len == 0 || text.trim_space().len == 0 {
					continue
				}
				insert_sql := 'insert into ${sqlite_ident(table_name)}(branch_name, row_pk, body) values (${sqlite_text(branch_name)}, ${sqlite_text(row.primary_key.hex())}, ${sqlite_text(text)})'
				sidecar.exec_none(insert_sql)!
			}
		}
	}
}

fn fts_sidecar_document_text(database &PersistentDatabase, table TableDef, row TypedSchemaRow, index SchemaIndexDef) !string {
	return fts_text_for_row_data(database, table, row.data, index)
}

fn extract_markdown_fts_text(raw string, mode string) !string {
	if raw.len == 0 {
		return ''
	}
	if mode == FtsTextMode.raw_markdown.str() {
		return raw
	}
	doc := vmarkdown.parse(raw)!
	return match mode {
		'visible_text' {
			markdown_document_visible_text(doc, false)
		}
		'visible_text_with_code' {
			markdown_document_visible_text(doc, true)
		}
		else {
			return error('unsupported markdown FTS text mode: ${mode}')
		}
	}
}

fn markdown_document_visible_text(doc vmarkdown.Document, include_code_blocks bool) string {
	return markdown_blocks_visible_text(doc.children, include_code_blocks)
}

fn markdown_blocks_visible_text(nodes []vmarkdown.BlockNode, include_code_blocks bool) string {
	mut parts := []string{}
	for node in nodes {
		text := markdown_block_visible_text(node, include_code_blocks)
		if text.len > 0 {
			parts << text
		}
	}
	return parts.join(' ').trim_space()
}

fn markdown_block_visible_text(node vmarkdown.BlockNode, include_code_blocks bool) string {
	return match node {
		vmarkdown.MetaNode {
			markdown_meta_text(node)
		}
		vmarkdown.HorizontalRuleNode {
			''
		}
		vmarkdown.HeadingNode {
			markdown_inline_text_value(node.children)
		}
		vmarkdown.ParagraphNode {
			markdown_inline_text_value(node.children)
		}
		vmarkdown.CodeBlockNode {
			if include_code_blocks {
				node.content.trim_space()
			} else {
				''
			}
		}
		vmarkdown.BlockquoteNode {
			markdown_blocks_visible_text(node.children, include_code_blocks)
		}
		vmarkdown.ListNode {
			mut texts := []string{}
			for item in node.items {
				text := markdown_blocks_visible_text(item.children, include_code_blocks)
				if text.len > 0 {
					texts << text
				}
			}
			texts.join(' ').trim_space()
		}
	}
}

fn fts_sidecar_table_name(table_name string, index_name string) string {
	return 'fts_${sqlite_safe_identifier(table_name)}_${sqlite_safe_identifier(index_name)}'
}

fn sqlite_safe_identifier(raw string) string {
	if raw.len == 0 {
		return '_'
	}
	mut out := []u8{}
	for ch in raw.bytes() {
		if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) {
			out << ch
		} else {
			out << `_`
		}
	}
	return out.bytestr()
}

fn sqlite_ident(raw string) string {
	return '"${raw.replace('"', '""')}"'
}

fn sqlite_literal_text(raw string) string {
	mut out := []u8{cap: raw.len}
	for b in raw.bytes() {
		if b == `\0` {
			out << ` `
			continue
		}
		out << b
	}
	return out.bytestr()
}

fn sqlite_text(raw string) string {
	escaped := sqlite_literal_text(raw).replace("'", "''")
	return "'${escaped}'"
}

pub fn fts_sidecar_branch_row_count(root_dir string, table_name string, branch_name string) !int {
	mut db := open_fts_sidecar(root_dir)!
	defer {
		db.close() or {}
	}
	query := 'select count(*) from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)}'
	return db.q_int(query)
}

pub fn fts_sidecar_match_count(root_dir string, table_name string, branch_name string, query_text string) !int {
	mut db := open_fts_sidecar(root_dir)!
	defer {
		db.close() or {}
	}
	query := 'select count(*) from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)} and body match ${sqlite_text(query_text)}'
	return db.q_int(query)
}

pub fn fts_sidecar_query_row_pks(root_dir string, table_name string, branch_name string, match_query string, limit int) ![]string {
	mut db := open_fts_sidecar(root_dir)!
	defer {
		db.close() or {}
	}
	query :=
		'select row_pk from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)} and body match ${sqlite_text(match_query)}' +
		if limit > 0 { ' limit ${limit}' } else { '' }
	return db.q_strings(query)
}

pub fn fts_sidecar_query_hits(root_dir string, table_name string, branch_name string, match_query string, limit int) ![]FtsSidecarHit {
	mut db := open_fts_sidecar(root_dir)!
	defer {
		db.close() or {}
	}
	row_pk_hexes := fts_sidecar_query_row_pks(root_dir, table_name, branch_name, match_query, limit)!
	mut out := []FtsSidecarHit{cap: row_pk_hexes.len}
	for row_pk_hex in row_pk_hexes {
		score_query := 'select bm25(${sqlite_ident(table_name)}) from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)} and row_pk = ${sqlite_text(row_pk_hex)} and body match ${sqlite_text(match_query)}'
		out << FtsSidecarHit{
			row_pk_hex: row_pk_hex
			score:      db.q_f64(score_query) or { 0.0 }
		}
	}
	return out
}
