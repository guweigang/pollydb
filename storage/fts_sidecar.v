module storage

import hash.crc32
import os
import time
import vmarkdown

$if windows {
	#flag windows -I @VMODROOT/thirdparty/native/include
	#flag windows @VMODROOT/thirdparty/native/lib/sqlite3.lib
	#include "sqlite3.h"
} $else $if $pkgconfig('sqlite3') {
	#pkgconfig --cflags --libs sqlite3
	#include "sqlite3.h"
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

fn C.sqlite3_reset(&C.sqlite3_stmt) int

fn C.sqlite3_clear_bindings(&C.sqlite3_stmt) int

fn C.sqlite3_finalize(&C.sqlite3_stmt) int

fn C.sqlite3_bind_text(&C.sqlite3_stmt, int, &char, int, voidptr) int

fn C.sqlite3_bind_int64(&C.sqlite3_stmt, int, i64) int

fn C.sqlite3_column_int(&C.sqlite3_stmt, int) int

fn C.sqlite3_column_int64(&C.sqlite3_stmt, int) i64

fn C.sqlite3_column_text(&C.sqlite3_stmt, int) &u8

fn C.sqlite3_column_bytes(&C.sqlite3_stmt, int) int

fn C.sqlite3_column_double(&C.sqlite3_stmt, int) f64

fn C.sqlite3_errmsg(&C.sqlite3) &char

fn C.sqlite3_last_insert_rowid(&C.sqlite3) i64

fn C.sqlite3_changes(&C.sqlite3) int

fn C.sqlite3_free(voidptr)

@[heap]
struct FtsSqliteDb {
mut:
	conn            &C.sqlite3 = unsafe { nil }
	ensured_indexes map[string]bool
	docid_backfills map[string]bool
}

struct FtsDocidEntry {
	docid       i64
	source_hash string
}

struct FtsDocidAllocation {
	docid    i64
	inserted bool
}

pub struct FtsSidecarHit {
pub:
	row_pk_hex string
	score      f64
}

pub struct FtsSidecarWriteTimings {
pub mut:
	begin_us        i64
	ensure_us       i64
	backfill_us     i64
	prepare_us      i64
	docid_select_us i64
	delete_us       i64
	text_us         i64
	insert_us       i64
	insert_fts_us   i64
	insert_map_us   i64
	commit_us       i64
	ops             int
	inserted        int
	deleted         int
}

fn (mut timings FtsSidecarWriteTimings) add(other FtsSidecarWriteTimings) {
	timings.begin_us += other.begin_us
	timings.ensure_us += other.ensure_us
	timings.backfill_us += other.backfill_us
	timings.prepare_us += other.prepare_us
	timings.docid_select_us += other.docid_select_us
	timings.delete_us += other.delete_us
	timings.text_us += other.text_us
	timings.insert_us += other.insert_us
	timings.insert_fts_us += other.insert_fts_us
	timings.insert_map_us += other.insert_map_us
	timings.commit_us += other.commit_us
	timings.ops += other.ops
	timings.inserted += other.inserted
	timings.deleted += other.deleted
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
		conn:            conn
		ensured_indexes: map[string]bool{}
		docid_backfills: map[string]bool{}
	}
	_ = C.sqlite3_busy_timeout(db.conn, 5000)
	db.exec_none('pragma journal_mode = WAL;') or {}
	db.exec_none('pragma synchronous = NORMAL;') or {}
	return db
}

