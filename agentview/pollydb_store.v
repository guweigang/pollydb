module agentview

import os
import storage

const store_branch = 'main'

pub struct PollyDbStore {
pub:
	root_dir string
}

pub fn PollyDbStore.open(root_dir string) !PollyDbStore {
	mut store := PollyDbStore{
		root_dir: root_dir
	}
	store.init_schema()!
	return store
}

fn (store PollyDbStore) init_schema() ! {
	if !os.exists(store.root_dir) {
		os.mkdir_all(store.root_dir)!
	}
	status := storage.PersistentDatabase.inspect(store.root_dir, store_branch) or {
		storage.PersistentDatabaseStatusReport{}
	}
	mut db := if status.repository_exists || status.catalog_exists {
		storage.PersistentDatabase.open(store.root_dir, store_branch)!
	} else {
		storage.PersistentDatabase.init(store.root_dir, store_branch)!
	}
	defer {
		db.close() or {}
	}
	if !db.has_table('sessions') {
		db.register_table(sessions_spec()!)!
	}
	if !db.has_table('entries') {
		db.register_table(entries_spec()!)!
	}
	db.checkpoint()!
}

pub fn (store PollyDbStore) sync_codex(codex_root string) !SyncStats {
	return store.sync_codex_with_progress(codex_root, no_sync_progress)
}

pub fn (store PollyDbStore) sync_codex_with_progress(codex_root string, reporter SyncProgressReporter) !SyncStats {
	summaries := list_codex_sessions(codex_root, 0)!
	if summaries.len == 0 {
		return SyncStats{}
	}
	mut title_by_id := load_codex_session_titles(codex_root)!
	status := storage.PersistentDatabase.inspect(store.root_dir, store_branch) or {
		storage.PersistentDatabaseStatusReport{}
	}
	mut existing := map[string]SessionSummary{}
	if store_branch in status.branches {
		for summary in store.list_sessions(0) or { []SessionSummary{} } {
			existing[summary.id] = summary
		}
	}
	mut pending := []SessionSummary{}
	mut skipped := 0
	for summary in summaries {
		current := existing[summary.id] or {
			pending << summary
			continue
		}
		if same_session_summary(current, summary) {
			skipped++
			reporter(SyncProgress{
				total_sessions: summaries.len
				processed_sessions: pending.len + skipped
				imported_sessions: pending.len
				imported_entries: 0
				skipped_sessions: skipped
				session_id: summary.id
				session_title: summary.title
				phase: 'skip'
			})
			continue
		}
		pending << summary
	}
	if pending.len == 0 {
		reporter(SyncProgress{
			total_sessions: summaries.len
			processed_sessions: summaries.len
			imported_sessions: 0
			imported_entries: 0
			skipped_sessions: skipped
			phase: 'done'
		})
		return SyncStats{
			skipped: skipped
		}
	}
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	if !store_branch_exists(mut db) {
		seed_store_branch(mut db, pending[0])!
	}
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(64))!
	delete_entries_for_sessions(mut db, mut session, pending.map(it.id))!
	reporter(SyncProgress{
		total_sessions: summaries.len
		imported_sessions: 0
		imported_entries: 0
		skipped_sessions: skipped
		phase: 'start'
	})
	mut entry_count := 0
	mut processed := skipped
	mut imported := 0
	for summary in pending {
		reporter(SyncProgress{
			total_sessions: summaries.len
			processed_sessions: processed
			imported_sessions: imported
			imported_entries: entry_count
			skipped_sessions: skipped
			session_id: summary.id
			session_title: summary.title
			phase: 'import'
		})
		transcript := read_codex_transcript(summary.path, mut title_by_id)!
		put_session_summary(mut db, mut session, transcript.summary)!
		for entry in transcript.entries {
			put_session_entry(mut db, mut session, transcript.summary, entry)!
			entry_count++
		}
		imported++
		processed++
	}
	session.finish(mut db)!
	db.checkpoint()!
	reporter(SyncProgress{
		total_sessions: summaries.len
		processed_sessions: summaries.len
		imported_sessions: imported
		imported_entries: entry_count
		skipped_sessions: skipped
		phase: 'done'
	})
	return SyncStats{
		sessions: pending.len
		entries: entry_count
		skipped: skipped
	}
}

