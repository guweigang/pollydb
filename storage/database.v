module storage

import os
import strings
import time
import vmarkdown
import x.json2

struct DatabaseCatalogReader {
	data []u8
mut:
	cursor int
}

pub struct PersistentDatabase {
pub:
	root_dir       string
	default_branch string
mut:
	engine              PersistentEngine
	catalog             map[string]TypedTableSpec
	projectors          map[string]AggregateProjectionDef
	memory_capabilities map[string]MemoryCapabilityDef
	field_registry      FieldCapabilityRegistry
	catalog_dirty       bool
}

pub struct PersistentDatabaseOpenTimings {
pub:
	backends_ms i64
	catalog_ms  i64
	engine      PersistentEngineOpenTimings
	total_ms    i64
}

pub struct PersistentDatabaseOpenResult {
pub:
	database PersistentDatabase
	timings  PersistentDatabaseOpenTimings
}

pub struct PersistentDatabaseTypedTransactionOpenResult {
pub:
	tx      TypedTransaction
	timings TypedTransactionOpenTimings
}

pub struct PersistentDatabaseCheckpointInfo {
pub:
	root_dir              string
	catalog_path          string
	catalog_exists        bool
	registered_tables     int
	registered_projectors int
	engine                PersistentEngineCheckpointInfo
}

pub struct PersistentDatabaseCheckpointTimings {
pub:
	catalog_us i64
	engine     PersistentEngineCheckpointTimings
	total_us   i64
}

pub struct PersistentDatabaseRecoveryStatus {
pub:
	root_dir       string
	catalog_path   string
	catalog_exists bool
	engine         PersistentEngineRecoveryStatus
}

pub struct PersistentDatabaseStatusReport {
pub:
	root_dir                                        string
	default_branch                                  string
	catalog_path                                    string
	repository_exists                               bool
	catalog_exists                                  bool
	registered_tables                               int
	registered_projectors                           int
	fresh_projectors                                int
	stale_projectors                                int
	recommended_aggregate_projection_refresh_policy string
	branch_count                                    int
	branches                                        []string
	data_durable                                    bool
	index_snapshots_fresh                           bool
	checkpoint_journal_exists                       bool
	node_index_snapshot_pending                     bool
	commit_index_snapshot_pending                   bool
	node_index_snapshot_valid                       bool
	commit_index_snapshot_valid                     bool
	node_index_entries                              int
	commit_index_entries                            int
	projector_states                                []string
	durable                                         bool
}

pub struct IndexSnapshotRefreshResult {
pub:
	ok  bool
	err string
}

pub struct IndexSnapshotRefreshHandle {
mut:
	worker thread IndexSnapshotRefreshResult
}

pub fn (mut handle IndexSnapshotRefreshHandle) wait() ! {
	result := handle.worker.wait()
	if !result.ok {
		return error(result.err)
	}
}

pub struct AggregateProjectionRefreshResult {
pub:
	ok  bool
	err string
}

pub struct AggregateProjectionRefreshHandle {
mut:
	active bool
	worker thread AggregateProjectionRefreshResult
}

pub fn (mut handle AggregateProjectionRefreshHandle) wait() ! {
	if !handle.active {
		return
	}
	result := handle.worker.wait()
	if !result.ok {
		return error(result.err)
	}
}

pub struct SnapshotRowLookupResult {
pub:
	commit_cid string
	table_name string
	row        TypedSchemaRow
}

struct SnapshotRowLookupWorkerResult {
	ok  bool
	err string
	row SnapshotRowLookupResult
}

pub struct SnapshotRowLookupHandle {
mut:
	worker thread SnapshotRowLookupWorkerResult
}

pub fn (mut handle SnapshotRowLookupHandle) wait() !SnapshotRowLookupResult {
	result := handle.worker.wait()
	if !result.ok {
		return error(result.err)
	}
	return result.row
}

pub struct SnapshotIndexLookupResult {
pub:
	commit_cid string
	table_name string
	index_name string
	rows       []TypedSchemaRow
}

pub struct SnapshotIndexLookupPairResult {
pub:
	left  SnapshotIndexLookupResult
	right SnapshotIndexLookupResult
}

struct SnapshotIndexLookupWorkerResult {
	ok   bool
	err  string
	rows SnapshotIndexLookupResult
}

pub struct SnapshotIndexLookupHandle {
mut:
	worker thread SnapshotIndexLookupWorkerResult
}

pub fn (mut handle SnapshotIndexLookupHandle) wait() !SnapshotIndexLookupResult {
	result := handle.worker.wait()
	if !result.ok {
		return error(result.err)
	}
	return result.rows
}

struct SnapshotIndexLookupPairWorkerResult {
	ok   bool
	err  string
	rows SnapshotIndexLookupPairResult
}

pub struct SnapshotIndexLookupPairHandle {
mut:
	worker thread SnapshotIndexLookupPairWorkerResult
}

pub fn (mut handle SnapshotIndexLookupPairHandle) wait() !SnapshotIndexLookupPairResult {
	result := handle.worker.wait()
	if !result.ok {
		return error(result.err)
	}
	return result.rows
}

pub fn (report PersistentDatabaseStatusReport) summary_lines() []string {
	mut lines := []string{cap: 10}
	lines << 'root_dir=${report.root_dir}'
	lines << 'default_branch=${report.default_branch}'
	lines << 'repository_exists=${report.repository_exists}'
	lines << 'catalog_exists=${report.catalog_exists}'
	lines << 'registered_tables=${report.registered_tables}'
	lines << 'registered_projectors=${report.registered_projectors}'
	lines << 'fresh_projectors=${report.fresh_projectors}'
	lines << 'stale_projectors=${report.stale_projectors}'
	lines << 'recommended_aggregate_projection_refresh_policy=${report.recommended_aggregate_projection_refresh_policy}'
	lines << 'branches=${report.branch_count} [${report.branches.join(', ')}]'
	lines << 'data_durable=${report.data_durable}'
	lines << 'index_snapshots_fresh=${report.index_snapshots_fresh}'
	lines << 'checkpoint_journal_exists=${report.checkpoint_journal_exists}'
	lines << 'node_index_snapshot_pending=${report.node_index_snapshot_pending}'
	lines << 'commit_index_snapshot_pending=${report.commit_index_snapshot_pending}'
	lines << 'node_index_snapshot_valid=${report.node_index_snapshot_valid} entries=${report.node_index_entries}'
	lines << 'commit_index_snapshot_valid=${report.commit_index_snapshot_valid} entries=${report.commit_index_entries}'
	for projector_state in report.projector_states {
		lines << projector_state
	}
	lines << 'durable=${report.durable}'
	return lines
}

pub fn (report PersistentDatabaseStatusReport) format() string {
	mut builder := strings.new_builder(256)
	for idx, line in report.summary_lines() {
		if idx > 0 {
			builder.write_string('\n')
		}
		builder.write_string(line)
	}
	return builder.str()
}

pub struct DatabaseSession {
pub:
	root_dir    string
	branch_name string
	specs       []TypedTableSpec
}

pub struct SessionOptions {
pub:
	branch_name string
}

pub struct TypedTableCursor {
pub:
	view TypedIndexedSchemaView
mut:
	cursor TableCursor
}

pub struct TypedIndexCursor {
pub:
	view       TypedIndexedSchemaView
	index_name string
mut:
	cursor           IndexCursor
	markdown_entries []TransactionMarkdownIndexEntry
	markdown_pos     int
}

pub struct TypedIndexRow {
pub:
	index_key   []u8
	primary_key []u8
	row         TypedSchemaRow
}

enum TypedIndexScanMode {
	all
	exact
	prefix
	after
	before
	between
}

struct TypedIndexScanRequest {
	mode              TypedIndexScanMode
	value             ColumnValue
	has_value         bool
	second_value      ColumnValue = NullValue{}
	has_second_value  bool
	start_primary_key []u8
	limit             int
	columns           []string
	reverse           bool
}

pub struct BranchTableReader {
pub:
	branch_name string
	spec        TypedTableSpec
	root_cid    string
mut:
	codec      TypedRowCodec
	row_prefix []u8
	node_store PersistentNodeStore
}

pub struct BranchIndexReader {
pub:
	branch_name string
	spec        TypedTableSpec
	index       SchemaIndexDef
	root_cid    string
mut:
	codec        TypedRowCodec
	row_prefix   []u8
	index_prefix []u8
	index_column ColumnDef
	node_store   PersistentNodeStore
}

pub struct SnapshotTableReader {
pub:
	commit_cid string
	root_cid   string
	spec       TypedTableSpec
mut:
	codec      TypedRowCodec
	row_prefix []u8
	node_store PersistentNodeStore
}

pub struct SnapshotIndexReader {
pub:
	commit_cid string
	root_cid   string
	spec       TypedTableSpec
	index      SchemaIndexDef
mut:
	codec        TypedRowCodec
	row_prefix   []u8
	index_prefix []u8
	index_column ColumnDef
	node_store   PersistentNodeStore
}

pub struct SnapshotTablePairReader {
pub:
	left_commit_cid  string
	right_commit_cid string
mut:
	left  SnapshotTableReader
	right SnapshotTableReader
}

pub struct SnapshotIndexPairReader {
pub:
	left_commit_cid  string
	right_commit_cid string
mut:
	left  SnapshotIndexReader
	right SnapshotIndexReader
}

pub struct SnapshotReadScheduler {
pub:
	root_dir       string
	default_branch string
}

pub fn SnapshotReadScheduler.new(provider LocalDatabaseBackendProvider) SnapshotReadScheduler {
	return SnapshotReadScheduler{
		root_dir:       provider.root_dir
		default_branch: provider.default_branch()
	}
}

pub fn (scheduler SnapshotReadScheduler) backend_provider() LocalDatabaseBackendProvider {
	return LocalDatabaseBackendProvider.new(scheduler.root_dir, scheduler.default_branch)
}

pub struct RootHashMergePreview {
pub:
	ours_branch       string
	theirs_branch     string
	base_commit_cid   string
	base_root_cid     string
	ours_commit_cid   string
	ours_root_cid     string
	theirs_commit_cid string
	theirs_root_cid   string
	conflicts         int
	changed_keys      int
	changed_subtrees  int
	fast_forward      bool
	ours_unchanged    bool
	theirs_unchanged  bool
}

pub struct MergeTableStat {
pub:
	table_name       string
	row_changes      int
	index_changes    int
	conflict_changes int
}

pub struct MergeConflictPreview {
pub:
	key        string
	table_name string
	index_name string
	base_row   string
	ours_row   string
	theirs_row string
}

pub struct RootHashMergeReport {
pub:
	preview        RootHashMergePreview
	table_stats    []MergeTableStat
	conflict_keys  []MergeConflictPreview
	conflict_limit int
}

pub struct TransactionSession {
pub:
	root_dir    string
	branch_name string
	specs       []TypedTableSpec
mut:
	working_set TypedWorkingSet
}

pub struct GroupCommitOptions {
pub:
	checkpoint_every                    int            = 8
	checkpoint_mode                     CheckpointMode = .full
	auto_refresh_index_snapshots        bool
	aggregate_projection_refresh_policy AggregateProjectionRefreshPolicy = .none
	max_aggregate_projection_refreshes  int
}

pub enum AggregateProjectionRefreshPolicy {
	none
	stale_one
	stale_up_to
	stale_all
}

pub fn GroupCommitOptions.high_throughput() GroupCommitOptions {
	return GroupCommitOptions{
		checkpoint_every:                    8
		checkpoint_mode:                     .data_only
		auto_refresh_index_snapshots:        true
		aggregate_projection_refresh_policy: .stale_one
		max_aggregate_projection_refreshes:  0
	}
}

pub fn GroupCommitOptions.durable_default() GroupCommitOptions {
	return GroupCommitOptions{
		checkpoint_every:                    8
		checkpoint_mode:                     .full
		auto_refresh_index_snapshots:        false
		aggregate_projection_refresh_policy: .none
		max_aggregate_projection_refreshes:  0
	}
}

pub fn (options GroupCommitOptions) with_checkpoint_every(value int) GroupCommitOptions {
	return GroupCommitOptions{
		checkpoint_every:                    if value > 0 { value } else { 1 }
		checkpoint_mode:                     options.checkpoint_mode
		auto_refresh_index_snapshots:        options.auto_refresh_index_snapshots
		aggregate_projection_refresh_policy: options.aggregate_projection_refresh_policy
		max_aggregate_projection_refreshes:  options.max_aggregate_projection_refreshes
	}
}

pub fn (options GroupCommitOptions) with_max_aggregate_projection_refreshes(value int) GroupCommitOptions {
	return GroupCommitOptions{
		checkpoint_every:                    options.checkpoint_every
		checkpoint_mode:                     options.checkpoint_mode
		auto_refresh_index_snapshots:        options.auto_refresh_index_snapshots
		aggregate_projection_refresh_policy: if value > 0 {
			.stale_up_to
		} else {
			options.aggregate_projection_refresh_policy
		}
		max_aggregate_projection_refreshes:  if value > 0 { value } else { 0 }
	}
}

pub fn (options GroupCommitOptions) with_aggregate_projection_refresh_policy(policy AggregateProjectionRefreshPolicy) GroupCommitOptions {
	return GroupCommitOptions{
		checkpoint_every:                    options.checkpoint_every
		checkpoint_mode:                     options.checkpoint_mode
		auto_refresh_index_snapshots:        options.auto_refresh_index_snapshots
		aggregate_projection_refresh_policy: policy
		max_aggregate_projection_refreshes:  options.max_aggregate_projection_refreshes
	}
}

pub struct GroupCommitSession {
pub:
	branch_name string
	specs       []TypedTableSpec
	options     GroupCommitOptions
mut:
	pending_writes            int
	working_set               TypedWorkingSet
	last_meta                 CommitMeta
	has_pending_meta          bool
	refresh_handles           []IndexSnapshotRefreshHandle
	aggregate_refresh_handles []AggregateProjectionRefreshHandle
}

pub struct SplitGroupCommitSession {
pub:
	branch_name string
	specs       []TypedTableSpec
	options     GroupCommitOptions
mut:
	pending_writes            int
	working_set               TypedSplitWorkingSet
	last_meta                 CommitMeta
	last_cfg                  ChunkConfig
	has_pending_meta          bool
	refresh_handles           []IndexSnapshotRefreshHandle
	aggregate_refresh_handles []AggregateProjectionRefreshHandle
}

fn database_catalog_path(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'catalog.meta')
}

fn database_table_row_prefix(table_name string) []u8 {
	return 't|${table_name}|'.bytes()
}

fn database_table_row_key(table_name string, primary_key []u8) []u8 {
	mut out := database_table_row_prefix(table_name)
	out << primary_key
	return out
}

fn database_row_key_with_prefix(prefix []u8, primary_key []u8) []u8 {
	mut out := prefix.clone()
	out << primary_key
	return out
}

fn database_index_entry_prefix(table_name string, index_name string) []u8 {
	return 'i|${table_name}|${index_name}|'.bytes()
}

fn bytes_has_prefix(data []u8, prefix []u8) bool {
	if prefix.len > data.len {
		return false
	}
	return data[..prefix.len] == prefix
}

fn merge_key_scope(key string) (string, string, string) {
	parts := key.split('|')
	if parts.len >= 3 && parts[0] == 't' {
		return 'row', parts[1], ''
	}
	if parts.len >= 4 && parts[0] == 'i' {
		return 'index', parts[1], parts[2]
	}
	return 'raw', '', ''
}

fn build_merge_table_stats(changed_keys []string, conflicts []MergeConflict) []MergeTableStat {
	mut stats := map[string]MergeTableStat{}
	for key in changed_keys {
		scope, table_name, _ := merge_key_scope(key)
		if table_name.len == 0 {
			continue
		}
		stat := stats[table_name] or {
			MergeTableStat{
				table_name: table_name
			}
		}
		mut row_changes := stat.row_changes
		mut index_changes := stat.index_changes
		if scope == 'row' {
			row_changes++
		} else if scope == 'index' {
			index_changes++
		}
		stats[table_name] = MergeTableStat{
			table_name:       table_name
			row_changes:      row_changes
			index_changes:    index_changes
			conflict_changes: stat.conflict_changes
		}
	}
	for conflict in conflicts {
		scope, table_name, _ := merge_key_scope(conflict.key.bytestr())
		if scope == 'raw' || table_name.len == 0 {
			continue
		}
		stat := stats[table_name] or {
			MergeTableStat{
				table_name: table_name
			}
		}
		stats[table_name] = MergeTableStat{
			table_name:       table_name
			row_changes:      stat.row_changes
			index_changes:    stat.index_changes
			conflict_changes: stat.conflict_changes + 1
		}
	}
	mut names := stats.keys()
	names.sort()
	mut out := []MergeTableStat{cap: names.len}
	for name in names {
		out << (stats[name] or { continue })
	}
	return out
}

fn build_merge_conflict_preview(conflicts []MergeConflict, limit int) []MergeConflictPreview {
	effective_limit := if limit > 0 { limit } else { conflicts.len }
	mut out := []MergeConflictPreview{cap: if conflicts.len < effective_limit {
		conflicts.len
	} else {
		effective_limit
	}}
	for idx, conflict in conflicts {
		if idx >= effective_limit {
			break
		}
		_, table_name, index_name := merge_key_scope(conflict.key.bytestr())
		out << MergeConflictPreview{
			key:        conflict.key.bytestr()
			table_name: table_name
			index_name: index_name
		}
	}
	return out
}

fn markdown_conflict_value_summary(database &PersistentDatabase, column ColumnDef, base ColumnValue, current ColumnValue) string {
	return external_field_diff_summary(database, column, base, current, 3) or {
		return ' diff=<unavailable>'
	}
}

fn format_merge_conflict_row(database &PersistentDatabase, codec TypedRowCodec, primary_key []u8, payload []u8, base_payload []u8) string {
	if payload.len == 0 {
		return '<deleted>'
	}
	row := codec.decode(payload) or { return '<decode-error>' }
	base_row := if base_payload.len > 0 {
		codec.decode(base_payload) or { TypedRowData.new() }
	} else {
		TypedRowData.new()
	}
	mut parts := []string{cap: codec.table.columns.len + 1}
	parts << 'pk=${primary_key.bytestr()}'
	for column in codec.table.columns {
		if !row.has(column.name) {
			parts << '${column.name}=<unset>'
			continue
		}
		value := row.get(column.name) or {
			parts << '${column.name}=<error>'
			continue
		}
		rendered := match value {
			MarkdownRef {
				base_value := if base_row.has(column.name) {
					base_row.get(column.name) or { ColumnValue(NullValue{}) }
				} else {
					ColumnValue(NullValue{})
				}
				'markdown:${value.doc_root_id}' +
					markdown_conflict_value_summary(database, column, base_value, value)
			}
			NullValue {
				'null'
			}
			bool {
				if value {
					'true'
				} else {
					'false'
				}
			}
			i64 {
				value.str()
			}
			string {
				value
			}
			[]u8 {
				'hex:${value.hex()}'
			}
		}
		parts << '${column.name}=${rendered}'
	}
	return parts.join(', ')
}

fn enrich_merge_conflict_preview(database &PersistentDatabase, conflicts []MergeConflictPreview, raw []MergeConflict, specs map[string]TypedTableSpec) []MergeConflictPreview {
	if conflicts.len == 0 {
		return conflicts
	}
	mut raw_map := map[string]MergeConflict{}
	for conflict in raw {
		raw_map[conflict.key.bytestr()] = conflict
	}
	mut out := []MergeConflictPreview{cap: conflicts.len}
	for preview in conflicts {
		if preview.table_name.len == 0 || preview.index_name.len > 0 || preview.table_name !in specs {
			out << preview
			continue
		}
		raw_conflict := raw_map[preview.key] or {
			out << preview
			continue
		}
		spec := specs[preview.table_name] or {
			out << preview
			continue
		}
		codec := TypedRowCodec.new(spec.table)
		prefix := database_table_row_prefix(spec.table.name)
		if !bytes_has_prefix(raw_conflict.key, prefix) {
			out << preview
			continue
		}
		primary_key := raw_conflict.key[prefix.len..].clone()
		out << MergeConflictPreview{
			key:        preview.key
			table_name: preview.table_name
			index_name: preview.index_name
			base_row:   format_merge_conflict_row(database, codec, primary_key, raw_conflict.base,
				raw_conflict.base)
			ours_row:   format_merge_conflict_row(database, codec, primary_key, raw_conflict.ours,
				raw_conflict.base)
			theirs_row: format_merge_conflict_row(database, codec, primary_key, raw_conflict.theirs,
				raw_conflict.base)
		}
	}
	return out
}

fn row_spec_for_merge_key(key []u8, specs []TypedTableSpec) ?TypedTableSpec {
	key_str := key.bytestr()
	for spec in specs {
		prefix := TableView.new(Tree{}, spec.table.name).row_prefix().bytestr()
		if key_str.starts_with(prefix) {
			return spec
		}
	}
	return none
}

fn persistent_typed_index_values_from_row(root_dir string, row TypedRowData, index SchemaIndexDef, table TableDef) ![]ColumnValue {
	if index.is_fts() || index.is_embedding() {
		return []ColumnValue{}
	}
	if !index.is_field_selector() {
		return [typed_index_value_from_row(row, index, table)!]
	}
	base_column := table.column(index.column)!
	if !row.has(index.column) {
		return []ColumnValue{}
	}
	base_value := row.get(index.column)!
	return expand_field_selector_index_values(root_dir, base_column, base_value, index)
}

fn rebuild_persistent_typed_indexes_for_changed_rows(root_dir string, tree Tree, specs []TypedTableSpec, changed_rows map[string]map[string][]u8, cfg ChunkConfig) !(Tree, ReindexStageTimings) {
	if changed_rows.len == 0 {
		return tree, ReindexStageTimings{}
	}
	mut items_sw := time.new_stopwatch()
	items := tree.items()!
	items_ms := items_sw.elapsed().milliseconds()
	mut item_map := map[string][]u8{}
	for item in items {
		item_map[item.key.bytestr()] = item.value.clone()
	}
	mut removed_indexes := 0
	mut changed_tables := 0
	mut changed_row_count := 0
	mut mutations := []Mutation{}
	mut remove_sw := time.new_stopwatch()
	for spec in specs {
		changed := (changed_rows[spec.table.name] or {
			map[string][]u8{}
		}).clone()
		if changed.len == 0 {
			continue
		}
		changed_tables++
		changed_row_count += changed.len
		for index in spec.indexes {
			index_view := IndexView.new(Tree{}, spec.table.name, index.name)
			prefix := index_view.entry_prefix()
			for key, _ in item_map {
				key_bytes := key.bytes()
				if !has_prefix_bytes(key_bytes, prefix) {
					continue
				}
				entry := decode_index_entry(index_view, KVPair{
					key:   key_bytes
					value: item_map[key]
				}) or { continue }
				if entry.primary_key.hex() in changed {
					item_map.delete(key)
					mutations << Mutation.delete(key_bytes)
					removed_indexes++
				}
			}
		}
	}
	remove_ms := remove_sw.elapsed().milliseconds()
	mut inserted_indexes := 0
	mut insert_sw := time.new_stopwatch()
	for spec in specs {
		changed := (changed_rows[spec.table.name] or {
			map[string][]u8{}
		}).clone()
		if changed.len == 0 {
			continue
		}
		codec := TypedRowCodec.new(spec.table)
		table_view := TableView.new(Tree{}, spec.table.name)
		for _, primary_key in changed {
			row_key := table_view.key_for(primary_key).bytestr()
			if row_key !in item_map {
				continue
			}
			row := codec.decode(item_map[row_key])!
			for index in spec.indexes {
				if !row.has(index.column) {
					continue
				}
				column := index.value_column(spec.table)!
				index_values := persistent_typed_index_values_from_row(root_dir, row,
					index, spec.table)!
				index_view := IndexView.new(Tree{}, spec.table.name, index.name)
				index_value := if index.stores_row { codec.encode(row)! } else { []u8{} }
				for index_value_entry in index_values {
					index_key := TypedValueEncoder.encode_index_value(index_value_entry,
						column)!
					index_entry_key := index_view.key_for(index_key, primary_key)
					item_map[index_entry_key.bytestr()] = index_value.clone()
					mutations << Mutation.put(index_entry_key, index_value.clone())
					inserted_indexes++
				}
			}
		}
	}
	insert_ms := insert_sw.elapsed().milliseconds()
	mut rebuild_sw := time.new_stopwatch()
	use_patch_strategy := should_patch_reindex(items.len, changed_row_count, mutations.len)
	rebuilt_tree := if use_patch_strategy {
		tree.apply_mutations(mutations, cfg)!.tree
	} else {
		mut keys := item_map.keys()
		keys.sort()
		mut rebuilt := []KVPair{cap: keys.len}
		for key in keys {
			rebuilt << KVPair{
				key:   key.bytes()
				value: item_map[key].clone()
			}
		}
		Tree.build(rebuilt, cfg)!
	}
	rebuild_ms := rebuild_sw.elapsed().milliseconds()
	return rebuilt_tree, ReindexStageTimings{
		items_ms:         items_ms
		remove_ms:        remove_ms
		insert_ms:        insert_ms
		rebuild_ms:       rebuild_ms
		strategy:         if use_patch_strategy { 'patch' } else { 'build' }
		item_count:       items.len
		changed_tables:   changed_tables
		changed_rows:     changed_row_count
		removed_indexes:  removed_indexes
		inserted_indexes: inserted_indexes
	}
}

fn typed_write_set_requires_scan_reindex(specs []TypedTableSpec, write_set TypedWriteSet) bool {
	mut spec_by_name := map[string]TypedTableSpec{}
	for spec in specs {
		spec_by_name[spec.table.name] = spec
	}
	for op in write_set.operations() {
		spec := spec_by_name[op.table_name] or { continue }
		for index in spec.indexes {
			if index.is_field_selector() && !index.is_fts() && !index.is_embedding() {
				return true
			}
		}
	}
	return false
}

fn persistent_typed_index_mutations_for_write_set(root_dir string, base_tree Tree, next_tree Tree, specs []TypedTableSpec, write_set TypedWriteSet) ![]Mutation {
	mut spec_by_name := map[string]TypedTableSpec{}
	for spec in specs {
		spec_by_name[spec.table.name] = spec
	}
	mut mutations := []Mutation{}
	for op in write_set.operations() {
		spec := spec_by_name[op.table_name] or { continue }
		codec := TypedRowCodec.new(spec.table)
		base_table := TableView.new(base_tree, spec.table.name)
		if old_raw := base_table.get(op.primary_key) {
			old_row := codec.decode(old_raw.value)!
			mutations << persistent_typed_index_delete_mutations_for_row(root_dir, spec,
				op.primary_key, old_row)!
		}
		if op.delete {
			continue
		}
		next_table := TableView.new(next_tree, spec.table.name)
		new_raw := next_table.get(op.primary_key) or { continue }
		new_row := codec.decode(new_raw.value)!
		mutations << persistent_typed_index_put_mutations_for_row(root_dir, spec, op.primary_key,
			new_row)!
	}
	return mutations
}

fn persistent_typed_index_delete_mutations_for_row(root_dir string, spec TypedTableSpec, primary_key []u8, row TypedRowData) ![]Mutation {
	mut mutations := []Mutation{}
	for index in spec.indexes {
		if !row.has(index.column) {
			continue
		}
		index_values := persistent_typed_index_values_from_row(root_dir, row, index, spec.table)!
		if index_values.len == 0 {
			continue
		}
		column := index.value_column(spec.table)!
		index_view := IndexView.new(Tree{}, spec.table.name, index.name)
		for value in index_values {
			index_key := TypedValueEncoder.encode_index_value(value, column)!
			mutations << Mutation.delete(index_view.key_for(index_key, primary_key))
		}
	}
	return mutations
}

fn persistent_typed_index_put_mutations_for_row(root_dir string, spec TypedTableSpec, primary_key []u8, row TypedRowData) ![]Mutation {
	codec := TypedRowCodec.new(spec.table)
	encoded_row := codec.encode(row)!
	mut mutations := []Mutation{}
	for index in spec.indexes {
		if !row.has(index.column) {
			continue
		}
		index_values := persistent_typed_index_values_from_row(root_dir, row, index, spec.table)!
		if index_values.len == 0 {
			continue
		}
		column := index.value_column(spec.table)!
		index_view := IndexView.new(Tree{}, spec.table.name, index.name)
		index_value := if index.stores_row { encoded_row.clone() } else { []u8{} }
		for value in index_values {
			index_key := TypedValueEncoder.encode_index_value(value, column)!
			mutations << Mutation.put(index_view.key_for(index_key, primary_key), index_value.clone())
		}
	}
	return mutations
}