fn (mut database PersistentDatabase) ensure_fts_sidecar_open() ! {
	if database.fts_sidecar_open {
		return
	}
	database.fts_sidecar = open_fts_sidecar(database.root_dir)!
	database.fts_sidecar_open = true
	ensure_fts_sidecar_base(mut database.fts_sidecar)!
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
	code := C.sqlite3_exec(db.conn, &char(query.str), unsafe { nil }, unsafe { nil }, &err_msg)
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

fn (db &FtsSqliteDb) prepare(query string) !&C.sqlite3_stmt {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	pres := C.sqlite3_prepare_v2(db.conn, &char(query.str), -1, &stmt, 0)
	if pres != sqlite_ok_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
	return stmt
}

fn (db &FtsSqliteDb) bind_text(stmt &C.sqlite3_stmt, idx int, value string) ! {
	code := C.sqlite3_bind_text(stmt, idx, &char(value.str), -1, unsafe { nil })
	if code != sqlite_ok_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
}

fn (db &FtsSqliteDb) bind_i64(stmt &C.sqlite3_stmt, idx int, value i64) ! {
	code := C.sqlite3_bind_int64(stmt, idx, value)
	if code != sqlite_ok_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
}

fn (db &FtsSqliteDb) step_done(stmt &C.sqlite3_stmt) ! {
	code := C.sqlite3_step(stmt)
	if code != sqlite_done_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
}

fn sqlite_stmt_reset(stmt &C.sqlite3_stmt) {
	C.sqlite3_reset(stmt)
	C.sqlite3_clear_bindings(stmt)
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

fn (db &FtsSqliteDb) q_fts_hits(query string) ![]FtsSidecarHit {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	pres := C.sqlite3_prepare_v2(db.conn, &char(query.str), -1, &stmt, 0)
	if pres != sqlite_ok_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) })
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	mut out := []FtsSidecarHit{}
	for {
		code := C.sqlite3_step(stmt)
		if code == sqlite_done_code {
			break
		}
		if code != sqlite_row_code {
			return error('failed to fetch FTS hit rows')
		}
		out << FtsSidecarHit{
			row_pk_hex: sqlite_stmt_text(stmt, 0)
			score:      C.sqlite3_column_double(stmt, 1)
		}
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
	sidecar.exec_none('create table if not exists pollydb_fts_docid_backfills (docid_table_name text not null, branch_name text not null, primary key(docid_table_name, branch_name))')!
}

fn ensure_fts_sidecar_for_specs(mut database PersistentDatabase, specs []TypedTableSpec) ! {
	if specs.len == 0 {
		return
	}
	database.ensure_fts_sidecar_open()!
	for spec in specs {
		for index in spec.indexes {
			if !index.is_fts() {
				continue
			}
			ensure_fts_sidecar_index_table(mut database.fts_sidecar, spec, index)!
		}
	}
}

fn ensure_fts_sidecar_index_table(mut sidecar FtsSqliteDb, spec TypedTableSpec, index SchemaIndexDef) ! {
	table_name := fts_sidecar_table_name(spec.table.name, index.name)
	docid_table_name := fts_sidecar_docid_table_name(spec.table.name, index.name)
	cache_key := '${table_name}|${docid_table_name}'
	if cache_key in sidecar.ensured_indexes {
		return
	}
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
	if automerge_sql := fts_sidecar_automerge_sql(table_name) {
		sidecar.exec_none(automerge_sql) or {}
	}
	ensure_fts_sidecar_docid_table(mut sidecar, docid_table_name)!
	meta_sql := 'insert or replace into pollydb_fts_indexes(table_name, index_name, column_name, source_plugin, text_mode, tokenizer, prefix_lengths) values (${sqlite_text(spec.table.name)}, ${sqlite_text(index.name)}, ${sqlite_text(index.column)}, ${sqlite_text(index.fts_source_plugin)}, ${sqlite_text(index.fts_text_mode)}, ${sqlite_text(index.fts_tokenizer)}, ${sqlite_text(index.fts_prefix_lengths.map(it.str()).join(','))})'
	sidecar.exec_none(meta_sql)!
	sidecar.ensured_indexes[cache_key] = true
}

fn ensure_fts_sidecar_docid_table(mut sidecar FtsSqliteDb, docid_table_name string) ! {
	table_ident := sqlite_ident(docid_table_name)
	sidecar.exec_none('create table if not exists ${table_ident} (docid integer primary key, branch_name text not null, row_pk text not null, source_hash text not null default \'\', unique(branch_name, row_pk))')!
	sidecar.exec_none('alter table ${table_ident} add column source_hash text not null default \'\'') or {}
	docid_pk := sidecar.q_int('select coalesce((select pk from pragma_table_info(${sqlite_text(docid_table_name)}) where name = \'docid\'), 0)') or {
		0
	}
	if docid_pk == 1 {
		return
	}
	legacy_name := '${docid_table_name}_legacy_docid_map'
	sidecar.exec_none('drop table if exists ${sqlite_ident(legacy_name)}')!
	sidecar.exec_none('alter table ${table_ident} rename to ${sqlite_ident(legacy_name)}')!
	sidecar.exec_none('create table ${table_ident} (docid integer primary key, branch_name text not null, row_pk text not null, source_hash text not null default \'\', unique(branch_name, row_pk))')!
	sidecar.exec_none('insert or ignore into ${table_ident}(docid, branch_name, row_pk, source_hash) select docid, branch_name, row_pk, source_hash from ${sqlite_ident(legacy_name)} where docid > 0 order by docid')!
	sidecar.exec_none('drop table ${sqlite_ident(legacy_name)}')!
}