fn no_sync_progress(_ SyncProgress) {}

pub fn (store PollyDbStore) list_sessions(limit int) ![]SessionSummary {
	result := store.list_sessions_page(SessionListRequest{
		limit: limit
	})!
	return result.sessions
}

pub fn (store PollyDbStore) list_sessions_page(request SessionListRequest) !SessionListResult {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'sessions', 0)!
	mut out := []SessionSummary{cap: rows.len}
	for row in rows {
		out << decode_session_summary(row)!
	}
	out.sort_with_compare(fn (a &SessionSummary, b &SessionSummary) int {
		if a.updated_at > b.updated_at {
			return -1
		}
		if a.updated_at < b.updated_at {
			return 1
		}
		return 0
	})
	if request.query.len > 0 || request.cwd_prefix.len > 0 || !request.include_archived {
		needle := request.query.to_lower()
		mut filtered := []SessionSummary{}
		for item in out {
			if !request.include_archived && item.archived {
				continue
			}
			if request.cwd_prefix.len > 0 && !item.cwd.starts_with(request.cwd_prefix) {
				continue
			}
			if needle.len > 0 {
				haystack := '${item.title}\n${item.cwd}\n${item.path}'.to_lower()
				if !haystack.contains(needle) {
					continue
				}
			}
			filtered << item
		}
		out = filtered.clone()
	}
	total := out.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	return SessionListResult{
		total: total
		sessions: out[start..end].clone()
	}
}

pub fn (store PollyDbStore) load_session(session_id string) !SessionTranscript {
	page := store.load_transcript_page(TranscriptRequest{
		session_id: session_id
		limit: 100000
	})!
	return SessionTranscript{
		summary: page.summary
		entries: page.entries
	}
}

pub fn (store PollyDbStore) load_transcript_page(request TranscriptRequest) !TranscriptPage {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	session_row := session.get_row(mut db, 'sessions', request.session_id.bytes())!
	summary := decode_session_summary(session_row)!
	rows := session.scan_table(mut db, 'entries', 0)!
	mut entries := []SessionEntry{}
	for row in rows {
		if entry_session_id(row)! != request.session_id {
			continue
		}
		entries << decode_session_entry_with_markdown(mut db, row)!
	}
	entries.sort_with_compare(fn (a &SessionEntry, b &SessionEntry) int {
		if a.seq < b.seq {
			return -1
		}
		if a.seq > b.seq {
			return 1
		}
		return 0
	})
	total := entries.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	return TranscriptPage{
		summary: summary
		total_entries: total
		entries: entries[start..end].clone()
	}
}

pub fn (store PollyDbStore) search(query string, limit int) ![]SearchHit {
	result := store.search_entries(SearchRequest{
		query: query
		limit: limit
	})!
	return result.hits
}

pub fn (store PollyDbStore) search_entries(request SearchRequest) !SearchResult {
	query := request.query
	terms := normalized_search_terms(query)
	if terms.len == 0 {
		return SearchResult{}
	}
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	mut hits := []SearchHit{}
	mut seen := map[string]bool{}
	for term in terms {
		rows := session.lookup_index_prefix_projected(mut db, 'entries', 'entries_fts_any_idx', term,
			if request.limit > 0 { (request.offset + request.limit) * 4 } else { 100 }, [
				'id',
				'session_id',
				'session_title',
				'seq',
				'role',
				'kind',
				'timestamp',
				'content_text',
			])!
		for row in rows {
			entry_id := must_string(row, 'id')!
			if seen[entry_id] {
				continue
			}
			if request.session_id.len > 0 && entry_session_id(row)! != request.session_id {
				continue
			}
			seen[entry_id] = true
			entry := decode_session_entry(row)!
			hits << SearchHit{
				session_id: entry_session_id(row)!
				session_title: entry_session_title(row)!
				path: ''
				entry_seq: entry.seq
				kind: entry.kind
				role: entry.role
				timestamp: entry.timestamp
				snippet: compact_snippet(entry.text, query, 160)
			}
				if request.limit > 0 && hits.len >= request.offset + request.limit {
					return paginate_search_hits(hits, request)
				}
		}
	}
	if hits.len > 0 {
		return paginate_search_hits(hits, request)
	}
	rows := session.scan_table(mut db, 'entries', 0)!
	for row in rows {
		entry_id := must_string(row, 'id') or { continue }
		if seen[entry_id] {
			continue
		}
		if request.session_id.len > 0 && entry_session_id(row) or { '' } != request.session_id {
			continue
		}
		entry := decode_session_entry(row) or { continue }
		haystack := '${entry.title}\n${entry.tool_name}\n${entry.text}'.to_lower()
		mut matched := true
		for term in terms {
			if !haystack.contains(term) {
				matched = false
				break
			}
		}
		if !matched {
			continue
		}
		seen[entry_id] = true
		hits << SearchHit{
			session_id: entry_session_id(row)!
			session_title: entry_session_title(row)!
			path: ''
			entry_seq: entry.seq
			kind: entry.kind
			role: entry.role
			timestamp: entry.timestamp
			snippet: compact_snippet(haystack, query, 160)
		}
		if request.limit > 0 && hits.len >= request.offset + request.limit {
			break
		}
	}
	return paginate_search_hits(hits, request)
}