struct TransactionMarkdownIndexEntry {
	encoded []u8
	row     TypedSchemaRow
}

fn compare_index_entry_order(left &TransactionMarkdownIndexEntry, right &TransactionMarkdownIndexEntry) int {
	key_cmp := compare_key_bytes(left.encoded, right.encoded)
	if key_cmp != 0 {
		return key_cmp
	}
	return compare_key_bytes(left.row.primary_key, right.row.primary_key)
}

fn transaction_markdown_index_entries(root_dir string, view TypedIndexedSchemaView, index SchemaIndexDef) ![]TransactionMarkdownIndexEntry {
	rows := view.schema.table.collect(0)!
	column := index.value_column(view.schema.codec.table)!
	mut entries := []TransactionMarkdownIndexEntry{cap: rows.len}
	for raw_row in rows {
		row := TypedSchemaRow{
			primary_key: raw_row.primary_key
			data:        view.schema.codec.decode(raw_row.value)!
		}
		if !row.data.has(index.column) {
			continue
		}
		index_values := persistent_typed_index_values_from_row(root_dir, row.data, index,
			view.schema.codec.table)!
		for index_value in index_values {
			entries << TransactionMarkdownIndexEntry{
				encoded: TypedValueEncoder.encode_index_value(index_value, column)!
				row:     row
			}
		}
	}
	entries.sort_with_compare(compare_index_entry_order)
	return entries
}

fn transaction_markdown_index_lookup(root_dir string, view TypedIndexedSchemaView, index SchemaIndexDef, target ColumnValue, limit int) ![]TypedSchemaRow {
	column := index.value_column(view.schema.codec.table)!
	target_encoded := TypedValueEncoder.encode_index_value(target, column)!
	entries := transaction_markdown_index_entries(root_dir, view, index)!
	mut rows := []TypedSchemaRow{}
	for entry in entries {
		if compare_key_bytes(entry.encoded, target_encoded) != 0 {
			continue
		}
		rows << entry.row
		if limit > 0 && rows.len >= limit {
			break
		}
	}
	return rows
}

fn transaction_markdown_index_lookup_prefix(root_dir string, view TypedIndexedSchemaView, index SchemaIndexDef, target ColumnValue, limit int) ![]TypedSchemaRow {
	column := index.value_column(view.schema.codec.table)!
	target_encoded := TypedValueEncoder.encode_index_prefix(target, column)!
	entries := transaction_markdown_index_entries(root_dir, view, index)!
	mut rows := []TypedSchemaRow{}
	for entry in entries {
		if !has_prefix_bytes(entry.encoded, target_encoded) {
			if compare_key_bytes(entry.encoded, target_encoded) > 0 {
				break
			}
			continue
		}
		rows << entry.row
		if limit > 0 && rows.len >= limit {
			break
		}
	}
	return rows
}

fn transaction_markdown_index_lookup_between(root_dir string, view TypedIndexedSchemaView, index SchemaIndexDef, start_value ColumnValue, end_value ColumnValue, limit int) ![]TypedSchemaRow {
	column := index.value_column(view.schema.codec.table)!
	start_encoded := TypedValueEncoder.encode_index_value(start_value, column)!
	end_encoded := TypedValueEncoder.encode_index_value(end_value, column)!
	entries := transaction_markdown_index_entries(root_dir, view, index)!
	mut rows := []TypedSchemaRow{}
	for entry in entries {
		if compare_key_bytes(entry.encoded, start_encoded) < 0 {
			continue
		}
		if compare_key_bytes(entry.encoded, end_encoded) > 0 {
			break
		}
		rows << entry.row
		if limit > 0 && rows.len >= limit {
			break
		}
	}
	return rows
}

fn transaction_markdown_index_lookup_after(root_dir string, view TypedIndexedSchemaView, index SchemaIndexDef, value ColumnValue, limit int) ![]TypedSchemaRow {
	column := index.value_column(view.schema.codec.table)!
	target_encoded := TypedValueEncoder.encode_index_value(value, column)!
	entries := transaction_markdown_index_entries(root_dir, view, index)!
	mut rows := []TypedSchemaRow{}
	for entry in entries {
		if compare_key_bytes(entry.encoded, target_encoded) <= 0 {
			continue
		}
		rows << entry.row
		if limit > 0 && rows.len >= limit {
			break
		}
	}
	return rows
}

fn transaction_markdown_index_lookup_before(root_dir string, view TypedIndexedSchemaView, index SchemaIndexDef, value ColumnValue, limit int) ![]TypedSchemaRow {
	column := index.value_column(view.schema.codec.table)!
	target_encoded := TypedValueEncoder.encode_index_value(value, column)!
	entries := transaction_markdown_index_entries(root_dir, view, index)!
	mut rows := []TypedSchemaRow{}
	for entry in entries {
		if compare_key_bytes(entry.encoded, target_encoded) >= 0 {
			break
		}
		rows << entry.row
		if limit > 0 && rows.len >= limit {
			break
		}
	}
	return rows
}

fn transaction_markdown_index_cursor_entries(root_dir string, view TypedIndexedSchemaView, index SchemaIndexDef, value ColumnValue, start_primary_key []u8, limit int) ![]TransactionMarkdownIndexEntry {
	column := index.value_column(view.schema.codec.table)!
	target_encoded := TypedValueEncoder.encode_index_value(value, column)!
	entries := transaction_markdown_index_entries(root_dir, view, index)!
	mut filtered := []TransactionMarkdownIndexEntry{}
	for entry in entries {
		key_cmp := compare_key_bytes(entry.encoded, target_encoded)
		if key_cmp < 0 {
			continue
		}
		if key_cmp == 0 && start_primary_key.len > 0
			&& compare_key_bytes(entry.row.primary_key, start_primary_key) < 0 {
			continue
		}
		filtered << entry
		if limit > 0 && filtered.len >= limit {
			break
		}
	}
	return filtered
}

fn try_auto_merge_typed_row_conflict(mut database PersistentDatabase, conflict MergeConflict, specs []TypedTableSpec) ?ConflictResolution {
	if conflict.base.len == 0 || conflict.ours.len == 0 || conflict.theirs.len == 0 {
		return none
	}
	spec := row_spec_for_merge_key(conflict.key, specs)?
	codec := TypedRowCodec.new(spec.table)
	base_row := codec.decode(conflict.base) or { return none }
	ours_row := codec.decode(conflict.ours) or { return none }
	theirs_row := codec.decode(conflict.theirs) or { return none }
	mut merged := TypedRowData.new()
	mut changed := false
	for column in spec.table.columns {
		base_value := base_row.get(column.name) or { return none }
		ours_value := ours_row.get(column.name) or { return none }
		theirs_value := theirs_row.get(column.name) or { return none }
		ours_same_as_base := column_values_equal(base_value, ours_value)
		theirs_same_as_base := column_values_equal(base_value, theirs_value)
		if ours_same_as_base && theirs_same_as_base {
			merged.set(column.name, base_value)
			continue
		}
		if ours_same_as_base {
			merged.set(column.name, theirs_value)
			changed = true
			continue
		}
		if theirs_same_as_base {
			merged.set(column.name, ours_value)
			changed = true
			continue
		}
		if merged_value := try_merge_field_values(mut database, column, base_value, ours_value,
			theirs_value)
		{
			merged.set(column.name, merged_value)
			changed = true
			continue
		}
		if column_values_equal(ours_value, theirs_value) {
			merged.set(column.name, ours_value)
			changed = true
			continue
		}
		return none
	}
	if !changed {
		return none
	}
	return ConflictResolution{
		key:      conflict.key.clone()
		strategy: .manual
		value:    codec.encode(merged) or { return none }
	}
}

fn auto_resolve_typed_row_conflicts(mut database PersistentDatabase, conflicts []MergeConflict, specs []TypedTableSpec) []ConflictResolution {
	mut out := []ConflictResolution{}
	for conflict in conflicts {
		resolution := try_auto_merge_typed_row_conflict(mut database, conflict, specs) or {
			continue
		}
		out << resolution
	}
	return out
}

fn snapshot_row_lookup_worker(provider LocalDatabaseBackendProvider, commit_cid string, table_name string, primary_key []u8) SnapshotRowLookupWorkerResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return SnapshotRowLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	mut reader := database.snapshot_table_reader_for_commit(commit_cid, table_name) or {
		return SnapshotRowLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	row := reader.get_row(primary_key) or {
		return SnapshotRowLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	return SnapshotRowLookupWorkerResult{
		ok:  true
		row: SnapshotRowLookupResult{
			commit_cid: commit_cid
			table_name: table_name
			row:        row
		}
	}
}

fn snapshot_index_lookup_worker(provider LocalDatabaseBackendProvider, commit_cid string, table_name string, index_name string, value ColumnValue, limit int) SnapshotIndexLookupWorkerResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	mut reader := database.snapshot_index_reader_for_commit(commit_cid, table_name, index_name) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	mut rows := []TypedSchemaRow{}
	if reader.index.stores_row {
		rows = reader.find_rows_covering(value, limit) or {
			return SnapshotIndexLookupWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	} else {
		rows = reader.find_rows(value, limit) or {
			return SnapshotIndexLookupWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	}
	return SnapshotIndexLookupWorkerResult{
		ok:   true
		rows: SnapshotIndexLookupResult{
			commit_cid: commit_cid
			table_name: table_name
			index_name: index_name
			rows:       rows
		}
	}
}

fn snapshot_table_scan_worker(provider LocalDatabaseBackendProvider, commit_cid string, table_name string, limit int) SnapshotIndexLookupWorkerResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	mut reader := database.snapshot_table_reader_for_commit(commit_cid, table_name) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	rows := reader.scan_rows(limit) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	return SnapshotIndexLookupWorkerResult{
		ok:   true
		rows: SnapshotIndexLookupResult{
			commit_cid: commit_cid
			table_name: table_name
			index_name: ''
			rows:       rows
		}
	}
}

fn snapshot_table_scan_from_worker(provider LocalDatabaseBackendProvider, commit_cid string, table_name string, start_primary_key []u8, limit int) SnapshotIndexLookupWorkerResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	mut reader := database.snapshot_table_reader_for_commit(commit_cid, table_name) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	rows := reader.scan_rows_from(start_primary_key, limit) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	return SnapshotIndexLookupWorkerResult{
		ok:   true
		rows: SnapshotIndexLookupResult{
			commit_cid: commit_cid
			table_name: table_name
			index_name: ''
			rows:       rows
		}
	}
}

