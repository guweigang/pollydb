module storage

import memory
import os

pub struct YamlDdlFile {
pub mut:
	schema_version        int
	tables                []YamlDdlTable
	aggregate_projections []YamlDdlAggregateProjection
	memory_capabilities   []YamlDdlMemoryCapability
}

pub struct YamlDdlTable {
pub mut:
	name        string
	description string
	primary_key []string
	columns     []YamlDdlColumn
	indexes     []YamlDdlIndex
}

pub struct YamlDdlColumn {
pub mut:
	name                          string
	typ                           string
	nullable                      bool
	aggregate                     string
	enum_values                   []string
	default_current_timestamp     bool
	auto_update_current_timestamp bool
}

pub struct YamlDdlIndex {
pub mut:
	name            string
	kind            string
	column          string
	stored_columns  []string
	json_field      string
	json_field_type string
	mode            string
	tokenizer       string
	prefix_lengths  []int
	selector        string
	plugin          string
	value_type      string
	profile         string
	scope           string
}

pub struct YamlDdlAggregateProjection {
pub mut:
	name       string
	table_name string
	column_name string
	kind       string
	json_path  string
	plugin     string
	selector   string
	priority   int = 100
	cost_hint  string = 'medium'
}

pub struct YamlDdlMemoryCapability {
pub mut:
	table_name               string
	column_name              string
	enabled                  bool = true
	embedding_index          string
	reflection_kind          string = 'summary'
	replay_anchor            bool = true
	link_evidence_blocks     bool = true
	link_semantic_neighbors  bool = true
}

pub fn load_yaml_ddl_file(path string) !YamlDdlFile {
	content := os.read_file(path)!
	return parse_yaml_ddl_text(content)
}

pub fn parse_yaml_ddl_text(text string) !YamlDdlFile {
	lines := preprocess_yaml_lines(text)
	mut file := YamlDdlFile{
		schema_version: 1
	}
	mut i := 0
	for i < lines.len {
		line := lines[i]
		indent := yaml_indent(line)
		trimmed := line.trim_space()
		if indent != 0 {
			return error('unexpected indentation at top level: ${trimmed}')
		}
		if trimmed.starts_with('schema_version:') {
			file.schema_version = yaml_parse_int(yaml_after_colon(trimmed))!
			i++
			continue
		}
		if trimmed == 'tables:' {
			mut tables := []YamlDdlTable{}
			i++
			for i < lines.len {
				if yaml_indent(lines[i]) <= indent {
					break
				}
				table, next_i := parse_yaml_ddl_table(lines, i)!
				tables << table
				i = next_i
			}
			file.tables = tables
			continue
		}
		if trimmed == 'aggregate_projections:' || trimmed == 'aggregate_projections: []' {
			if trimmed == 'aggregate_projections: []' {
				file.aggregate_projections = []YamlDdlAggregateProjection{}
				i++
				continue
			}
			mut projections := []YamlDdlAggregateProjection{}
			i++
			for i < lines.len {
				if yaml_indent(lines[i]) <= indent {
					break
				}
				projection, next_i := parse_yaml_ddl_aggregate_projection(lines, i)!
				projections << projection
				i = next_i
			}
			file.aggregate_projections = projections
			continue
		}
		if trimmed == 'memory_capabilities:' || trimmed == 'memory_capabilities: []' {
			if trimmed == 'memory_capabilities: []' {
				file.memory_capabilities = []YamlDdlMemoryCapability{}
				i++
				continue
			}
			mut capabilities := []YamlDdlMemoryCapability{}
			i++
			for i < lines.len {
				if yaml_indent(lines[i]) <= indent {
					break
				}
				capability, next_i := parse_yaml_ddl_memory_capability(lines, i)!
				capabilities << capability
				i = next_i
			}
			file.memory_capabilities = capabilities
			continue
		}
		return error('unsupported ddl yaml key: ${trimmed}')
	}
	return file
}

pub fn (file YamlDdlFile) to_typed_specs() ![]TypedTableSpec {
	mut specs := []TypedTableSpec{cap: file.tables.len}
	for table in file.tables {
		specs << table.to_typed_spec()!
	}
	return specs
}

pub fn (file YamlDdlFile) table_spec(name string) !TypedTableSpec {
	for table in file.tables {
		if table.name == name {
			return table.to_typed_spec()!
		}
	}
	return error('ddl yaml table not found: ${name}')
}

pub fn (file YamlDdlFile) aggregate_projection_defs() ![]AggregateProjectionDef {
	mut defs := []AggregateProjectionDef{cap: file.aggregate_projections.len}
	for projection in file.aggregate_projections {
		defs << projection.to_aggregate_projection_def()!
	}
	return defs
}

