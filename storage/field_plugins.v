module storage

import vmarkdown

pub interface FieldIndexStrategy {
	plugin_name() string
	supports(column ColumnDef) bool
	validate_selector(selector string, value_type ColumnType) !
	expand_index_values(root_dir string, column ColumnDef, stored ColumnValue, selector string, value_type ColumnType) ![]ColumnValue
}

pub interface FieldProjectionStrategy {
	plugin_name() string
	supports(column ColumnDef) bool
	validate_selector(selector string) !
	compute_projection(mut db PersistentDatabase, branch_name string, table_name string, column ColumnDef, selector string) !i64
}

pub interface FieldMergeStrategy {
	plugin_name() string
	supports(column ColumnDef) bool
	try_merge(mut db PersistentDatabase, column ColumnDef, base ColumnValue, ours ColumnValue, theirs ColumnValue) ?ColumnValue
}

pub interface ExternalFieldStorage {
	plugin_name() string
	supports(column ColumnDef) bool
	ingest(mut db PersistentDatabase, column ColumnDef, raw ColumnValue) !ColumnValue
	load(database &PersistentDatabase, column ColumnDef, stored ColumnValue) !ColumnValue
	diff_summary(database &PersistentDatabase, column ColumnDef, base ColumnValue, current ColumnValue, limit int) !string
}

pub struct FieldCapabilityRegistry {
pub mut:
	index_strategies      []FieldIndexStrategy
	projection_strategies []FieldProjectionStrategy
	merge_strategies      []FieldMergeStrategy
	external_storages     []ExternalFieldStorage
}

struct MarkdownFieldIndexStrategy {}
struct MarkdownFieldProjectionStrategy {}
struct MarkdownFieldMergeStrategy {}
struct MarkdownExternalFieldStorage {}

pub fn FieldCapabilityRegistry.new() FieldCapabilityRegistry {
	return FieldCapabilityRegistry{
		index_strategies: []FieldIndexStrategy{}
		projection_strategies: []FieldProjectionStrategy{}
		merge_strategies: []FieldMergeStrategy{}
		external_storages: []ExternalFieldStorage{}
	}
}

pub fn default_field_capability_registry() FieldCapabilityRegistry {
	mut registry := FieldCapabilityRegistry.new()
	registry.install_markdown_defaults()
	return registry
}

pub fn (mut registry FieldCapabilityRegistry) register_index_strategy(strategy FieldIndexStrategy) {
	registry.index_strategies << strategy
}

pub fn (mut registry FieldCapabilityRegistry) register_projection_strategy(strategy FieldProjectionStrategy) {
	registry.projection_strategies << strategy
}

pub fn (mut registry FieldCapabilityRegistry) register_merge_strategy(strategy FieldMergeStrategy) {
	registry.merge_strategies << strategy
}

pub fn (mut registry FieldCapabilityRegistry) register_external_storage(handler ExternalFieldStorage) {
	registry.external_storages << handler
}

pub fn (mut registry FieldCapabilityRegistry) install_markdown_defaults() {
	registry.register_index_strategy(MarkdownFieldIndexStrategy{})
	registry.register_projection_strategy(MarkdownFieldProjectionStrategy{})
	registry.register_merge_strategy(MarkdownFieldMergeStrategy{})
	registry.register_external_storage(MarkdownExternalFieldStorage{})
}

pub fn (registry FieldCapabilityRegistry) index_strategy_for(column ColumnDef) ?FieldIndexStrategy {
	for strategy in registry.index_strategies {
		if strategy.supports(column) {
			return strategy
		}
	}
	return none
}

pub fn (registry FieldCapabilityRegistry) projection_strategy_for(column ColumnDef) ?FieldProjectionStrategy {
	for strategy in registry.projection_strategies {
		if strategy.supports(column) {
			return strategy
		}
	}
	return none
}

pub fn (registry FieldCapabilityRegistry) merge_strategy_for(column ColumnDef) ?FieldMergeStrategy {
	for strategy in registry.merge_strategies {
		if strategy.supports(column) {
			return strategy
		}
	}
	return none
}

pub fn (registry FieldCapabilityRegistry) external_storage_for(column ColumnDef) ?ExternalFieldStorage {
	for storage in registry.external_storages {
		if storage.supports(column) {
			return storage
		}
	}
	return none
}

pub fn (registry FieldCapabilityRegistry) plugin_names() []string {
	mut seen := map[string]bool{}
	mut names := []string{}
	for strategy in registry.index_strategies {
		name := strategy.plugin_name()
		if name.len == 0 || seen[name] {
			continue
		}
		seen[name] = true
		names << name
	}
	for strategy in registry.projection_strategies {
		name := strategy.plugin_name()
		if name.len == 0 || seen[name] {
			continue
		}
		seen[name] = true
		names << name
	}
	for strategy in registry.merge_strategies {
		name := strategy.plugin_name()
		if name.len == 0 || seen[name] {
			continue
		}
		seen[name] = true
		names << name
	}
	for handler in registry.external_storages {
		name := handler.plugin_name()
		if name.len == 0 || seen[name] {
			continue
		}
		seen[name] = true
		names << name
	}
	names.sort()
	return names
}