fn snapshot_index_prefix_lookup_worker(provider LocalDatabaseBackendProvider, commit_cid string, table_name string, index_name string, value ColumnValue, limit int) SnapshotIndexLookupWorkerResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	mut reader := database.snapshot_index_reader_for_commit(commit_cid, table_name, index_name) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	mut rows := []TypedSchemaRow{}
	if reader.index.stores_row {
		rows = reader.find_rows_covering_prefix(value, limit) or {
			return SnapshotIndexLookupWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	} else {
		rows = reader.find_rows_prefix(value, limit) or {
			return SnapshotIndexLookupWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	}
	return SnapshotIndexLookupWorkerResult{
		ok:   true
		rows: SnapshotIndexLookupResult{
			commit_cid: commit_cid
			table_name: table_name
			index_name: index_name
			rows:       rows
		}
	}
}

fn snapshot_index_prefix_lookup_from_worker(provider LocalDatabaseBackendProvider, commit_cid string, table_name string, index_name string, value ColumnValue, start_primary_key []u8, limit int) SnapshotIndexLookupWorkerResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	mut reader := database.snapshot_index_reader_for_commit(commit_cid, table_name, index_name) or {
		return SnapshotIndexLookupWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	mut rows := []TypedSchemaRow{}
	if reader.index.stores_row {
		rows = reader.find_rows_covering_prefix_from(value, start_primary_key, limit) or {
			return SnapshotIndexLookupWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	} else {
		rows = reader.find_rows_prefix_from(value, start_primary_key, limit) or {
			return SnapshotIndexLookupWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	}
	return SnapshotIndexLookupWorkerResult{
		ok:   true
		rows: SnapshotIndexLookupResult{
			commit_cid: commit_cid
			table_name: table_name
			index_name: index_name
			rows:       rows
		}
	}
}

fn snapshot_table_scan_pair_from_worker(provider LocalDatabaseBackendProvider, left_commit_cid string, right_commit_cid string, table_name string, start_primary_key []u8, limit int) SnapshotIndexLookupPairWorkerResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return SnapshotIndexLookupPairWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	mut left_reader := database.snapshot_table_reader_for_commit(left_commit_cid, table_name) or {
		return SnapshotIndexLookupPairWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	mut right_reader := database.snapshot_table_reader_for_commit(right_commit_cid, table_name) or {
		return SnapshotIndexLookupPairWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	left_rows := left_reader.scan_rows_from(start_primary_key, limit) or {
		return SnapshotIndexLookupPairWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	right_rows := right_reader.scan_rows_from(start_primary_key, limit) or {
		return SnapshotIndexLookupPairWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	return SnapshotIndexLookupPairWorkerResult{
		ok:   true
		rows: SnapshotIndexLookupPairResult{
			left:  SnapshotIndexLookupResult{
				commit_cid: left_commit_cid
				table_name: table_name
				index_name: ''
				rows:       left_rows
			}
			right: SnapshotIndexLookupResult{
				commit_cid: right_commit_cid
				table_name: table_name
				index_name: ''
				rows:       right_rows
			}
		}
	}
}

fn snapshot_index_prefix_lookup_pair_from_worker(provider LocalDatabaseBackendProvider, left_commit_cid string, right_commit_cid string, table_name string, index_name string, value ColumnValue, start_primary_key []u8, limit int) SnapshotIndexLookupPairWorkerResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return SnapshotIndexLookupPairWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	mut left_reader := database.snapshot_index_reader_for_commit(left_commit_cid, table_name,
		index_name) or {
		return SnapshotIndexLookupPairWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	mut right_reader := database.snapshot_index_reader_for_commit(right_commit_cid, table_name,
		index_name) or {
		return SnapshotIndexLookupPairWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	mut left_rows := []TypedSchemaRow{}
	if left_reader.index.stores_row {
		left_rows = left_reader.find_rows_covering_prefix_from(value, start_primary_key,
			limit) or {
			return SnapshotIndexLookupPairWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	} else {
		left_rows = left_reader.find_rows_prefix_from(value, start_primary_key, limit) or {
			return SnapshotIndexLookupPairWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	}
	mut right_rows := []TypedSchemaRow{}
	if right_reader.index.stores_row {
		right_rows = right_reader.find_rows_covering_prefix_from(value, start_primary_key,
			limit) or {
			return SnapshotIndexLookupPairWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	} else {
		right_rows = right_reader.find_rows_prefix_from(value, start_primary_key, limit) or {
			return SnapshotIndexLookupPairWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
	}
	return SnapshotIndexLookupPairWorkerResult{
		ok:   true
		rows: SnapshotIndexLookupPairResult{
			left:  SnapshotIndexLookupResult{
				commit_cid: left_commit_cid
				table_name: table_name
				index_name: index_name
				rows:       left_rows
			}
			right: SnapshotIndexLookupResult{
				commit_cid: right_commit_cid
				table_name: table_name
				index_name: index_name
				rows:       right_rows
			}
		}
	}
}

fn bytes_index_byte(data []u8, target u8) ?int {
	for idx, value in data {
		if value == target {
			return idx
		}
	}
	return none
}

fn bytes_compare(left []u8, right []u8) int {
	common_len := if left.len < right.len { left.len } else { right.len }
	for idx in 0 .. common_len {
		if left[idx] < right[idx] {
			return -1
		}
		if left[idx] > right[idx] {
			return 1
		}
	}
	if left.len < right.len {
		return -1
	}
	if left.len > right.len {
		return 1
	}
	return 0
}

fn aggregate_bucket_for_primary_key(primary_key []u8) int {
	if primary_key.len == 0 {
		return 0
	}
	return int(primary_key[0])
}

fn aggregate_bucket_start_primary_key(bucket int) []u8 {
	return [u8(bucket)]
}

fn aggregate_bucket_end_primary_key(bucket int) []u8 {
	if bucket >= 255 {
		return []u8{}
	}
	return [u8(bucket + 1)]
}

fn read_declared_sum_bucket(root_cid string, table_name string, column_name string, bucket int, mut node_store NodeByteStore) !i64 {
	item := Tree.lookup_in_byte_store(root_cid, encode_table_sum_bucket_key(table_name,
		column_name, u8(bucket)), mut node_store)!
	value := TypedValueEncoder.decode_value(item.value, .i64_)!
	return match value {
		i64 { value }
		else { error('aggregate bucket ${table_name}.${column_name}[${bucket}] did not decode as i64') }
	}
}

fn sum_declared_i64_range(root_cid string, table_name string, column_name string, start_primary_key []u8, end_primary_key []u8, codec TypedRowCodec, mut node_store NodeByteStore) !i64 {
	if start_primary_key.len == 0 && end_primary_key.len == 0 {
		item := Tree.lookup_in_byte_store(root_cid, encode_table_sum_aggregate_key(table_name,
			column_name), mut node_store)!
		value := TypedValueEncoder.decode_value(item.value, .i64_)!
		return match value {
			i64 { value }
			else { error('aggregate ${table_name}.${column_name} did not decode as i64') }
		}
	}
	start_bucket := aggregate_bucket_for_primary_key(start_primary_key)
	end_bucket := if end_primary_key.len == 0 {
		256
	} else {
		aggregate_bucket_for_primary_key(end_primary_key)
	}
	if end_primary_key.len > 0 && start_primary_key.len > 0 && start_bucket == end_bucket {
		start_key := encode_table_row_key(table_name, start_primary_key)
		end_key := encode_table_row_key(table_name, end_primary_key)
		return Tree.sum_i64_column_range_in_byte_store(root_cid, start_key, end_key, codec,
			column_name, mut node_store)
	}
	mut total := i64(0)
	if start_primary_key.len > 0 {
		left_end_pk := aggregate_bucket_end_primary_key(start_bucket)
		start_key := encode_table_row_key(table_name, start_primary_key)
		end_key := if left_end_pk.len == 0 {
			encode_table_range_end(table_name)!
		} else {
			encode_table_row_key(table_name, left_end_pk)
		}
		total += Tree.sum_i64_column_range_in_byte_store(root_cid, start_key, end_key,
			codec, column_name, mut node_store)!
	}
	middle_start := if start_primary_key.len > 0 { start_bucket + 1 } else { 0 }
	middle_end := if end_primary_key.len == 0 { 256 } else { end_bucket }
	for bucket := middle_start; bucket < middle_end; bucket++ {
		total += read_declared_sum_bucket(root_cid, table_name, column_name, bucket, mut
			node_store) or { i64(0) }
	}
	if end_primary_key.len > 0 && (start_primary_key.len == 0 || end_bucket != start_bucket) {
		right_start_pk := aggregate_bucket_start_primary_key(end_bucket)
		start_key := encode_table_row_key(table_name, right_start_pk)
		end_key := encode_table_row_key(table_name, end_primary_key)
		total += Tree.sum_i64_column_range_in_byte_store(root_cid, start_key, end_key,
			codec, column_name, mut node_store)!
	}
	return total
}

fn database_append_u32(mut out []u8, value u32) {
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
}

fn database_append_u8(mut out []u8, value u8) {
	out << value
}

fn database_append_field(mut out []u8, data []u8) {
	database_append_u32(mut out, u32(data.len))
	out << data
}

fn (mut reader DatabaseCatalogReader) read_u32() !u32 {
	if reader.cursor + 4 > reader.data.len {
		return error('database catalog truncated')
	}
	value := u32(reader.data[reader.cursor]) | (u32(reader.data[reader.cursor + 1]) << 8) | (u32(reader.data[
		reader.cursor + 2]) << 16) | (u32(reader.data[reader.cursor + 3]) << 24)
	reader.cursor += 4
	return value
}

fn (mut reader DatabaseCatalogReader) read_u8() !u8 {
	if reader.cursor + 1 > reader.data.len {
		return error('database catalog truncated')
	}
	value := reader.data[reader.cursor]
	reader.cursor++
	return value
}

fn (mut reader DatabaseCatalogReader) read_field() ![]u8 {
	length := int(reader.read_u32()!)
	if reader.cursor + length > reader.data.len {
		return error('database catalog field truncated')
	}
	field := reader.data[reader.cursor..reader.cursor + length].clone()
	reader.cursor += length
	return field
}

fn column_type_to_u8(typ ColumnType) u8 {
	return match typ {
		.bool_ { 1 }
		.i64_ { 2 }
		.string_ { 3 }
		.bytes_ { 4 }
		.enum_ { 5 }
		.json_ { 6 }
		.datetime_ { 7 }
		.markdown_ { 8 }
	}
}

fn column_aggregate_to_u8(value ColumnAggregate) u8 {
	return match value {
		.none { 0 }
		.sum { 1 }
	}
}

fn column_aggregate_from_u8(value u8) !ColumnAggregate {
	return match value {
		0 { .none }
		1 { .sum }
		else { error('invalid column aggregate tag: ${value}') }
	}
}

fn column_type_from_u8(value u8) !ColumnType {
	return match value {
		1 { .bool_ }
		2 { .i64_ }
		3 { .string_ }
		4 { .bytes_ }
		5 { .enum_ }
		6 { .json_ }
		7 { .datetime_ }
		8 { .markdown_ }
		else { error('invalid column type tag: ${value}') }
	}
}

fn sorted_catalog_names(catalog map[string]TypedTableSpec) []string {
	mut names := catalog.keys()
	names.sort()
	return names
}

fn sorted_projector_names(projectors map[string]AggregateProjectionDef) []string {
	mut names := projectors.keys()
	names.sort()
	return names
}

fn sorted_projector_names_by_priority(projectors map[string]AggregateProjectionDef) []string {
	mut defs := []AggregateProjectionDef{}
	for _, def in projectors {
		defs << def
	}
	defs.sort_with_compare(fn (a &AggregateProjectionDef, b &AggregateProjectionDef) int {
		if a.priority > b.priority {
			return -1
		}
		if a.priority < b.priority {
			return 1
		}
		if int(a.cost_hint) < int(b.cost_hint) {
			return -1
		}
		if int(a.cost_hint) > int(b.cost_hint) {
			return 1
		}
		if a.name < b.name {
			return -1
		}
		if a.name > b.name {
			return 1
		}
		return 0
	})
	mut names := []string{cap: defs.len}
	for def in defs {
		names << def.name
	}
	return names
}

fn sorted_memory_capability_keys(capabilities map[string]MemoryCapabilityDef) []string {
	mut keys := capabilities.keys()
	keys.sort()
	return keys
}

fn memory_capability_key(table_name string, column_name string) string {
	return '${table_name}\x00${column_name}'
}

fn catalog_data(catalog map[string]TypedTableSpec, projectors map[string]AggregateProjectionDef, memory_capabilities map[string]MemoryCapabilityDef) []u8 {
	mut out := []u8{}
	names := sorted_catalog_names(catalog)
	database_append_u32(mut out, u32(names.len))
	for name in names {
		spec := catalog[name] or { continue }
		database_append_field(mut out, spec.table.name.bytes())
		database_append_u32(mut out, u32(spec.table.columns.len))
		for column in spec.table.columns {
			database_append_field(mut out, column.name.bytes())
			database_append_u8(mut out, column_type_to_u8(column.typ))
			database_append_u8(mut out, if column.nullable { u8(1) } else { u8(0) })
			database_append_u8(mut out, column_aggregate_to_u8(column.aggregate))
			database_append_u32(mut out, u32(column.enum_values.len))
			for enum_value in column.enum_values {
				database_append_field(mut out, enum_value.bytes())
			}
		}
		database_append_u32(mut out, u32(spec.table.primary_key.len))
		for key in spec.table.primary_key {
			database_append_field(mut out, key.bytes())
		}
		database_append_u32(mut out, u32(spec.indexes.len))
		for index in spec.indexes {
			database_append_field(mut out, index.name.bytes())
			database_append_field(mut out, index.column.bytes())
			database_append_field(mut out, index.json_field.bytes())
			database_append_field(mut out, index.field_selector().bytes())
			database_append_u8(mut out, column_type_to_u8(index.json_field_type))
			database_append_u8(mut out, if index.stores_row { u8(1) } else { u8(0) })
		}
	}
	mut fts_table_names := []string{}
	mut fts_indexes := []SchemaIndexDef{}
	mut embedding_table_names := []string{}
	mut embedding_indexes := []SchemaIndexDef{}
	for name in names {
		spec := catalog[name] or { continue }
		for index in spec.indexes {
			if index.is_fts() {
				fts_table_names << spec.table.name
				fts_indexes << index
			}
			if index.is_embedding() {
				embedding_table_names << spec.table.name
				embedding_indexes << index
			}
		}
	}
	projector_names := sorted_projector_names(projectors)
	database_append_u32(mut out, u32(projector_names.len))
	for name in projector_names {
		projector := projectors[name] or { continue }
		database_append_field(mut out, projector.name.bytes())
		database_append_field(mut out, projector.table_name.bytes())
		database_append_field(mut out, projector.column_name.bytes())
		database_append_field(mut out, projector.source_json_path.bytes())
		database_append_u8(mut out, column_aggregate_to_u8(projector.aggregate))
	}
	database_append_field(mut out, 'projector_markdown_selectors_v1'.bytes())
	database_append_u32(mut out, u32(projector_names.len))
	for name in projector_names {
		projector := projectors[name] or { continue }
		database_append_field(mut out, projector.name.bytes())
		database_append_field(mut out, projector.source_markdown_selector.bytes())
	}
	database_append_field(mut out, 'projector_field_selectors_v1'.bytes())
	database_append_u32(mut out, u32(projector_names.len))
	for name in projector_names {
		projector := projectors[name] or { continue }
		selector_meta := projector.field_projection_meta() or { FieldSelectorRef{} }
		database_append_field(mut out, projector.name.bytes())
		database_append_field(mut out, selector_meta.plugin_name.bytes())
		database_append_field(mut out, selector_meta.selector.bytes())
	}
	database_append_field(mut out, 'projector_priorities_v1'.bytes())
	database_append_u32(mut out, u32(projector_names.len))
	for name in projector_names {
		projector := projectors[name] or { continue }
		database_append_field(mut out, projector.name.bytes())
		database_append_u32(mut out, u32(projector.priority))
	}
	database_append_field(mut out, 'projector_cost_hints_v1'.bytes())
	database_append_u32(mut out, u32(projector_names.len))
	for name in projector_names {
		projector := projectors[name] or { continue }
		database_append_field(mut out, projector.name.bytes())
		database_append_u8(mut out, u8(projector.cost_hint))
	}
	mut temporal_columns := []ColumnDef{}
	mut temporal_tables := []string{}
	for name in names {
		spec := catalog[name] or { continue }
		for column in spec.table.columns {
			if column.default_current_timestamp || column.auto_update_current_timestamp {
				temporal_tables << spec.table.name
				temporal_columns << column
			}
		}
	}
	database_append_field(mut out, 'column_datetime_behaviors_v1'.bytes())
	database_append_u32(mut out, u32(temporal_columns.len))
	for idx, column in temporal_columns {
		database_append_field(mut out, temporal_tables[idx].bytes())
		database_append_field(mut out, column.name.bytes())
		database_append_u8(mut out, if column.default_current_timestamp { u8(1) } else { u8(0) })
		database_append_u8(mut out, if column.auto_update_current_timestamp { u8(1) } else { u8(0) })
	}
	database_append_field(mut out, 'schema_fts_indexes_v1'.bytes())
	database_append_u32(mut out, u32(fts_indexes.len))
	for idx, index in fts_indexes {
		database_append_field(mut out, fts_table_names[idx].bytes())
		database_append_field(mut out, index.name.bytes())
		database_append_field(mut out, index.fts_source_plugin.bytes())
		database_append_field(mut out, index.fts_text_mode.bytes())
		database_append_field(mut out, index.fts_tokenizer.bytes())
		database_append_u32(mut out, u32(index.fts_prefix_lengths.len))
		for prefix_len in index.fts_prefix_lengths {
			database_append_u32(mut out, u32(prefix_len))
		}
	}
	database_append_field(mut out, 'schema_embedding_indexes_v1'.bytes())
	database_append_u32(mut out, u32(embedding_indexes.len))
	for idx, index in embedding_indexes {
		database_append_field(mut out, embedding_table_names[idx].bytes())
		database_append_field(mut out, index.name.bytes())
		database_append_field(mut out, index.embedding_source_plugin.bytes())
		database_append_field(mut out, index.embedding_scope.bytes())
		database_append_field(mut out, index.embedding_profile.bytes())
	}
	capability_keys := sorted_memory_capability_keys(memory_capabilities)
	database_append_field(mut out, 'memory_capabilities_v1'.bytes())
	database_append_u32(mut out, u32(capability_keys.len))
	for key in capability_keys {
		capability := memory_capabilities[key] or { continue }
		database_append_field(mut out, capability.table_name.bytes())
		database_append_field(mut out, capability.column_name.bytes())
		database_append_u8(mut out, if capability.options.enabled { u8(1) } else { u8(0) })
		database_append_field(mut out, capability.options.embedding_index.bytes())
		database_append_field(mut out, capability.options.reflection_kind.bytes())
		database_append_u8(mut out, if capability.options.replay_anchor { u8(1) } else { u8(0) })
		database_append_u8(mut out, if capability.options.link_evidence_blocks {
			u8(1)
		} else {
			u8(0)
		})
		database_append_u8(mut out, if capability.options.link_semantic_neighbors {
			u8(1)
		} else {
			u8(0)
		})
	}
	return out
}

fn catalog_from_data(data []u8) !(map[string]TypedTableSpec, map[string]AggregateProjectionDef, map[string]MemoryCapabilityDef) {
	if data.len == 0 {
		return map[string]TypedTableSpec{}, map[string]AggregateProjectionDef{}, map[string]MemoryCapabilityDef{}
	}
	mut reader := DatabaseCatalogReader{
		data: data
	}
	spec_count := int(reader.read_u32()!)
	mut catalog := map[string]TypedTableSpec{}
	for _ in 0 .. spec_count {
		table_name := reader.read_field()!.bytestr()
		column_count := int(reader.read_u32()!)
		mut columns := []ColumnDef{cap: column_count}
		for _ in 0 .. column_count {
			column_name := reader.read_field()!.bytestr()
			column_type := column_type_from_u8(reader.read_u8()!)!
			nullable := reader.read_u8()! == 1
			aggregate := column_aggregate_from_u8(reader.read_u8()!)!
			enum_count := int(reader.read_u32()!)
			mut enum_values := []string{cap: enum_count}
			for _ in 0 .. enum_count {
				enum_values << reader.read_field()!.bytestr()
			}
			columns << if column_type == .enum_ {
				ColumnDef{
					name:        column_name
					typ:         .enum_
					nullable:    nullable
					aggregate:   aggregate
					enum_values: enum_values.clone()
				}
			} else {
				ColumnDef.new_with_aggregate(column_name, column_type, nullable, aggregate)!
			}
		}
		primary_key_count := int(reader.read_u32()!)
		mut primary_key := []string{cap: primary_key_count}
		for _ in 0 .. primary_key_count {
			primary_key << reader.read_field()!.bytestr()
		}
		index_count := int(reader.read_u32()!)
		mut indexes := []SchemaIndexDef{cap: index_count}
		for _ in 0 .. index_count {
			index_name := reader.read_field()!.bytestr()
			index_column := reader.read_field()!.bytestr()
			index_json_field := reader.read_field()!.bytestr()
			index_markdown_selector := reader.read_field()!.bytestr()
			index_json_field_type := column_type_from_u8(reader.read_u8()!)!
			stores_row := reader.read_u8()! == 1
			indexes << if index_markdown_selector.len > 0 {
				SchemaIndexDef.field_selector(index_name, index_column, 'markdown', index_markdown_selector,
					index_json_field_type, stores_row)!
			} else if index_json_field.len > 0 {
				if stores_row {
					SchemaIndexDef.json_path_covering(index_name, index_column, index_json_field,
						index_json_field_type)!
				} else {
					SchemaIndexDef.json_path(index_name, index_column, index_json_field,
						index_json_field_type)!
				}
			} else if stores_row {
				SchemaIndexDef.covering(index_name, index_column)!
			} else {
				SchemaIndexDef.new(index_name, index_column)!
			}
		}
		table := TableDef.new(table_name, columns, primary_key)!
		spec := TypedTableSpec.new(table, indexes)!
		catalog[spec.name()] = spec
	}
	mut projectors := map[string]AggregateProjectionDef{}
	mut memory_capabilities := map[string]MemoryCapabilityDef{}
	if reader.cursor < data.len {
		projector_count := int(reader.read_u32()!)
		for _ in 0 .. projector_count {
			name := reader.read_field()!.bytestr()
			table_name := reader.read_field()!.bytestr()
			column_name := reader.read_field()!.bytestr()
			source_json_path := reader.read_field()!.bytestr()
			aggregate := column_aggregate_from_u8(reader.read_u8()!)!
			projectors[name] = AggregateProjectionDef{
				name:                     name
				table_name:               table_name
				column_name:              column_name
				source_json_path:         source_json_path
				source_markdown_selector: ''
				aggregate:                aggregate
				priority:                 100
				cost_hint:                .medium
			}
		}
	}
	for reader.cursor < data.len {
		section_tag := reader.read_field()!.bytestr()
		match section_tag {
			'projector_markdown_selectors_v1' {
				selector_count := int(reader.read_u32()!)
				for _ in 0 .. selector_count {
					name := reader.read_field()!.bytestr()
					selector := reader.read_field()!.bytestr()
					projector := projectors[name] or { continue }
					projectors[name] = AggregateProjectionDef{
						...projector
						source_markdown_selector: selector
					}
				}
			}
			'projector_field_selectors_v1' {
				selector_count := int(reader.read_u32()!)
				for _ in 0 .. selector_count {
					name := reader.read_field()!.bytestr()
					plugin_name := reader.read_field()!.bytestr()
					selector := reader.read_field()!.bytestr()
					if plugin_name.len == 0 || selector.len == 0 {
						continue
					}
					projector := projectors[name] or { continue }
					updated := AggregateProjectionDef.count_field_selector(projector.name,
						projector.table_name, projector.column_name, plugin_name, selector) or {
						continue
					}
					projectors[name] = AggregateProjectionDef{
						...updated
						source_json_path: projector.source_json_path
						aggregate:        projector.aggregate
						priority:         projector.priority
						cost_hint:        projector.cost_hint
					}
				}
			}
			'projector_priorities_v1' {
				priority_count := int(reader.read_u32()!)
				for _ in 0 .. priority_count {
					name := reader.read_field()!.bytestr()
					priority := int(reader.read_u32()!)
					projector := projectors[name] or { continue }
					projectors[name] = projector.with_priority(priority)
				}
			}
			'projector_cost_hints_v1' {
				cost_count := int(reader.read_u32()!)
				for _ in 0 .. cost_count {
					name := reader.read_field()!.bytestr()
					cost_hint := unsafe { AggregateProjectionCostHint(reader.read_u8()!) }
					projector := projectors[name] or { continue }
					projectors[name] = projector.with_cost_hint(cost_hint)
				}
			}
			'column_datetime_behaviors_v1' {
				behavior_count := int(reader.read_u32()!)
				for _ in 0 .. behavior_count {
					table_name := reader.read_field()!.bytestr()
					column_name := reader.read_field()!.bytestr()
					default_current_timestamp := reader.read_u8()! == 1
					auto_update_current_timestamp := reader.read_u8()! == 1
					spec := catalog[table_name] or { continue }
					mut columns := spec.table.columns.clone()
					for idx, column in columns {
						if column.name == column_name {
							columns[idx] = ColumnDef.new_with_options(column.name, column.typ,
								column.nullable, column.aggregate, default_current_timestamp,
								auto_update_current_timestamp)!
						}
					}
					table := TableDef.new(spec.table.name, columns, spec.table.primary_key)!
					catalog[table_name] = TypedTableSpec.new(table, spec.indexes)!
				}
			}
			'schema_fts_indexes_v1' {
				fts_count := int(reader.read_u32()!)
				for _ in 0 .. fts_count {
					table_name := reader.read_field()!.bytestr()
					index_name := reader.read_field()!.bytestr()
					source_plugin := reader.read_field()!.bytestr()
					text_mode := reader.read_field()!.bytestr()
					tokenizer := reader.read_field()!.bytestr()
					prefix_count := int(reader.read_u32()!)
					mut prefix_lengths := []int{cap: prefix_count}
					for _ in 0 .. prefix_count {
						prefix_lengths << int(reader.read_u32()!)
					}
					spec := catalog[table_name] or { continue }
					mut indexes := spec.indexes.clone()
					for idx, index in indexes {
						if index.name != index_name {
							continue
						}
						indexes[idx] = SchemaIndexDef{
							...index
							fts_source_plugin:  source_plugin
							fts_text_mode:      text_mode
							fts_tokenizer:      tokenizer
							fts_prefix_lengths: prefix_lengths.clone()
						}
					}
					catalog[table_name] = TypedTableSpec.new(spec.table, indexes)!
				}
			}
			'schema_embedding_indexes_v1' {
				embedding_count := int(reader.read_u32()!)
				for _ in 0 .. embedding_count {
					table_name := reader.read_field()!.bytestr()
					index_name := reader.read_field()!.bytestr()
					source_plugin := reader.read_field()!.bytestr()
					scope := reader.read_field()!.bytestr()
					profile := reader.read_field()!.bytestr()
					spec := catalog[table_name] or { continue }
					mut indexes := spec.indexes.clone()
					for idx, index in indexes {
						if index.name != index_name {
							continue
						}
						indexes[idx] = SchemaIndexDef{
							...index
							embedding_source_plugin: source_plugin
							embedding_scope:         scope
							embedding_profile:       profile
						}
					}
					catalog[table_name] = TypedTableSpec.new(spec.table, indexes)!
				}
			}
			'memory_capabilities_v1' {
				capability_count := int(reader.read_u32()!)
				for _ in 0 .. capability_count {
					table_name := reader.read_field()!.bytestr()
					column_name := reader.read_field()!.bytestr()
					enabled := reader.read_u8()! == 1
					embedding_index := reader.read_field()!.bytestr()
					reflection_kind := reader.read_field()!.bytestr()
					replay_anchor := reader.read_u8()! == 1
					link_evidence_blocks := reader.read_u8()! == 1
					link_semantic_neighbors := reader.read_u8()! == 1
					capability := MemoryCapabilityDef.reflective_field(table_name, column_name,
						ReflectionOptions{
						enabled:                 enabled
						embedding_index:         embedding_index
						reflection_kind:         reflection_kind
						replay_anchor:           replay_anchor
						link_evidence_blocks:    link_evidence_blocks
						link_semantic_neighbors: link_semantic_neighbors
					}) or { continue }
					memory_capabilities[memory_capability_key(table_name, column_name)] = capability
				}
			}
			else {
				return error('unknown database catalog extension section: ${section_tag}')
			}
		}
	}
	if reader.cursor != data.len {
		return error('database catalog has trailing bytes')
	}
	return catalog, projectors, memory_capabilities
}

fn load_database_catalog(root_dir string) !(map[string]TypedTableSpec, map[string]AggregateProjectionDef, map[string]MemoryCapabilityDef) {
	path := database_catalog_path(root_dir)
	if !os.exists(path) {
		return map[string]TypedTableSpec{}, map[string]AggregateProjectionDef{}, map[string]MemoryCapabilityDef{}
	}
	return catalog_from_data(os.read_bytes(path)!)
}

pub fn PersistentDatabase.open(root_dir string, default_branch string) !PersistentDatabase {
	return (PersistentDatabase.open_profiled(root_dir, default_branch)!).database
}

pub fn PersistentDatabase.init(root_dir string, default_branch string) !PersistentDatabase {
	return PersistentDatabase.init_with_provider(LocalDatabaseBackendProvider.new(root_dir,
		default_branch))
}

pub fn PersistentDatabase.open_with_provider(provider LocalDatabaseBackendProvider) !PersistentDatabase {
	return (PersistentDatabase.open_with_provider_profiled(provider)!).database
}

pub fn PersistentDatabase.open_profiled(root_dir string, default_branch string) !PersistentDatabaseOpenResult {
	return PersistentDatabase.open_with_provider_profiled(LocalDatabaseBackendProvider.new(root_dir,
		default_branch))
}

pub fn PersistentDatabase.open_with_provider_profiled(provider LocalDatabaseBackendProvider) !PersistentDatabaseOpenResult {
	mut total_sw := time.new_stopwatch()
	os.mkdir_all(repository_layout_dir(provider.root_dir))!
	backends_ms := i64(0)
	mut catalog_sw := time.new_stopwatch()
	catalog, projectors, memory_capabilities := load_database_catalog(provider.root_dir)!
	catalog_ms := catalog_sw.elapsed().milliseconds()
	engine_result := PersistentEngine.open_with_provider_profiled(provider)!
	database := PersistentDatabase{
		root_dir:            provider.root_dir
		default_branch:      provider.default_branch()
		engine:              engine_result.engine
		catalog:             catalog
		projectors:          projectors
		memory_capabilities: memory_capabilities
		field_registry:      default_field_capability_registry()
		catalog_dirty:       false
	}
	return PersistentDatabaseOpenResult{
		database: database
		timings:  PersistentDatabaseOpenTimings{
			backends_ms: backends_ms
			catalog_ms:  catalog_ms
			engine:      engine_result.timings
			total_ms:    total_sw.elapsed().milliseconds()
		}
	}
}

pub fn PersistentDatabase.init_with_provider(provider LocalDatabaseBackendProvider) !PersistentDatabase {
	os.mkdir_all(repository_layout_dir(provider.root_dir))!
	mut database := PersistentDatabase{
		root_dir:            provider.root_dir
		default_branch:      provider.default_branch()
		engine:              PersistentEngine.init_with_provider(provider)!
		catalog:             map[string]TypedTableSpec{}
		projectors:          map[string]AggregateProjectionDef{}
		memory_capabilities: map[string]MemoryCapabilityDef{}
		field_registry:      default_field_capability_registry()
		catalog_dirty:       true
	}
	database.persist_catalog()!
	return database
}

pub fn (database PersistentDatabase) backend_paths() LocalBackendPaths {
	return local_backend_paths(database.root_dir)
}

pub fn (database PersistentDatabase) backend_provider() LocalDatabaseBackendProvider {
	return LocalDatabaseBackendProvider.new(database.root_dir, database.default_branch)
}

pub fn (database PersistentDatabase) field_capability_registry() FieldCapabilityRegistry {
	return database.field_registry
}

pub fn (database PersistentDatabase) field_plugin_names() []string {
	return database.field_registry.plugin_names()
}

pub fn (mut database PersistentDatabase) set_field_capability_registry(registry FieldCapabilityRegistry) {
	database.field_registry = registry
}

pub fn (database PersistentDatabase) open_local_backends() !LocalDatabaseBackends {
	return database.backend_provider().open_backends()
}

pub fn open_database(root_dir string, default_branch string) !PersistentDatabase {
	return PersistentDatabase.open_with_provider(LocalDatabaseBackendProvider.new(root_dir,
		default_branch))
}

pub fn init_database(root_dir string, default_branch string) !PersistentDatabase {
	return PersistentDatabase.init_with_provider(LocalDatabaseBackendProvider.new(root_dir,
		default_branch))
}

pub fn (mut database PersistentDatabase) persist_catalog() ! {
	if !database.catalog_dirty {
		return
	}
	os.mkdir_all(repository_layout_dir(database.root_dir))!
	os.write_file(database_catalog_path(database.root_dir), catalog_data(database.catalog,
		database.projectors, database.memory_capabilities).bytestr())!
	database.catalog_dirty = false
}

pub fn (mut database PersistentDatabase) close() ! {
	database.checkpoint() or {}
	database.engine.close()!
}

pub fn (mut database PersistentDatabase) root_cid_at_branch(branch_name string) !string {
	return database.engine.root_cid_at_branch(branch_name)
}

pub fn (mut database PersistentDatabase) checkpoint() ! {
	if database.catalog_dirty {
		database.persist_catalog()!
		$if darwin {
			catalog_path := database_catalog_path(database.root_dir)
			mut catalog_file := os.open_file(catalog_path, 'rb', 0o666)!
			defer {
				catalog_file.close()
			}
			catalog_file.flush()
			chunk_store_fsync_fd(catalog_file.fd)!
		}
	}
	database.engine.checkpoint()!
}

pub fn (mut database PersistentDatabase) refresh_index_snapshots() ! {
	database.engine.refresh_index_snapshots()!
}

fn refresh_index_snapshots_worker(provider LocalDatabaseBackendProvider) IndexSnapshotRefreshResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return IndexSnapshotRefreshResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	database.refresh_index_snapshots() or {
		return IndexSnapshotRefreshResult{
			ok:  false
			err: err.msg()
		}
	}
	return IndexSnapshotRefreshResult{
		ok:  true
		err: ''
	}
}

pub fn PersistentDatabase.refresh_index_snapshots_async_for(root_dir string, default_branch string) IndexSnapshotRefreshHandle {
	provider := LocalDatabaseBackendProvider.new(root_dir, default_branch)
	return IndexSnapshotRefreshHandle{
		worker: spawn refresh_index_snapshots_worker(provider)
	}
}

fn refresh_aggregate_projections_worker(provider LocalDatabaseBackendProvider, branch_name string) AggregateProjectionRefreshResult {
	return refresh_aggregate_projections_limited_worker(provider, branch_name, 0)
}

fn refresh_aggregate_projections_limited_worker(provider LocalDatabaseBackendProvider, branch_name string, limit int) AggregateProjectionRefreshResult {
	mut database := PersistentDatabase.open_with_provider(provider) or {
		return AggregateProjectionRefreshResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		database.close() or {}
	}
	database.refresh_aggregate_projections_limited(branch_name, ChunkConfig.default(),
		CommitMeta{
		author:    'pollydb/projector'
		message:   'async refresh aggregate projections'
		timestamp: 0
	}, limit) or { return AggregateProjectionRefreshResult{
		ok:  false
		err: err.msg()
	} }
	database.checkpoint() or {
		return AggregateProjectionRefreshResult{
			ok:  false
			err: err.msg()
		}
	}
	return AggregateProjectionRefreshResult{
		ok:  true
		err: ''
	}
}

pub fn PersistentDatabase.refresh_aggregate_projections_async_for(root_dir string, default_branch string, branch_name string) AggregateProjectionRefreshHandle {
	return PersistentDatabase.refresh_aggregate_projections_async_limited_for(root_dir,
		default_branch, branch_name, 0)
}

pub fn PersistentDatabase.refresh_aggregate_projections_async_limited_for(root_dir string, default_branch string, branch_name string, limit int) AggregateProjectionRefreshHandle {
	provider := LocalDatabaseBackendProvider.new(root_dir, default_branch)
	return AggregateProjectionRefreshHandle{
		active: true
		worker: spawn refresh_aggregate_projections_limited_worker(provider, branch_name,
			limit)
	}
}

pub fn (mut database PersistentDatabase) refresh_aggregate_projections_async(branch_name string) !AggregateProjectionRefreshHandle {
	if !database.has_stale_projections_at_branch(branch_name)! {
		return AggregateProjectionRefreshHandle{}
	}
	database.checkpoint_mode(.data_only)!
	return PersistentDatabase.refresh_aggregate_projections_async_limited_for(database.root_dir,
		database.default_branch, branch_name, 0)
}

pub fn (mut database PersistentDatabase) refresh_aggregate_projections_async_with_policy(branch_name string, policy AggregateProjectionRefreshPolicy, limit int) !AggregateProjectionRefreshHandle {
	if policy == .none || !database.has_stale_projections_at_branch(branch_name)! {
		return AggregateProjectionRefreshHandle{}
	}
	database.checkpoint_mode(.data_only)!
	effective_limit := match policy {
		.none {
			-1
		}
		.stale_one {
			1
		}
		.stale_up_to {
			if limit > 0 { limit } else { 1 }
		}
		.stale_all {
			0
		}
	}
	if effective_limit < 0 {
		return AggregateProjectionRefreshHandle{}
	}
	return PersistentDatabase.refresh_aggregate_projections_async_limited_for(database.root_dir,
		database.default_branch, branch_name, effective_limit)
}

pub fn (mut database PersistentDatabase) checkpoint_mode(mode CheckpointMode) ! {
	if database.catalog_dirty {
		database.persist_catalog()!
		$if darwin {
			catalog_path := database_catalog_path(database.root_dir)
			mut catalog_file := os.open_file(catalog_path, 'rb', 0o666)!
			defer {
				catalog_file.close()
			}
			catalog_file.flush()
			chunk_store_fsync_fd(catalog_file.fd)!
		}
	}
	database.engine.checkpoint_mode(mode)!
}

pub fn (mut database PersistentDatabase) checkpoint_timed() !PersistentDatabaseCheckpointTimings {
	mut total_sw := time.new_stopwatch()
	mut catalog_us := i64(0)
	if database.catalog_dirty {
		mut sw := time.new_stopwatch()
		database.persist_catalog()!
		$if darwin {
			catalog_path := database_catalog_path(database.root_dir)
			mut catalog_file := os.open_file(catalog_path, 'rb', 0o666)!
			defer {
				catalog_file.close()
			}
			catalog_file.flush()
			chunk_store_fsync_fd(catalog_file.fd)!
		}
		catalog_us = sw.elapsed().microseconds()
	}
	engine_timings := database.engine.checkpoint_timed()!
	return PersistentDatabaseCheckpointTimings{
		catalog_us: catalog_us
		engine:     engine_timings
		total_us:   total_sw.elapsed().microseconds()
	}
}

pub fn (mut database PersistentDatabase) checkpoint_timed_mode(mode CheckpointMode) !PersistentDatabaseCheckpointTimings {
	mut total_sw := time.new_stopwatch()
	mut catalog_us := i64(0)
	if database.catalog_dirty {
		mut sw := time.new_stopwatch()
		database.persist_catalog()!
		$if darwin {
			catalog_path := database_catalog_path(database.root_dir)
			mut catalog_file := os.open_file(catalog_path, 'rb', 0o666)!
			defer {
				catalog_file.close()
			}
			catalog_file.flush()
			chunk_store_fsync_fd(catalog_file.fd)!
		}
		catalog_us = sw.elapsed().microseconds()
	}
	engine_timings := database.engine.checkpoint_timed_mode(mode)!
	return PersistentDatabaseCheckpointTimings{
		catalog_us: catalog_us
		engine:     engine_timings
		total_us:   total_sw.elapsed().microseconds()
	}
}

pub fn (database PersistentDatabase) checkpoint_info() PersistentDatabaseCheckpointInfo {
	return PersistentDatabaseCheckpointInfo{
		root_dir:              database.root_dir
		catalog_path:          database_catalog_path(database.root_dir)
		catalog_exists:        os.exists(database_catalog_path(database.root_dir))
		registered_tables:     database.catalog.len
		registered_projectors: database.projectors.len
		engine:                database.engine.checkpoint_info()
	}
}

pub fn PersistentDatabase.recovery_status(root_dir string, default_branch string) !PersistentDatabaseRecoveryStatus {
	return PersistentDatabase.recovery_status_with_provider(LocalDatabaseBackendProvider.new(root_dir,
		default_branch))
}

pub fn PersistentDatabase.recovery_status_with_provider(provider LocalDatabaseBackendProvider) !PersistentDatabaseRecoveryStatus {
	return PersistentDatabaseRecoveryStatus{
		root_dir:       provider.root_dir
		catalog_path:   database_catalog_path(provider.root_dir)
		catalog_exists: os.exists(database_catalog_path(provider.root_dir))
		engine:         PersistentEngine.recovery_status_with_provider(provider)!
	}
}

fn database_status_report_from_recovery(root_dir string, default_branch string, registered_tables int, registered_projectors int, branches []string, recovery PersistentDatabaseRecoveryStatus) PersistentDatabaseStatusReport {
	node_status := recovery.engine.repository.node_store.chunk_store
	commit_status := recovery.engine.repository.commit_store.chunk_store
	data_durable := recovery.catalog_exists && recovery.engine.repository.repository_exists
		&& (recovery.engine.repository.checkpoint_journal_exists
		|| (os.exists(repository_nodes_path(root_dir))
		&& os.exists(repository_commits_path(root_dir))))
	index_snapshots_fresh := node_status.index_snapshot_valid && commit_status.index_snapshot_valid
	durable := data_durable && node_status.index_snapshot_valid
		&& commit_status.index_snapshot_valid
	return PersistentDatabaseStatusReport{
		root_dir:                                        root_dir
		default_branch:                                  default_branch
		catalog_path:                                    recovery.catalog_path
		repository_exists:                               recovery.engine.repository.repository_exists
		catalog_exists:                                  recovery.catalog_exists
		registered_tables:                               registered_tables
		registered_projectors:                           registered_projectors
		fresh_projectors:                                0
		stale_projectors:                                registered_projectors
		recommended_aggregate_projection_refresh_policy: 'stale_one'
		branch_count:                                    branches.len
		branches:                                        branches.clone()
		data_durable:                                    data_durable
		index_snapshots_fresh:                           index_snapshots_fresh
		checkpoint_journal_exists:                       recovery.engine.repository.checkpoint_journal_exists
		node_index_snapshot_pending:                     false
		commit_index_snapshot_pending:                   false
		node_index_snapshot_valid:                       node_status.index_snapshot_valid
		commit_index_snapshot_valid:                     commit_status.index_snapshot_valid
		node_index_entries:                              node_status.index_entries
		commit_index_entries:                            commit_status.index_entries
		projector_states:                                []string{}
		durable:                                         durable
	}
}

fn projector_state_summary(state AggregateProjectorState) string {
	mut summary := 'projector=${state.projection.name} fresh=${state.fresh}'
	summary += ' priority=${state.projection.priority}'
	summary += ' cost_hint=${state.projection.cost_hint}'
	summary += ' current_data_root=${state.current_data_root_cid}'
	summary += ' source_data_root=${state.source_data_root_cid}'
	summary += ' virtual_root=${if state.virtual_root_cid.len > 0 {
		state.virtual_root_cid
	} else {
		'(pending)'
	}}'
	if state.stale_reason.len > 0 {
		summary += ' stale_reason=${state.stale_reason}'
	}
	return summary
}

fn database_status_report_from_live(mut database PersistentDatabase, recovery PersistentDatabaseRecoveryStatus) PersistentDatabaseStatusReport {
	node_status := recovery.engine.repository.node_store.chunk_store
	commit_status := recovery.engine.repository.commit_store.chunk_store
	node_chunks := database.engine.repository.node_store.chunks
	commit_chunks := database.engine.repository.commit_store.chunks
	repository_exists := recovery.engine.repository.repository_exists
		|| database.engine.repository.meta_dirty
	catalog_exists := recovery.catalog_exists || database.catalog_dirty
	journal_exists := recovery.engine.repository.checkpoint_journal_exists
		|| os.exists(repository_checkpoint_journal_path(database.root_dir))
	data_durable := catalog_exists && repository_exists && !database.catalog_dirty
		&& !database.engine.repository.meta_dirty
		&& ((!node_chunks.data_dirty && !commit_chunks.data_dirty) || journal_exists)
	node_pending := node_chunks.index_dirty || node_chunks.index_snapshot_sync_pending
		|| journal_exists
	commit_pending := commit_chunks.index_dirty || commit_chunks.index_snapshot_sync_pending
		|| journal_exists
	index_snapshots_fresh := node_status.index_snapshot_valid && commit_status.index_snapshot_valid
		&& !node_pending && !commit_pending
	mut projector_states := []string{}
	mut fresh_projectors := 0
	mut stale_projectors := 0
	if database.projectors.len > 0 && database.engine.repository.has_branch(database.default_branch) {
		for state in database.projection_states_at_branch(database.default_branch) or {
			[]AggregateProjectorState{}
		} {
			projector_states << projector_state_summary(state)
			if state.fresh {
				fresh_projectors++
			} else {
				stale_projectors++
			}
		}
	}
	return PersistentDatabaseStatusReport{
		root_dir:                                        database.root_dir
		default_branch:                                  database.default_branch
		catalog_path:                                    recovery.catalog_path
		repository_exists:                               repository_exists
		catalog_exists:                                  catalog_exists
		registered_tables:                               database.catalog.len
		registered_projectors:                           database.projectors.len
		fresh_projectors:                                fresh_projectors
		stale_projectors:                                stale_projectors
		recommended_aggregate_projection_refresh_policy: 'stale_one'
		branch_count:                                    database.branch_names().len
		branches:                                        database.branch_names()
		data_durable:                                    data_durable
		index_snapshots_fresh:                           index_snapshots_fresh
		checkpoint_journal_exists:                       journal_exists
		node_index_snapshot_pending:                     node_pending
		commit_index_snapshot_pending:                   commit_pending
		node_index_snapshot_valid:                       node_status.index_snapshot_valid
		commit_index_snapshot_valid:                     commit_status.index_snapshot_valid
		node_index_entries:                              node_status.index_entries
		commit_index_entries:                            commit_status.index_entries
		projector_states:                                projector_states
		durable:                                         data_durable && index_snapshots_fresh
	}
}

pub fn (mut database PersistentDatabase) status_report() !PersistentDatabaseStatusReport {
	recovery := PersistentDatabase.recovery_status(database.root_dir, database.default_branch)!
	return database_status_report_from_live(mut database, recovery)
}

pub fn PersistentDatabase.inspect(root_dir string, default_branch string) !PersistentDatabaseStatusReport {
	return PersistentDatabase.inspect_with_provider(LocalDatabaseBackendProvider.new(root_dir,
		default_branch))
}

pub fn PersistentDatabase.inspect_with_provider(provider LocalDatabaseBackendProvider) !PersistentDatabaseStatusReport {
	recovery := PersistentDatabase.recovery_status_with_provider(provider)!
	catalog, projectors, _ := load_database_catalog(provider.root_dir) or {
		map[string]TypedTableSpec{}, map[string]AggregateProjectionDef{}, map[string]MemoryCapabilityDef{}
	}
	mut branches := []string{}
	if recovery.engine.repository.repository_exists {
		mut opened := PersistentRepository.open_default(provider.root_dir, provider.default_branch()) or {
			return database_status_report_from_recovery(provider.root_dir, provider.default_branch(),
				catalog.len, projectors.len, branches, recovery)
		}
		defer {
			opened.close() or {}
		}
		branches = opened.branch_names()
	}
	return database_status_report_from_recovery(provider.root_dir, provider.default_branch(),
		catalog.len, projectors.len, branches, recovery)
}

pub fn (mut database PersistentDatabase) head() !Branch {
	return database.engine.head()
}

pub fn (mut database PersistentDatabase) branch(name string) !Branch {
	return database.engine.branch(name)
}

pub fn (mut database PersistentDatabase) branch_names() []string {
	return database.engine.branch_names()
}

pub fn (mut database PersistentDatabase) create_branch(name string, from_commit_cid string) !Branch {
	return database.engine.create_branch(name, from_commit_cid)
}

pub fn (mut database PersistentDatabase) merge_base_branch(left_branch string, right_branch string) !Commit {
	return database.engine.merge_base_branch(left_branch, right_branch)
}

pub fn (mut database PersistentDatabase) merge_branches(ours_branch string, theirs_branch string, cfg ChunkConfig) !MergeResult {
	return database.engine.merge_branches(ours_branch, theirs_branch, cfg)
}

pub fn (mut database PersistentDatabase) auto_merge_by_roots(base_root_cid string, ours_root_cid string, theirs_root_cid string, cfg ChunkConfig) !MergeResult {
	return auto_merge_by_roots(base_root_cid, ours_root_cid, theirs_root_cid, cfg, mut
		database.engine.repository.node_store)
}

pub fn (mut database PersistentDatabase) merge_branch_into(ours_branch string, theirs_branch string, resolutions []ConflictResolution, cfg ChunkConfig, meta CommitMeta) !BranchUpdate {
	return database.engine.merge_branch_into(ours_branch, theirs_branch, resolutions,
		cfg, meta)
}

pub fn (mut database PersistentDatabase) preview_merge(ours_branch string, theirs_branch string, cfg ChunkConfig) !RootHashMergePreview {
	base := database.engine.merge_base_branch(ours_branch, theirs_branch)!
	ours := database.engine.checkout(ours_branch)!
	theirs := database.engine.checkout(theirs_branch)!
	result := database.engine.merge_branches(ours_branch, theirs_branch, cfg)!
	return RootHashMergePreview{
		ours_branch:       ours_branch
		theirs_branch:     theirs_branch
		base_commit_cid:   base.cid
		base_root_cid:     base.root_cid
		ours_commit_cid:   ours.cid
		ours_root_cid:     ours.root_cid
		theirs_commit_cid: theirs.cid
		theirs_root_cid:   theirs.root_cid
		conflicts:         result.conflicts.len
		changed_keys:      result.changed_keys.len
		changed_subtrees:  result.changed_subtrees.len
		fast_forward:      base.cid == ours.cid || base.cid == theirs.cid
		ours_unchanged:    base.root_cid == ours.root_cid
		theirs_unchanged:  base.root_cid == theirs.root_cid
	}
}

pub fn (mut database PersistentDatabase) merge_report(ours_branch string, theirs_branch string, cfg ChunkConfig, conflict_limit int) !RootHashMergeReport {
	base := database.engine.merge_base_branch(ours_branch, theirs_branch)!
	ours := database.engine.checkout(ours_branch)!
	theirs := database.engine.checkout(theirs_branch)!
	result := database.engine.merge_branches(ours_branch, theirs_branch, cfg)!
	preview := RootHashMergePreview{
		ours_branch:       ours_branch
		theirs_branch:     theirs_branch
		base_commit_cid:   base.cid
		base_root_cid:     base.root_cid
		ours_commit_cid:   ours.cid
		ours_root_cid:     ours.root_cid
		theirs_commit_cid: theirs.cid
		theirs_root_cid:   theirs.root_cid
		conflicts:         result.conflicts.len
		changed_keys:      result.changed_keys.len
		changed_subtrees:  result.changed_subtrees.len
		fast_forward:      base.cid == ours.cid || base.cid == theirs.cid
		ours_unchanged:    base.root_cid == ours.root_cid
		theirs_unchanged:  base.root_cid == theirs.root_cid
	}
	return RootHashMergeReport{
		preview:        preview
		table_stats:    build_merge_table_stats(result.changed_keys, result.conflicts)
		conflict_keys:  enrich_merge_conflict_preview(database, build_merge_conflict_preview(result.conflicts,
			conflict_limit), result.conflicts, database.catalog)
		conflict_limit: if conflict_limit > 0 { conflict_limit } else { result.conflicts.len }
	}
}

pub fn (mut database PersistentDatabase) commit_to_branch(branch_name string, tree Tree, meta CommitMeta) !BranchUpdate {
	return database.engine.commit_to_branch(branch_name, tree, meta)
}

pub fn (mut database PersistentDatabase) tree_at_branch(branch_name string) !Tree {
	return database.engine.tree_at_branch(branch_name)
}

pub fn (mut database PersistentDatabase) checkout(branch_name string) !Commit {
	return database.engine.checkout(branch_name)
}

pub fn (mut database PersistentDatabase) branch_log(branch_name string, limit int) ![]Commit {
	return database.engine.branch_log(branch_name, limit)
}

pub fn (mut database PersistentDatabase) register_table(spec TypedTableSpec) ! {
	if spec.name() in database.catalog {
		return error('typed table already registered: ${spec.name()}')
	}
	database.catalog[spec.name()] = spec
	database.catalog_dirty = true
	database.persist_catalog()!
	ensure_fts_sidecar_for_specs(mut database, [spec])!
}

pub fn (mut database PersistentDatabase) register_or_update_table(spec TypedTableSpec) !bool {
	existing := database.catalog[spec.name()] or {
		database.catalog[spec.name()] = spec
		database.catalog_dirty = true
		database.persist_catalog()!
		return true
	}
	if !typed_table_schema_compatible(existing, spec) {
		return error('typed table schema mismatch: ${spec.name()}')
	}
	merged_indexes := merge_schema_indexes(existing.indexes, spec.indexes)
	if merged_indexes.len == existing.indexes.len {
		return false
	}
	database.catalog[spec.name()] = TypedTableSpec.new(existing.table, merged_indexes)!
	database.catalog_dirty = true
	database.persist_catalog()!
	ensure_fts_sidecar_for_specs(mut database, [database.catalog[spec.name()] or { spec }])!
	return true
}

pub fn (mut database PersistentDatabase) rebuild_indexes_at_branch(branch_name string, table_names []string, cfg ChunkConfig) !BranchUpdate {
	tree := database.tree_at_branch(branch_name)!
	next_tree := rebuild_typed_indexes_for_tables(tree, database.registered_specs(), table_names,
		cfg)!
	update := database.commit_to_branch(branch_name, next_tree, CommitMeta{
		author:    'pollydb'
		message:   if table_names.len > 0 {
			'rebuild indexes for ${table_names.join(',')}'
		} else {
			'rebuild indexes'
		}
		timestamp: 0
	})!
	database.rebuild_fts_indexes_at_branch(branch_name, table_names)!
	return update
}

pub fn (mut database PersistentDatabase) register_aggregate_projection(def AggregateProjectionDef) ! {
	if def.name in database.projectors {
		return error('aggregate projection already registered: ${def.name}')
	}
	spec := database.catalog[def.table_name] or {
		return error('aggregate projection table not registered: ${def.table_name}')
	}
	column := spec.table.column(def.column_name)!
	if def.aggregate != .sum {
		return error('unsupported aggregate projection type for ${def.name}')
	}
	if def.is_field_projection_selector() {
		if column.typ != .markdown_ {
			return error('aggregate projection markdown selector requires markdown column: ${def.column_name}')
		}
		validate_field_projection_selector(column, def.field_projection_selector())!
		if def.source_json_path.len > 0 {
			return error('aggregate projection cannot combine json path and markdown selector: ${def.name}')
		}
	} else if def.source_json_path.len == 0 && column.typ != .i64_ {
		return error('aggregate projection column must be i64: ${def.column_name}')
	}
	database.projectors[def.name] = def
	database.catalog_dirty = true
	database.persist_catalog()!
}

pub fn (mut database PersistentDatabase) register_memory_capability(def MemoryCapabilityDef) ! {
	spec := database.catalog[def.table_name] or {
		return error('memory capability table not registered: ${def.table_name}')
	}
	if !spec.table.has_column(def.column_name) {
		return error('memory capability column not in table: ${def.column_name}')
	}
	if def.options.embedding_index.len > 0 {
		mut found := false
		for index in spec.indexes {
			if index.name != def.options.embedding_index {
				continue
			}
			if !index.is_embedding() {
				return error('memory capability embedding_index is not an embedding index: ${def.options.embedding_index}')
			}
			if index.column != def.column_name {
				return error('memory capability embedding_index must target the same column: ${def.options.embedding_index}')
			}
			found = true
			break
		}
		if !found {
			return error('memory capability embedding_index not found on table: ${def.options.embedding_index}')
		}
	}
	key := memory_capability_key(def.table_name, def.column_name)
	if key in database.memory_capabilities {
		return error('memory capability already registered: ${def.table_name}.${def.column_name}')
	}
	database.memory_capabilities[key] = def
	database.catalog_dirty = true
	database.persist_catalog()!
}

pub fn (database PersistentDatabase) memory_capabilities_for_table(table_name string) []MemoryCapabilityDef {
	mut out := []MemoryCapabilityDef{}
	for key in sorted_memory_capability_keys(database.memory_capabilities) {
		capability := database.memory_capabilities[key] or { continue }
		if capability.table_name == table_name {
			out << capability
		}
	}
	return out
}

pub fn (database PersistentDatabase) memory_capability(table_name string, column_name string) ?MemoryCapabilityDef {
	key := memory_capability_key(table_name, column_name)
	return database.memory_capabilities[key]
}

pub fn (database PersistentDatabase) has_table(name string) bool {
	return name in database.catalog
}

pub fn (database PersistentDatabase) table_names() []string {
	return sorted_catalog_names(database.catalog)
}

pub fn (database PersistentDatabase) table_spec(name string) !TypedTableSpec {
	spec := database.catalog[name] or { return error('typed table not registered: ${name}') }
	return spec
}

pub fn (database PersistentDatabase) aggregate_projectors() map[string]AggregateProjectionDef {
	return database.projectors.clone()
}

pub fn (database PersistentDatabase) projector_names() []string {
	return sorted_projector_names(database.projectors)
}

pub fn (database PersistentDatabase) projector_spec(name string) !AggregateProjectionDef {
	projector := database.projectors[name] or {
		return error('aggregate projection not registered: ${name}')
	}
	return projector
}

fn typed_table_schema_compatible(existing TypedTableSpec, incoming TypedTableSpec) bool {
	if existing.table.name != incoming.table.name {
		return false
	}
	if existing.table.primary_key != incoming.table.primary_key {
		return false
	}
	if existing.table.columns.len != incoming.table.columns.len {
		return false
	}
	for idx, column in existing.table.columns {
		other := incoming.table.columns[idx]
		if column.name != other.name || column.typ != other.typ || column.nullable != other.nullable
			|| column.aggregate != other.aggregate || column.enum_values != other.enum_values
			|| column.default_current_timestamp != other.default_current_timestamp
			|| column.auto_update_current_timestamp != other.auto_update_current_timestamp {
			return false
		}
	}
	return true
}

fn merge_schema_indexes(existing []SchemaIndexDef, incoming []SchemaIndexDef) []SchemaIndexDef {
	mut merged := existing.clone()
	mut seen := map[string]bool{}
	for index in existing {
		seen[index_signature(index)] = true
	}
	for index in incoming {
		signature := index_signature(index)
		if seen[signature] {
			continue
		}
		merged << index
		seen[signature] = true
	}
	return merged
}

fn index_signature(index SchemaIndexDef) string {
	return [
		index.name,
		index.column,
		index.json_field,
		index.markdown_selector,
		index.fts_source_plugin,
		index.fts_text_mode,
		index.fts_tokenizer,
		'prefix:${index.fts_prefix_lengths.map(it.str()).join(',')}',
		'typ:${index.json_field_type.str()}',
		'stores:${index.stores_row}',
	].join('|')
}

pub fn (mut database PersistentDatabase) projection_states_at_branch(branch_name string) ![]AggregateProjectorState {
	commit := database.engine.checkout(branch_name)!
	mut existing := map[string]VirtualRootRef{}
	for virtual_root in commit.virtual_roots {
		existing[virtual_root.name] = virtual_root
	}
	mut states := []AggregateProjectorState{cap: database.projectors.len}
	for name in sorted_projector_names_by_priority(database.projectors) {
		projector := database.projectors[name] or { continue }
		virtual_root := existing[name] or {
			VirtualRootRef{
				name:                 projector.name
				root_cid:             ''
				source_data_root_cid: commit.root_cid
				fresh:                false
				stale_reason:         'registration_backfill'
			}
		}
		stale_reason := if virtual_root.fresh {
			''
		} else if virtual_root.stale_reason.len > 0 {
			virtual_root.stale_reason
		} else if virtual_root.source_data_root_cid != commit.root_cid {
			'new_data_root'
		} else if virtual_root.root_cid.len == 0 {
			'registration_backfill'
		} else {
			'policy_budget_skipped'
		}
		states << AggregateProjectorState{
			projection:            projector
			current_data_root_cid: commit.root_cid
			source_data_root_cid:  virtual_root.source_data_root_cid
			virtual_root_cid:      virtual_root.root_cid
			fresh:                 virtual_root.fresh
			stale_reason:          stale_reason
		}
	}
	return states
}

pub fn (mut database PersistentDatabase) stale_projection_states_at_branch(branch_name string, limit int) ![]AggregateProjectorState {
	mut states := []AggregateProjectorState{}
	for state in database.projection_states_at_branch(branch_name)! {
		if state.fresh {
			continue
		}
		states << state
		if limit > 0 && states.len >= limit {
			break
		}
	}
	return states
}

pub fn (mut database PersistentDatabase) has_stale_projections_at_branch(branch_name string) !bool {
	for state in database.projection_states_at_branch(branch_name)! {
		if !state.fresh {
			return true
		}
	}
	return false
}

fn (options GroupCommitOptions) aggregate_projection_refresh_limit() int {
	return match options.aggregate_projection_refresh_policy {
		.none {
			-1
		}
		.stale_one {
			1
		}
		.stale_up_to {
			if options.max_aggregate_projection_refreshes > 0 {
				options.max_aggregate_projection_refreshes
			} else {
				1
			}
		}
		.stale_all {
			0
		}
	}
}

pub fn (database PersistentDatabase) snapshot_read_scheduler() SnapshotReadScheduler {
	return SnapshotReadScheduler.new(database.backend_provider())
}

pub fn (database PersistentDatabase) registered_specs() []TypedTableSpec {
	mut specs := []TypedTableSpec{}
	for name in sorted_catalog_names(database.catalog) {
		spec := database.catalog[name] or { continue }
		specs << spec
	}
	return specs
}

fn (mut database PersistentDatabase) virtual_roots_for_new_data_root(branch_name string, new_root_cid string) []VirtualRootRef {
	if database.projectors.len == 0 {
		return []VirtualRootRef{}
	}
	mut previous_roots := map[string]VirtualRootRef{}
	previous_commit := database.engine.checkout(branch_name) or { Commit{} }
	mut refs := []VirtualRootRef{}
	for virtual_root in previous_commit.virtual_roots {
		previous_roots[virtual_root.name] = virtual_root
		if virtual_root.name !in database.projectors {
			refs << virtual_root
		}
	}
	for name in sorted_projector_names_by_priority(database.projectors) {
		projector := database.projectors[name] or { continue }
		previous := previous_roots[name] or {
			VirtualRootRef{
				name:                 projector.name
				root_cid:             ''
				source_data_root_cid: previous_commit.root_cid
				fresh:                false
				stale_reason:         'registration_backfill'
			}
		}
		refs << VirtualRootRef{
			name:                 projector.name
			root_cid:             previous.root_cid
			source_data_root_cid: new_root_cid
			fresh:                false
			stale_reason:         if previous.root_cid.len == 0 {
				'registration_backfill'
			} else {
				'new_data_root'
			}
		}
	}
	return refs
}

pub fn SessionOptions.for_branch(branch_name string) SessionOptions {
	return SessionOptions{
		branch_name: branch_name
	}
}

pub fn (database PersistentDatabase) begin_session(options SessionOptions) !DatabaseSession {
	if options.branch_name.len == 0 {
		return error('session branch name cannot be empty')
	}
	return DatabaseSession{
		root_dir:    database.root_dir
		branch_name: options.branch_name
		specs:       database.registered_specs()
	}
}

pub fn (database PersistentDatabase) open_session(branch_name string) !DatabaseSession {
	return database.begin_session(SessionOptions.for_branch(branch_name))
}

pub fn (database PersistentDatabase) begin_default_session() !DatabaseSession {
	return database.begin_session(SessionOptions.for_branch(database.default_branch))
}

pub fn (mut database PersistentDatabase) begin_group_commit_session(options SessionOptions, group GroupCommitOptions) !GroupCommitSession {
	if options.branch_name.len == 0 {
		return error('session branch name cannot be empty')
	}
	return GroupCommitSession{
		branch_name:               options.branch_name
		specs:                     database.registered_specs()
		options:                   GroupCommitOptions{
			checkpoint_every:                    if group.checkpoint_every > 0 {
				group.checkpoint_every
			} else {
				1
			}
			checkpoint_mode:                     group.checkpoint_mode
			auto_refresh_index_snapshots:        group.auto_refresh_index_snapshots
			aggregate_projection_refresh_policy: group.aggregate_projection_refresh_policy
			max_aggregate_projection_refreshes:  group.max_aggregate_projection_refreshes
		}
		working_set:               database.begin_working_set_with_specs(options.branch_name,
			database.registered_specs())!
		last_meta:                 CommitMeta{}
		refresh_handles:           []IndexSnapshotRefreshHandle{}
		aggregate_refresh_handles: []AggregateProjectionRefreshHandle{}
	}
}

pub fn (mut database PersistentDatabase) begin_default_group_commit_session(group GroupCommitOptions) !GroupCommitSession {
	return database.begin_group_commit_session(SessionOptions.for_branch(database.default_branch),
		group)
}

pub fn (mut database PersistentDatabase) begin_high_throughput_group_commit_session(options SessionOptions) !GroupCommitSession {
	return database.begin_group_commit_session(options, GroupCommitOptions.high_throughput())
}

pub fn (mut database PersistentDatabase) begin_default_high_throughput_group_commit_session() !GroupCommitSession {
	return database.begin_default_group_commit_session(GroupCommitOptions.high_throughput())
}

pub fn (mut database PersistentDatabase) begin_split_group_commit_session(options SessionOptions, group GroupCommitOptions, cfg ChunkConfig) !SplitGroupCommitSession {
	if options.branch_name.len == 0 {
		return error('session branch name cannot be empty')
	}
	return SplitGroupCommitSession{
		branch_name:               options.branch_name
		specs:                     database.registered_specs()
		options:                   GroupCommitOptions{
			checkpoint_every:                    if group.checkpoint_every > 0 {
				group.checkpoint_every
			} else {
				1
			}
			checkpoint_mode:                     group.checkpoint_mode
			auto_refresh_index_snapshots:        group.auto_refresh_index_snapshots
			aggregate_projection_refresh_policy: group.aggregate_projection_refresh_policy
			max_aggregate_projection_refreshes:  group.max_aggregate_projection_refreshes
		}
		working_set:               database.begin_split_working_set_with_specs(options.branch_name,
			database.registered_specs(), cfg)!
		last_meta:                 CommitMeta{}
		last_cfg:                  cfg
		refresh_handles:           []IndexSnapshotRefreshHandle{}
		aggregate_refresh_handles: []AggregateProjectionRefreshHandle{}
	}
}

pub fn (mut database PersistentDatabase) begin_default_split_group_commit_session(group GroupCommitOptions, cfg ChunkConfig) !SplitGroupCommitSession {
	return database.begin_split_group_commit_session(SessionOptions.for_branch(database.default_branch),
		group, cfg)
}

pub fn (mut database PersistentDatabase) begin_split_high_throughput_group_commit_session(options SessionOptions, cfg ChunkConfig) !SplitGroupCommitSession {
	return database.begin_split_group_commit_session(options, GroupCommitOptions.high_throughput(),
		cfg)
}

pub fn (mut database PersistentDatabase) begin_default_split_high_throughput_group_commit_session(cfg ChunkConfig) !SplitGroupCommitSession {
	return database.begin_default_split_group_commit_session(GroupCommitOptions.high_throughput(),
		cfg)
}

pub fn (mut database PersistentDatabase) begin_transaction_with_specs(branch_name string, specs []TypedTableSpec) !TypedTransaction {
	return database.engine.typed_transaction_at_branch(branch_name, specs)
}

pub fn (mut database PersistentDatabase) begin_transaction_profiled(branch_name string) !PersistentDatabaseTypedTransactionOpenResult {
	result := database.engine.typed_transaction_at_branch_profiled(branch_name, database.registered_specs())!
	return PersistentDatabaseTypedTransactionOpenResult{
		tx:      result.tx
		timings: result.timings
	}
}

pub fn (mut database PersistentDatabase) begin_transaction(branch_name string) !TypedTransaction {
	return database.begin_transaction_with_specs(branch_name, database.registered_specs())
}

pub fn (mut database PersistentDatabase) begin_working_set_with_specs(branch_name string, specs []TypedTableSpec) !TypedWorkingSet {
	return database.engine.typed_working_set_at_branch(branch_name, specs)
}

pub fn (mut database PersistentDatabase) begin_working_set(branch_name string) !TypedWorkingSet {
	return database.begin_working_set_with_specs(branch_name, database.registered_specs())
}

pub fn (mut database PersistentDatabase) begin_split_working_set_with_specs(branch_name string, specs []TypedTableSpec, cfg ChunkConfig) !TypedSplitWorkingSet {
	return database.engine.typed_split_working_set_at_branch(branch_name, specs, cfg)
}

pub fn (mut database PersistentDatabase) begin_split_working_set(branch_name string, cfg ChunkConfig) !TypedSplitWorkingSet {
	return database.begin_split_working_set_with_specs(branch_name, database.registered_specs(),
		cfg)
}

pub fn (mut database PersistentDatabase) apply_typed_write_set_with_specs(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	if cfg.enable_split_backed_working_set {
		split_result := database.apply_typed_write_set_split_backed_with_specs(branch_name,
			specs, write_set, cfg, meta)!
		return BranchTypedTransactionResult{
			update:             split_result.update
			transaction_update: split_result.transaction_update
			timings:            BranchTypedTransactionTimings{}
		}
	}
	vector_progress('typed write begin ops=${write_set.len()} specs=${specs.len}')
	tx := database.engine.typed_transaction_at_branch(branch_name, specs)!
	base_tree := tx.current_tree()
	normalized_write_set := normalize_temporal_write_set(tx, write_set)!
	vector_progress('typed write apply ops=${normalized_write_set.len()}')
	transaction_update := tx.apply_write_set(normalized_write_set, cfg)!
	vector_progress('typed write index normalize ops=${normalized_write_set.len()}')
	normalized_tree := if typed_write_set_requires_scan_reindex(specs, normalized_write_set) {
		vector_progress('typed write scan reindex fallback ops=${normalized_write_set.len()}')
		changed_rows := collect_changed_typed_rows_exact(specs, base_tree, transaction_update.tx.current_tree())!
		normalized, _ := rebuild_persistent_typed_indexes_for_changed_rows(database.root_dir,
			transaction_update.tx.current_tree(), specs, changed_rows, cfg)!
		normalized
	} else {
		vector_progress('typed write targeted reindex ops=${normalized_write_set.len()}')
		index_mutations := persistent_typed_index_mutations_for_write_set(database.root_dir,
			base_tree, transaction_update.tx.current_tree(), specs, normalized_write_set)!
		transaction_update.tx.current_tree().apply_mutations(index_mutations, cfg)!.tree
	}
	vector_progress('typed write commit ops=${normalized_write_set.len()}')
	virtual_roots := database.virtual_roots_for_new_data_root(branch_name, normalized_tree.root.cid)
	update := database.engine.commit_to_branch_with_virtual_roots(branch_name, normalized_tree,
		meta, virtual_roots)!
	vector_progress('typed write fts ops=${normalized_write_set.len()}')
	database.apply_fts_write_set(branch_name, specs, normalized_write_set)!
	vector_progress('typed write done ops=${normalized_write_set.len()}')
	return BranchTypedTransactionResult{
		update:             update
		transaction_update: TypedTransactionResult{
			tx:   new_typed_transaction_with_specs(normalized_tree, specs)!
			diff: base_tree.diff(normalized_tree)
		}
		timings:            BranchTypedTransactionTimings{}
	}
}

pub fn (mut database PersistentDatabase) apply_typed_write_set(branch_name string, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	return database.apply_typed_write_set_with_specs(branch_name, database.registered_specs(),
		write_set, cfg, meta)
}

pub fn (mut database PersistentDatabase) apply_typed_write_set_split_backed_with_specs(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedWorkingSetResult {
	mut set := database.begin_split_working_set_with_specs(branch_name, specs, cfg)!
	normalized_write_set := normalize_temporal_split_write_set(set.transaction(), write_set)!
	_ = set.apply_write_set(normalized_write_set, cfg)!
	result := database.commit_typed_split_working_set(mut set, meta, cfg)!
	database.apply_fts_write_set(branch_name, specs, normalized_write_set)!
	return result
}

pub fn (mut database PersistentDatabase) apply_typed_write_set_split_backed(branch_name string, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedWorkingSetResult {
	return database.apply_typed_write_set_split_backed_with_specs(branch_name, database.registered_specs(),
		write_set, cfg, meta)
}

pub fn (mut database PersistentDatabase) apply_typed_write_set_buffered_with_specs(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	if cfg.enable_split_backed_working_set {
		split_result := database.apply_typed_write_set_split_backed_with_specs(branch_name,
			specs, write_set, cfg, meta)!
		return BranchTypedTransactionResult{
			update:             split_result.update
			transaction_update: split_result.transaction_update
			timings:            BranchTypedTransactionTimings{}
		}
	}
	vector_progress('typed write buffered begin ops=${write_set.len()} specs=${specs.len}')
	tx := database.engine.typed_transaction_at_branch(branch_name, specs)!
	base_tree := tx.current_tree()
	normalized_write_set := normalize_temporal_write_set(tx, write_set)!
	vector_progress('typed write buffered apply ops=${normalized_write_set.len()}')
	transaction_update := tx.apply_write_set(normalized_write_set, cfg)!
	vector_progress('typed write buffered index normalize ops=${normalized_write_set.len()}')
	normalized_tree := if typed_write_set_requires_scan_reindex(specs, normalized_write_set) {
		vector_progress('typed write buffered scan reindex fallback ops=${normalized_write_set.len()}')
		changed_rows := collect_changed_typed_rows_exact(specs, base_tree, transaction_update.tx.current_tree())!
		normalized, _ := rebuild_persistent_typed_indexes_for_changed_rows(database.root_dir,
			transaction_update.tx.current_tree(), specs, changed_rows, cfg)!
		normalized
	} else {
		vector_progress('typed write buffered targeted reindex ops=${normalized_write_set.len()}')
		index_mutations := persistent_typed_index_mutations_for_write_set(database.root_dir,
			base_tree, transaction_update.tx.current_tree(), specs, normalized_write_set)!
		transaction_update.tx.current_tree().apply_mutations(index_mutations, cfg)!.tree
	}
	vector_progress('typed write buffered commit ops=${normalized_write_set.len()}')
	virtual_roots := database.virtual_roots_for_new_data_root(branch_name, normalized_tree.root.cid)
	update := database.engine.commit_to_branch_with_virtual_roots(branch_name, normalized_tree,
		meta, virtual_roots)!
	vector_progress('typed write buffered fts ops=${normalized_write_set.len()}')
	database.apply_fts_write_set(branch_name, specs, normalized_write_set)!
	vector_progress('typed write buffered done ops=${normalized_write_set.len()}')
	return BranchTypedTransactionResult{
		update:             update
		transaction_update: TypedTransactionResult{
			tx:   new_typed_transaction_with_specs(normalized_tree, specs)!
			diff: base_tree.diff(normalized_tree)
		}
		timings:            BranchTypedTransactionTimings{}
	}
}

pub fn (mut database PersistentDatabase) apply_typed_write_set_buffered(branch_name string, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	return database.apply_typed_write_set_buffered_with_specs(branch_name, database.registered_specs(),
		write_set, cfg, meta)
}

pub fn (mut database PersistentDatabase) commit_typed_working_set(mut set TypedWorkingSet, meta CommitMeta) !BranchTypedWorkingSetResult {
	changed_rows := collect_changed_typed_rows_exact(set.specs, set.base_tree, set.transaction().current_tree())!
	normalized_tree, _ := rebuild_persistent_typed_indexes_for_changed_rows(database.root_dir,
		set.transaction().current_tree(), set.specs, changed_rows, ChunkConfig.default())!
	set.replace_working_tree(normalized_tree)!
	diff := set.staged_diff()
	virtual_roots := database.virtual_roots_for_new_data_root(set.branch_name, normalized_tree.root.cid)
	update := database.engine.commit_to_branch_with_virtual_roots(set.branch_name, normalized_tree,
		meta, virtual_roots)!
	set.sync_to_tree(update.snapshot.tree, update.snapshot.commit.cid)!
	return BranchTypedWorkingSetResult{
		update:             update
		transaction_update: TypedTransactionResult{
			tx:   set.transaction()
			diff: diff
		}
	}
}

pub fn (mut database PersistentDatabase) commit_typed_split_working_set(mut set TypedSplitWorkingSet, meta CommitMeta, cfg ChunkConfig) !BranchTypedWorkingSetResult {
	return database.commit_typed_split_working_set_mode(mut set, meta, cfg, true)
}

fn (mut database PersistentDatabase) commit_typed_split_working_set_mode(mut set TypedSplitWorkingSet, meta CommitMeta, cfg ChunkConfig, sync_back bool) !BranchTypedWorkingSetResult {
	mixed_tree := set.current_tree(cfg)!
	mut mixed_tx := new_typed_transaction_with_specs(mixed_tree, set.specs)!
	diff := set.base_tree.diff(mixed_tree)
	virtual_roots := database.virtual_roots_for_new_data_root(set.branch_name, mixed_tree.root.cid)
	update := database.engine.commit_to_branch_with_virtual_roots(set.branch_name, mixed_tree,
		meta, virtual_roots)!
	if sync_back {
		set.sync_to_tree(update.snapshot.tree, update.snapshot.commit.cid, cfg)!
	}
	mixed_tx = new_typed_transaction_with_specs(update.snapshot.tree, set.specs)!
	return BranchTypedWorkingSetResult{
		update:             update
		transaction_update: TypedTransactionResult{
			tx:   mixed_tx
			diff: diff
		}
	}
}

pub fn (mut database PersistentDatabase) commit_typed_working_set_buffered(mut set TypedWorkingSet, meta CommitMeta) !BranchTypedWorkingSetResult {
	changed_rows := collect_changed_typed_rows_exact(set.specs, set.base_tree, set.transaction().current_tree())!
	normalized_tree, _ := rebuild_persistent_typed_indexes_for_changed_rows(database.root_dir,
		set.transaction().current_tree(), set.specs, changed_rows, ChunkConfig.default())!
	set.replace_working_tree(normalized_tree)!
	diff := set.staged_diff()
	virtual_roots := database.virtual_roots_for_new_data_root(set.branch_name, normalized_tree.root.cid)
	update := database.engine.commit_to_branch_with_virtual_roots(set.branch_name, normalized_tree,
		meta, virtual_roots)!
	set.sync_to_tree(update.snapshot.tree, update.snapshot.commit.cid)!
	return BranchTypedWorkingSetResult{
		update:             update
		transaction_update: TypedTransactionResult{
			tx:   set.transaction()
			diff: diff
		}
	}
}

pub fn (mut database PersistentDatabase) merge_into_working_set(mut set TypedWorkingSet, theirs_branch string, resolutions []ConflictResolution, cfg ChunkConfig) !WorkingSetMergeResult {
	base_commit := database.engine.repository.repo.merge_base_commit(set.base_commit_cid,
		(database.engine.repository.repo.branch(theirs_branch)!).commit_cid, mut database.engine.repository.commit_store)!
	ours_commit := database.engine.repository.commit_store.get(set.base_commit_cid)!
	theirs_commit := database.engine.repository.repo.checkout(theirs_branch, mut database.engine.repository.commit_store)!
	base_tree := Tree.load(base_commit.root_cid, mut database.engine.repository.node_store)!
	ours_tree := set.transaction().current_tree()
	theirs_tree := Tree.load(theirs_commit.root_cid, mut database.engine.repository.node_store)!
	merge_progress_log('   -> merge stage: three_way_merge')
	mut merge_sw := time.new_stopwatch()
	merge_result := three_way_merge(base_commit, ours_commit, theirs_commit, base_tree,
		ours_tree, theirs_tree, cfg)!
	merge_ms := merge_sw.elapsed().milliseconds()
	merge_progress_log('   -> merge stage done: three_way_merge (${merge_ms} ms, changed_keys=${merge_result.changed_keys.len}, changed_subtrees=${merge_result.changed_subtrees.len}, conflicts=${merge_result.conflicts.len})')
	auto_resolutions := auto_resolve_typed_row_conflicts(mut database, merge_result.conflicts,
		set.specs)
	merge_progress_log('   -> merge stage: resolve_conflicts')
	mut resolve_sw := time.new_stopwatch()
	mut combined_resolutions := auto_resolutions.clone()
	combined_resolutions << resolutions
	resolution := merge_result.resolve_conflicts(combined_resolutions, cfg)!
	resolve_ms := resolve_sw.elapsed().milliseconds()
	merge_progress_log('   -> merge stage done: resolve_conflicts (${resolve_ms} ms, resolved_keys=${resolution.resolved_keys.len})')
	merge_progress_log('   -> merge stage: exact_changed_rows')
	mut changed_rows_sw := time.new_stopwatch()
	changed_rows := collect_changed_typed_rows_exact(set.specs, base_tree, resolution.tree)!
	changed_rows_ms := changed_rows_sw.elapsed().milliseconds()
	mut changed_row_count := 0
	for _, table_rows in changed_rows {
		changed_row_count += table_rows.len
	}
	merge_progress_log('   -> merge stage done: exact_changed_rows (${changed_rows_ms} ms, tables=${changed_rows.len}, rows=${changed_row_count})')
	merge_progress_log('   -> merge stage: reindex')
	mut reindex_sw := time.new_stopwatch()
	normalized_tree, reindex_timings := rebuild_persistent_typed_indexes_for_changed_rows(database.root_dir,
		resolution.tree, set.specs, changed_rows, cfg)!
	reindex_ms := reindex_sw.elapsed().milliseconds()
	merge_progress_log('   -> merge stage done: reindex (${reindex_ms} ms, strategy=${reindex_timings.strategy}, items=${reindex_timings.item_count}, changed_rows=${reindex_timings.changed_rows})')
	set.replace_working_tree(normalized_tree)!
	return WorkingSetMergeResult{
		merge_result: merge_result
		resolution:   MergeResolution{
			tree:          normalized_tree
			resolved_keys: resolution.resolved_keys.clone()
		}
		staged_diff:  set.staged_diff()
		timings:      MergeStageTimings{
			merge_ms:        merge_ms
			resolve_ms:      resolve_ms
			changed_rows_ms: changed_rows_ms
			reindex_ms:      reindex_ms
			reindex:         reindex_timings
		}
	}
}

pub fn (session DatabaseSession) table_names() []string {
	mut names := []string{cap: session.specs.len}
	for spec in session.specs {
		names << spec.name()
	}
	return names
}

pub fn (session DatabaseSession) table_spec(name string) !TypedTableSpec {
	for spec in session.specs {
		if spec.name() == name {
			return spec
		}
	}
	return error('typed table not registered: ${name}')
}

pub fn (session TransactionSession) table_spec(name string) !TypedTableSpec {
	return session.working_set.transaction().table_spec(name)
}

pub fn (session DatabaseSession) begin_transaction(mut database PersistentDatabase) !TypedTransaction {
	return database.begin_transaction_with_specs(session.branch_name, session.specs)
}

pub fn (session DatabaseSession) begin_transaction_profiled(mut database PersistentDatabase) !PersistentDatabaseTypedTransactionOpenResult {
	result := database.engine.typed_transaction_at_branch_profiled(session.branch_name,
		session.specs)!
	return PersistentDatabaseTypedTransactionOpenResult{
		tx:      result.tx
		timings: result.timings
	}
}

pub fn (session DatabaseSession) begin_working_set(mut database PersistentDatabase) !TransactionSession {
	return TransactionSession{
		root_dir:    session.root_dir
		branch_name: session.branch_name
		specs:       session.specs.clone()
		working_set: database.begin_working_set_with_specs(session.branch_name, session.specs)!
	}
}

pub fn (session DatabaseSession) begin_split_working_set(mut database PersistentDatabase, cfg ChunkConfig) !TypedSplitWorkingSet {
	return database.begin_split_working_set_with_specs(session.branch_name, session.specs,
		cfg)
}

pub fn (session DatabaseSession) begin_group_commit(mut database PersistentDatabase, group GroupCommitOptions) !GroupCommitSession {
	return database.begin_group_commit_session(SessionOptions.for_branch(session.branch_name),
		group)
}

pub fn (session DatabaseSession) begin_high_throughput_group_commit(mut database PersistentDatabase) !GroupCommitSession {
	return database.begin_high_throughput_group_commit_session(SessionOptions.for_branch(session.branch_name))
}

pub fn (session DatabaseSession) begin_split_group_commit(mut database PersistentDatabase, group GroupCommitOptions, cfg ChunkConfig) !SplitGroupCommitSession {
	return database.begin_split_group_commit_session(SessionOptions.for_branch(session.branch_name),
		group, cfg)
}

pub fn (session DatabaseSession) begin_split_high_throughput_group_commit(mut database PersistentDatabase, cfg ChunkConfig) !SplitGroupCommitSession {
	return database.begin_split_high_throughput_group_commit_session(SessionOptions.for_branch(session.branch_name),
		cfg)
}

pub fn (session DatabaseSession) apply_write_set(mut database PersistentDatabase, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	return database.apply_typed_write_set_with_specs(session.branch_name, session.specs,
		write_set, cfg, meta)
}

pub fn (session DatabaseSession) table_reader(mut database PersistentDatabase, table_name string) !BranchTableReader {
	spec := session.table_spec(table_name)!
	root_cid := database.engine.root_cid_at_branch(session.branch_name)!
	return BranchTableReader{
		branch_name: session.branch_name
		spec:        spec
		root_cid:    root_cid
		codec:       TypedRowCodec.new(spec.table)
		row_prefix:  database_table_row_prefix(spec.table.name)
		node_store:  database.engine.repository.node_store
	}
}

pub fn (mut database PersistentDatabase) snapshot_table_reader_for_commit(commit_cid string, table_name string) !SnapshotTableReader {
	spec := database.table_spec(table_name)!
	root_cid := database.engine.root_cid_at_commit(commit_cid)!
	return SnapshotTableReader{
		commit_cid: commit_cid
		root_cid:   root_cid
		spec:       spec
		codec:      TypedRowCodec.new(spec.table)
		row_prefix: database_table_row_prefix(spec.table.name)
		node_store: database.engine.repository.node_store
	}
}

pub fn (mut database PersistentDatabase) snapshot_table_reader_for_branch(branch_name string, table_name string) !SnapshotTableReader {
	commit := database.engine.checkout(branch_name)!
	return database.snapshot_table_reader_for_commit(commit.cid, table_name)
}

pub fn (mut database PersistentDatabase) snapshot_table_pair_reader_for_commits(left_commit_cid string, right_commit_cid string, table_name string) !SnapshotTablePairReader {
	return SnapshotTablePairReader{
		left_commit_cid:  left_commit_cid
		right_commit_cid: right_commit_cid
		left:             database.snapshot_table_reader_for_commit(left_commit_cid, table_name)!
		right:            database.snapshot_table_reader_for_commit(right_commit_cid,
			table_name)!
	}
}

pub fn (session DatabaseSession) index_reader(mut database PersistentDatabase, table_name string, index_name string) !BranchIndexReader {
	spec := session.table_spec(table_name)!
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in spec.indexes {
		if index.name == index_name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		return error('typed schema index not found: ${index_name}')
	}
	root_cid := database.engine.root_cid_at_branch(session.branch_name)!
	column := target_index.value_column(spec.table)!
	return BranchIndexReader{
		branch_name:  session.branch_name
		spec:         spec
		index:        target_index
		root_cid:     root_cid
		codec:        TypedRowCodec.new(spec.table)
		row_prefix:   database_table_row_prefix(spec.table.name)
		index_prefix: database_index_entry_prefix(spec.table.name, target_index.name)
		index_column: column
		node_store:   database.engine.repository.node_store
	}
}

pub fn (mut database PersistentDatabase) snapshot_index_reader_for_commit(commit_cid string, table_name string, index_name string) !SnapshotIndexReader {
	spec := database.table_spec(table_name)!
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in spec.indexes {
		if index.name == index_name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		return error('typed schema index not found: ${index_name}')
	}
	root_cid := database.engine.root_cid_at_commit(commit_cid)!
	column := target_index.value_column(spec.table)!
	return SnapshotIndexReader{
		commit_cid:   commit_cid
		root_cid:     root_cid
		spec:         spec
		index:        target_index
		codec:        TypedRowCodec.new(spec.table)
		row_prefix:   database_table_row_prefix(spec.table.name)
		index_prefix: database_index_entry_prefix(spec.table.name, target_index.name)
		index_column: column
		node_store:   database.engine.repository.node_store
	}
}

pub fn (mut database PersistentDatabase) snapshot_index_reader_for_branch(branch_name string, table_name string, index_name string) !SnapshotIndexReader {
	commit := database.engine.checkout(branch_name)!
	return database.snapshot_index_reader_for_commit(commit.cid, table_name, index_name)
}

pub fn (mut database PersistentDatabase) snapshot_index_pair_reader_for_commits(left_commit_cid string, right_commit_cid string, table_name string, index_name string) !SnapshotIndexPairReader {
	return SnapshotIndexPairReader{
		left_commit_cid:  left_commit_cid
		right_commit_cid: right_commit_cid
		left:             database.snapshot_index_reader_for_commit(left_commit_cid, table_name,
			index_name)!
		right:            database.snapshot_index_reader_for_commit(right_commit_cid,
			table_name, index_name)!
	}
}

pub fn (session DatabaseSession) get_row(mut db PersistentDatabase, table_name string, primary_key []u8) !TypedSchemaRow {
	mut reader := session.table_reader(mut db, table_name)!
	return reader.get_row(primary_key)
}

pub fn (session DatabaseSession) get_rows_projected(mut db PersistentDatabase, table_name string, primary_keys [][]u8, columns []string) ![]TypedSchemaRow {
	if primary_keys.len == 0 {
		return []TypedSchemaRow{}
	}
	mut reader := session.table_reader(mut db, table_name)!
	mut rows := []TypedSchemaRow{cap: primary_keys.len}
	for primary_key in primary_keys {
		rows << reader.get_row_projected(primary_key, columns)!
	}
	return rows
}

pub fn (session DatabaseSession) scan_table(mut db PersistentDatabase, table_name string, limit int) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	rows := view.schema.table.collect(limit)!
	mut decoded := []TypedSchemaRow{cap: rows.len}
	for row in rows {
		decoded << TypedSchemaRow{
			primary_key: row.primary_key
			data:        view.schema.codec.decode(row.value)!
		}
	}
	return decoded
}

pub fn (session DatabaseSession) count_rows(mut db PersistentDatabase, table_name string) !int {
	mut reader := session.table_reader(mut db, table_name)!
	start_key := encode_table_row_key(reader.spec.table.name, []u8{})
	end_key := encode_table_range_end(reader.spec.table.name)!
	return Tree.count_range_in_byte_store(reader.root_cid, start_key, end_key, mut reader.node_store)
}

pub fn (session DatabaseSession) sum_i64_column(mut db PersistentDatabase, table_name string, column_name string) !i64 {
	mut reader := session.table_reader(mut db, table_name)!
	column := reader.spec.table.column(column_name)!
	if column.aggregate == .sum {
		return sum_declared_i64_range(reader.root_cid, reader.spec.table.name, column_name,
			[]u8{}, []u8{}, reader.codec, mut reader.node_store)
	}
	start_key := encode_table_row_key(reader.spec.table.name, []u8{})
	end_key := encode_table_range_end(reader.spec.table.name)!
	return Tree.sum_i64_column_range_in_byte_store(reader.root_cid, start_key, end_key,
		reader.codec, column_name, mut reader.node_store)
}

pub fn (session DatabaseSession) count_rows_range(mut db PersistentDatabase, table_name string, start_primary_key []u8, end_primary_key []u8) !int {
	mut reader := session.table_reader(mut db, table_name)!
	start_key := encode_table_row_key(reader.spec.table.name, start_primary_key)
	end_key := if end_primary_key.len == 0 {
		encode_table_range_end(reader.spec.table.name)!
	} else {
		encode_table_row_key(reader.spec.table.name, end_primary_key)
	}
	return Tree.count_range_in_byte_store(reader.root_cid, start_key, end_key, mut reader.node_store)
}

pub fn (session DatabaseSession) sum_i64_column_range(mut db PersistentDatabase, table_name string, column_name string, start_primary_key []u8, end_primary_key []u8) !i64 {
	mut reader := session.table_reader(mut db, table_name)!
	column := reader.spec.table.column(column_name)!
	if column.aggregate == .sum {
		return sum_declared_i64_range(reader.root_cid, reader.spec.table.name, column_name,
			start_primary_key, end_primary_key, reader.codec, mut reader.node_store)
	}
	start_key := encode_table_row_key(reader.spec.table.name, start_primary_key)
	end_key := if end_primary_key.len == 0 {
		encode_table_range_end(reader.spec.table.name)!
	} else {
		encode_table_row_key(reader.spec.table.name, end_primary_key)
	}
	return Tree.sum_i64_column_range_in_byte_store(reader.root_cid, start_key, end_key,
		reader.codec, column_name, mut reader.node_store)
}

pub fn (session DatabaseSession) lookup_index(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	mut reader := session.index_reader(mut db, table_name, index_name)!
	return if reader.index.stores_row {
		reader.find_rows_covering(value, limit)
	} else {
		reader.find_rows(value, limit)
	}
}

pub fn (session DatabaseSession) lookup_index_ordered(mut db PersistentDatabase, table_name string, index_name string, start_value ColumnValue, has_start_value bool, start_primary_key []u8, limit int, reverse bool) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:              .all
		value:             clone_column_value(start_value)
		has_value:         has_start_value
		start_primary_key: start_primary_key.clone()
		limit:             limit
		reverse:           reverse
	})!
}

pub fn (session DatabaseSession) lookup_index_ordered_projected(mut db PersistentDatabase, table_name string, index_name string, start_value ColumnValue, has_start_value bool, start_primary_key []u8, limit int, columns []string, reverse bool) ![]TypedSchemaRow {
	mut reader := session.index_reader(mut db, table_name, index_name)!
	if reader.index.stores_row {
		return reader.find_rows_covering_ordered_projected(start_value, has_start_value,
			start_primary_key, limit, columns, reverse)
	}
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:              .all
		value:             clone_column_value(start_value)
		has_value:         has_start_value
		start_primary_key: start_primary_key.clone()
		limit:             limit
		columns:           columns.clone()
		reverse:           reverse
	})!
}

pub fn (session DatabaseSession) lookup_index_projected(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	mut reader := session.index_reader(mut db, table_name, index_name)!
	if reader.index.stores_row {
		return reader.find_rows_covering_projected(value, limit, columns)
	}
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .exact
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
	})
}

pub fn (session DatabaseSession) lookup_index_prefix(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	mut reader := session.index_reader(mut db, table_name, index_name)!
	return if reader.index.stores_row {
		reader.find_rows_covering_prefix(value, limit)
	} else {
		reader.find_rows_prefix(value, limit)
	}
}

pub fn (session DatabaseSession) lookup_index_prefix_projected(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	mut reader := session.index_reader(mut db, table_name, index_name)!
	return if reader.index.stores_row {
		reader.find_rows_covering_prefix_projected(value, limit, columns)
	} else {
		reader.find_rows_prefix(value, limit)
	}
}

pub fn (session DatabaseSession) lookup_index_prefix_reverse(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .prefix
		value:   clone_column_value(value)
		limit:   limit
		reverse: true
	})
}