pub fn (file YamlDdlFile) memory_capability_defs() ![]MemoryCapabilityDef {
	mut defs := []MemoryCapabilityDef{cap: file.memory_capabilities.len}
	for capability in file.memory_capabilities {
		defs << capability.to_memory_capability_def()!
	}
	return defs
}

pub fn (table YamlDdlTable) to_typed_spec() !TypedTableSpec {
	mut columns := []ColumnDef{cap: table.columns.len}
	for column in table.columns {
		columns << column.to_column_def()!
	}
	table_def := TableDef.new(table.name, columns, table.primary_key)!
	mut indexes := []SchemaIndexDef{cap: table.indexes.len}
	for index in table.indexes {
		indexes << index.to_schema_index_def()!
	}
	return TypedTableSpec.new(table_def, indexes)!
}

fn (column YamlDdlColumn) to_column_def() !ColumnDef {
	col_type := yaml_column_type(column.typ)!
	aggregate := yaml_column_aggregate(column.aggregate)!
	if aggregate == .sum {
		if col_type != .i64_ {
			return error('sum aggregate only supports i64 columns: ${column.name}')
		}
		return ColumnDef.sum_i64(column.name, column.nullable)!
	}
	match col_type {
		.enum_ {
			return ColumnDef.enum_string(column.name, column.enum_values, column.nullable)!
		}
		.datetime_ {
			if column.default_current_timestamp || column.auto_update_current_timestamp {
				return ColumnDef.datetime_with_current_timestamp(column.name, column.nullable,
					column.auto_update_current_timestamp)!
			}
			return ColumnDef.datetime(column.name, column.nullable)!
		}
		else {
			return ColumnDef.new(column.name, col_type, column.nullable)!
		}
	}
}

fn (index YamlDdlIndex) to_schema_index_def() !SchemaIndexDef {
	return match index.kind {
		'column' {
			SchemaIndexDef.new(index.name, index.column)!
		}
		'covering' {
			SchemaIndexDef.covering(index.name, index.column)!
		}
		'covering_projected' {
			SchemaIndexDef.covering_projected(index.name, index.column, index.stored_columns)!
		}
		'json_path' {
			SchemaIndexDef.json_path(index.name, index.column, index.json_field,
				yaml_column_type(index.json_field_type)!)!
		}
		'json_path_covering' {
			SchemaIndexDef.json_path_covering(index.name, index.column, index.json_field,
				yaml_column_type(index.json_field_type)!)!
		}
		'fts_text' {
			SchemaIndexDef.fts_text_with_options(index.name, index.column, FtsIndexOptions{
				tokenizer:      index.tokenizer
				prefix_lengths: index.prefix_lengths
			})!
		}
		'fts_markdown' {
			SchemaIndexDef.fts_markdown_with_options(index.name, index.column,
				yaml_fts_text_mode(index.mode)!, FtsIndexOptions{
				tokenizer:      index.tokenizer
				prefix_lengths: index.prefix_lengths
			})!
		}
		'embedding_text' {
			SchemaIndexDef.embedding_text(index.name, index.column, index.profile)!
		}
		'embedding_markdown' {
			SchemaIndexDef.embedding_markdown(index.name, index.column,
				yaml_markdown_embedding_scope(index.scope)!, index.profile)!
		}
		'field_selector' {
			mut plugin := 'markdown'
			if index.plugin.len > 0 {
				plugin = index.plugin
			}
			SchemaIndexDef.field_selector(index.name, index.column, plugin, index.selector,
				yaml_column_type(index.value_type)!, false)!
		}
		else {
			return error('unsupported ddl yaml index kind: ${index.kind}')
		}
	}
}

fn (projection YamlDdlAggregateProjection) to_aggregate_projection_def() !AggregateProjectionDef {
	mut def := match projection.kind {
		'', 'sum_i64' {
			AggregateProjectionDef.sum_i64(projection.name, projection.table_name, projection.column_name)!
		}
		'sum_json_i64' {
			AggregateProjectionDef.sum_json_i64(projection.name, projection.table_name,
				projection.column_name, projection.json_path)!
		}
		'count_field_selector' {
			mut plugin := projection.plugin
			if plugin.len == 0 {
				plugin = 'markdown'
			}
			AggregateProjectionDef.count_field_selector(projection.name, projection.table_name,
				projection.column_name, plugin, projection.selector)!
		}
		else {
			return error('unsupported ddl yaml aggregate projection kind: ${projection.kind}')
		}
	}
	def = def.with_priority(projection.priority)
	def = def.with_cost_hint(yaml_aggregate_projection_cost_hint(projection.cost_hint)!)
	return def
}