fn fts_sidecar_automerge_sql(table_name string) ?string {
	raw := os.getenv('POLLYDB_FTS_AUTOMERGE').trim_space().to_lower()
	if raw in ['default', 'sqlite', 'off', '-1'] {
		return none
	}
	level := if raw.len == 0 { 0 } else { raw.int() }
	if level < 0 {
		return none
	}
	return "insert into ${sqlite_ident(table_name)}(${sqlite_ident(table_name)}, rank) values('automerge', ${level})"
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
					if value.is_zero() {
						return ''
					}
					if cached := database.cached_markdown_fts_text(value.doc_root_id,
						index.fts_text_mode)
					{
						return cached
					}
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

fn fts_sidecar_delete_row_prepared(sidecar &FtsSqliteDb, stmt &C.sqlite3_stmt, branch_name string, row_pk_hex string) ! {
	sidecar.bind_text(stmt, 1, branch_name)!
	sidecar.bind_text(stmt, 2, row_pk_hex)!
	sidecar.step_done(stmt)!
	sqlite_stmt_reset(stmt)
}

fn fts_sidecar_select_docid_prepared(sidecar &FtsSqliteDb, stmt &C.sqlite3_stmt, branch_name string, row_pk_hex string) !i64 {
	sidecar.bind_text(stmt, 1, branch_name)!
	sidecar.bind_text(stmt, 2, row_pk_hex)!
	code := C.sqlite3_step(stmt)
	if code == sqlite_done_code {
		sqlite_stmt_reset(stmt)
		return i64(0)
	}
	if code != sqlite_row_code {
		return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(sidecar.conn))) })
	}
	docid := C.sqlite3_column_int64(stmt, 0)
	finish := C.sqlite3_step(stmt)
	if finish != sqlite_done_code {
		return error('unexpected trailing rows in FTS docid lookup')
	}
	sqlite_stmt_reset(stmt)
	return docid
}

fn fts_sidecar_select_docids_for_rows(sidecar &FtsSqliteDb, docid_table_name string, branch_name string, row_pk_hexes []string) !map[string]i64 {
	if row_pk_hexes.len == 0 {
		return map[string]i64{}
	}
	mut unique := map[string]bool{}
	mut values := []string{cap: row_pk_hexes.len}
	for row_pk_hex in row_pk_hexes {
		if row_pk_hex in unique {
			continue
		}
		unique[row_pk_hex] = true
		values << sqlite_text(row_pk_hex)
	}
	if values.len == 0 {
		return map[string]i64{}
	}
	query := 'select row_pk, docid from ${sqlite_ident(docid_table_name)} where branch_name = ${sqlite_text(branch_name)} and row_pk in (${values.join(',')})'
	stmt := sidecar.prepare(query)!
	defer {
		C.sqlite3_finalize(stmt)
	}
	mut out := map[string]i64{}
	for {
		code := C.sqlite3_step(stmt)
		if code == sqlite_done_code {
			break
		}
		if code != sqlite_row_code {
			return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(sidecar.conn))) })
		}
		row_pk_text := C.sqlite3_column_text(stmt, 0)
		if row_pk_text == unsafe { nil } {
			continue
		}
		row_pk := unsafe { (&char(row_pk_text)).vstring() }
		out[row_pk] = C.sqlite3_column_int64(stmt, 1)
	}
	return out
}