pub fn (session DatabaseSession) lookup_index_prefix_reverse_projected(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .prefix
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
		reverse: true
	})
}

pub fn (session DatabaseSession) lookup_index_between_projected(mut db PersistentDatabase, table_name string, index_name string, start_value ColumnValue, end_value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
		limit:            limit
		columns:          columns.clone()
	})
}

pub fn (session DatabaseSession) lookup_index_after_projected(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:      .after
		value:     clone_column_value(value)
		has_value: true
		limit:     limit
		columns:   columns.clone()
	})
}

pub fn (session DatabaseSession) lookup_index_after_reverse(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:      .after
		value:     clone_column_value(value)
		has_value: true
		limit:     limit
		reverse:   true
	})
}

pub fn (session DatabaseSession) lookup_index_after_reverse_projected(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:      .after
		value:     clone_column_value(value)
		has_value: true
		limit:     limit
		columns:   columns.clone()
		reverse:   true
	})
}

pub fn (session DatabaseSession) lookup_index_before_projected(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .before
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
	})
}

pub fn (session DatabaseSession) lookup_index_between(mut db PersistentDatabase, table_name string, index_name string, start_value ColumnValue, end_value ColumnValue, limit int) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	for index in view.indexes {
		if index.name == index_name && index.is_field_selector() {
			return transaction_markdown_index_lookup_between(session.root_dir, view, index,
				start_value, end_value, limit)
		}
	}
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_value:        true
		has_second_value: true
		limit:            limit
	})
}