fn sessions_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('sessions', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('title', .string_, false)!,
		storage.ColumnDef.new('updated_at', .datetime_, false)!,
		storage.ColumnDef.new('started_at', .datetime_, true)!,
		storage.ColumnDef.new('cwd', .string_, true)!,
		storage.ColumnDef.new('source', .string_, true)!,
		storage.ColumnDef.new('originator', .string_, true)!,
		storage.ColumnDef.new('cli_version', .string_, true)!,
		storage.ColumnDef.new('path', .string_, false)!,
		storage.ColumnDef.new('archived', .bool_, false)!,
		storage.ColumnDef.new('entry_count', .i64_, false)!,
		storage.ColumnDef.new('user_turns', .i64_, false)!,
		storage.ColumnDef.new('tool_calls', .i64_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('updated_at_idx', 'updated_at')!,
		storage.SchemaIndexDef.new('path_idx', 'path')!,
	])!
}

fn entries_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('entries', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('session_title', .string_, false)!,
		storage.ColumnDef.new('seq', .i64_, false)!,
		storage.ColumnDef.new('timestamp', .datetime_, false)!,
		storage.ColumnDef.new('role', .string_, false)!,
		storage.ColumnDef.new('kind', .string_, false)!,
		storage.ColumnDef.new('tool_name', .string_, true)!,
		storage.ColumnDef.new('call_id', .string_, true)!,
		storage.ColumnDef.new('title', .string_, true)!,
		storage.ColumnDef.new('content_text', .string_, false)!,
		storage.ColumnDef.new('content_md', .markdown_, false)!,
		storage.ColumnDef.new('raw_type', .string_, true)!,
		storage.ColumnDef.new('phase', .string_, true)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('entries_session_idx', 'session_id')!,
		storage.SchemaIndexDef.new('entries_timestamp_idx', 'timestamp')!,
		storage.SchemaIndexDef.markdown_value('entries_fts_any_idx', 'content_md', 'fts')!,
		storage.SchemaIndexDef.markdown_value('entries_fts_heading_idx', 'content_md', 'fts:heading')!,
	])!
}

fn put_session_summary(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, summary SessionSummary) ! {
	row := build_session_row(summary)
	_ = session.put_row(mut db, 'sessions', summary.id.bytes(), row, storage.ChunkConfig.default(), sync_meta('sync session ${summary.id}'))!
}

fn put_session_entry(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, summary SessionSummary, entry SessionEntry) ! {
	entry_id := '${summary.id}:${entry.seq}'
	mut row := storage.TypedRowData.new()
	row.set('id', entry_id)
	row.set('session_id', summary.id)
	row.set('session_title', summary.title)
	row.set('seq', i64(entry.seq))
	row.set('timestamp', if entry.timestamp.len > 0 { entry.timestamp } else { summary.updated_at })
	row.set('role', entry.role)
	row.set('kind', entry.kind.str())
	if entry.tool_name.len > 0 {
		row.set('tool_name', entry.tool_name)
	} else {
		row.set_null('tool_name')
	}
	if entry.call_id.len > 0 {
		row.set('call_id', entry.call_id)
	} else {
		row.set_null('call_id')
	}
	if entry.title.len > 0 {
		row.set('title', entry.title)
	} else {
		row.set_null('title')
	}
	content_text := if entry.text.len > 0 { entry.text } else { entry.tool_name }
	row.set('content_text', content_text)
	row.set('content_md', ingest_markdown_for_store(mut db, content_text)!)
	if entry.raw_type.len > 0 {
		row.set('raw_type', entry.raw_type)
	} else {
		row.set_null('raw_type')
	}
	if entry.phase.len > 0 {
		row.set('phase', entry.phase)
	} else {
		row.set_null('phase')
	}
	_ = session.put_row(mut db, 'entries', entry_id.bytes(), row, storage.ChunkConfig.default(), sync_meta('sync entry ${entry_id}'))!
}