fn fts_sidecar_select_docid_entries_for_rows(sidecar &FtsSqliteDb, docid_table_name string, branch_name string, row_pk_hexes []string) !map[string]FtsDocidEntry {
	if row_pk_hexes.len == 0 {
		return map[string]FtsDocidEntry{}
	}
	mut unique := map[string]bool{}
	mut values := []string{cap: row_pk_hexes.len}
	for row_pk_hex in row_pk_hexes {
		if row_pk_hex in unique {
			continue
		}
		unique[row_pk_hex] = true
		values << sqlite_text(row_pk_hex)
	}
	if values.len == 0 {
		return map[string]FtsDocidEntry{}
	}
	query := 'select row_pk, docid, source_hash from ${sqlite_ident(docid_table_name)} where branch_name = ${sqlite_text(branch_name)} and row_pk in (${values.join(',')})'
	stmt := sidecar.prepare(query)!
	defer {
		C.sqlite3_finalize(stmt)
	}
	mut out := map[string]FtsDocidEntry{}
	for {
		code := C.sqlite3_step(stmt)
		if code == sqlite_done_code {
			break
		}
		if code != sqlite_row_code {
			return error(unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(sidecar.conn))) })
		}
		row_pk_text := C.sqlite3_column_text(stmt, 0)
		if row_pk_text == unsafe { nil } {
			continue
		}
		row_pk := unsafe { (&char(row_pk_text)).vstring() }
		out[row_pk] = FtsDocidEntry{
			docid:       C.sqlite3_column_int64(stmt, 1)
			source_hash: sqlite_stmt_text(stmt, 2)
		}
	}
	return out
}

fn fts_text_has_non_space(text string) bool {
	for ch in text {
		if ch != ` ` && ch != `\n` && ch != `\r` && ch != `\t` {
			return true
		}
	}
	return false
}

fn fts_text_source_hash(text string) string {
	return '${text.len}:${crc32.sum(text.bytes())}'
}

fn fts_sidecar_backfill_docid_map_for_branch(mut sidecar FtsSqliteDb, table_name string, docid_table_name string, branch_name string) ! {
	cache_key := '${docid_table_name}|${branch_name}'
	if cache_key in sidecar.docid_backfills {
		return
	}
	done :=
		sidecar.q_int('select count(*) from pollydb_fts_docid_backfills where docid_table_name = ${sqlite_text(docid_table_name)} and branch_name = ${sqlite_text(branch_name)}')!
	if done > 0 {
		sidecar.docid_backfills[cache_key] = true
		return
	}
	sidecar.exec_none('insert or ignore into ${sqlite_ident(docid_table_name)}(branch_name, row_pk, docid, source_hash) select branch_name, row_pk, rowid, \'\' from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)}')!
	sidecar.exec_none('insert or ignore into pollydb_fts_docid_backfills(docid_table_name, branch_name) values (${sqlite_text(docid_table_name)}, ${sqlite_text(branch_name)})')!
	sidecar.docid_backfills[cache_key] = true
}

fn fts_sidecar_delete_mapped_row_prepared(sidecar &FtsSqliteDb, select_docid_stmt &C.sqlite3_stmt, delete_fts_stmt &C.sqlite3_stmt, delete_map_stmt &C.sqlite3_stmt, branch_name string, row_pk_hex string) ! {
	docid := fts_sidecar_select_docid_prepared(sidecar, select_docid_stmt, branch_name, row_pk_hex)!
	if docid > 0 {
		sidecar.bind_i64(delete_fts_stmt, 1, docid)!
		sidecar.step_done(delete_fts_stmt)!
		sqlite_stmt_reset(delete_fts_stmt)
	}
	fts_sidecar_delete_row_prepared(sidecar, delete_map_stmt, branch_name, row_pk_hex)!
}

fn fts_sidecar_delete_mapped_docid_prepared(sidecar &FtsSqliteDb, delete_fts_stmt &C.sqlite3_stmt, delete_map_stmt &C.sqlite3_stmt, branch_name string, row_pk_hex string, docid i64) ! {
	if docid > 0 {
		sidecar.bind_i64(delete_fts_stmt, 1, docid)!
		sidecar.step_done(delete_fts_stmt)!
		sqlite_stmt_reset(delete_fts_stmt)
	}
	fts_sidecar_delete_row_prepared(sidecar, delete_map_stmt, branch_name, row_pk_hex)!
}

fn fts_sidecar_allocate_docid_prepared(sidecar &FtsSqliteDb, insert_map_new_stmt &C.sqlite3_stmt, select_docid_stmt &C.sqlite3_stmt, branch_name string, row_pk_hex string, source_hash string) !FtsDocidAllocation {
	sidecar.bind_text(insert_map_new_stmt, 1, branch_name)!
	sidecar.bind_text(insert_map_new_stmt, 2, row_pk_hex)!
	sidecar.bind_text(insert_map_new_stmt, 3, source_hash)!
	sidecar.step_done(insert_map_new_stmt)!
	inserted := C.sqlite3_changes(sidecar.conn) > 0
	sqlite_stmt_reset(insert_map_new_stmt)
	if inserted {
		return FtsDocidAllocation{
			docid:    C.sqlite3_last_insert_rowid(sidecar.conn)
			inserted: true
		}
	}
	return FtsDocidAllocation{
		docid: fts_sidecar_select_docid_prepared(sidecar, select_docid_stmt, branch_name,
			row_pk_hex)!
	}
}