pub fn (session DatabaseSession) lookup_index_between_reverse(mut db PersistentDatabase, table_name string, index_name string, start_value ColumnValue, end_value ColumnValue, limit int) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_value:        true
		has_second_value: true
		limit:            limit
		reverse:          true
	})
}

pub fn (session DatabaseSession) lookup_index_between_reverse_projected(mut db PersistentDatabase, table_name string, index_name string, start_value ColumnValue, end_value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_value:        true
		has_second_value: true
		limit:            limit
		columns:          columns.clone()
		reverse:          true
	})
}

pub fn (session DatabaseSession) lookup_index_after(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	for index in view.indexes {
		if index.name == index_name && index.is_field_selector() {
			return transaction_markdown_index_lookup_after(session.root_dir, view, index,
				value, limit)
		}
	}
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:      .after
		value:     clone_column_value(value)
		has_value: true
		limit:     limit
	})
}

pub fn (session DatabaseSession) lookup_index_before(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	for index in view.indexes {
		if index.name == index_name && index.is_field_selector() {
			return transaction_markdown_index_lookup_before(session.root_dir, view, index,
				value, limit)
		}
	}
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:  .before
		value: clone_column_value(value)
		limit: limit
	})
}

pub fn (session DatabaseSession) lookup_index_before_reverse(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .before
		value:   clone_column_value(value)
		limit:   limit
		reverse: true
	})
}

pub fn (session DatabaseSession) lookup_index_before_reverse_projected(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .before
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
		reverse: true
	})
}

pub fn (session DatabaseSession) table_cursor(mut db PersistentDatabase, table_name string, start_primary_key []u8, limit int) !TypedTableCursor {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	return TypedTableCursor{
		view:   view
		cursor: view.schema.table.cursor(start_primary_key, limit)!
	}
}

pub fn (session DatabaseSession) index_cursor(mut db PersistentDatabase, table_name string, index_name string, value ColumnValue, start_primary_key []u8, limit int) !TypedIndexCursor {
	tx := session.begin_transaction(mut db)!
	view := tx.indexed_view(table_name)!
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in view.indexes {
		if index.name == index_name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		return error('typed schema index not found: ${index_name}')
	}
	column := target_index.value_column(view.schema.codec.table)!
	encoded := TypedValueEncoder.encode_index_value(value, column)!
	return TypedIndexCursor{
		view:       view
		index_name: index_name
		cursor:     IndexView.new(view.schema.table.tree, table_name, index_name).cursor(encoded,
			start_primary_key, limit)!
	}
}

fn normalize_temporal_row(table TableDef, existing_row TypedRowData, has_existing bool, patch_row TypedRowData, current_timestamp string) !TypedRowData {
	mut next_row := if has_existing { existing_row.clone() } else { TypedRowData.new() }
	for name, value in patch_row.fields() {
		match value {
			NullValue {
				next_row.set_null(name)
			}
			else {
				next_row.set(name, value)
			}
		}
	}
	for column in table.columns {
		if !has_existing {
			if !next_row.has(column.name)
				&& (column.default_current_timestamp || column.auto_update_current_timestamp) {
				next_row.set(column.name, current_timestamp)
			}
			continue
		}
		if column.auto_update_current_timestamp {
			next_row.set(column.name, current_timestamp)
		}
	}
	return next_row
}

fn normalize_temporal_write_set_with_views(specs map[string]TypedTableSpec, mut views map[string]TypedIndexedSchemaView, write_set TypedWriteSet) !TypedWriteSet {
	if write_set.len() == 0 {
		return write_set
	}
	current_timestamp := current_datetime_string()
	mut normalized := TypedWriteSet.new()
	mut cached_rows := map[string]TypedRowData{}
	mut cached_exists := map[string]bool{}
	for op in write_set.operations() {
		cache_key := '${op.table_name}\x00${op.primary_key.hex()}'
		if op.delete {
			normalized.delete(op.table_name, op.primary_key)
			cached_rows[cache_key] = TypedRowData.new()
			cached_exists[cache_key] = false
			continue
		}
		spec := specs[op.table_name] or {
			return error('typed table not registered: ${op.table_name}')
		}
		mut existing_row := TypedRowData.new()
		mut has_existing := false
		if cache_key in cached_exists {
			has_existing = cached_exists[cache_key]
			existing_row = (cached_rows[cache_key] or { TypedRowData.new() }).clone()
		} else {
			if op.table_name !in views {
				return error('typed indexed view not prepared: ${op.table_name}')
			}
			existing := views[op.table_name].get(op.primary_key) or { TypedSchemaRow{} }
			if existing.primary_key.len > 0 {
				has_existing = true
				existing_row = existing.data.clone()
			}
		}
		next_row := normalize_temporal_row(spec.table, existing_row, has_existing, op.row,
			current_timestamp)!
		normalized.put(op.table_name, op.primary_key, next_row)
		cached_rows[cache_key] = next_row.clone()
		cached_exists[cache_key] = true
	}
	return normalized
}