pub fn field_index_strategy_for(column ColumnDef) ?FieldIndexStrategy {
	return default_field_capability_registry().index_strategy_for(column)
}

pub fn field_projection_strategy_for(column ColumnDef) ?FieldProjectionStrategy {
	return default_field_capability_registry().projection_strategy_for(column)
}

pub fn field_merge_strategy_for(column ColumnDef) ?FieldMergeStrategy {
	return default_field_capability_registry().merge_strategy_for(column)
}

pub fn external_field_storage_for(column ColumnDef) ?ExternalFieldStorage {
	return default_field_capability_registry().external_storage_for(column)
}

pub fn validate_named_field_selector(plugin_name string, selector string, value_type ColumnType) ! {
	match plugin_name {
		'markdown' {
			validate_markdown_index_selector(selector, value_type)!
		}
		else {
			return error('unsupported field selector plugin: ${plugin_name}')
		}
	}
}

pub fn validate_field_projection_selector(column ColumnDef, selector string) ! {
	strategy := field_projection_strategy_for(column) or {
		return error('field projection requires capability-enabled column: ${column.name}')
	}
	strategy.validate_selector(selector)!
}

pub fn compute_field_projection_i64(mut db PersistentDatabase, branch_name string, table_name string, column ColumnDef, selector string) !i64 {
	strategy := db.field_capability_registry().projection_strategy_for(column) or {
		return error('field projection requires capability-enabled column: ${column.name}')
	}
	return strategy.compute_projection(mut db, branch_name, table_name, column, selector)
}

pub fn try_merge_field_values(mut db PersistentDatabase, column ColumnDef, base ColumnValue, ours ColumnValue, theirs ColumnValue) ?ColumnValue {
	strategy := db.field_capability_registry().merge_strategy_for(column)?
	return strategy.try_merge(mut db, column, base, ours, theirs)
}

pub fn ingest_external_field_value(mut db PersistentDatabase, column ColumnDef, raw ColumnValue) !ColumnValue {
	handler := db.field_capability_registry().external_storage_for(column) or {
		return error('external field storage not available for column: ${column.name}')
	}
	return handler.ingest(mut db, column, raw)
}

pub fn load_external_field_value(database &PersistentDatabase, column ColumnDef, stored ColumnValue) !ColumnValue {
	handler := database.field_capability_registry().external_storage_for(column) or {
		return error('external field storage not available for column: ${column.name}')
	}
	return handler.load(database, column, stored)
}

pub fn external_field_diff_summary(database &PersistentDatabase, column ColumnDef, base ColumnValue, current ColumnValue, limit int) !string {
	handler := database.field_capability_registry().external_storage_for(column) or {
		return error('external field storage not available for column: ${column.name}')
	}
	return handler.diff_summary(database, column, base, current, limit)
}

pub fn validate_field_selector_index(column ColumnDef, index SchemaIndexDef) ! {
	if !index.is_field_selector() {
		return
	}
	strategy := field_index_strategy_for(column) or {
		return error('typed field selector index requires capability-enabled column: ${index.column}')
	}
	strategy.validate_selector(index.field_selector(), index.json_field_type)!
}

pub fn expand_field_selector_index_values(root_dir string, column ColumnDef, stored ColumnValue, index SchemaIndexDef) ![]ColumnValue {
	if !index.is_field_selector() {
		return error('field selector expansion requires selector-backed index: ${index.name}')
	}
	strategy := field_index_strategy_for(column) or {
		return error('field selector index requires capability-enabled column: ${index.column}')
	}
	return strategy.expand_index_values(root_dir, column, stored, index.field_selector(), index.json_field_type)
}

fn (strategy MarkdownFieldIndexStrategy) plugin_name() string {
	return 'markdown'
}

fn (strategy MarkdownFieldIndexStrategy) supports(column ColumnDef) bool {
	return column.typ == .markdown_
}

fn (strategy MarkdownFieldIndexStrategy) validate_selector(selector string, value_type ColumnType) ! {
	validate_markdown_index_selector(selector, value_type)!
}

fn (strategy MarkdownFieldIndexStrategy) expand_index_values(root_dir string, column ColumnDef, stored ColumnValue, selector string, value_type ColumnType) ![]ColumnValue {
	if column.typ != .markdown_ {
		return error('markdown field index strategy requires markdown column: ${column.name}')
	}
	match stored {
		NullValue { return []ColumnValue{} }
		MarkdownRef {
			source := load_markdown_source(root_dir, stored.doc_root_id)!
			doc := vmarkdown.parse(source)!
			return markdown_index_values(selector, doc, value_type)
		}
		else {
			return error('markdown field index strategy requires MarkdownRef payload: ${column.name}')
		}
	}
}