fn ingest_markdown_for_store(mut db storage.PersistentDatabase, text string) !storage.MarkdownRef {
	stored := storage.ingest_external_field_value(mut db, storage.ColumnDef.new('content_md', .markdown_, false)!, text)!
	return match stored {
		storage.MarkdownRef { stored }
		else { return error('expected markdown ref from external storage ingest') }
	}
}

fn sync_meta(message string) storage.CommitMeta {
	return storage.CommitMeta{
		author: 'agentview'
		message: message
		timestamp: 0
	}
}

fn store_branch_exists(mut db storage.PersistentDatabase) bool {
	return store_branch in db.branch_names()
}

fn seed_store_branch(mut db storage.PersistentDatabase, summary SessionSummary) ! {
	spec := sessions_spec()!
	cfg := storage.ChunkConfig.default()
	codec := storage.TypedRowCodec.new(spec.table)
	row := build_session_row(summary)
	table_view := storage.TableView.new(storage.Tree{}, 'sessions')
	mut tree := storage.Tree.build([
		storage.KVPair{
			key: table_view.row_key(summary.id.bytes())
			value: codec.encode(row)!
		},
	], cfg)!
	tree = storage.rebuild_typed_indexes_for_specs(tree, [spec, entries_spec()!], cfg)!
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [spec, entries_spec()!], cfg)!
	_ = db.commit_to_branch(store_branch, tree, storage.CommitMeta{
		author: 'agentview'
		message: 'seed agentview store'
		timestamp: 0
	})!
}

fn decode_session_summary(row storage.TypedSchemaRow) !SessionSummary {
	return SessionSummary{
		id: must_string(row, 'id')!
		title: must_string(row, 'title')!
		updated_at: must_string(row, 'updated_at')!
		started_at: opt_string(row, 'started_at')
		cwd: opt_string(row, 'cwd')
		source: opt_string(row, 'source')
		originator: opt_string(row, 'originator')
		cli_version: opt_string(row, 'cli_version')
		path: must_string(row, 'path')!
		archived: must_bool(row, 'archived')!
		entry_count: int(must_i64(row, 'entry_count')!)
		user_turns: int(must_i64(row, 'user_turns')!)
		tool_calls: int(must_i64(row, 'tool_calls')!)
	}
}

fn load_existing_sessions_by_id(mut db storage.PersistentDatabase) !map[string]SessionSummary {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'sessions', 0)!
	mut out := map[string]SessionSummary{}
	for row in rows {
		summary := decode_session_summary(row)!
		out[summary.id] = summary
	}
	return out
}

fn same_session_summary(left SessionSummary, right SessionSummary) bool {
	return left.id == right.id && left.title == right.title && left.updated_at == right.updated_at
		&& left.started_at == right.started_at && left.cwd == right.cwd && left.source == right.source
		&& left.originator == right.originator && left.cli_version == right.cli_version
		&& left.path == right.path && left.archived == right.archived
		&& left.entry_count == right.entry_count && left.user_turns == right.user_turns
		&& left.tool_calls == right.tool_calls
}

fn delete_entries_for_sessions(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, session_ids []string) ! {
	if session_ids.len == 0 {
		return
	}
	mut wanted := map[string]bool{}
	for id in session_ids {
		wanted[id] = true
	}
	reader := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := reader.scan_table(mut db, 'entries', 0)!
	for row in rows {
		session_id := entry_session_id(row) or { continue }
		if !wanted[session_id] {
			continue
		}
		_ = session.delete_row(mut db, 'entries', row.primary_key, storage.ChunkConfig.default(),
			sync_meta('delete stale entry ${row.primary_key.bytestr()}'))!
	}
}