fn normalize_temporal_write_set(tx TypedTransaction, write_set TypedWriteSet) !TypedWriteSet {
	mut views := map[string]TypedIndexedSchemaView{}
	for table_name, _ in tx.specs {
		views[table_name] = tx.indexed_view(table_name)!
	}
	return normalize_temporal_write_set_with_views(tx.specs, mut views, write_set)
}

fn normalize_temporal_split_write_set(tx TypedSplitTransaction, write_set TypedWriteSet) !TypedWriteSet {
	mut views := map[string]TypedIndexedSchemaView{}
	for table_name, _ in tx.specs {
		views[table_name] = tx.indexed_view(table_name)!
	}
	return normalize_temporal_write_set_with_views(tx.specs, mut views, write_set)
}

pub fn (session DatabaseSession) put_row(mut db PersistentDatabase, table_name string, primary_key []u8, row TypedRowData, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.put(table_name, primary_key, row)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (session DatabaseSession) put_rows(mut db PersistentDatabase, table_name string, rows map[string]TypedRowData, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.put_many(table_name, rows)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

fn patch_json_column_in_row(row TypedSchemaRow, column ColumnDef, column_name string, updates []JsonPathUpdate) !TypedRowData {
	if column.typ != .json_ {
		return error('column is not json: ${column_name}')
	}
	mut next_row := row.data.clone()
	raw := next_row.get(column_name)!
	match raw {
		string {
			next_row.set(column_name, json_patch_scalar_paths(raw, updates)!)
		}
		else {
			return error('json column ${column_name} must contain string payload')
		}
	}
	return next_row
}

fn set_markdown_ref_in_row(row TypedSchemaRow, column ColumnDef, column_name string, value MarkdownRef) !TypedRowData {
	if column.typ != .markdown_ {
		return error('column is not markdown: ${column_name}')
	}
	mut next_row := row.data.clone()
	next_row.set(column_name, value)
	return next_row
}

fn get_markdown_ref_from_row(row TypedSchemaRow, column ColumnDef, column_name string) !MarkdownRef {
	if column.typ != .markdown_ {
		return error('column is not markdown: ${column_name}')
	}
	value := row.data.get(column_name)!
	match value {
		MarkdownRef {
			return value
		}
		else {
			return error('markdown column ${column_name} must contain MarkdownRef payload')
		}
	}
}

pub fn (session DatabaseSession) patch_json_paths(mut database PersistentDatabase, table_name string, primary_key []u8, column_name string, updates []JsonPathUpdate, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	current := session.get_row(mut database, table_name, primary_key)!
	spec := database.table_spec(table_name)!
	column := spec.table.column(column_name)!
	next_row := patch_json_column_in_row(current, column, column_name, updates)!
	return session.put_row(mut database, table_name, primary_key, next_row, cfg, meta)
}

pub fn (session DatabaseSession) set_json_path(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string, json_path string, value ColumnValue, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	return session.patch_json_paths(mut db, table_name, primary_key, column_name, [
		JsonPathUpdate{
			path:  json_path
			op:    .set
			value: value
		},
	], cfg, meta)
}

pub fn (session DatabaseSession) put_markdown_ref(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string, value MarkdownRef, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	current := session.get_row(mut db, table_name, primary_key)!
	spec := db.table_spec(table_name)!
	column := spec.table.column(column_name)!
	next_row := set_markdown_ref_in_row(current, column, column_name, value)!
	return session.put_row(mut db, table_name, primary_key, next_row, cfg, meta)
}

pub fn (session DatabaseSession) put_markdown(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string, raw string, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	spec := db.table_spec(table_name)!
	column := spec.table.column(column_name)!
	stored := ingest_external_field_value(mut db, column, raw)!
	ref := match stored {
		MarkdownRef { stored }
		else { return error('markdown ingest did not return MarkdownRef payload: ${column_name}') }
	}
	return session.put_markdown_ref(mut db, table_name, primary_key, column_name, ref,
		cfg, meta)
}

pub fn (session DatabaseSession) get_markdown_ref(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string) !MarkdownRef {
	row := session.get_row(mut db, table_name, primary_key)!
	spec := db.table_spec(table_name)!
	column := spec.table.column(column_name)!
	return get_markdown_ref_from_row(row, column, column_name)
}

pub fn (session DatabaseSession) get_markdown(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string) !string {
	ref := session.get_markdown_ref(mut db, table_name, primary_key, column_name)!
	spec := db.table_spec(table_name)!
	column := spec.table.column(column_name)!
	loaded := load_external_field_value(db, column, ref)!
	return match loaded {
		string { loaded }
		else { error('markdown load did not return string payload: ${column_name}') }
	}
}

pub fn (session DatabaseSession) set_json_path_null(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string, json_path string, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	return session.set_json_path(mut db, table_name, primary_key, column_name, json_path,
		NullValue{}, cfg, meta)
}

pub fn (session DatabaseSession) delete_json_path(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string, json_path string, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	return session.patch_json_paths(mut db, table_name, primary_key, column_name, [
		JsonPathUpdate{
			path:  json_path
			op:    .delete
			value: NullValue{}
		},
	], cfg, meta)
}

pub fn (session DatabaseSession) delete_row(mut db PersistentDatabase, table_name string, primary_key []u8, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.delete(table_name, primary_key)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (session DatabaseSession) delete_rows(mut db PersistentDatabase, table_name string, primary_keys [][]u8, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.delete_many(table_name, primary_keys)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (session TransactionSession) has_changes() bool {
	return session.working_set.has_changes()
}

pub fn (session TransactionSession) status() !WorkingSetStatus {
	return session.working_set.status()
}

pub fn (session TransactionSession) transaction() TypedTransaction {
	return session.working_set.transaction()
}

pub fn (session TransactionSession) staged_diff() TreeDiff {
	return session.working_set.staged_diff()
}

pub fn (mut session TransactionSession) apply_write_set(write_set TypedWriteSet, cfg ChunkConfig) !TypedTransactionResult {
	normalized_write_set := normalize_temporal_write_set(session.working_set.transaction(),
		write_set)!
	return session.working_set.apply_write_set(normalized_write_set, cfg)
}

pub fn (mut session TransactionSession) put_rows(table_name string, rows map[string]TypedRowData, cfg ChunkConfig) !TypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.put_many(table_name, rows)
	return session.apply_write_set(write_set, cfg)
}

pub fn (mut session TransactionSession) delete_rows(table_name string, primary_keys [][]u8, cfg ChunkConfig) !TypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.delete_many(table_name, primary_keys)
	return session.apply_write_set(write_set, cfg)
}

pub fn (session TransactionSession) get_row(table_name string, primary_key []u8) !TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return view.get(primary_key)
}

pub fn (session TransactionSession) scan_table(table_name string, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	rows := view.schema.table.collect(limit)!
	mut decoded := []TypedSchemaRow{cap: rows.len}
	for row in rows {
		decoded << TypedSchemaRow{
			primary_key: row.primary_key
			data:        view.schema.codec.decode(row.value)!
		}
	}
	return decoded
}

pub fn (session TransactionSession) count_rows(table_name string) !int {
	view := session.working_set.transaction().indexed_view(table_name)!
	mut cursor := view.schema.table.raw_cursor([]u8{}, 0)!
	return cursor.count_remaining()
}

pub fn (session TransactionSession) sum_i64_column(table_name string, column_name string) !i64 {
	view := session.working_set.transaction().indexed_view(table_name)!
	mut cursor := view.schema.table.raw_cursor([]u8{}, 0)!
	return cursor.sum_i64_column(view.schema.codec, column_name)
}

pub fn (session TransactionSession) count_rows_range(table_name string, start_primary_key []u8, end_primary_key []u8) !int {
	view := session.working_set.transaction().indexed_view(table_name)!
	mut cursor := view.schema.table.raw_range_cursor(start_primary_key, end_primary_key,
		0)!
	return cursor.count_remaining()
}

pub fn (session TransactionSession) sum_i64_column_range(table_name string, column_name string, start_primary_key []u8, end_primary_key []u8) !i64 {
	view := session.working_set.transaction().indexed_view(table_name)!
	mut cursor := view.schema.table.raw_range_cursor(start_primary_key, end_primary_key,
		0)!
	return cursor.sum_i64_column(view.schema.codec, column_name)
}

pub fn (session TransactionSession) lookup_index(table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	for index in view.indexes {
		if index.name == index_name && index.is_field_selector() {
			return transaction_markdown_index_lookup(session.root_dir, view, index, value,
				limit)
		}
	}
	return view.find_by_index(index_name, value, limit)
}

pub fn (session TransactionSession) lookup_index_ordered(table_name string, index_name string, start_value ColumnValue, has_start_value bool, start_primary_key []u8, limit int, reverse bool) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:              .all
		value:             clone_column_value(start_value)
		has_value:         has_start_value
		start_primary_key: start_primary_key.clone()
		limit:             limit
		reverse:           reverse
	})!
}

pub fn (session TransactionSession) lookup_index_ordered_projected(table_name string, index_name string, start_value ColumnValue, has_start_value bool, start_primary_key []u8, limit int, columns []string, reverse bool) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:              .all
		value:             clone_column_value(start_value)
		has_value:         has_start_value
		start_primary_key: start_primary_key.clone()
		limit:             limit
		columns:           columns.clone()
		reverse:           reverse
	})!
}

pub fn (session TransactionSession) lookup_index_prefix(table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	for index in view.indexes {
		if index.name == index_name && index.is_field_selector() {
			return transaction_markdown_index_lookup_prefix(session.root_dir, view, index,
				value, limit)
		}
	}
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:  .prefix
		value: clone_column_value(value)
		limit: limit
	})
}

pub fn (session TransactionSession) lookup_index_projected(table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .exact
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
	})
}

pub fn (session TransactionSession) lookup_index_prefix_projected(table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .prefix
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
	})
}

pub fn (session TransactionSession) lookup_index_prefix_reverse(table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .prefix
		value:   clone_column_value(value)
		limit:   limit
		reverse: true
	})
}

pub fn (session TransactionSession) lookup_index_prefix_reverse_projected(table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .prefix
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
		reverse: true
	})
}

pub fn (session TransactionSession) lookup_index_between(table_name string, index_name string, start_value ColumnValue, end_value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	for index in view.indexes {
		if index.name == index_name && index.is_field_selector() {
			return transaction_markdown_index_lookup_between(session.root_dir, view, index,
				start_value, end_value, limit)
		}
	}
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_value:        true
		has_second_value: true
		limit:            limit
	})
}

pub fn (session TransactionSession) lookup_index_between_reverse(table_name string, index_name string, start_value ColumnValue, end_value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_value:        true
		has_second_value: true
		limit:            limit
		reverse:          true
	})
}

pub fn (session TransactionSession) lookup_index_between_reverse_projected(table_name string, index_name string, start_value ColumnValue, end_value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_value:        true
		has_second_value: true
		limit:            limit
		columns:          columns.clone()
		reverse:          true
	})
}

pub fn (session TransactionSession) lookup_index_between_projected(table_name string, index_name string, start_value ColumnValue, end_value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
		limit:            limit
		columns:          columns.clone()
	})
}

pub fn (session TransactionSession) lookup_index_after(table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	for index in view.indexes {
		if index.name == index_name && index.is_field_selector() {
			return transaction_markdown_index_lookup_after(session.root_dir, view, index,
				value, limit)
		}
	}
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:  .after
		value: clone_column_value(value)
		limit: limit
	})
}

pub fn (session TransactionSession) lookup_index_after_projected(table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:      .after
		value:     clone_column_value(value)
		has_value: true
		limit:     limit
		columns:   columns.clone()
	})
}

pub fn (session TransactionSession) lookup_index_after_reverse(table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:      .after
		value:     clone_column_value(value)
		has_value: true
		limit:     limit
		reverse:   true
	})
}

pub fn (session TransactionSession) lookup_index_after_reverse_projected(table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:      .after
		value:     clone_column_value(value)
		has_value: true
		limit:     limit
		columns:   columns.clone()
		reverse:   true
	})
}

pub fn (session TransactionSession) lookup_index_before(table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	for index in view.indexes {
		if index.name == index_name && index.is_field_selector() {
			return transaction_markdown_index_lookup_before(session.root_dir, view, index,
				value, limit)
		}
	}
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:  .before
		value: clone_column_value(value)
		limit: limit
	})
}

pub fn (session TransactionSession) lookup_index_before_projected(table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .before
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
	})
}

pub fn (session TransactionSession) lookup_index_before_reverse(table_name string, index_name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .before
		value:   clone_column_value(value)
		limit:   limit
		reverse: true
	})
}

pub fn (session TransactionSession) lookup_index_before_reverse_projected(table_name string, index_name string, value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	view := session.working_set.transaction().indexed_view(table_name)!
	return typed_scan_rows_by_index(view, index_name, TypedIndexScanRequest{
		mode:    .before
		value:   clone_column_value(value)
		limit:   limit
		columns: columns.clone()
		reverse: true
	})
}

pub fn (session TransactionSession) table_cursor(table_name string, start_primary_key []u8, limit int) !TypedTableCursor {
	view := session.working_set.transaction().indexed_view(table_name)!
	return TypedTableCursor{
		view:   view
		cursor: view.schema.table.cursor(start_primary_key, limit)!
	}
}

pub fn (session TransactionSession) index_cursor(table_name string, index_name string, value ColumnValue, start_primary_key []u8, limit int) !TypedIndexCursor {
	view := session.working_set.transaction().indexed_view(table_name)!
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in view.indexes {
		if index.name == index_name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		return error('typed schema index not found: ${index_name}')
	}
	if target_index.is_field_selector() {
		return TypedIndexCursor{
			view:             view
			index_name:       index_name
			markdown_entries: transaction_markdown_index_cursor_entries(session.root_dir,
				view, target_index, value, start_primary_key, limit)!
			markdown_pos:     0
		}
	}
	column := target_index.value_column(view.schema.codec.table)!
	encoded := TypedValueEncoder.encode_index_value(value, column)!
	return TypedIndexCursor{
		view:             view
		index_name:       index_name
		cursor:           IndexView.new(view.schema.table.tree, table_name, index_name).cursor(encoded,
			start_primary_key, limit)!
		markdown_entries: []TransactionMarkdownIndexEntry{}
		markdown_pos:     0
	}
}

pub fn (mut session TransactionSession) put_row(table_name string, primary_key []u8, row TypedRowData, cfg ChunkConfig) !TypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.put(table_name, primary_key, row)
	return session.apply_write_set(write_set, cfg)
}

pub fn (mut session TransactionSession) patch_json_paths(table_name string, primary_key []u8, column_name string, updates []JsonPathUpdate, cfg ChunkConfig) !TypedTransactionResult {
	current := session.get_row(table_name, primary_key)!
	view := session.working_set.transaction().indexed_view(table_name)!
	column := view.schema.codec.table.column(column_name)!
	next_row := patch_json_column_in_row(current, column, column_name, updates)!
	return session.put_row(table_name, primary_key, next_row, cfg)
}

pub fn (mut session TransactionSession) set_json_path(table_name string, primary_key []u8, column_name string, json_path string, value ColumnValue, cfg ChunkConfig) !TypedTransactionResult {
	return session.patch_json_paths(table_name, primary_key, column_name, [
		JsonPathUpdate{
			path:  json_path
			op:    .set
			value: value
		},
	], cfg)
}

pub fn (mut session TransactionSession) put_markdown_ref(table_name string, primary_key []u8, column_name string, value MarkdownRef, cfg ChunkConfig) !TypedTransactionResult {
	current := session.get_row(table_name, primary_key)!
	view := session.working_set.transaction().indexed_view(table_name)!
	column := view.schema.codec.table.column(column_name)!
	next_row := set_markdown_ref_in_row(current, column, column_name, value)!
	return session.put_row(table_name, primary_key, next_row, cfg)
}

pub fn (mut session TransactionSession) put_markdown(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string, raw string, cfg ChunkConfig) !TypedTransactionResult {
	view := session.working_set.transaction().indexed_view(table_name)!
	column := view.schema.codec.table.column(column_name)!
	stored := ingest_external_field_value(mut db, column, raw)!
	ref := match stored {
		MarkdownRef { stored }
		else { return error('markdown ingest did not return MarkdownRef payload: ${column_name}') }
	}
	return session.put_markdown_ref(table_name, primary_key, column_name, ref, cfg)
}

pub fn (session TransactionSession) get_markdown_ref(table_name string, primary_key []u8, column_name string) !MarkdownRef {
	row := session.get_row(table_name, primary_key)!
	view := session.working_set.transaction().indexed_view(table_name)!
	column := view.schema.codec.table.column(column_name)!
	return get_markdown_ref_from_row(row, column, column_name)
}

pub fn (session TransactionSession) get_markdown(mut db PersistentDatabase, table_name string, primary_key []u8, column_name string) !string {
	ref := session.get_markdown_ref(table_name, primary_key, column_name)!
	view := session.working_set.transaction().indexed_view(table_name)!
	column := view.schema.codec.table.column(column_name)!
	loaded := load_external_field_value(db, column, ref)!
	return match loaded {
		string { loaded }
		else { error('markdown load did not return string payload: ${column_name}') }
	}
}

pub fn (mut session TransactionSession) set_json_path_null(table_name string, primary_key []u8, column_name string, json_path string, cfg ChunkConfig) !TypedTransactionResult {
	return session.set_json_path(table_name, primary_key, column_name, json_path, NullValue{},
		cfg)
}

pub fn (mut session TransactionSession) delete_json_path(table_name string, primary_key []u8, column_name string, json_path string, cfg ChunkConfig) !TypedTransactionResult {
	return session.patch_json_paths(table_name, primary_key, column_name, [
		JsonPathUpdate{
			path:  json_path
			op:    .delete
			value: NullValue{}
		},
	], cfg)
}

pub fn (mut session TransactionSession) delete_row(table_name string, primary_key []u8, cfg ChunkConfig) !TypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.delete(table_name, primary_key)
	return session.apply_write_set(write_set, cfg)
}

pub fn (mut cursor TypedTableCursor) seek(primary_key []u8) ! {
	cursor.cursor.seek(primary_key)!
}

pub fn (cursor TypedTableCursor) current() !TypedSchemaRow {
	row := cursor.cursor.current()!
	return TypedSchemaRow{
		primary_key: row.primary_key
		data:        cursor.view.schema.codec.decode(row.value)!
	}
}

pub fn (mut cursor TypedTableCursor) peek() !TypedSchemaRow {
	row := cursor.cursor.peek()!
	return TypedSchemaRow{
		primary_key: row.primary_key
		data:        cursor.view.schema.codec.decode(row.value)!
	}
}

pub fn (mut cursor TypedTableCursor) next() !TypedSchemaRow {
	row := cursor.cursor.next()!
	return TypedSchemaRow{
		primary_key: row.primary_key
		data:        cursor.view.schema.codec.decode(row.value)!
	}
}

pub fn (mut cursor TypedTableCursor) skip(count int) !int {
	return cursor.cursor.skip(count)
}

pub fn (mut cursor TypedTableCursor) collect(count int) ![]TypedSchemaRow {
	rows := cursor.cursor.collect(count)!
	mut decoded := []TypedSchemaRow{cap: rows.len}
	for row in rows {
		decoded << TypedSchemaRow{
			primary_key: row.primary_key
			data:        cursor.view.schema.codec.decode(row.value)!
		}
	}
	return decoded
}

pub fn (mut cursor TypedIndexCursor) seek(index_key []u8, primary_key []u8) ! {
	if cursor.markdown_entries.len > 0 {
		for idx, entry in cursor.markdown_entries {
			key_cmp := compare_key_bytes(entry.encoded, index_key)
			if key_cmp > 0
				|| (key_cmp == 0 && compare_key_bytes(entry.row.primary_key, primary_key) >= 0) {
				cursor.markdown_pos = idx
				return
			}
		}
		cursor.markdown_pos = cursor.markdown_entries.len
		return
	}
	cursor.cursor.seek(index_key, primary_key)!
}

fn typed_index_row_from_entry(view TypedIndexedSchemaView, entry IndexEntry) !TypedIndexRow {
	if entry.value.len > 0 {
		return TypedIndexRow{
			index_key:   entry.index_key
			primary_key: entry.primary_key
			row:         TypedSchemaRow{
				primary_key: entry.primary_key
				data:        view.schema.codec.decode(entry.value)!
			}
		}
	}
	return TypedIndexRow{
		index_key:   entry.index_key
		primary_key: entry.primary_key
		row:         view.get(entry.primary_key)!
	}
}

fn typed_schema_row_from_index_entry(view TypedIndexedSchemaView, entry IndexEntry, columns []string) !TypedSchemaRow {
	if columns.len == 0 {
		return (typed_index_row_from_entry(view, entry)!).row
	}
	if entry.value.len > 0 {
		return TypedSchemaRow{
			primary_key: entry.primary_key
			data:        view.schema.codec.decode_projected(entry.value, columns)!
		}
	}
	full_row := view.get(entry.primary_key)!
	mut projected := TypedRowData.new()
	for name in columns {
		if full_row.data.has(name) {
			projected.set(name, full_row.data.get(name)!)
		}
	}
	return TypedSchemaRow{
		primary_key: full_row.primary_key
		data:        projected
	}
}