fn fts_sidecar_upsert_docid_map_prepared(sidecar &FtsSqliteDb, insert_map_stmt &C.sqlite3_stmt, branch_name string, row_pk_hex string, docid i64, source_hash string) ! {
	sidecar.bind_text(insert_map_stmt, 1, branch_name)!
	sidecar.bind_text(insert_map_stmt, 2, row_pk_hex)!
	sidecar.bind_i64(insert_map_stmt, 3, docid)!
	sidecar.bind_text(insert_map_stmt, 4, source_hash)!
	sidecar.step_done(insert_map_stmt)!
	sqlite_stmt_reset(insert_map_stmt)
}

fn fts_sidecar_insert_rowid_prepared(sidecar &FtsSqliteDb, insert_fts_stmt &C.sqlite3_stmt, docid i64, branch_name string, row_pk_hex string, text string) ! {
	sidecar.bind_i64(insert_fts_stmt, 1, docid)!
	sidecar.bind_text(insert_fts_stmt, 2, branch_name)!
	sidecar.bind_text(insert_fts_stmt, 3, row_pk_hex)!
	sidecar.bind_text(insert_fts_stmt, 4, text)!
	sidecar.step_done(insert_fts_stmt)!
	sqlite_stmt_reset(insert_fts_stmt)
}

fn fts_index_may_change_for_op(index SchemaIndexDef, op TypedWriteOp) bool {
	if op.delete || !op.changed_columns_known {
		return true
	}
	return index.column in op.changed_columns
}

fn fts_write_set_has_relevant_ops(spec_by_name map[string]TypedTableSpec, operations []TypedWriteOp) bool {
	for op in operations {
		spec := spec_by_name[op.table_name] or { continue }
		for index in spec_fts_indexes(spec) {
			if fts_index_may_change_for_op(index, op) {
				return true
			}
		}
	}
	return false
}