fn build_session_row(summary SessionSummary) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', summary.id)
	row.set('title', summary.title)
	row.set('updated_at', summary.updated_at)
	if summary.started_at.len > 0 {
		row.set('started_at', summary.started_at)
	} else {
		row.set_null('started_at')
	}
	if summary.cwd.len > 0 {
		row.set('cwd', summary.cwd)
	} else {
		row.set_null('cwd')
	}
	if summary.source.len > 0 {
		row.set('source', summary.source)
	} else {
		row.set_null('source')
	}
	if summary.originator.len > 0 {
		row.set('originator', summary.originator)
	} else {
		row.set_null('originator')
	}
	if summary.cli_version.len > 0 {
		row.set('cli_version', summary.cli_version)
	} else {
		row.set_null('cli_version')
	}
	row.set('path', summary.path)
	row.set('archived', summary.archived)
	row.set('entry_count', i64(summary.entry_count))
	row.set('user_turns', i64(summary.user_turns))
	row.set('tool_calls', i64(summary.tool_calls))
	return row
}

fn decode_session_entry(row storage.TypedSchemaRow) !SessionEntry {
	return SessionEntry{
		seq: int(must_i64(row, 'seq')!)
		timestamp: must_string(row, 'timestamp')!
		kind: parse_entry_kind(must_string(row, 'kind')!)
		role: must_string(row, 'role')!
		title: opt_string(row, 'title')
		text: must_string(row, 'content_text')!
		markdown: ''
		tool_name: opt_string(row, 'tool_name')
		call_id: opt_string(row, 'call_id')
		raw_type: opt_string(row, 'raw_type')
		phase: opt_string(row, 'phase')
	}
}

fn decode_session_entry_with_markdown(mut db storage.PersistentDatabase, row storage.TypedSchemaRow) !SessionEntry {
	mut entry := decode_session_entry(row)!
	ref := opt_markdown_ref(row, 'content_md') or {
		return entry
	}
	entry.markdown = db.load_markdown(ref) or { entry.text }
	return entry
}

fn entry_session_id(row storage.TypedSchemaRow) !string {
	return must_string(row, 'session_id')
}

fn entry_session_title(row storage.TypedSchemaRow) !string {
	return must_string(row, 'session_title')
}

fn must_string(row storage.TypedSchemaRow, name string) !string {
	value := row.data.get(name)!
	return match value {
		string { value }
		else { return error('expected string column: ${name}') }
	}
}

fn opt_markdown_ref(row storage.TypedSchemaRow, name string) ?storage.MarkdownRef {
	value := row.data.get(name) or {
		return none
	}
	return match value {
		storage.MarkdownRef { value }
		else { none }
	}
}

fn opt_string(row storage.TypedSchemaRow, name string) string {
	if !row.data.has(name) {
		return ''
	}
	value := row.data.get(name) or { return '' }
	return match value {
		string { value }
		else { '' }
	}
}

fn must_i64(row storage.TypedSchemaRow, name string) !i64 {
	value := row.data.get(name)!
	return match value {
		i64 { value }
		else { return error('expected i64 column: ${name}') }
	}
}

fn must_bool(row storage.TypedSchemaRow, name string) !bool {
	value := row.data.get(name)!
	return match value {
		bool { value }
		else { return error('expected bool column: ${name}') }
	}
}

fn parse_entry_kind(value string) EntryKind {
	return match value {
		'message' { .message }
		'reasoning' { .reasoning }
		'tool_call' { .tool_call }
		'tool_result' { .tool_result }
		else { .meta }
	}
}

fn normalized_search_terms(query string) []string {
	mut terms := []string{}
	for raw in query.replace('\n', ' ').split(' ') {
		term := raw.trim_space().to_lower()
		if term.len > 0 {
			terms << term
		}
	}
	return terms
}

fn clamp_offset(offset int, total int) int {
	if offset <= 0 {
		return 0
	}
	if offset >= total {
		return total
	}
	return offset
}

fn clamp_limit(start int, limit int, total int) int {
	if limit <= 0 {
		return total
	}
	end := start + limit
	if end > total {
		return total
	}
	return end
}

fn paginate_search_hits(hits []SearchHit, request SearchRequest) SearchResult {
	total := hits.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	return SearchResult{
		total: total
		hits: hits[start..end]
	}
}