fn typed_scan_rows_by_index(view TypedIndexedSchemaView, index_name string, request TypedIndexScanRequest) ![]TypedSchemaRow {
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in view.indexes {
		if index.name == index_name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		return error('typed schema index not found: ${index_name}')
	}
	column := target_index.value_column(view.schema.codec.table)!
	index_view := view.index_view_by_name(index_name)!
	mut rows := []TypedSchemaRow{}
	match request.mode {
		.all {
			if request.reverse {
				end_index_key := if request.has_value {
					TypedValueEncoder.encode_index_value(request.value, column)!
				} else {
					[]u8{}
				}
				mut cursor := index_view.reverse_cursor([]u8{}, []u8{}, end_index_key,
					request.start_primary_key, request.limit)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if request.has_value {
						value_cmp := compare_key_bytes(entry.index_key, end_index_key)
						if value_cmp > 0 {
							_ = cursor.next()!
							continue
						}
						if value_cmp == 0 && request.start_primary_key.len > 0
							&& compare_key_bytes(entry.primary_key, request.start_primary_key) >= 0 {
							_ = cursor.next()!
							continue
						}
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			} else {
				start_index_key := if request.has_value {
					TypedValueEncoder.encode_index_value(request.value, column)!
				} else {
					[]u8{}
				}
				mut cursor := index_view.cursor(start_index_key, request.start_primary_key,
					request.limit)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if request.has_value {
						value_cmp := compare_key_bytes(entry.index_key, start_index_key)
						if value_cmp < 0 {
							_ = cursor.next()!
							continue
						}
						if value_cmp == 0 && request.start_primary_key.len > 0
							&& compare_key_bytes(entry.primary_key, request.start_primary_key) <= 0 {
							_ = cursor.next()!
							continue
						}
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			}
		}
		.exact {
			encoded := TypedValueEncoder.encode_index_value(request.value, column)!
			mut cursor := index_view.cursor(encoded, request.start_primary_key, request.limit)!
			for {
				if request.limit > 0 && rows.len >= request.limit {
					break
				}
				entry := cursor.peek() or { break }
				if compare_key_bytes(entry.index_key, encoded) != 0 {
					break
				}
				rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
			}
		}
		.prefix {
			encoded := TypedValueEncoder.encode_index_prefix(request.value, column)!
			if request.reverse {
				mut cursor := index_view.reverse_prefix_cursor(encoded, request.limit)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if !has_prefix_bytes(entry.index_key, encoded) {
						break
					}
					if request.start_primary_key.len > 0
						&& compare_key_bytes(entry.primary_key, request.start_primary_key) > 0 {
						_ = cursor.next()!
						continue
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			} else {
				mut cursor := index_view.prefix_cursor(encoded, 0)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if !has_prefix_bytes(entry.index_key, encoded) {
						break
					}
					if request.start_primary_key.len > 0
						&& compare_key_bytes(entry.primary_key, request.start_primary_key) < 0 {
						_ = cursor.next()!
						continue
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			}
		}
		.after {
			encoded := TypedValueEncoder.encode_index_value(request.value, column)!
			if request.reverse {
				mut cursor := index_view.reverse_cursor(encoded, request.start_primary_key,
					[]u8{}, []u8{}, request.limit)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if compare_key_bytes(entry.index_key, encoded) <= 0 {
						_ = cursor.next()!
						continue
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			} else {
				mut cursor := index_view.cursor(encoded, request.start_primary_key, request.limit)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if compare_key_bytes(entry.index_key, encoded) <= 0 {
						_ = cursor.next()!
						continue
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			}
		}
		.before {
			encoded := TypedValueEncoder.encode_index_value(request.value, column)!
			if request.reverse {
				mut cursor := index_view.reverse_cursor([]u8{}, []u8{}, encoded, request.start_primary_key,
					request.limit)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if compare_key_bytes(entry.index_key, encoded) >= 0 {
						_ = cursor.next()!
						continue
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			} else {
				mut cursor := index_view.cursor([]u8{}, []u8{}, 0)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if compare_key_bytes(entry.index_key, encoded) >= 0 {
						break
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			}
		}
		.between {
			encoded_start := TypedValueEncoder.encode_index_value(request.value, column)!
			encoded_end := TypedValueEncoder.encode_index_value(request.second_value,
				column)!
			if request.reverse {
				mut cursor := index_view.reverse_cursor(encoded_start, request.start_primary_key,
					encoded_end, []u8{}, request.limit)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if compare_key_bytes(entry.index_key, encoded_start) < 0 {
						break
					}
					if compare_key_bytes(entry.index_key, encoded_end) > 0 {
						_ = cursor.next()!
						continue
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			} else {
				mut cursor := index_view.cursor(encoded_start, request.start_primary_key,
					request.limit)!
				for {
					if request.limit > 0 && rows.len >= request.limit {
						break
					}
					entry := cursor.peek() or { break }
					if compare_key_bytes(entry.index_key, encoded_end) > 0 {
						break
					}
					rows << typed_schema_row_from_index_entry(view, cursor.next()!, request.columns)!
				}
			}
		}
	}
	return rows
}

pub fn (cursor TypedIndexCursor) current() !TypedIndexRow {
	if cursor.markdown_entries.len > 0 {
		if cursor.markdown_pos < 0 || cursor.markdown_pos >= cursor.markdown_entries.len {
			return error('iterator exhausted')
		}
		entry := cursor.markdown_entries[cursor.markdown_pos]
		return TypedIndexRow{
			index_key:   entry.encoded.clone()
			primary_key: entry.row.primary_key.clone()
			row:         entry.row
		}
	}
	entry := cursor.cursor.current()!
	return typed_index_row_from_entry(cursor.view, entry)
}

pub fn (mut cursor TypedIndexCursor) peek() !TypedIndexRow {
	if cursor.markdown_entries.len > 0 {
		if cursor.markdown_pos >= cursor.markdown_entries.len {
			return error('iterator exhausted')
		}
		entry := cursor.markdown_entries[cursor.markdown_pos]
		return TypedIndexRow{
			index_key:   entry.encoded.clone()
			primary_key: entry.row.primary_key.clone()
			row:         entry.row
		}
	}
	entry := cursor.cursor.peek()!
	return typed_index_row_from_entry(cursor.view, entry)
}

pub fn (mut cursor TypedIndexCursor) next() !TypedIndexRow {
	if cursor.markdown_entries.len > 0 {
		if cursor.markdown_pos >= cursor.markdown_entries.len {
			return error('iterator exhausted')
		}
		entry := cursor.markdown_entries[cursor.markdown_pos]
		cursor.markdown_pos++
		return TypedIndexRow{
			index_key:   entry.encoded.clone()
			primary_key: entry.row.primary_key.clone()
			row:         entry.row
		}
	}
	entry := cursor.cursor.next()!
	return typed_index_row_from_entry(cursor.view, entry)
}

pub fn (mut cursor TypedIndexCursor) skip(count int) !int {
	if cursor.markdown_entries.len > 0 {
		if count <= 0 {
			return 0
		}
		remaining := cursor.markdown_entries.len - cursor.markdown_pos
		skipped := if count < remaining { count } else { remaining }
		cursor.markdown_pos += skipped
		return skipped
	}
	return cursor.cursor.skip(count)
}

pub fn (mut cursor TypedIndexCursor) collect(count int) ![]TypedIndexRow {
	if cursor.markdown_entries.len > 0 {
		mut rows := []TypedIndexRow{}
		for count <= 0 || rows.len < count {
			row := cursor.next() or { break }
			rows << row
		}
		return rows
	}
	entries := cursor.cursor.collect(count)!
	mut rows := []TypedIndexRow{cap: entries.len}
	for entry in entries {
		rows << typed_index_row_from_entry(cursor.view, entry)!
	}
	return rows
}

pub fn (mut reader BranchTableReader) get_row(primary_key []u8) !TypedSchemaRow {
	item := Tree.lookup_in_byte_store(reader.root_cid, database_row_key_with_prefix(reader.row_prefix,
		primary_key), mut reader.node_store)!
	return TypedSchemaRow{
		primary_key: primary_key.clone()
		data:        reader.codec.decode(item.value)!
	}
}

pub fn (mut reader BranchTableReader) get_row_projected(primary_key []u8, columns []string) !TypedSchemaRow {
	item := Tree.lookup_in_byte_store(reader.root_cid, database_row_key_with_prefix(reader.row_prefix,
		primary_key), mut reader.node_store)!
	return TypedSchemaRow{
		primary_key: primary_key.clone()
		data:        reader.codec.decode_projected(item.value, columns)!
	}
}

pub fn (mut reader BranchTableReader) get_row_with_stats(primary_key []u8) !StoreLookupResult {
	return Tree.lookup_in_byte_store_with_stats(reader.root_cid, database_row_key_with_prefix(reader.row_prefix,
		primary_key), mut reader.node_store)
}

pub fn (mut reader BranchIndexReader) find_rows(value ColumnValue, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_value(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	prefix << [u8(`|`)]
	primary_keys := Tree.suffix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: primary_keys.len}
	mut table_reader := BranchTableReader{
		branch_name: reader.branch_name
		spec:        reader.spec
		root_cid:    reader.root_cid
		codec:       reader.codec
		row_prefix:  reader.row_prefix.clone()
		node_store:  reader.node_store
	}
	for primary_key in primary_keys {
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader BranchIndexReader) find_rows_prefix(value ColumnValue, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_prefix(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	suffixes := Tree.suffix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: suffixes.len}
	mut table_reader := BranchTableReader{
		branch_name: reader.branch_name
		spec:        reader.spec
		root_cid:    reader.root_cid
		codec:       reader.codec
		row_prefix:  reader.row_prefix.clone()
		node_store:  reader.node_store
	}
	for suffix in suffixes {
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader BranchIndexReader) find_rows_covering(value ColumnValue, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_value(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	prefix << [u8(`|`)]
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	mut table_reader := BranchTableReader{
		branch_name: reader.branch_name
		spec:        reader.spec
		root_cid:    reader.root_cid
		codec:       reader.codec
		row_prefix:  reader.row_prefix.clone()
		node_store:  reader.node_store
	}
	for item in items {
		primary_key := item.key[prefix.len..].clone()
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode(item.value)!
			}
			continue
		}
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader BranchIndexReader) find_rows_covering_projected(value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_value(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	prefix << [u8(`|`)]
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	mut table_reader := BranchTableReader{
		branch_name: reader.branch_name
		spec:        reader.spec
		root_cid:    reader.root_cid
		codec:       reader.codec
		row_prefix:  reader.row_prefix.clone()
		node_store:  reader.node_store
	}
	for item in items {
		primary_key := item.key[prefix.len..].clone()
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode_projected(item.value, columns)!
			}
			continue
		}
		full_row := table_reader.get_row(primary_key)!
		mut projected := TypedRowData.new()
		for name in columns {
			if full_row.data.has(name) {
				projected.set(name, full_row.data.get(name)!)
			}
		}
		rows << TypedSchemaRow{
			primary_key: full_row.primary_key
			data:        projected
		}
	}
	return rows
}

pub fn (mut reader BranchIndexReader) find_rows_covering_prefix(value ColumnValue, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_prefix(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	mut table_reader := BranchTableReader{
		branch_name: reader.branch_name
		spec:        reader.spec
		root_cid:    reader.root_cid
		codec:       reader.codec
		row_prefix:  reader.row_prefix.clone()
		node_store:  reader.node_store
	}
	for item in items {
		suffix := item.key[prefix.len..]
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode(item.value)!
			}
			continue
		}
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader BranchIndexReader) find_rows_covering_prefix_projected(value ColumnValue, limit int, columns []string) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_prefix(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	mut table_reader := BranchTableReader{
		branch_name: reader.branch_name
		spec:        reader.spec
		root_cid:    reader.root_cid
		codec:       reader.codec
		row_prefix:  reader.row_prefix.clone()
		node_store:  reader.node_store
	}
	for item in items {
		suffix := item.key[prefix.len..]
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode_projected(item.value, columns)!
			}
			continue
		}
		full_row := table_reader.get_row(primary_key)!
		mut projected := TypedRowData.new()
		for name in columns {
			if full_row.data.has(name) {
				projected.set(name, full_row.data.get(name)!)
			}
		}
		rows << TypedSchemaRow{
			primary_key: full_row.primary_key
			data:        projected
		}
	}
	return rows
}

fn branch_index_scan_bounds(mut reader BranchIndexReader, start_value ColumnValue, has_start_value bool, start_primary_key []u8, reverse bool) !([]u8, []u8) {
	range_start := reader.index_prefix.clone()
	range_end := prefix_upper_bound(reader.index_prefix)!
	if !has_start_value {
		return range_start, range_end
	}
	encoded := TypedValueEncoder.encode_index_value(start_value, reader.index_column)!
	mut entry_prefix := reader.index_prefix.clone()
	entry_prefix << encoded
	entry_prefix << [u8(`|`)]
	if reverse {
		if start_primary_key.len > 0 {
			return range_start, build_index_entry_key(reader.index_prefix, encoded, start_primary_key)
		}
		return range_start, prefix_upper_bound(entry_prefix)!
	}
	if start_primary_key.len > 0 {
		return prefix_upper_bound(build_index_entry_key(reader.index_prefix, encoded,
			start_primary_key))!, range_end
	}
	return entry_prefix, range_end
}

pub fn (mut reader BranchIndexReader) find_rows_covering_ordered_projected(start_value ColumnValue, has_start_value bool, start_primary_key []u8, limit int, columns []string, reverse bool) ![]TypedSchemaRow {
	rows, _ := reader.find_rows_covering_ordered_projected_with_stats(start_value, has_start_value,
		start_primary_key, limit, columns, reverse)!
	return rows
}

pub fn (mut reader BranchIndexReader) find_rows_covering_ordered_projected_with_stats(start_value ColumnValue, has_start_value bool, start_primary_key []u8, limit int, columns []string, reverse bool) !([]TypedSchemaRow, OrderedScanStats) {
	start_key, end_key := branch_index_scan_bounds(mut reader, start_value, has_start_value,
		start_primary_key, reverse)!
	items, stats := Tree.ordered_scan_in_byte_store_with_stats(reader.root_cid, start_key,
		end_key, limit, reverse, mut reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	mut table_reader := BranchTableReader{
		branch_name: reader.branch_name
		spec:        reader.spec
		root_cid:    reader.root_cid
		codec:       reader.codec
		row_prefix:  reader.row_prefix.clone()
		node_store:  reader.node_store
	}
	for item in items {
		suffix := item.key[reader.index_prefix.len..]
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode_projected(item.value, columns)!
			}
			continue
		}
		full_row := table_reader.get_row(primary_key)!
		mut projected := TypedRowData.new()
		for name in columns {
			if full_row.data.has(name) {
				projected.set(name, full_row.data.get(name)!)
			}
		}
		rows << TypedSchemaRow{
			primary_key: full_row.primary_key
			data:        projected
		}
	}
	return rows, stats
}

pub fn (mut reader SnapshotTableReader) get_row(primary_key []u8) !TypedSchemaRow {
	item := Tree.lookup_in_byte_store(reader.root_cid, database_row_key_with_prefix(reader.row_prefix,
		primary_key), mut reader.node_store)!
	return TypedSchemaRow{
		primary_key: primary_key.clone()
		data:        reader.codec.decode(item.value)!
	}
}

pub fn (mut reader SnapshotTableReader) scan_rows(limit int) ![]TypedSchemaRow {
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, reader.row_prefix, reader.row_prefix,
		limit, mut reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	for item in items {
		primary_key := item.key[reader.row_prefix.len..].clone()
		rows << TypedSchemaRow{
			primary_key: primary_key
			data:        reader.codec.decode(item.value)!
		}
	}
	return rows
}

pub fn (mut reader SnapshotTableReader) scan_rows_from(start_primary_key []u8, limit int) ![]TypedSchemaRow {
	start_key := database_row_key_with_prefix(reader.row_prefix, start_primary_key)
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, start_key, reader.row_prefix,
		limit, mut reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	for item in items {
		primary_key := item.key[reader.row_prefix.len..].clone()
		rows << TypedSchemaRow{
			primary_key: primary_key
			data:        reader.codec.decode(item.value)!
		}
	}
	return rows
}

pub fn (mut reader SnapshotIndexReader) find_rows(value ColumnValue, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_value(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	prefix << [u8(`|`)]
	primary_keys := Tree.suffix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: primary_keys.len}
	mut table_reader := SnapshotTableReader{
		commit_cid: reader.commit_cid
		root_cid:   reader.root_cid
		spec:       reader.spec
		codec:      reader.codec
		row_prefix: reader.row_prefix.clone()
		node_store: reader.node_store
	}
	for primary_key in primary_keys {
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader SnapshotIndexReader) find_rows_prefix(value ColumnValue, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_prefix(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	suffixes := Tree.suffix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: suffixes.len}
	mut table_reader := SnapshotTableReader{
		commit_cid: reader.commit_cid
		root_cid:   reader.root_cid
		spec:       reader.spec
		codec:      reader.codec
		row_prefix: reader.row_prefix.clone()
		node_store: reader.node_store
	}
	for suffix in suffixes {
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader SnapshotIndexReader) find_rows_prefix_from(value ColumnValue, start_primary_key []u8, limit int) ![]TypedSchemaRow {
	primary_keys := reader.prefix_primary_keys_from(value, start_primary_key, limit)!
	mut rows := []TypedSchemaRow{cap: primary_keys.len}
	mut table_reader := SnapshotTableReader{
		commit_cid: reader.commit_cid
		root_cid:   reader.root_cid
		spec:       reader.spec
		codec:      reader.codec
		row_prefix: reader.row_prefix.clone()
		node_store: reader.node_store
	}
	for primary_key in primary_keys {
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader SnapshotIndexReader) find_rows_covering(value ColumnValue, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_value(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	prefix << [u8(`|`)]
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	mut table_reader := SnapshotTableReader{
		commit_cid: reader.commit_cid
		root_cid:   reader.root_cid
		spec:       reader.spec
		codec:      reader.codec
		row_prefix: reader.row_prefix.clone()
		node_store: reader.node_store
	}
	for item in items {
		primary_key := item.key[prefix.len..].clone()
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode(item.value)!
			}
			continue
		}
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader SnapshotIndexReader) find_rows_covering_prefix(value ColumnValue, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_prefix(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, prefix, prefix, limit, mut
		reader.node_store)!
	mut rows := []TypedSchemaRow{cap: items.len}
	mut table_reader := SnapshotTableReader{
		commit_cid: reader.commit_cid
		root_cid:   reader.root_cid
		spec:       reader.spec
		codec:      reader.codec
		row_prefix: reader.row_prefix.clone()
		node_store: reader.node_store
	}
	for item in items {
		suffix := item.key[prefix.len..]
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode(item.value)!
			}
			continue
		}
		rows << table_reader.get_row(primary_key)!
	}
	return rows
}

pub fn (mut reader SnapshotIndexReader) find_rows_covering_prefix_from(value ColumnValue, start_primary_key []u8, limit int) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_prefix(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, prefix, prefix, 0, mut reader.node_store)!
	mut rows := []TypedSchemaRow{}
	mut table_reader := SnapshotTableReader{
		commit_cid: reader.commit_cid
		root_cid:   reader.root_cid
		spec:       reader.spec
		codec:      reader.codec
		row_prefix: reader.row_prefix.clone()
		node_store: reader.node_store
	}
	for item in items {
		suffix := item.key[prefix.len..]
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		if start_primary_key.len > 0 && bytes_compare(primary_key, start_primary_key) < 0 {
			continue
		}
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode(item.value)!
			}
			continue
		}
		rows << table_reader.get_row(primary_key)!
		if limit > 0 && rows.len >= limit {
			break
		}
	}
	return rows
}

pub fn (mut reader SnapshotIndexReader) find_rows_covering_prefix_projected_from(value ColumnValue, start_primary_key []u8, limit int, columns []string) ![]TypedSchemaRow {
	encoded := TypedValueEncoder.encode_index_prefix(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	items := Tree.prefix_scan_in_byte_store(reader.root_cid, prefix, prefix, 0, mut reader.node_store)!
	mut rows := []TypedSchemaRow{}
	mut table_reader := SnapshotTableReader{
		commit_cid: reader.commit_cid
		root_cid:   reader.root_cid
		spec:       reader.spec
		codec:      reader.codec
		row_prefix: reader.row_prefix.clone()
		node_store: reader.node_store
	}
	for item in items {
		suffix := item.key[prefix.len..]
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		if start_primary_key.len > 0 && bytes_compare(primary_key, start_primary_key) < 0 {
			continue
		}
		if item.value.len > 0 {
			rows << TypedSchemaRow{
				primary_key: primary_key
				data:        reader.codec.decode_projected(item.value, columns)!
			}
		} else {
			full_row := table_reader.get_row(primary_key)!
			mut projected := TypedRowData.new()
			for name in columns {
				if full_row.data.has(name) {
					projected.set(name, full_row.data.get(name)!)
				}
			}
			rows << TypedSchemaRow{
				primary_key: full_row.primary_key
				data:        projected
			}
		}
		if limit > 0 && rows.len >= limit {
			break
		}
	}
	return rows
}

pub fn (mut reader SnapshotIndexReader) prefix_primary_keys_from(value ColumnValue, start_primary_key []u8, limit int) ![][]u8 {
	encoded := TypedValueEncoder.encode_index_prefix(value, reader.index_column)!
	mut prefix := reader.index_prefix.clone()
	prefix << encoded
	suffixes := Tree.suffix_scan_in_byte_store(reader.root_cid, prefix, prefix, 0, mut
		reader.node_store)!
	mut primary_keys := [][]u8{}
	for suffix in suffixes {
		separator_idx := bytes_index_byte(suffix, `|`) or {
			return error('invalid index key without primary-key separator')
		}
		primary_key := suffix[separator_idx + 1..].clone()
		if start_primary_key.len > 0 && bytes_compare(primary_key, start_primary_key) < 0 {
			continue
		}
		primary_keys << primary_key
		if limit > 0 && primary_keys.len >= limit {
			break
		}
	}
	return primary_keys
}

pub fn (mut reader SnapshotIndexReader) prefix_count_from(value ColumnValue, start_primary_key []u8, limit int) !int {
	primary_keys := reader.prefix_primary_keys_from(value, start_primary_key, limit)!
	return primary_keys.len
}

pub fn (mut reader SnapshotTablePairReader) scan_rows_from(start_primary_key []u8, limit int) !SnapshotIndexLookupPairResult {
	return SnapshotIndexLookupPairResult{
		left:  SnapshotIndexLookupResult{
			commit_cid: reader.left_commit_cid
			table_name: reader.left.spec.name()
			index_name: ''
			rows:       reader.left.scan_rows_from(start_primary_key, limit)!
		}
		right: SnapshotIndexLookupResult{
			commit_cid: reader.right_commit_cid
			table_name: reader.right.spec.name()
			index_name: ''
			rows:       reader.right.scan_rows_from(start_primary_key, limit)!
		}
	}
}

pub fn (mut reader SnapshotIndexPairReader) find_rows_covering_prefix_from(value ColumnValue, start_primary_key []u8, limit int) !SnapshotIndexLookupPairResult {
	return SnapshotIndexLookupPairResult{
		left:  SnapshotIndexLookupResult{
			commit_cid: reader.left_commit_cid
			table_name: reader.left.spec.name()
			index_name: reader.left.index.name
			rows:       reader.left.find_rows_covering_prefix_from(value, start_primary_key,
				limit)!
		}
		right: SnapshotIndexLookupResult{
			commit_cid: reader.right_commit_cid
			table_name: reader.right.spec.name()
			index_name: reader.right.index.name
			rows:       reader.right.find_rows_covering_prefix_from(value, start_primary_key,
				limit)!
		}
	}
}

pub fn (mut reader SnapshotIndexPairReader) find_rows_covering(value ColumnValue, limit int) !SnapshotIndexLookupPairResult {
	return SnapshotIndexLookupPairResult{
		left:  SnapshotIndexLookupResult{
			commit_cid: reader.left_commit_cid
			table_name: reader.left.spec.name()
			index_name: reader.left.index.name
			rows:       reader.left.find_rows_covering(value, limit)!
		}
		right: SnapshotIndexLookupResult{
			commit_cid: reader.right_commit_cid
			table_name: reader.right.spec.name()
			index_name: reader.right.index.name
			rows:       reader.right.find_rows_covering(value, limit)!
		}
	}
}

pub fn (mut reader SnapshotIndexPairReader) find_rows_prefix_from(value ColumnValue, start_primary_key []u8, limit int) !SnapshotIndexLookupPairResult {
	return SnapshotIndexLookupPairResult{
		left:  SnapshotIndexLookupResult{
			commit_cid: reader.left_commit_cid
			table_name: reader.left.spec.name()
			index_name: reader.left.index.name
			rows:       reader.left.find_rows_prefix_from(value, start_primary_key, limit)!
		}
		right: SnapshotIndexLookupResult{
			commit_cid: reader.right_commit_cid
			table_name: reader.right.spec.name()
			index_name: reader.right.index.name
			rows:       reader.right.find_rows_prefix_from(value, start_primary_key, limit)!
		}
	}
}

pub fn (mut reader SnapshotIndexPairReader) find_rows_covering_prefix_projected_from(value ColumnValue, start_primary_key []u8, limit int, columns []string) !SnapshotIndexLookupPairResult {
	return SnapshotIndexLookupPairResult{
		left:  SnapshotIndexLookupResult{
			commit_cid: reader.left_commit_cid
			table_name: reader.left.spec.name()
			index_name: reader.left.index.name
			rows:       reader.left.find_rows_covering_prefix_projected_from(value, start_primary_key,
				limit, columns)!
		}
		right: SnapshotIndexLookupResult{
			commit_cid: reader.right_commit_cid
			table_name: reader.right.spec.name()
			index_name: reader.right.index.name
			rows:       reader.right.find_rows_covering_prefix_projected_from(value, start_primary_key,
				limit, columns)!
		}
	}
}

pub fn (mut reader SnapshotIndexPairReader) prefix_primary_keys_from(value ColumnValue, start_primary_key []u8, limit int) !([][]u8, [][]u8) {
	left_keys := reader.left.prefix_primary_keys_from(value, start_primary_key, limit)!
	right_keys := reader.right.prefix_primary_keys_from(value, start_primary_key, limit)!
	return left_keys, right_keys
}

pub fn (mut reader SnapshotIndexPairReader) prefix_counts_from(value ColumnValue, start_primary_key []u8, limit int) !(int, int) {
	left_count := reader.left.prefix_count_from(value, start_primary_key, limit)!
	right_count := reader.right.prefix_count_from(value, start_primary_key, limit)!
	return left_count, right_count
}

pub fn (scheduler SnapshotReadScheduler) get_row_async(commit_cid string, table_name string, primary_key []u8) SnapshotRowLookupHandle {
	provider := scheduler.backend_provider()
	return SnapshotRowLookupHandle{
		worker: spawn snapshot_row_lookup_worker(provider, commit_cid, table_name, primary_key.clone())
	}
}

pub fn (scheduler SnapshotReadScheduler) lookup_index_async(commit_cid string, table_name string, index_name string, value ColumnValue, limit int) SnapshotIndexLookupHandle {
	provider := scheduler.backend_provider()
	return SnapshotIndexLookupHandle{
		worker: spawn snapshot_index_lookup_worker(provider, commit_cid, table_name, index_name,
			value, limit)
	}
}

pub fn (scheduler SnapshotReadScheduler) scan_table_async(commit_cid string, table_name string, limit int) SnapshotIndexLookupHandle {
	provider := scheduler.backend_provider()
	return SnapshotIndexLookupHandle{
		worker: spawn snapshot_table_scan_worker(provider, commit_cid, table_name, limit)
	}
}

pub fn (scheduler SnapshotReadScheduler) scan_table_from_async(commit_cid string, table_name string, start_primary_key []u8, limit int) SnapshotIndexLookupHandle {
	provider := scheduler.backend_provider()
	return SnapshotIndexLookupHandle{
		worker: spawn snapshot_table_scan_from_worker(provider, commit_cid, table_name,
			start_primary_key.clone(), limit)
	}
}

pub fn (scheduler SnapshotReadScheduler) lookup_index_prefix_async(commit_cid string, table_name string, index_name string, value ColumnValue, limit int) SnapshotIndexLookupHandle {
	provider := scheduler.backend_provider()
	return SnapshotIndexLookupHandle{
		worker: spawn snapshot_index_prefix_lookup_worker(provider, commit_cid, table_name,
			index_name, value, limit)
	}
}

pub fn (scheduler SnapshotReadScheduler) lookup_index_prefix_from_async(commit_cid string, table_name string, index_name string, value ColumnValue, start_primary_key []u8, limit int) SnapshotIndexLookupHandle {
	provider := scheduler.backend_provider()
	return SnapshotIndexLookupHandle{
		worker: spawn snapshot_index_prefix_lookup_from_worker(provider, commit_cid, table_name,
			index_name, value, start_primary_key.clone(), limit)
	}
}

pub fn (scheduler SnapshotReadScheduler) scan_table_pair_from_async(left_commit_cid string, right_commit_cid string, table_name string, start_primary_key []u8, limit int) SnapshotIndexLookupPairHandle {
	provider := scheduler.backend_provider()
	return SnapshotIndexLookupPairHandle{
		worker: spawn snapshot_table_scan_pair_from_worker(provider, left_commit_cid,
			right_commit_cid, table_name, start_primary_key.clone(), limit)
	}
}

pub fn (scheduler SnapshotReadScheduler) lookup_index_prefix_pair_from_async(left_commit_cid string, right_commit_cid string, table_name string, index_name string, value ColumnValue, start_primary_key []u8, limit int) SnapshotIndexLookupPairHandle {
	provider := scheduler.backend_provider()
	return SnapshotIndexLookupPairHandle{
		worker: spawn snapshot_index_prefix_lookup_pair_from_worker(provider, left_commit_cid,
			right_commit_cid, table_name, index_name, value, start_primary_key.clone(),
			limit)
	}
}

pub fn (mut session TransactionSession) commit(mut database PersistentDatabase, meta CommitMeta) !BranchTypedWorkingSetResult {
	return database.commit_typed_working_set(mut session.working_set, meta)
}

pub fn (mut session TransactionSession) merge_from(mut database PersistentDatabase, theirs_branch string, resolutions []ConflictResolution, cfg ChunkConfig) !WorkingSetMergeResult {
	return database.merge_into_working_set(mut session.working_set, theirs_branch, resolutions,
		cfg)
}

pub fn (session GroupCommitSession) transaction() TypedTransaction {
	return session.working_set.transaction()
}

pub fn (session GroupCommitSession) has_changes() bool {
	return session.working_set.has_changes()
}

pub fn (session GroupCommitSession) staged_diff() TreeDiff {
	return session.working_set.staged_diff()
}

pub fn (mut session GroupCommitSession) apply_write_set(mut db PersistentDatabase, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !TypedTransactionResult {
	normalized_write_set := normalize_temporal_write_set(session.working_set.transaction(),
		write_set)!
	mut tx_sw := time.new_stopwatch()
	result := session.working_set.apply_write_set(normalized_write_set, cfg)!
	mut group_commit := GroupCommitStageTimings{
		transaction_ms: tx_sw.elapsed().milliseconds()
	}
	session.pending_writes++
	session.last_meta = meta
	session.has_pending_meta = true
	if session.pending_writes >= session.options.checkpoint_every {
		flush_timings := session.flush_with_timings(mut db)!
		group_commit = GroupCommitStageTimings{
			transaction_ms: group_commit.transaction_ms
			commit_ms:      flush_timings.commit_ms
			checkpoint_ms:  flush_timings.checkpoint_ms
			flush_ms:       flush_timings.flush_ms
			flushed:        flush_timings.flushed
		}
	}
	return TypedTransactionResult{
		tx:           result.tx
		diff:         result.diff
		timings:      result.timings
		group_commit: group_commit
	}
}

pub fn (mut session GroupCommitSession) put_row(mut db PersistentDatabase, table_name string, primary_key []u8, row TypedRowData, cfg ChunkConfig, meta CommitMeta) !TypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.put(table_name, primary_key, row)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (mut session GroupCommitSession) put_rows(mut db PersistentDatabase, table_name string, rows map[string]TypedRowData, cfg ChunkConfig, meta CommitMeta) !TypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.put_many(table_name, rows)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (mut session GroupCommitSession) delete_row(mut db PersistentDatabase, table_name string, primary_key []u8, cfg ChunkConfig, meta CommitMeta) !TypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.delete(table_name, primary_key)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (mut session GroupCommitSession) delete_rows(mut db PersistentDatabase, table_name string, primary_keys [][]u8, cfg ChunkConfig, meta CommitMeta) !TypedTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.delete_many(table_name, primary_keys)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (mut session GroupCommitSession) flush(mut database PersistentDatabase) ! {
	_ = session.flush_with_timings(mut database)!
}

fn (mut session GroupCommitSession) flush_with_timings(mut database PersistentDatabase) !GroupCommitStageTimings {
	if session.pending_writes == 0 {
		return GroupCommitStageTimings{}
	}
	mut total_sw := time.new_stopwatch()
	mut commit_sw := time.new_stopwatch()
	database.commit_typed_working_set_buffered(mut session.working_set, session.last_meta)!
	commit_ms := commit_sw.elapsed().milliseconds()
	mut checkpoint_sw := time.new_stopwatch()
	database.checkpoint_mode(session.options.checkpoint_mode)!
	checkpoint_ms := checkpoint_sw.elapsed().milliseconds()
	if session.options.checkpoint_mode == .data_only && session.options.auto_refresh_index_snapshots {
		session.refresh_handles << PersistentDatabase.refresh_index_snapshots_async_for(database.root_dir,
			database.default_branch)
	}
	if session.options.checkpoint_mode == .data_only {
		limit := session.options.aggregate_projection_refresh_limit()
		mut handle := database.refresh_aggregate_projections_async_with_policy(session.branch_name,
			session.options.aggregate_projection_refresh_policy, if limit > 0 {
			limit
		} else {
			session.options.max_aggregate_projection_refreshes
		})!
		if handle.active {
			session.aggregate_refresh_handles << handle
		}
	}
	session.pending_writes = 0
	session.has_pending_meta = false
	return GroupCommitStageTimings{
		transaction_ms: 0
		commit_ms:      commit_ms
		checkpoint_ms:  checkpoint_ms
		flush_ms:       total_sw.elapsed().milliseconds()
		flushed:        true
	}
}

pub fn (mut session GroupCommitSession) wait_refreshes() ! {
	for mut handle in session.refresh_handles {
		handle.wait()!
	}
	session.refresh_handles = []IndexSnapshotRefreshHandle{}
	for mut handle in session.aggregate_refresh_handles {
		handle.wait()!
	}
	session.aggregate_refresh_handles = []AggregateProjectionRefreshHandle{}
}

pub fn (mut session GroupCommitSession) finish(mut database PersistentDatabase) ! {
	session.flush(mut database)!
	session.wait_refreshes()!
}

pub fn (session SplitGroupCommitSession) transaction() TypedSplitTransaction {
	return session.working_set.transaction()
}

pub fn (session SplitGroupCommitSession) has_changes() bool {
	return session.working_set.has_changes(session.last_cfg)
}

pub fn (mut session SplitGroupCommitSession) apply_write_set(mut db PersistentDatabase, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !TypedSplitTransactionResult {
	normalized_write_set := normalize_temporal_split_write_set(session.working_set.transaction(),
		write_set)!
	mut tx_sw := time.new_stopwatch()
	result := session.working_set.apply_write_set(normalized_write_set, cfg)!
	mut group_commit := GroupCommitStageTimings{
		transaction_ms: tx_sw.elapsed().milliseconds()
	}
	session.pending_writes++
	session.last_meta = meta
	session.last_cfg = cfg
	session.has_pending_meta = true
	if session.pending_writes >= session.options.checkpoint_every {
		flush_timings := session.flush_with_timings(mut db, false)!
		group_commit = GroupCommitStageTimings{
			transaction_ms: group_commit.transaction_ms
			commit_ms:      flush_timings.commit_ms
			checkpoint_ms:  flush_timings.checkpoint_ms
			flush_ms:       flush_timings.flush_ms
			flushed:        flush_timings.flushed
		}
	}
	return TypedSplitTransactionResult{
		tx:           result.tx
		group_commit: group_commit
	}
}

pub fn (mut session SplitGroupCommitSession) put_row(mut db PersistentDatabase, table_name string, primary_key []u8, row TypedRowData, cfg ChunkConfig, meta CommitMeta) !TypedSplitTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.put(table_name, primary_key, row)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (mut session SplitGroupCommitSession) put_rows(mut db PersistentDatabase, table_name string, rows map[string]TypedRowData, cfg ChunkConfig, meta CommitMeta) !TypedSplitTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.put_many(table_name, rows)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (mut session SplitGroupCommitSession) delete_row(mut db PersistentDatabase, table_name string, primary_key []u8, cfg ChunkConfig, meta CommitMeta) !TypedSplitTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.delete(table_name, primary_key)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (mut session SplitGroupCommitSession) delete_rows(mut db PersistentDatabase, table_name string, primary_keys [][]u8, cfg ChunkConfig, meta CommitMeta) !TypedSplitTransactionResult {
	mut write_set := TypedWriteSet.new()
	write_set.delete_many(table_name, primary_keys)
	return session.apply_write_set(mut db, write_set, cfg, meta)
}

pub fn (mut session SplitGroupCommitSession) flush(mut database PersistentDatabase) ! {
	_ = session.flush_with_timings(mut database, false)!
}

fn (mut session SplitGroupCommitSession) flush_with_timings(mut database PersistentDatabase, final_flush bool) !GroupCommitStageTimings {
	if session.pending_writes == 0 {
		return GroupCommitStageTimings{}
	}
	mut total_sw := time.new_stopwatch()
	mut commit_sw := time.new_stopwatch()
	database.commit_typed_split_working_set_mode(mut session.working_set, session.last_meta,
		session.last_cfg, !final_flush)!
	commit_ms := commit_sw.elapsed().milliseconds()
	mut checkpoint_sw := time.new_stopwatch()
	database.checkpoint_mode(session.options.checkpoint_mode)!
	checkpoint_ms := checkpoint_sw.elapsed().milliseconds()
	if session.options.checkpoint_mode == .data_only && session.options.auto_refresh_index_snapshots {
		session.refresh_handles << PersistentDatabase.refresh_index_snapshots_async_for(database.root_dir,
			database.default_branch)
	}
	if session.options.checkpoint_mode == .data_only {
		limit := session.options.aggregate_projection_refresh_limit()
		mut handle := database.refresh_aggregate_projections_async_with_policy(session.branch_name,
			session.options.aggregate_projection_refresh_policy, if limit > 0 {
			limit
		} else {
			session.options.max_aggregate_projection_refreshes
		})!
		if handle.active {
			session.aggregate_refresh_handles << handle
		}
	}
	session.pending_writes = 0
	session.has_pending_meta = false
	return GroupCommitStageTimings{
		transaction_ms: 0
		commit_ms:      commit_ms
		checkpoint_ms:  checkpoint_ms
		flush_ms:       total_sw.elapsed().milliseconds()
		flushed:        true
	}
}

pub fn (mut session SplitGroupCommitSession) wait_refreshes() ! {
	for mut handle in session.refresh_handles {
		handle.wait()!
	}
	session.refresh_handles = []IndexSnapshotRefreshHandle{}
	for mut handle in session.aggregate_refresh_handles {
		handle.wait()!
	}
	session.aggregate_refresh_handles = []AggregateProjectionRefreshHandle{}
}

pub fn (mut session SplitGroupCommitSession) finish(mut database PersistentDatabase) ! {
	_ = session.flush_with_timings(mut database, true)!
	session.wait_refreshes()!
}

pub enum AggregateProjectionCostHint {
	low
	medium
	high
}

pub struct FieldProjectionSelectorRef {
pub:
	plugin_name string
	selector    string
}

pub struct AggregateProjectionDef {
pub:
	name                     string
	table_name               string
	column_name              string
	source_json_path         string
	source_markdown_selector string
	aggregate                ColumnAggregate
	priority                 int                         = 100
	cost_hint                AggregateProjectionCostHint = .medium
}

pub struct AggregateProjectorState {
pub:
	projection            AggregateProjectionDef
	current_data_root_cid string
	source_data_root_cid  string
	virtual_root_cid      string
	fresh                 bool
	stale_reason          string
}

pub struct AggregateProjectionValue {
pub:
	projection            AggregateProjectionDef
	branch_name           string
	value                 i64
	current_data_root_cid string
	source_data_root_cid  string
	virtual_root_cid      string
	fresh                 bool
	stale_reason          string
}

pub fn AggregateProjectionDef.sum_i64(name string, table_name string, column_name string) !AggregateProjectionDef {
	if name.len == 0 {
		return error('aggregate projection name cannot be empty')
	}
	if table_name.len == 0 {
		return error('aggregate projection table name cannot be empty')
	}
	if column_name.len == 0 {
		return error('aggregate projection column name cannot be empty')
	}
	return AggregateProjectionDef{
		name:             name
		table_name:       table_name
		column_name:      column_name
		source_json_path: ''
		aggregate:        .sum
		priority:         100
		cost_hint:        .medium
	}
}

pub fn AggregateProjectionDef.sum_json_i64(name string, table_name string, column_name string, source_json_path string) !AggregateProjectionDef {
	if source_json_path.len == 0 {
		return error('aggregate projection json path cannot be empty')
	}
	AggregateProjectionDef.sum_i64(name, table_name, column_name)!
	return AggregateProjectionDef{
		name:                     name
		table_name:               table_name
		column_name:              column_name
		source_json_path:         source_json_path
		source_markdown_selector: ''
		aggregate:                .sum
		priority:                 100
		cost_hint:                .medium
	}
}

pub fn AggregateProjectionDef.count_markdown_blocks(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'blocks')
}

pub fn AggregateProjectionDef.count_markdown_block_kind(name string, table_name string, column_name string, kind string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'blocks:${kind}')
}

pub fn AggregateProjectionDef.count_markdown_headings(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'headings')
}

pub fn AggregateProjectionDef.count_markdown_heading_level(name string, table_name string, column_name string, level int) !AggregateProjectionDef {
	if level < 1 || level > 6 {
		return error('markdown heading level must be between 1 and 6')
	}
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'headings:${level}')
}

pub fn AggregateProjectionDef.count_markdown_links(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'links')
}

pub fn AggregateProjectionDef.count_markdown_images(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'images')
}

pub fn AggregateProjectionDef.count_markdown_code_blocks(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'code_blocks')
}

pub fn AggregateProjectionDef.count_markdown_code_blocks_with_lang(name string, table_name string, column_name string, lang string) !AggregateProjectionDef {
	if lang.len == 0 {
		return error('markdown code block language cannot be empty')
	}
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'code_blocks:${lang}')
}