fn fts_sidecar_apply_write_set_for_index(mut sidecar FtsSqliteDb, database &PersistentDatabase, branch_name string, spec TypedTableSpec, index SchemaIndexDef, operations []TypedWriteOp) !FtsSidecarWriteTimings {
	mut timings := FtsSidecarWriteTimings{}
	mut relevant_ops := []TypedWriteOp{}
	for op in operations {
		if op.table_name != spec.table.name || !fts_index_may_change_for_op(index, op) {
			continue
		}
		relevant_ops << op
	}
	if relevant_ops.len == 0 {
		return timings
	}
	table_name := fts_sidecar_table_name(spec.table.name, index.name)
	docid_table_name := fts_sidecar_docid_table_name(spec.table.name, index.name)
	mut backfill_sw := time.new_stopwatch()
	fts_sidecar_backfill_docid_map_for_branch(mut sidecar, table_name, docid_table_name,
		branch_name)!
	timings.backfill_us += backfill_sw.elapsed().microseconds()
	delete_fts_sql := 'delete from ${sqlite_ident(table_name)} where rowid = ?'
	delete_map_sql := 'delete from ${sqlite_ident(docid_table_name)} where branch_name = ? and row_pk = ?'
	insert_rowid_sql := 'insert into ${sqlite_ident(table_name)}(rowid, branch_name, row_pk, body) values (?, ?, ?, ?)'
	replace_rowid_sql := 'insert or replace into ${sqlite_ident(table_name)}(rowid, branch_name, row_pk, body) values (?, ?, ?, ?)'
	insert_map_new_sql := 'insert or ignore into ${sqlite_ident(docid_table_name)}(branch_name, row_pk, source_hash) values (?, ?, ?)'
	insert_map_sql := 'insert or replace into ${sqlite_ident(docid_table_name)}(branch_name, row_pk, docid, source_hash) values (?, ?, ?, ?)'
	select_docid_sql := 'select docid from ${sqlite_ident(docid_table_name)} where branch_name = ? and row_pk = ?'
	mut prepare_sw := time.new_stopwatch()
	delete_fts_stmt := sidecar.prepare(delete_fts_sql)!
	delete_map_stmt := sidecar.prepare(delete_map_sql)!
	insert_rowid_stmt := sidecar.prepare(insert_rowid_sql)!
	replace_rowid_stmt := sidecar.prepare(replace_rowid_sql)!
	insert_map_new_stmt := sidecar.prepare(insert_map_new_sql)!
	insert_map_stmt := sidecar.prepare(insert_map_sql)!
	select_docid_stmt := sidecar.prepare(select_docid_sql)!
	timings.prepare_us += prepare_sw.elapsed().microseconds()
	defer {
		C.sqlite3_finalize(delete_fts_stmt)
		C.sqlite3_finalize(delete_map_stmt)
		C.sqlite3_finalize(insert_rowid_stmt)
		C.sqlite3_finalize(replace_rowid_stmt)
		C.sqlite3_finalize(insert_map_new_stmt)
		C.sqlite3_finalize(insert_map_stmt)
		C.sqlite3_finalize(select_docid_stmt)
	}
	mut row_pk_hexes := []string{}
	for op in relevant_ops {
		if op.existing_row_known && !op.had_existing_row && !op.delete {
			continue
		}
		row_pk_hexes << op.primary_key.hex()
	}
	mut docids := map[string]FtsDocidEntry{}
	if row_pk_hexes.len > 0 {
		mut docid_sw := time.new_stopwatch()
		docids = fts_sidecar_select_docid_entries_for_rows(&sidecar, docid_table_name, branch_name,
			row_pk_hexes)!
		timings.docid_select_us += docid_sw.elapsed().microseconds()
	}
	for op in relevant_ops {
		timings.ops++
		row_pk_hex := op.primary_key.hex()
		docid_entry := docids[row_pk_hex] or { FtsDocidEntry{} }
		docid := docid_entry.docid
		if docid > 0 {
			if op.delete {
				mut delete_sw := time.new_stopwatch()
				sidecar.bind_i64(delete_fts_stmt, 1, docid)!
				sidecar.step_done(delete_fts_stmt)!
				sqlite_stmt_reset(delete_fts_stmt)
				timings.delete_us += delete_sw.elapsed().microseconds()
			}
		}
		if op.delete {
			mut delete_sw := time.new_stopwatch()
			fts_sidecar_delete_row_prepared(&sidecar, delete_map_stmt, branch_name, row_pk_hex)!
			timings.delete_us += delete_sw.elapsed().microseconds()
			timings.deleted++
			continue
		}
		mut text_sw := time.new_stopwatch()
		text := (fts_text_for_row_data(database, spec.table, op.row, index) or { continue }).clone()
		source_hash := fts_text_source_hash(text)
		timings.text_us += text_sw.elapsed().microseconds()
		if docid > 0 && docid_entry.source_hash == source_hash {
			continue
		}
		if text.len == 0 || !fts_text_has_non_space(text) {
			if docid > 0 {
				mut delete_sw := time.new_stopwatch()
				sidecar.bind_i64(delete_fts_stmt, 1, docid)!
				sidecar.step_done(delete_fts_stmt)!
				sqlite_stmt_reset(delete_fts_stmt)
				fts_sidecar_delete_row_prepared(&sidecar, delete_map_stmt, branch_name, row_pk_hex)!
				timings.delete_us += delete_sw.elapsed().microseconds()
				timings.deleted++
			}
			continue
		}
		mut target_docid := docid
		mut new_docid := false
		mut map_has_source_hash := docid > 0 && docid_entry.source_hash == source_hash
		if target_docid <= 0 {
			mut map_sw := time.new_stopwatch()
			allocation := fts_sidecar_allocate_docid_prepared(&sidecar, insert_map_new_stmt,
				select_docid_stmt, branch_name, row_pk_hex, source_hash)!
			target_docid = allocation.docid
			new_docid = allocation.inserted
			map_has_source_hash = allocation.inserted
			map_elapsed := map_sw.elapsed().microseconds()
			timings.insert_map_us += map_elapsed
			timings.insert_us += map_elapsed
		}
		mut insert_sw := time.new_stopwatch()
		write_stmt := if new_docid { insert_rowid_stmt } else { replace_rowid_stmt }
		fts_sidecar_insert_rowid_prepared(&sidecar, write_stmt, target_docid, branch_name,
			row_pk_hex, text)!
		insert_elapsed := insert_sw.elapsed().microseconds()
		timings.insert_us += insert_elapsed
		timings.insert_fts_us += insert_elapsed
		if !map_has_source_hash {
			mut map_sw := time.new_stopwatch()
			fts_sidecar_upsert_docid_map_prepared(&sidecar, insert_map_stmt, branch_name,
				row_pk_hex, target_docid, source_hash)!
			map_elapsed := map_sw.elapsed().microseconds()
			timings.insert_map_us += map_elapsed
			timings.insert_us += map_elapsed
		}
		timings.inserted++
	}
	return timings
}

