module storage

import time
import vmarkdown
import x.json2

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
	name              string
	table_name        string
	column_name       string
	source_json_path  string
	source_markdown_selector string
	aggregate         ColumnAggregate
	priority          int = 100
	cost_hint         AggregateProjectionCostHint = .medium
}

pub struct AggregateProjectorState {
pub:
	projection           AggregateProjectionDef
	current_data_root_cid string
	source_data_root_cid string
	virtual_root_cid     string
	fresh                bool
	stale_reason         string
}

pub struct AggregateProjectionValue {
pub:
	projection           AggregateProjectionDef
	branch_name          string
	value                i64
	current_data_root_cid string
	source_data_root_cid string
	virtual_root_cid     string
	fresh                bool
	stale_reason         string
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
		name: name
		table_name: table_name
		column_name: column_name
		source_json_path: ''
		aggregate: .sum
		priority: 100
		cost_hint: .medium
	}
}

pub fn AggregateProjectionDef.sum_json_i64(name string, table_name string, column_name string, source_json_path string) !AggregateProjectionDef {
	if source_json_path.len == 0 {
		return error('aggregate projection json path cannot be empty')
	}
	AggregateProjectionDef.sum_i64(name, table_name, column_name)!
	return AggregateProjectionDef{
		name: name
		table_name: table_name
		column_name: column_name
		source_json_path: source_json_path
		source_markdown_selector: ''
		aggregate: .sum
		priority: 100
		cost_hint: .medium
	}
}

pub fn AggregateProjectionDef.count_markdown_blocks(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'blocks')
}

pub fn AggregateProjectionDef.count_markdown_block_kind(name string, table_name string, column_name string, kind string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'blocks:${kind}')
}

pub fn AggregateProjectionDef.count_markdown_headings(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'headings')
}

pub fn AggregateProjectionDef.count_markdown_heading_level(name string, table_name string, column_name string, level int) !AggregateProjectionDef {
	if level < 1 || level > 6 {
		return error('markdown heading level must be between 1 and 6')
	}
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'headings:${level}')
}

pub fn AggregateProjectionDef.count_markdown_links(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'links')
}

pub fn AggregateProjectionDef.count_markdown_images(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'images')
}

pub fn AggregateProjectionDef.count_markdown_code_blocks(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'code_blocks')
}

pub fn AggregateProjectionDef.count_markdown_code_blocks_with_lang(name string, table_name string, column_name string, lang string) !AggregateProjectionDef {
	if lang.len == 0 {
		return error('markdown code block language cannot be empty')
	}
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'code_blocks:${lang}')
}

pub fn AggregateProjectionDef.count_markdown_code_spans(name string, table_name string, column_name string) !AggregateProjectionDef {
	return AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, 'code_spans')
}

pub fn AggregateProjectionDef.count_field_selector(name string, table_name string, column_name string, plugin_name string, selector string) !AggregateProjectionDef {
	if plugin_name.len == 0 {
		return error('aggregate projection field selector plugin cannot be empty')
	}
	AggregateProjectionDef.sum_i64(name, table_name, column_name)!
	return match plugin_name {
		'markdown' {
			AggregateProjectionDef.count_markdown_selector(name, table_name, column_name, selector)!
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
		name: name
		table_name: table_name
		column_name: column_name
		source_json_path: ''
		source_markdown_selector: selector
		aggregate: .sum
		priority: 100
		cost_hint: .medium
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
		selector: selector
	}
}

pub fn (def AggregateProjectionDef) field_projection_meta() ?FieldSelectorMeta {
	plugin_name := def.field_projection_plugin()
	selector := def.field_projection_selector()
	if plugin_name.len == 0 || selector.len == 0 {
		return none
	}
	return FieldSelectorMeta{
		plugin_name: plugin_name
		selector: selector
		value_type: .i64_
		stores_row: false
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
		name: state.projection.name
		root_cid: state.virtual_root_cid
		source_data_root_cid: state.source_data_root_cid
		fresh: state.fresh
		stale_reason: state.stale_reason
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
			if parts.len == 2 && parts[1] !in ['meta', 'heading', 'paragraph', 'blockquote', 'list', 'code_block', 'horizontal_rule'] {
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
	for sep in ['/','?','#'] {
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
				collect_markdown_index_values_from_inlines(selector, node.children, mut out)
			}
			vmarkdown.StrongNode {
				collect_markdown_index_values_from_inlines(selector, node.children, mut out)
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
				collect_markdown_index_values_from_inlines(selector, node.children, mut out)
			}
			vmarkdown.ParagraphNode {
				collect_markdown_index_values_from_inlines(selector, node.children, mut out)
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
			key: aggregate_projection_value_key(def.name)
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
					i64 { total += value }
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
	return compute_field_projection_i64(mut db, branch_name, def.table_name, column,
		def.field_projection_selector())
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
		item := Tree.lookup_in_byte_store(state.virtual_root_cid, aggregate_projection_value_key(name),
			mut db.engine.repository.node_store)!
		raw := TypedValueEncoder.decode_value(item.value, .i64_)!
		match raw {
			i64 {
				return AggregateProjectionValue{
					projection: state.projection
					branch_name: branch_name
					value: raw
					current_data_root_cid: state.current_data_root_cid
					source_data_root_cid: state.source_data_root_cid
					virtual_root_cid: state.virtual_root_cid
					fresh: state.fresh
					stale_reason: state.stale_reason
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
	return db.markdown_projection_i64_at_branch(db.default_branch, table_name, column_name, selector)
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
				name: projector.name
				root_cid: ''
				source_data_root_cid: current.root_cid
				fresh: false
				stale_reason: 'registration_backfill'
			}
		}
		if current_ref.fresh && current_ref.source_data_root_cid == current.root_cid && current_ref.root_cid.len > 0 {
			next_roots << current_ref
			continue
		}
		if limit > 0 && refreshed >= limit {
			next_roots << VirtualRootRef{
				name: projector.name
				root_cid: current_ref.root_cid
				source_data_root_cid: current.root_cid
				fresh: false
				stale_reason: 'policy_budget_skipped'
			}
			continue
		}
		value := compute_aggregate_projection_value(mut db, branch_name, projector)!
		tree := build_aggregate_projection_tree(projector, value, cfg)!
		db.engine.repository.node_store.put_tree(tree)!
		refreshed++
		next_roots << VirtualRootRef{
			name: projector.name
			root_cid: tree.root.cid
			source_data_root_cid: current.root_cid
			fresh: true
			stale_reason: ''
		}
	}
	return db.engine.commit_virtual_roots_for_branch(branch_name, next_roots, CommitMeta{
		author: if meta.author.len > 0 { meta.author } else { 'pollydb/projector' }
		message: if meta.message.len > 0 { meta.message } else { 'refresh aggregate projections' }
		timestamp: if meta.timestamp != 0 { meta.timestamp } else { time.now().unix() }
	})
}