pub fn AggregateProjectionDef.count_markdown_code_spans(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
		'code_spans')
}

pub fn AggregateProjectionDef.count_field_selector(name string, table_name string, column_name string, plugin_name string, selector string) !AggregateProjectionDef {
	if plugin_name.len == 0 {
		return error('aggregate projection field selector plugin cannot be empty')
	}
	AggregateProjectionDef.sum_i64(name, table_name, column_name)!
	return match plugin_name {
		'markdown' {
			AggregateProjectionDef.count_markdown_selector(name, table_name, column_name,
				selector)!
		}
		else {
			return error('unsupported aggregate projection field selector plugin: ${plugin_name}')
		}
	}
}

pub fn AggregateProjectionDef.count_markdown_selector(name string, table_name string, column_name string, selector string) !AggregateProjectionDef {
	AggregateProjectionDef.sum_i64(name, table_name, column_name)!
	validate_markdown_projection_selector(selector)!
	return AggregateProjectionDef{
		name:                     name
		table_name:               table_name
		column_name:              column_name
		source_json_path:         ''
		source_markdown_selector: selector
		aggregate:                .sum
		priority:                 100
		cost_hint:                .medium
	}
}

pub fn (def AggregateProjectionDef) is_field_projection_selector() bool {
	return def.source_markdown_selector.len > 0
}

pub fn (def AggregateProjectionDef) field_projection_plugin() string {
	if def.source_markdown_selector.len > 0 {
		return 'markdown'
	}
	return ''
}

pub fn (def AggregateProjectionDef) field_projection_selector() string {
	if def.source_markdown_selector.len > 0 {
		return def.source_markdown_selector
	}
	return ''
}

pub fn (def AggregateProjectionDef) field_projection_selector_ref() ?FieldProjectionSelectorRef {
	plugin_name := def.field_projection_plugin()
	selector := def.field_projection_selector()
	if plugin_name.len == 0 || selector.len == 0 {
		return none
	}
	return FieldProjectionSelectorRef{
		plugin_name: plugin_name
		selector:    selector
	}
}

pub fn (def AggregateProjectionDef) field_projection_meta() ?FieldSelectorRef {
	plugin_name := def.field_projection_plugin()
	selector := def.field_projection_selector()
	if plugin_name.len == 0 || selector.len == 0 {
		return none
	}
	return FieldSelectorRef{
		plugin_name: plugin_name
		selector:    selector
		value_type:  .i64_
		stores_row:  false
	}
}

pub fn (def AggregateProjectionDef) with_priority(priority int) AggregateProjectionDef {
	return AggregateProjectionDef{
		...def
		priority: if priority >= 0 { priority } else { 0 }
	}
}

pub fn (def AggregateProjectionDef) with_cost_hint(cost_hint AggregateProjectionCostHint) AggregateProjectionDef {
	return AggregateProjectionDef{
		...def
		cost_hint: cost_hint
	}
}

pub fn (state AggregateProjectorState) to_virtual_root_ref() VirtualRootRef {
	return VirtualRootRef{
		name:                 state.projection.name
		root_cid:             state.virtual_root_cid
		source_data_root_cid: state.source_data_root_cid
		fresh:                state.fresh
		stale_reason:         state.stale_reason
	}
}

fn aggregate_projection_value_key(name string) []u8 {
	return 'aggregate:${name}'.bytes()
}

fn validate_markdown_projection_selector(selector string) ! {
	if selector.len == 0 {
		return error('markdown projection selector cannot be empty')
	}
	parts := selector.split(':')
	match parts[0] {
		'blocks' {
			if parts.len > 2 {
				return error('markdown block selector must be blocks or blocks:<kind>')
			}
			if parts.len == 2
				&& parts[1] !in ['meta', 'heading', 'paragraph', 'blockquote', 'list', 'code_block', 'horizontal_rule'] {
				return error('unsupported markdown block kind selector: ${parts[1]}')
			}
		}
		'headings' {
			if parts.len > 2 {
				return error('markdown heading selector must be headings or headings:<level>')
			}
			if parts.len == 2 {
				level := parts[1].int()
				if level < 1 || level > 6 {
					return error('markdown heading selector level must be between 1 and 6')
				}
			}
		}
		'links', 'images', 'code_spans', 'code_blocks' {
			if parts[0] != 'code_blocks' && parts.len > 1 {
				return error('markdown selector ${parts[0]} does not accept a qualifier')
			}
			if parts[0] == 'code_blocks' && parts.len > 2 {
				return error('markdown code block selector must be code_blocks or code_blocks:<lang>')
			}
		}
		else {
			return error('unsupported markdown projection selector: ${selector}')
		}
	}
}

fn validate_markdown_index_selector(selector string, value_type ColumnType) ! {
	parts := selector.split(':')
	match parts[0] {
		'links', 'images', 'code_spans', 'code_blocks', 'blocks', 'headings' {
			if value_type != .i64_ {
				return error('markdown metric selector ${selector} requires i64 index type')
			}
			validate_markdown_projection_selector(selector)!
		}
		'code_block_lang', 'link_host', 'image_host', 'heading_text' {
			if value_type != .string_ {
				return error('markdown value selector ${selector} requires string index type')
			}
			if parts[0] == 'heading_text' && parts.len > 2 {
				return error('markdown heading_text selector must be heading_text or heading_text:<level>')
			}
			if parts[0] == 'heading_text' && parts.len == 2 {
				level := parts[1].int()
				if level < 1 || level > 6 {
					return error('markdown heading_text selector level must be between 1 and 6')
				}
			}
			if parts[0] != 'heading_text' && parts.len > 1 {
				return error('markdown value selector ${selector} does not accept a qualifier')
			}
		}
		'fts' {
			if value_type != .string_ {
				return error('markdown value selector ${selector} requires string index type')
			}
			if parts.len > 2 {
				return error('markdown fts selector must be fts or fts:<scope>')
			}
			if parts.len == 2 && parts[1] !in ['heading', 'paragraph', 'code_block', 'list_item'] {
				return error('unsupported markdown fts scope selector: ${parts[1]}')
			}
		}
		else {
			return error('unsupported markdown index selector: ${selector}')
		}
	}
}

fn markdown_url_host(url string) string {
	mut raw := url.trim_space()
	if raw.len == 0 {
		return ''
	}
	if raw.contains('://') {
		raw = raw.all_after('://')
	}
	if raw.starts_with('//') {
		raw = raw[2..]
	}
	for sep in ['/', '?', '#'] {
		if raw.contains(sep) {
			raw = raw.all_before(sep)
		}
	}
	if raw.contains('@') {
		raw = raw.all_after('@')
	}
	if raw.contains(':') {
		raw = raw.all_before(':')
	}
	return raw.to_lower()
}

fn markdown_inline_text_value(nodes []vmarkdown.InlineNode) string {
	mut out := ''
	for node in nodes {
		match node {
			vmarkdown.TextNode {
				out += node.text
			}
			vmarkdown.EmphasisNode {
				out += markdown_inline_text_value(node.children)
			}
			vmarkdown.StrongNode {
				out += markdown_inline_text_value(node.children)
			}
			vmarkdown.CodeSpanNode {
				out += node.text
			}
			vmarkdown.LinkNode {
				out += markdown_inline_text_value(node.text)
			}
			vmarkdown.ImageNode {
				out += markdown_inline_text_value(node.alt)
			}
		}
	}
	return out.trim_space()
}

fn markdown_append_distinct(mut out []ColumnValue, value ColumnValue) {
	for existing in out {
		if column_values_equal(existing, value) {
			return
		}
	}
	out << value
}

fn collect_markdown_index_values_from_inlines(selector string, nodes []vmarkdown.InlineNode, mut out []ColumnValue) {
	parts := selector.split(':')
	for node in nodes {
		match node {
			vmarkdown.EmphasisNode {
				collect_markdown_index_values_from_inlines(selector, node.children, mut
					out)
			}
			vmarkdown.StrongNode {
				collect_markdown_index_values_from_inlines(selector, node.children, mut
					out)
			}
			vmarkdown.LinkNode {
				if parts[0] == 'link_host' {
					host := markdown_url_host(node.url)
					if host.len > 0 {
						markdown_append_distinct(mut out, ColumnValue(host))
					}
				}
				collect_markdown_index_values_from_inlines(selector, node.text, mut out)
			}
			vmarkdown.ImageNode {
				if parts[0] == 'image_host' {
					host := markdown_url_host(node.url)
					if host.len > 0 {
						markdown_append_distinct(mut out, ColumnValue(host))
					}
				}
				collect_markdown_index_values_from_inlines(selector, node.alt, mut out)
			}
			else {}
		}
	}
}

fn collect_markdown_index_values(selector string, nodes []vmarkdown.BlockNode, mut out []ColumnValue) {
	parts := selector.split(':')
	for node in nodes {
		match node {
			vmarkdown.MetaNode {}
			vmarkdown.HeadingNode {
				if parts[0] == 'heading_text' && (parts.len == 1 || node.level == parts[1].int()) {
					text := markdown_inline_text_value(node.children)
					if text.len > 0 {
						markdown_append_distinct(mut out, ColumnValue(text))
					}
				}
				collect_markdown_index_values_from_inlines(selector, node.children, mut
					out)
			}
			vmarkdown.ParagraphNode {
				collect_markdown_index_values_from_inlines(selector, node.children, mut
					out)
			}
			vmarkdown.BlockquoteNode {
				collect_markdown_index_values(selector, node.children, mut out)
			}
			vmarkdown.ListNode {
				for item in node.items {
					collect_markdown_index_values(selector, item.children, mut out)
				}
			}
			vmarkdown.CodeBlockNode {
				if parts[0] == 'code_block_lang' {
					lang := node.lang.trim_space()
					if lang.len > 0 {
						markdown_append_distinct(mut out, ColumnValue(lang))
					}
				}
			}
			vmarkdown.HorizontalRuleNode {}
		}
	}
}

fn markdown_fts_scope_from_selector(selector string) FtsScope {
	parts := selector.split(':')
	if parts.len == 1 {
		return .any
	}
	return match parts[1] {
		'heading' { .heading }
		'paragraph' { .paragraph }
		'code_block' { .code_block }
		'list_item' { .list_item }
		else { .any }
	}
}

fn markdown_index_values(selector string, doc vmarkdown.Document, value_type ColumnType) ![]ColumnValue {
	validate_markdown_index_selector(selector, value_type)!
	if value_type == .i64_ {
		return [ColumnValue(count_markdown_blocks(selector, doc.children))]
	}
	if selector.starts_with('fts') {
		scope := markdown_fts_scope_from_selector(selector)
		mut out := []ColumnValue{}
		for key in fts_distinct_keys(emit_markdown_fts_tokens_from_doc(doc)) {
			if key.scope != scope {
				continue
			}
			markdown_append_distinct(mut out, ColumnValue(key.term))
		}
		return out
	}
	mut out := []ColumnValue{}
	collect_markdown_index_values(selector, doc.children, mut out)
	return out
}

fn build_aggregate_projection_tree(def AggregateProjectionDef, value i64, cfg ChunkConfig) !Tree {
	return Tree.build([
		KVPair{
			key:   aggregate_projection_value_key(def.name)
			value: TypedValueEncoder.encode_value(value, .i64_)!
		},
	], cfg)
}

fn compute_sum_json_i64_projection(mut db PersistentDatabase, branch_name string, def AggregateProjectionDef) !i64 {
	session := db.begin_session(SessionOptions.for_branch(branch_name))!
	mut cursor := session.table_cursor(mut db, def.table_name, []u8{}, 0)!
	mut total := i64(0)
	for {
		row := cursor.next() or { break }
		if !row.data.has(def.column_name) {
			continue
		}
		raw := row.data.get(def.column_name)!
		match raw {
			string {
				root := json2.decode[map[string]json2.Any](raw)!
				value := json_lookup_path_value(root, def.source_json_path)!
				match value {
					i64 {
						total += value
					}
					NullValue {}
					else {
						return error('aggregate projection ${def.name} requires i64 json scalar at ${def.source_json_path}')
					}
				}
			}
			else {
				return error('aggregate projection ${def.name} requires json string payload in ${def.column_name}')
			}
		}
	}
	return total
}

fn markdown_block_kind(node vmarkdown.BlockNode) string {
	return match node {
		vmarkdown.MetaNode { 'meta' }
		vmarkdown.HeadingNode { 'heading' }
		vmarkdown.ParagraphNode { 'paragraph' }
		vmarkdown.BlockquoteNode { 'blockquote' }
		vmarkdown.ListNode { 'list' }
		vmarkdown.CodeBlockNode { 'code_block' }
		vmarkdown.HorizontalRuleNode { 'horizontal_rule' }
	}
}

fn markdown_inline_kind(node vmarkdown.InlineNode) string {
	return match node {
		vmarkdown.TextNode { 'text' }
		vmarkdown.EmphasisNode { 'emphasis' }
		vmarkdown.StrongNode { 'strong' }
		vmarkdown.CodeSpanNode { 'code_span' }
		vmarkdown.LinkNode { 'link' }
		vmarkdown.ImageNode { 'image' }
	}
}

fn markdown_selector_matches_block(selector string, node vmarkdown.BlockNode) bool {
	parts := selector.split(':')
	kind := markdown_block_kind(node)
	match parts[0] {
		'blocks' {
			return parts.len == 1 || kind == parts[1]
		}
		'headings' {
			if node is vmarkdown.HeadingNode {
				if parts.len == 1 {
					return true
				}
				return node.level == parts[1].int()
			}
			return false
		}
		'code_blocks' {
			if node is vmarkdown.CodeBlockNode {
				if parts.len == 1 {
					return true
				}
				return node.lang == parts[1]
			}
			return false
		}
		else {
			return false
		}
	}
}

fn markdown_selector_matches_inline(selector string, node vmarkdown.InlineNode) bool {
	return match selector {
		'links' { markdown_inline_kind(node) == 'link' }
		'images' { markdown_inline_kind(node) == 'image' }
		'code_spans' { markdown_inline_kind(node) == 'code_span' }
		else { false }
	}
}

fn count_markdown_inline_nodes(selector string, nodes []vmarkdown.InlineNode) i64 {
	mut total := i64(0)
	for node in nodes {
		if markdown_selector_matches_inline(selector, node) {
			total++
		}
		match node {
			vmarkdown.EmphasisNode {
				total += count_markdown_inline_nodes(selector, node.children)
			}
			vmarkdown.StrongNode {
				total += count_markdown_inline_nodes(selector, node.children)
			}
			vmarkdown.LinkNode {
				total += count_markdown_inline_nodes(selector, node.text)
			}
			vmarkdown.ImageNode {
				total += count_markdown_inline_nodes(selector, node.alt)
			}
			else {}
		}
	}
	return total
}

fn count_markdown_blocks(selector string, nodes []vmarkdown.BlockNode) i64 {
	mut total := i64(0)
	for node in nodes {
		if markdown_selector_matches_block(selector, node) {
			total++
		}
		match node {
			vmarkdown.MetaNode {}
			vmarkdown.HeadingNode {
				total += count_markdown_inline_nodes(selector, node.children)
			}
			vmarkdown.ParagraphNode {
				total += count_markdown_inline_nodes(selector, node.children)
			}
			vmarkdown.BlockquoteNode {
				total += count_markdown_blocks(selector, node.children)
			}
			vmarkdown.ListNode {
				for item in node.items {
					total += count_markdown_blocks(selector, item.children)
				}
			}
			vmarkdown.CodeBlockNode {}
			vmarkdown.HorizontalRuleNode {}
		}
	}
	return total
}

fn compute_markdown_projection_value(mut db PersistentDatabase, branch_name string, def AggregateProjectionDef) !i64 {
	spec := db.table_spec(def.table_name)!
	column := spec.table.column(def.column_name)!
	return compute_field_projection_i64(mut db, branch_name, def.table_name, column, def.field_projection_selector())
}

fn compute_aggregate_projection_value(mut db PersistentDatabase, branch_name string, def AggregateProjectionDef) !i64 {
	session := db.begin_session(SessionOptions.for_branch(branch_name))!
	return if def.is_field_projection_selector() {
		compute_markdown_projection_value(mut db, branch_name, def)
	} else if def.source_json_path.len == 0 {
		session.sum_i64_column(mut db, def.table_name, def.column_name)
	} else {
		compute_sum_json_i64_projection(mut db, branch_name, def)
	}
}

pub fn (mut db PersistentDatabase) projection_value_at_branch(branch_name string, name string) !AggregateProjectionValue {
	states := db.projection_states_at_branch(branch_name)!
	for state in states {
		if state.projection.name != name {
			continue
		}
		if state.virtual_root_cid.len == 0 {
			return error('aggregate projection ${name} has no materialized virtual root on ${branch_name}')
		}
		item := Tree.lookup_in_byte_store(state.virtual_root_cid, aggregate_projection_value_key(name), mut
			db.engine.repository.node_store)!
		raw := TypedValueEncoder.decode_value(item.value, .i64_)!
		match raw {
			i64 {
				return AggregateProjectionValue{
					projection:            state.projection
					branch_name:           branch_name
					value:                 raw
					current_data_root_cid: state.current_data_root_cid
					source_data_root_cid:  state.source_data_root_cid
					virtual_root_cid:      state.virtual_root_cid
					fresh:                 state.fresh
					stale_reason:          state.stale_reason
				}
			}
			else {
				return error('aggregate projection ${name} stored a non-i64 value')
			}
		}
	}
	return error('aggregate projection not registered: ${name}')
}

pub fn (mut db PersistentDatabase) projection_i64_at_branch(branch_name string, name string) !i64 {
	return db.projection_value_at_branch(branch_name, name)!.value
}

pub fn (mut db PersistentDatabase) projection_value(name string) !AggregateProjectionValue {
	return db.projection_value_at_branch(db.default_branch, name)
}

pub fn (mut db PersistentDatabase) projection_i64(name string) !i64 {
	return db.projection_i64_at_branch(db.default_branch, name)
}

pub fn (mut db PersistentDatabase) markdown_projection_i64_at_branch(branch_name string, table_name string, column_name string, selector string) !i64 {
	spec := db.table_spec(table_name)!
	column := spec.table.column(column_name)!
	return compute_field_projection_i64(mut db, branch_name, table_name, column, selector)
}

pub fn (mut db PersistentDatabase) markdown_projection_i64(table_name string, column_name string, selector string) !i64 {
	return db.markdown_projection_i64_at_branch(db.default_branch, table_name, column_name,
		selector)
}

pub fn (mut db PersistentDatabase) refresh_aggregate_projections(branch_name string, cfg ChunkConfig, meta CommitMeta) !Commit {
	return db.refresh_aggregate_projections_limited(branch_name, cfg, meta, 0)
}

pub fn (mut db PersistentDatabase) refresh_aggregate_projections_limited(branch_name string, cfg ChunkConfig, meta CommitMeta, limit int) !Commit {
	current := db.engine.checkout(branch_name)!
	mut existing := map[string]VirtualRootRef{}
	for virtual_root in current.virtual_roots {
		existing[virtual_root.name] = virtual_root
	}

	mut next_roots := []VirtualRootRef{}
	for virtual_root in current.virtual_roots {
		if virtual_root.name !in db.projectors {
			next_roots << virtual_root
		}
	}
	mut refreshed := 0
	for name in sorted_projector_names_by_priority(db.projectors) {
		projector := db.projectors[name] or { continue }
		current_ref := existing[name] or {
			VirtualRootRef{
				name:                 projector.name
				root_cid:             ''
				source_data_root_cid: current.root_cid
				fresh:                false
				stale_reason:         'registration_backfill'
			}
		}
		if current_ref.fresh && current_ref.source_data_root_cid == current.root_cid
			&& current_ref.root_cid.len > 0 {
			next_roots << current_ref
			continue
		}
		if limit > 0 && refreshed >= limit {
			next_roots << VirtualRootRef{
				name:                 projector.name
				root_cid:             current_ref.root_cid
				source_data_root_cid: current.root_cid
				fresh:                false
				stale_reason:         'policy_budget_skipped'
			}
			continue
		}
		value := compute_aggregate_projection_value(mut db, branch_name, projector)!
		tree := build_aggregate_projection_tree(projector, value, cfg)!
		db.engine.repository.node_store.put_tree(tree)!
		refreshed++
		next_roots << VirtualRootRef{
			name:                 projector.name
			root_cid:             tree.root.cid
			source_data_root_cid: current.root_cid
			fresh:                true
			stale_reason:         ''
		}
	}
	return db.engine.commit_virtual_roots_for_branch(branch_name, next_roots, CommitMeta{
		author:    if meta.author.len > 0 { meta.author } else { 'pollydb/projector' }
		message:   if meta.message.len > 0 { meta.message } else { 'refresh aggregate projections' }
		timestamp: if meta.timestamp != 0 { meta.timestamp } else { time.now().unix() }
	})
}