pub fn (mut database PersistentDatabase) apply_fts_write_set(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet) !FtsSidecarWriteTimings {
	if write_set.len() == 0 {
		return FtsSidecarWriteTimings{}
	}
	mut spec_by_name := map[string]TypedTableSpec{}
	for spec in specs {
		if !spec.indexes.any(it.is_fts()) {
			continue
		}
		spec_by_name[spec.table.name] = spec
	}
	if spec_by_name.len == 0 {
		return FtsSidecarWriteTimings{}
	}
	operations := write_set.operations()
	if !fts_write_set_has_relevant_ops(spec_by_name, operations) {
		return FtsSidecarWriteTimings{}
	}
	mut timings := FtsSidecarWriteTimings{}
	mut ensure_sw := time.new_stopwatch()
	ensure_fts_sidecar_for_specs(mut database, spec_by_name.values())!
	database.ensure_fts_sidecar_open()!
	timings.ensure_us += ensure_sw.elapsed().microseconds()
	mut begin_sw := time.new_stopwatch()
	database.fts_sidecar.exec_none('begin immediate')!
	timings.begin_us += begin_sw.elapsed().microseconds()
	for spec in spec_by_name.values() {
		for index in spec_fts_indexes(spec) {
			index_timings := fts_sidecar_apply_write_set_for_index(mut database.fts_sidecar,
				database, branch_name, spec, index, operations)!
			timings.add(index_timings)
		}
	}
	mut commit_sw := time.new_stopwatch()
	database.fts_sidecar.exec_none('commit')!
	timings.commit_us += commit_sw.elapsed().microseconds()
	return timings
}

fn fts_sidecar_optimize_index_table(mut sidecar FtsSqliteDb, table_name string) ! {
	sidecar.exec_none("insert into ${sqlite_ident(table_name)}(${sqlite_ident(table_name)}) values('optimize')")!
}