fn (strategy MarkdownFieldProjectionStrategy) plugin_name() string {
	return 'markdown'
}

fn (strategy MarkdownFieldProjectionStrategy) supports(column ColumnDef) bool {
	return column.typ == .markdown_
}

fn (strategy MarkdownFieldProjectionStrategy) validate_selector(selector string) ! {
	validate_markdown_projection_selector(selector)!
}

fn (strategy MarkdownFieldProjectionStrategy) compute_projection(mut db PersistentDatabase, branch_name string, table_name string, column ColumnDef, selector string) !i64 {
	validate_markdown_projection_selector(selector)!
	session := db.begin_session(SessionOptions.for_branch(branch_name))!
	mut cursor := session.table_cursor(mut db, table_name, []u8{}, 0)!
	mut total := i64(0)
	for {
		row := cursor.next() or { break }
		if !row.data.has(column.name) {
			continue
		}
		value := row.data.get(column.name)!
		match value {
			MarkdownRef {
				source := db.load_markdown(value) or {
					return error('field projection failed to load markdown source: ${err}')
				}
				doc := vmarkdown.parse(source) or {
					return error('field projection failed to parse markdown: ${err}')
				}
				total += count_markdown_blocks(selector, doc.children)
			}
			NullValue {}
			else {
				return error('field projection requires markdown payload in ${column.name}')
			}
		}
	}
	return total
}

fn (strategy MarkdownFieldMergeStrategy) plugin_name() string {
	return 'markdown'
}

fn (strategy MarkdownFieldMergeStrategy) supports(column ColumnDef) bool {
	return column.typ == .markdown_
}

fn (strategy MarkdownFieldMergeStrategy) try_merge(mut db PersistentDatabase, column ColumnDef, base ColumnValue, ours ColumnValue, theirs ColumnValue) ?ColumnValue {
	if column.typ != .markdown_ {
		return none
	}
	if base is MarkdownRef && ours is MarkdownRef && theirs is MarkdownRef {
		merged := db.try_merge_markdown_refs(base, ours, theirs)?
		return ColumnValue(merged)
	}
	return none
}

fn (handler MarkdownExternalFieldStorage) plugin_name() string {
	return 'markdown'
}

fn (handler MarkdownExternalFieldStorage) supports(column ColumnDef) bool {
	return column.typ == .markdown_
}

fn (handler MarkdownExternalFieldStorage) ingest(mut db PersistentDatabase, column ColumnDef, raw ColumnValue) !ColumnValue {
	if column.typ != .markdown_ {
		return error('markdown external storage requires markdown column: ${column.name}')
	}
	match raw {
		string {
			ref := db.ingest_markdown(raw)!
			return ColumnValue(ref)
		}
		MarkdownRef {
			return ColumnValue(raw)
		}
		else {
			return error('markdown external storage requires string or MarkdownRef payload: ${column.name}')
		}
	}
}

fn (handler MarkdownExternalFieldStorage) load(database &PersistentDatabase, column ColumnDef, stored ColumnValue) !ColumnValue {
	if column.typ != .markdown_ {
		return error('markdown external storage requires markdown column: ${column.name}')
	}
	match stored {
		MarkdownRef {
			return ColumnValue(database.load_markdown(stored)!)
		}
		NullValue {
			return ColumnValue(NullValue{})
		}
		else {
			return error('markdown external storage requires MarkdownRef payload: ${column.name}')
		}
	}
}

fn markdown_diff_summary_text(diff MarkdownDiff, limit int) string {
	if diff.entries.len == 0 {
		return ' unchanged'
	}
	mut lines := []string{}
	for idx, entry in diff.entries {
		if idx >= limit {
			break
		}
		verb := match entry.op {
			.added { 'added' }
			.removed { 'removed' }
			.moved { 'moved' }
			.edited { 'edited' }
			.reused { 'reused' }
		}
		location := if entry.new_anchor.len > 0 { entry.new_anchor } else { entry.old_anchor }
		lines << '${verb} ${entry.kind} @ ${location}'
	}
	return ' diff=[' + lines.join('; ') + ']'
}

fn (handler MarkdownExternalFieldStorage) diff_summary(database &PersistentDatabase, column ColumnDef, base ColumnValue, current ColumnValue, limit int) !string {
	if column.typ != .markdown_ {
		return error('markdown external storage requires markdown column: ${column.name}')
	}
	if base !is MarkdownRef || current !is MarkdownRef {
		return ''
	}
	base_ref := base as MarkdownRef
	current_ref := current as MarkdownRef
	if base_ref.doc_root_id == current_ref.doc_root_id {
		return ' unchanged'
	}
	diff := database.diff_markdown_refs(base_ref, current_ref)!
	return markdown_diff_summary_text(diff, limit)
}