fn (capability YamlDdlMemoryCapability) to_memory_capability_def() !MemoryCapabilityDef {
	return MemoryCapabilityDef.reflective_field(capability.table_name, capability.column_name,
		memory.ReflectionOptions{
		enabled:                 capability.enabled
		embedding_index:         capability.embedding_index
		reflection_kind:         capability.reflection_kind
		replay_anchor:           capability.replay_anchor
		link_evidence_blocks:    capability.link_evidence_blocks
		link_semantic_neighbors: capability.link_semantic_neighbors
	})
}

fn parse_yaml_ddl_table(lines []string, start int) !(YamlDdlTable, int) {
	mut table := YamlDdlTable{}
	mut i := start
	first := lines[i].trim_space()
	if !first.starts_with('- ') {
		return error('expected table list item, got: ${first}')
	}
	inline := first[2..].trim_space()
	if inline.starts_with('name:') {
		table.name = yaml_parse_string(yaml_after_colon(inline))
	} else if inline.len > 0 {
		return error('unsupported inline table field: ${inline}')
	}
	base_indent := yaml_indent(lines[i])
	i++
	for i < lines.len {
		line := lines[i]
		indent := yaml_indent(line)
		if indent <= base_indent {
			break
		}
		trimmed := line.trim_space()
		if indent != base_indent + 2 {
			return error('unexpected table indentation: ${trimmed}')
		}
		if trimmed.starts_with('name:') {
			table.name = yaml_parse_string(yaml_after_colon(trimmed))
			i++
			continue
		}
		if trimmed.starts_with('description:') {
			table.description = yaml_parse_string(yaml_after_colon(trimmed))
			i++
			continue
		}
		if trimmed.starts_with('primary_key:') {
			table.primary_key = yaml_parse_string_list(yaml_after_colon(trimmed))
			i++
			continue
		}
		if trimmed == 'columns:' || trimmed == 'columns: []' {
			if trimmed == 'columns: []' {
				table.columns = []YamlDdlColumn{}
				i++
				continue
			}
			mut columns := []YamlDdlColumn{}
			i++
			for i < lines.len {
				if yaml_indent(lines[i]) <= indent {
					break
				}
				column, next_i := parse_yaml_ddl_column(lines, i)!
				columns << column
				i = next_i
			}
			table.columns = columns
			continue
		}
		if trimmed == 'indexes:' || trimmed == 'indexes: []' {
			if trimmed == 'indexes: []' {
				table.indexes = []YamlDdlIndex{}
				i++
				continue
			}
			mut indexes := []YamlDdlIndex{}
			i++
			for i < lines.len {
				if yaml_indent(lines[i]) <= indent {
					break
				}
				index, next_i := parse_yaml_ddl_index(lines, i)!
				indexes << index
				i = next_i
			}
			table.indexes = indexes
			continue
		}
		return error('unsupported table ddl field: ${trimmed}')
	}
	return table, i
}