pub fn (mut database PersistentDatabase) optimize_fts_indexes(table_names []string) ! {
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
	database.ensure_fts_sidecar_open()!
	for spec in specs {
		for index in spec.indexes {
			if !index.is_fts() {
				continue
			}
			table_name := fts_sidecar_table_name(spec.table.name, index.name)
			fts_sidecar_optimize_index_table(mut database.fts_sidecar, table_name)!
		}
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
	database.ensure_fts_sidecar_open()!
	session := database.begin_session(SessionOptions.for_branch(branch_name))!
	database.fts_sidecar.exec_none('begin immediate')!
	for spec in specs {
		rows := session.scan_table(mut database, spec.table.name, 0) or { []TypedSchemaRow{} }
		for index in spec.indexes {
			if !index.is_fts() {
				continue
			}
			ensure_fts_sidecar_index_table(mut database.fts_sidecar, spec, index)!
			table_name := fts_sidecar_table_name(spec.table.name, index.name)
			docid_table_name := fts_sidecar_docid_table_name(spec.table.name, index.name)
			database.fts_sidecar.exec_none('delete from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)}')!
			database.fts_sidecar.exec_none('delete from ${sqlite_ident(docid_table_name)} where branch_name = ${sqlite_text(branch_name)}')!
			database.fts_sidecar.exec_none('delete from pollydb_fts_docid_backfills where docid_table_name = ${sqlite_text(docid_table_name)} and branch_name = ${sqlite_text(branch_name)}')!
			database.fts_sidecar.docid_backfills.delete('${docid_table_name}|${branch_name}')
			insert_stmt :=
				database.fts_sidecar.prepare('insert into ${sqlite_ident(table_name)}(rowid, branch_name, row_pk, body) values (?, ?, ?, ?)')!
			insert_map_new_stmt :=
				database.fts_sidecar.prepare('insert or ignore into ${sqlite_ident(docid_table_name)}(branch_name, row_pk, source_hash) values (?, ?, ?)')!
			select_docid_stmt :=
				database.fts_sidecar.prepare('select docid from ${sqlite_ident(docid_table_name)} where branch_name = ? and row_pk = ?')!
			defer {
				C.sqlite3_finalize(insert_stmt)
				C.sqlite3_finalize(insert_map_new_stmt)
				C.sqlite3_finalize(select_docid_stmt)
			}
			for row in rows {
				text :=
					(fts_sidecar_document_text(database, spec.table, row, index) or { continue }).clone()
				if text.len == 0 || text.trim_space().len == 0 {
					continue
				}
				row_pk_hex := row.primary_key.hex()
				allocation := fts_sidecar_allocate_docid_prepared(&database.fts_sidecar,
					insert_map_new_stmt, select_docid_stmt, branch_name, row_pk_hex,
					fts_text_source_hash(text))!
				fts_sidecar_insert_rowid_prepared(&database.fts_sidecar, insert_stmt,
					allocation.docid, branch_name, row_pk_hex, text)!
			}
			database.fts_sidecar.exec_none('insert or ignore into pollydb_fts_docid_backfills(docid_table_name, branch_name) values (${sqlite_text(docid_table_name)}, ${sqlite_text(branch_name)})')!
			fts_sidecar_optimize_index_table(mut database.fts_sidecar, table_name)!
		}
	}
	database.fts_sidecar.exec_none('commit')!
}

pub fn fts_sidecar_document_text(database &PersistentDatabase, table TableDef, row TypedSchemaRow, index SchemaIndexDef) !string {
	return fts_text_for_row_data(database, table, row.data, index)
}

fn extract_markdown_fts_text(raw string, mode string) !string {
	if raw.len == 0 {
		return ''
	}
	if mode == FtsTextMode.raw_markdown.str() {
		return raw
	}
	return match mode {
		'visible_text' {
			extract_markdown_visible_text_fast(raw, false)
		}
		'visible_text_with_code' {
			extract_markdown_visible_text_fast(raw, true)
		}
		else {
			return error('unsupported markdown FTS text mode: ${mode}')
		}
	}
}

fn extract_markdown_visible_text_fast(raw string, include_code_blocks bool) string {
	mut parts := []string{}
	mut in_fenced_code := false
	for line in raw.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('```') || trimmed.starts_with('~~~') {
			in_fenced_code = !in_fenced_code
			continue
		}
		if in_fenced_code {
			if include_code_blocks && trimmed.len > 0 {
				parts << trimmed
			}
			continue
		}
		text := markdown_visible_line_text(trimmed)
		if text.len > 0 {
			parts << text
		}
	}
	return parts.join(' ').trim_space()
}

fn markdown_visible_line_text(line string) string {
	if line.len == 0 || markdown_line_is_horizontal_rule(line) {
		return ''
	}
	mut text := line
	for text.starts_with('#') {
		text = text[1..].trim_space()
	}
	for text.starts_with('>') {
		text = text[1..].trim_space()
	}
	if text.len >= 2 && (text.starts_with('- ') || text.starts_with('* ') || text.starts_with('+ ')) {
		text = text[2..].trim_space()
	} else {
		dot_idx := text.index('.') or { -1 }
		if dot_idx > 0 && dot_idx < 4 && dot_idx + 1 < text.len && text[dot_idx + 1] == ` ` {
			mut numeric := true
			for ch in text[..dot_idx] {
				if ch < `0` || ch > `9` {
					numeric = false
					break
				}
			}
			if numeric {
				text = text[dot_idx + 2..].trim_space()
			}
		}
	}
	return text
}

fn markdown_line_is_horizontal_rule(line string) bool {
	if line.len < 3 {
		return false
	}
	marker := line[0]
	if marker !in [`-`, `*`, `_`] {
		return false
	}
	for ch in line {
		if ch != marker && ch != ` ` && ch != `\t` {
			return false
		}
	}
	return true
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

fn fts_sidecar_docid_table_name(table_name string, index_name string) string {
	return 'ftsmap_${sqlite_safe_identifier(table_name)}_${sqlite_safe_identifier(index_name)}'
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
	query :=
		'select row_pk, bm25(${sqlite_ident(table_name)}) from ${sqlite_ident(table_name)} where branch_name = ${sqlite_text(branch_name)} and body match ${sqlite_text(match_query)}' +
		if limit > 0 { ' limit ${limit}' } else { '' }
	return db.q_fts_hits(query)
}