fn parse_yaml_ddl_column(lines []string, start int) !(YamlDdlColumn, int) {
	mut column := YamlDdlColumn{}
	mut i := start
	first := lines[i].trim_space()
	if !first.starts_with('- ') {
		return error('expected column list item, got: ${first}')
	}
	inline := first[2..].trim_space()
	if inline.starts_with('name:') {
		column.name = yaml_parse_string(yaml_after_colon(inline))
	} else if inline.len > 0 {
		return error('unsupported inline column field: ${inline}')
	}
	base_indent := yaml_indent(lines[i])
	i++
	for i < lines.len {
		line := lines[i]
		indent := yaml_indent(line)
		if indent <= base_indent {
			break
		}
		if indent != base_indent + 2 {
			return error('unexpected column indentation: ${line.trim_space()}')
		}
		trimmed := line.trim_space()
		match true {
			trimmed.starts_with('name:') {
				column.name = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('type:') {
				column.typ = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('nullable:') {
				column.nullable = yaml_parse_bool(yaml_after_colon(trimmed))!
			}
			trimmed.starts_with('aggregate:') {
				column.aggregate = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('enum_values:') {
				column.enum_values = yaml_parse_string_list(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('default_current_timestamp:') {
				column.default_current_timestamp = yaml_parse_bool(yaml_after_colon(trimmed))!
			}
			trimmed.starts_with('auto_update_current_timestamp:') {
				column.auto_update_current_timestamp = yaml_parse_bool(yaml_after_colon(trimmed))!
			}
			else {
				return error('unsupported column ddl field: ${trimmed}')
			}
		}

		i++
	}
	return column, i
}

fn parse_yaml_ddl_index(lines []string, start int) !(YamlDdlIndex, int) {
	mut index := YamlDdlIndex{}
	mut i := start
	first := lines[i].trim_space()
	if !first.starts_with('- ') {
		return error('expected index list item, got: ${first}')
	}
	inline := first[2..].trim_space()
	if inline.starts_with('name:') {
		index.name = yaml_parse_string(yaml_after_colon(inline))
	} else if inline.len > 0 {
		return error('unsupported inline index field: ${inline}')
	}
	base_indent := yaml_indent(lines[i])
	i++
	for i < lines.len {
		line := lines[i]
		indent := yaml_indent(line)
		if indent <= base_indent {
			break
		}
		if indent != base_indent + 2 {
			return error('unexpected index indentation: ${line.trim_space()}')
		}
		trimmed := line.trim_space()
		match true {
			trimmed.starts_with('name:') {
				index.name = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('kind:') {
				index.kind = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('column:') {
				index.column = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('stored_columns:') {
				index.stored_columns = yaml_parse_string_list(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('json_field:') {
				index.json_field = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('json_field_type:') {
				index.json_field_type = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('mode:') {
				index.mode = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('tokenizer:') {
				index.tokenizer = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('prefix_lengths:') {
				index.prefix_lengths = yaml_parse_int_list(yaml_after_colon(trimmed))!
			}
			trimmed.starts_with('selector:') {
				index.selector = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('plugin:') {
				index.plugin = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('value_type:') {
				index.value_type = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('profile:') {
				index.profile = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('scope:') {
				index.scope = yaml_parse_string(yaml_after_colon(trimmed))
			}
			else {
				return error('unsupported index ddl field: ${trimmed}')
			}
		}

		i++
	}
	return index, i
}

fn parse_yaml_ddl_aggregate_projection(lines []string, start int) !(YamlDdlAggregateProjection, int) {
	mut projection := YamlDdlAggregateProjection{}
	mut i := start
	first := lines[i].trim_space()
	if !first.starts_with('- ') {
		return error('expected aggregate projection list item, got: ${first}')
	}
	inline := first[2..].trim_space()
	if inline.starts_with('name:') {
		projection.name = yaml_parse_string(yaml_after_colon(inline))
	} else if inline.len > 0 {
		return error('unsupported inline aggregate projection field: ${inline}')
	}
	base_indent := yaml_indent(lines[i])
	i++
	for i < lines.len {
		line := lines[i]
		indent := yaml_indent(line)
		if indent <= base_indent {
			break
		}
		if indent != base_indent + 2 {
			return error('unexpected aggregate projection indentation: ${line.trim_space()}')
		}
		trimmed := line.trim_space()
		match true {
			trimmed.starts_with('name:') {
				projection.name = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('table_name:') {
				projection.table_name = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('column_name:') {
				projection.column_name = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('kind:') {
				projection.kind = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('json_path:') {
				projection.json_path = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('plugin:') {
				projection.plugin = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('selector:') {
				projection.selector = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('priority:') {
				projection.priority = yaml_parse_int(yaml_after_colon(trimmed))!
			}
			trimmed.starts_with('cost_hint:') {
				projection.cost_hint = yaml_parse_string(yaml_after_colon(trimmed))
			}
			else {
				return error('unsupported aggregate projection ddl field: ${trimmed}')
			}
		}
		i++
	}
	return projection, i
}

fn parse_yaml_ddl_memory_capability(lines []string, start int) !(YamlDdlMemoryCapability, int) {
	mut capability := YamlDdlMemoryCapability{}
	mut i := start
	first := lines[i].trim_space()
	if !first.starts_with('- ') {
		return error('expected memory capability list item, got: ${first}')
	}
	inline := first[2..].trim_space()
	if inline.starts_with('table_name:') {
		capability.table_name = yaml_parse_string(yaml_after_colon(inline))
	} else if inline.len > 0 {
		return error('unsupported inline memory capability field: ${inline}')
	}
	base_indent := yaml_indent(lines[i])
	i++
	for i < lines.len {
		line := lines[i]
		indent := yaml_indent(line)
		if indent <= base_indent {
			break
		}
		if indent != base_indent + 2 {
			return error('unexpected memory capability indentation: ${line.trim_space()}')
		}
		trimmed := line.trim_space()
		match true {
			trimmed.starts_with('table_name:') {
				capability.table_name = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('column_name:') {
				capability.column_name = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('enabled:') {
				capability.enabled = yaml_parse_bool(yaml_after_colon(trimmed))!
			}
			trimmed.starts_with('embedding_index:') {
				capability.embedding_index = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('reflection_kind:') {
				capability.reflection_kind = yaml_parse_string(yaml_after_colon(trimmed))
			}
			trimmed.starts_with('replay_anchor:') {
				capability.replay_anchor = yaml_parse_bool(yaml_after_colon(trimmed))!
			}
			trimmed.starts_with('link_evidence_blocks:') {
				capability.link_evidence_blocks = yaml_parse_bool(yaml_after_colon(trimmed))!
			}
			trimmed.starts_with('link_semantic_neighbors:') {
				capability.link_semantic_neighbors = yaml_parse_bool(yaml_after_colon(trimmed))!
			}
			else {
				return error('unsupported memory capability ddl field: ${trimmed}')
			}
		}
		i++
	}
	return capability, i
}

fn preprocess_yaml_lines(text string) []string {
	mut lines := []string{}
	for raw in text.split_into_lines() {
		mut line := raw.replace('\t', '    ')
		if idx := line.index('#') {
			if idx == 0 || line[..idx].trim_space().len > 0 {
				line = line[..idx]
			}
		}
		if line.trim_space().len == 0 {
			continue
		}
		lines << line.trim_right(' \r\n\t')
	}
	return lines
}

fn yaml_indent(line string) int {
	mut count := 0
	for ch in line {
		if ch != ` ` {
			break
		}
		count++
	}
	return count
}

fn yaml_after_colon(line string) string {
	idx := line.index(':') or { return '' }
	return line[idx + 1..].trim_space()
}

fn yaml_parse_string(raw string) string {
	mut value := raw.trim_space()
	if value.len >= 2 {
		if (value[0] == `'` && value[value.len - 1] == `'`)
			|| (value[0] == `"` && value[value.len - 1] == `"`) {
			value = value[1..value.len - 1]
		}
	}
	return value
}

fn yaml_parse_bool(raw string) !bool {
	value := yaml_parse_string(raw).to_lower()
	return match value {
		'true' { true }
		'false' { false }
		else { return error('invalid yaml bool: ${raw}') }
	}
}

fn yaml_parse_int(raw string) !int {
	return yaml_parse_string(raw).int()
}

fn yaml_parse_string_list(raw string) []string {
	value := yaml_parse_string(raw)
	if value.len == 0 {
		return []string{}
	}
	if value.starts_with('[') && value.ends_with(']') {
		inner := value[1..value.len - 1].trim_space()
		if inner.len == 0 {
			return []string{}
		}
		mut out := []string{}
		for part in inner.split(',') {
			item := yaml_parse_string(part)
			if item.len > 0 {
				out << item
			}
		}
		return out
	}
	return [value]
}

fn yaml_parse_int_list(raw string) ![]int {
	items := yaml_parse_string_list(raw)
	mut out := []int{cap: items.len}
	for item in items {
		out << item.int()
	}
	return out
}

fn yaml_column_type(name string) !ColumnType {
	return match name {
		'bool' { .bool_ }
		'i64', 'int', 'integer' { .i64_ }
		'string', 'text' { .string_ }
		'bytes' { .bytes_ }
		'enum' { .enum_ }
		'json' { .json_ }
		'datetime' { .datetime_ }
		'markdown' { .markdown_ }
		else { return error('unsupported ddl yaml column type: ${name}') }
	}
}

fn yaml_column_aggregate(name string) !ColumnAggregate {
	if name.len == 0 {
		return .none
	}
	return match name {
		'none' { .none }
		'sum' { .sum }
		else { return error('unsupported ddl yaml aggregate: ${name}') }
	}
}

fn yaml_fts_text_mode(name string) !FtsTextMode {
	return match name {
		'plain_text' { .plain_text }
		'visible_text' { .visible_text }
		'visible_text_with_code' { .visible_text_with_code }
		'raw_markdown' { .raw_markdown }
		else { return error('unsupported ddl yaml fts mode: ${name}') }
	}
}

fn yaml_markdown_embedding_scope(name string) !memory.MarkdownEmbeddingScope {
	return match name {
		'path' { memory.MarkdownEmbeddingScope.path }
		'block' { memory.MarkdownEmbeddingScope.block }
		else { return error('unsupported ddl yaml embedding scope: ${name}') }
	}
}

fn yaml_aggregate_projection_cost_hint(name string) !AggregateProjectionCostHint {
	if name.len == 0 {
		return .medium
	}
	return match name {
		'low' { .low }
		'medium' { .medium }
		'high' { .high }
		else { return error('unsupported ddl yaml aggregate projection cost_hint: ${name}') }
	}
}
