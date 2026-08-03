module storage

import crypto.sha256
import os
import vmarkdown

const markdown_store_version = u8(1)
const markdown_ast_version = u8(1)
const default_markdown_source_cache_mb = 16
const default_markdown_fts_cache_mb = 16

pub enum MarkdownDiffOp {
	added
	removed
	moved
	edited
	reused
}

pub struct MarkdownOccurrence {
pub:
	occurrence_id string
	content_id    string
	parent_id     string
	kind          string
	anchor        string
	order         int
	path_hint     string
}

pub struct MarkdownDiffEntry {
pub:
	op            MarkdownDiffOp
	occurrence_id string
	content_id    string
	kind          string
	old_anchor    string
	new_anchor    string
	old_order     int = -1
	new_order     int = -1
	path_hint     string
}

pub struct MarkdownDiff {
pub:
	left_root_id  string
	right_root_id string
	entries       []MarkdownDiffEntry
}

pub struct MarkdownMergePreview {
pub:
	base_ref       MarkdownRef
	ours_ref       MarkdownRef
	theirs_ref     MarkdownRef
	base_to_ours   MarkdownDiff
	base_to_theirs MarkdownDiff
	mergeable      bool
	merged_ref     MarkdownRef
	merged_source  string
}

pub struct MarkdownArtifactRebuildResult {
pub mut:
	scanned       int
	markdown_refs int
	pending       int
	rebuilt       int
	skipped_ready int
	failed        int
	errors        []string
}

struct MarkdownOccurrenceLookup {
	by_path map[string]MarkdownOccurrence
}

struct MarkdownMergeContext {
	base_lookup   MarkdownOccurrenceLookup
	ours_lookup   MarkdownOccurrenceLookup
	theirs_lookup MarkdownOccurrenceLookup
}

fn markdown_store_dir(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'markdown')
}

fn markdown_chunk_dir(root_dir string) string {
	return os.join_path(markdown_store_dir(root_dir), 'chunks')
}

fn markdown_doc_dir(root_dir string) string {
	return os.join_path(markdown_store_dir(root_dir), 'docs')
}

fn markdown_manifest_dir(root_dir string) string {
	return os.join_path(markdown_store_dir(root_dir), 'manifests')
}

fn markdown_source_dir(root_dir string) string {
	return os.join_path(markdown_store_dir(root_dir), 'sources')
}

fn markdown_occurrence_dir(root_dir string) string {
	return os.join_path(markdown_store_dir(root_dir), 'occurrences')
}

fn ensure_markdown_store_layout(root_dir string) ! {
	os.mkdir_all(markdown_chunk_dir(root_dir))!
	os.mkdir_all(markdown_doc_dir(root_dir))!
	os.mkdir_all(markdown_manifest_dir(root_dir))!
	os.mkdir_all(markdown_source_dir(root_dir))!
	os.mkdir_all(markdown_occurrence_dir(root_dir))!
}

fn markdown_file_key(id string) string {
	return sha256.sum(id.bytes()).hex()
}

fn markdown_chunk_path(root_dir string, id string) string {
	return os.join_path(markdown_chunk_dir(root_dir), markdown_file_key(id) + '.bin')
}

fn markdown_doc_path(root_dir string, id string) string {
	return os.join_path(markdown_doc_dir(root_dir), markdown_file_key(id) + '.txt')
}

fn markdown_manifest_path(root_dir string, id string) string {
	return os.join_path(markdown_manifest_dir(root_dir), markdown_file_key(id) + '.txt')
}

fn markdown_source_path(root_dir string, id string) string {
	return os.join_path(markdown_source_dir(root_dir), markdown_file_key(id) + '.md')
}

fn markdown_occurrence_path(root_dir string, id string) string {
	return os.join_path(markdown_occurrence_dir(root_dir), markdown_file_key(id) + '.txt')
}

fn markdown_source_hash(raw string) string {
	return sha256.sum(raw.bytes()).hex()
}

fn markdown_source_id(raw string) string {
	return 'src:' + markdown_source_hash(raw)
}

fn markdown_cache_limit_bytes(env_name string, default_mb int) int {
	raw := os.getenv(env_name).trim_space()
	mb := if raw.len == 0 { default_mb } else { raw.int() }
	if mb <= 0 {
		return 0
	}
	return mb * 1024 * 1024
}

fn markdown_fts_cache_key(doc_root_id string, mode string) string {
	return '${doc_root_id}|${mode}'
}

fn (mut database PersistentDatabase) evict_markdown_source_cache(limit int) {
	for database.markdown_source_bytes > limit && database.markdown_source_order.len > 0 {
		key := database.markdown_source_order[0]
		database.markdown_source_order.delete(0)
		value := database.markdown_sources[key] or { continue }
		database.markdown_source_bytes -= key.len + value.len
		database.markdown_sources.delete(key)
	}
	if database.markdown_source_bytes < 0 {
		database.markdown_source_bytes = 0
	}
}

fn (mut database PersistentDatabase) cache_markdown_source(doc_root_id string, raw string) {
	limit := markdown_cache_limit_bytes('POLLYDB_MARKDOWN_SOURCE_CACHE_MB',
		default_markdown_source_cache_mb)
	if limit <= 0 || doc_root_id.len + raw.len > limit {
		if old := database.markdown_sources[doc_root_id] {
			database.markdown_source_bytes -= doc_root_id.len + old.len
			database.markdown_sources.delete(doc_root_id)
		}
		return
	}
	mut existed := false
	if old := database.markdown_sources[doc_root_id] {
		existed = true
		database.markdown_source_bytes -= doc_root_id.len + old.len
	}
	database.markdown_sources[doc_root_id] = raw
	if !existed {
		database.markdown_source_order << doc_root_id
	}
	database.markdown_source_bytes += doc_root_id.len + raw.len
	database.evict_markdown_source_cache(limit)
}

fn (mut database PersistentDatabase) evict_markdown_fts_text_cache(limit int) {
	for database.markdown_fts_bytes > limit && database.markdown_fts_order.len > 0 {
		key := database.markdown_fts_order[0]
		database.markdown_fts_order.delete(0)
		value := database.markdown_fts_texts[key] or { continue }
		database.markdown_fts_bytes -= key.len + value.len
		database.markdown_fts_texts.delete(key)
	}
	if database.markdown_fts_bytes < 0 {
		database.markdown_fts_bytes = 0
	}
}

fn (mut database PersistentDatabase) cache_markdown_fts_text(doc_root_id string, mode string, text string) {
	key := markdown_fts_cache_key(doc_root_id, mode)
	limit := markdown_cache_limit_bytes('POLLYDB_MARKDOWN_FTS_CACHE_MB',
		default_markdown_fts_cache_mb)
	if limit <= 0 || key.len + text.len > limit {
		if old := database.markdown_fts_texts[key] {
			database.markdown_fts_bytes -= key.len + old.len
			database.markdown_fts_texts.delete(key)
		}
		return
	}
	mut existed := false
	if old := database.markdown_fts_texts[key] {
		existed = true
		database.markdown_fts_bytes -= key.len + old.len
	}
	database.markdown_fts_texts[key] = text
	if !existed {
		database.markdown_fts_order << key
	}
	database.markdown_fts_bytes += key.len + text.len
	database.evict_markdown_fts_text_cache(limit)
}

fn (database &PersistentDatabase) cached_markdown_fts_text(doc_root_id string, mode string) ?string {
	key := markdown_fts_cache_key(doc_root_id, mode)
	if value := database.markdown_fts_texts[key] {
		return value
	}
	return none
}

struct MarkdownFileStore {
	root_dir string
}

fn new_markdown_file_store(root_dir string) !MarkdownFileStore {
	ensure_markdown_store_layout(root_dir)!
	return MarkdownFileStore{
		root_dir: root_dir
	}
}

fn (mut database PersistentDatabase) markdown_file_store() !MarkdownFileStore {
	if !database.markdown_store_ready {
		ensure_markdown_store_layout(database.root_dir)!
		database.markdown_store_ready = true
	}
	return MarkdownFileStore{
		root_dir: database.root_dir
	}
}

fn (store MarkdownFileStore) has_chunk(id string) bool {
	return os.exists(markdown_chunk_path(store.root_dir, id))
}

fn (store MarkdownFileStore) root_refs(root_id string) ?[]string {
	path := markdown_doc_path(store.root_dir, root_id)
	if !os.exists(path) {
		return none
	}
	data := os.read_file(path) or { return none }
	mut refs := []string{}
	for line in data.split_into_lines() {
		if line.len == 0 {
			continue
		}
		refs << line
	}
	return refs
}

fn (store MarkdownFileStore) root_manifest(root_id string) ?[]vmarkdown.BlockManifestEntry {
	path := markdown_manifest_path(store.root_dir, root_id)
	if !os.exists(path) {
		return none
	}
	data := os.read_file(path) or { return none }
	mut manifest := []vmarkdown.BlockManifestEntry{}
	for line in data.split_into_lines() {
		if line.len == 0 {
			continue
		}
		fields := line.split('\t')
		if fields.len != 4 {
			return none
		}
		manifest << vmarkdown.BlockManifestEntry{
			id:    fields[0]
			kind:  fields[1]
			path:  fields[2]
			index: fields[3].int()
		}
	}
	return manifest
}

fn (store MarkdownFileStore) last_root_id() string {
	return ''
}

fn (mut store MarkdownFileStore) put_chunk(chunk vmarkdown.Chunk) ! {
	path := markdown_chunk_path(store.root_dir, chunk.id)
	if os.exists(path) {
		return
	}
	mut out := ByteWriter{}
	kind_bytes := chunk.kind.bytes()
	out.write_u32(u32(kind_bytes.len))
	out.write_bytes(kind_bytes)
	out.write_u32(u32(chunk.refs.len))
	for ref in chunk.refs {
		ref_bytes := ref.bytes()
		out.write_u32(u32(ref_bytes.len))
		out.write_bytes(ref_bytes)
	}
	out.write_u32(u32(chunk.data.len))
	out.write_bytes(chunk.data)
	os.write_file(path, out.bytes().bytestr())!
}

fn (mut store MarkdownFileStore) put_root(root_id string, refs []string) ! {
	path := markdown_doc_path(store.root_dir, root_id)
	os.write_file(path, refs.join('\n'))!
}

fn (mut store MarkdownFileStore) put_root_manifest(root_id string, manifest []vmarkdown.BlockManifestEntry) ! {
	path := markdown_manifest_path(store.root_dir, root_id)
	mut lines := []string{cap: manifest.len}
	for entry in manifest {
		lines << '${entry.id}\t${entry.kind}\t${entry.path}\t${entry.index}'
	}
	os.write_file(path, lines.join('\n'))!
}

fn (mut store MarkdownFileStore) set_last_root_id(root_id string) ! {
	_ = root_id
}

fn commit_markdown_artifacts(mut store MarkdownFileStore, artifact_id string, plan vmarkdown.IngestPlan) ! {
	for chunk in plan.to_add {
		store.put_chunk(chunk)!
	}
	store.put_root(artifact_id, plan.root_refs)!
	store.put_root_manifest(artifact_id, plan.manifest)!
	store.set_last_root_id(artifact_id)!
}

fn markdown_ref_for_source(raw string) MarkdownRef {
	source_hash := markdown_source_hash(raw)
	return MarkdownRef{
		version:     markdown_store_version
		doc_root_id: 'src:' + source_hash
		source_hash: source_hash
		source_len:  raw.len
		ast_version: markdown_ast_version
		parse_flags: u32(0)
	}
}

fn markdown_artifacts_ready_at(root_dir string, artifact_id string) bool {
	if artifact_id.len == 0 {
		return false
	}
	return os.exists(markdown_doc_path(root_dir, artifact_id))
		&& os.exists(markdown_manifest_path(root_dir, artifact_id))
		&& os.exists(markdown_occurrence_path(root_dir, artifact_id))
}

fn persist_markdown_source(root_dir string, root_id string, raw string) ! {
	os.write_file(markdown_source_path(root_dir, root_id), raw)!
}

pub fn load_markdown_source(root_dir string, root_id string) !string {
	if root_id.len == 0 {
		return ''
	}
	return os.read_file(markdown_source_path(root_dir, root_id))!
}

fn persist_markdown_occurrences(root_dir string, root_id string, occurrences []MarkdownOccurrence) ! {
	path := markdown_occurrence_path(root_dir, root_id)
	mut lines := []string{cap: occurrences.len}
	for occurrence in occurrences {
		lines << [
			occurrence.occurrence_id,
			occurrence.content_id,
			occurrence.parent_id,
			occurrence.kind,
			occurrence.anchor,
			occurrence.order.str(),
			occurrence.path_hint,
		].join('\t')
	}
	os.write_file(path, lines.join('\n'))!
}

fn load_markdown_occurrences(root_dir string, root_id string) ![]MarkdownOccurrence {
	path := markdown_occurrence_path(root_dir, root_id)
	data := os.read_file(path)!
	mut occurrences := []MarkdownOccurrence{}
	for line in data.split_into_lines() {
		if line.len == 0 {
			continue
		}
		fields := line.split('\t')
		if fields.len != 7 {
			return error('invalid markdown occurrence row for ${root_id}')
		}
		occurrences << MarkdownOccurrence{
			occurrence_id: fields[0]
			content_id:    fields[1]
			parent_id:     fields[2]
			kind:          fields[3]
			anchor:        fields[4]
			order:         fields[5].int()
			path_hint:     fields[6]
		}
	}
	return occurrences
}

fn heading_anchor_segment(node vmarkdown.HeadingNode) string {
	text := markdown_slug(markdown_inline_text(node.children))
	return 'h${node.level}:${text}'
}

fn markdown_inline_text(nodes []vmarkdown.InlineNode) string {
	mut parts := []string{}
	for node in nodes {
		match node {
			vmarkdown.TextNode {
				parts << node.text
			}
			vmarkdown.CodeSpanNode {
				parts << node.text
			}
			vmarkdown.EmphasisNode {
				parts << markdown_inline_text(node.children)
			}
			vmarkdown.StrongNode {
				parts << markdown_inline_text(node.children)
			}
			vmarkdown.LinkNode {
				parts << markdown_inline_text(node.text)
			}
			vmarkdown.ImageNode {
				parts << markdown_inline_text(node.alt)
			}
		}
	}
	return parts.join(' ').trim_space()
}

fn markdown_slug(text string) string {
	if text.len == 0 {
		return 'empty'
	}
	mut out := []u8{}
	mut last_dash := false
	for b in text.to_lower().bytes() {
		if (b >= `a` && b <= `z`) || (b >= `0` && b <= `9`) {
			out << b
			last_dash = false
			continue
		}
		if !last_dash {
			out << `-`
			last_dash = true
		}
	}
	mut slug := out.bytestr().trim('-')
	if slug.len == 0 {
		slug = 'empty'
	}
	if slug.len > 48 {
		slug = slug[..48]
	}
	return slug
}

fn markdown_hash_id(parts []string) string {
	return sha256.sum(parts.join('|').bytes()).hex()[..16]
}

struct MarkdownOccurrenceCollector {
mut:
	occurrences   []MarkdownOccurrence
	sibling_dupes map[string]int
}

fn build_markdown_occurrences(root_id string, doc vmarkdown.Document) []MarkdownOccurrence {
	mut collector := MarkdownOccurrenceCollector{
		sibling_dupes: map[string]int{}
	}
	mut anchor_stack := []string{}
	for idx, block in doc.children {
		collector.collect_block(block, root_id, '/', mut anchor_stack, 'blocks[${idx}]', idx)
	}
	return collector.occurrences.clone()
}

fn (mut collector MarkdownOccurrenceCollector) collect_block(block vmarkdown.BlockNode, parent_id string, current_anchor string, mut anchor_stack []string, path string, order int) {
	content_id := block.stable_id()
	dup_key := '${parent_id}|${content_id}'
	dup_ordinal := collector.sibling_dupes[dup_key] or { 0 }
	collector.sibling_dupes[dup_key] = dup_ordinal + 1
	mut anchor := current_anchor
	match block {
		vmarkdown.HeadingNode {
			segment := heading_anchor_segment(block)
			if block.level <= anchor_stack.len {
				anchor_stack = anchor_stack[..block.level - 1].clone()
			}
			anchor_stack << segment
			anchor = '/' + anchor_stack.join('/')
		}
		else {}
	}

	occurrence_id := markdown_hash_id([parent_id, content_id, dup_ordinal.str(), anchor, path])
	kind := match block {
		vmarkdown.HeadingNode { 'heading' }
		vmarkdown.ParagraphNode { 'paragraph' }
		vmarkdown.CodeBlockNode { 'code_block' }
		vmarkdown.HorizontalRuleNode { 'horizontal_rule' }
		vmarkdown.MetaNode { 'meta' }
		vmarkdown.BlockquoteNode { 'blockquote' }
		vmarkdown.ListNode { 'list' }
	}

	collector.occurrences << MarkdownOccurrence{
		occurrence_id: occurrence_id
		content_id:    content_id
		parent_id:     parent_id
		kind:          kind
		anchor:        anchor
		order:         order
		path_hint:     path
	}
	match block {
		vmarkdown.BlockquoteNode {
			for idx, child in block.children {
				collector.collect_block(child, occurrence_id, anchor, mut anchor_stack,
					'${path}.children[${idx}]', idx)
			}
		}
		vmarkdown.ListNode {
			for item_idx, item in block.items {
				for child_idx, child in item.children {
					collector.collect_block(child, occurrence_id, anchor, mut anchor_stack,
						'${path}.items[${item_idx}].children[${child_idx}]', child_idx)
				}
			}
		}
		else {}
	}
}

fn occurrence_map(entries []MarkdownOccurrence) map[string]MarkdownOccurrence {
	mut out := map[string]MarkdownOccurrence{}
	for entry in entries {
		out[entry.occurrence_id] = entry
	}
	return out
}

fn occurrence_lookup(entries []MarkdownOccurrence) MarkdownOccurrenceLookup {
	mut by_path := map[string]MarkdownOccurrence{}
	for entry in entries {
		by_path[entry.path_hint] = entry
	}
	return MarkdownOccurrenceLookup{
		by_path: by_path
	}
}

fn markdown_diff_entries(previous []MarkdownOccurrence, current []MarkdownOccurrence) []MarkdownDiffEntry {
	prev_by_id := occurrence_map(previous)
	curr_by_id := occurrence_map(current)
	mut entries := []MarkdownDiffEntry{}
	mut added_by_content := map[string][]MarkdownOccurrence{}
	mut removed_by_content := map[string][]MarkdownOccurrence{}
	for entry in current {
		if prior := prev_by_id[entry.occurrence_id] {
			if prior.content_id == entry.content_id {
				entries << MarkdownDiffEntry{
					op:            .reused
					occurrence_id: entry.occurrence_id
					content_id:    entry.content_id
					kind:          entry.kind
					old_anchor:    prior.anchor
					new_anchor:    entry.anchor
					old_order:     prior.order
					new_order:     entry.order
					path_hint:     entry.path_hint
				}
			} else {
				entries << MarkdownDiffEntry{
					op:            .edited
					occurrence_id: entry.occurrence_id
					content_id:    entry.content_id
					kind:          entry.kind
					old_anchor:    prior.anchor
					new_anchor:    entry.anchor
					old_order:     prior.order
					new_order:     entry.order
					path_hint:     entry.path_hint
				}
			}
			continue
		}
		added_by_content[entry.content_id] << entry
	}
	for entry in previous {
		if entry.occurrence_id !in curr_by_id {
			removed_by_content[entry.content_id] << entry
		}
	}
	for content_id, added in added_by_content {
		removed := removed_by_content[content_id] or { []MarkdownOccurrence{} }
		pair_count := if added.len < removed.len { added.len } else { removed.len }
		for idx in 0 .. pair_count {
			left := removed[idx]
			right := added[idx]
			entries << MarkdownDiffEntry{
				op:            .moved
				occurrence_id: right.occurrence_id
				content_id:    content_id
				kind:          right.kind
				old_anchor:    left.anchor
				new_anchor:    right.anchor
				old_order:     left.order
				new_order:     right.order
				path_hint:     right.path_hint
			}
		}
		for idx in pair_count .. added.len {
			entry := added[idx]
			entries << MarkdownDiffEntry{
				op:            .added
				occurrence_id: entry.occurrence_id
				content_id:    entry.content_id
				kind:          entry.kind
				new_anchor:    entry.anchor
				new_order:     entry.order
				path_hint:     entry.path_hint
			}
		}
		for idx in pair_count .. removed.len {
			entry := removed[idx]
			entries << MarkdownDiffEntry{
				op:            .removed
				occurrence_id: entry.occurrence_id
				content_id:    entry.content_id
				kind:          entry.kind
				old_anchor:    entry.anchor
				old_order:     entry.order
				path_hint:     entry.path_hint
			}
		}
		removed_by_content.delete(content_id)
	}
	for _, removed in removed_by_content {
		for entry in removed {
			entries << MarkdownDiffEntry{
				op:            .removed
				occurrence_id: entry.occurrence_id
				content_id:    entry.content_id
				kind:          entry.kind
				old_anchor:    entry.anchor
				old_order:     entry.order
				path_hint:     entry.path_hint
			}
		}
	}
	return entries
}

pub fn (mut database PersistentDatabase) ingest_markdown(raw string) !MarkdownRef {
	mut store := database.markdown_file_store()!
	ref := markdown_ref_for_source(raw)
	doc := vmarkdown.parse(raw)!
	plan := vmarkdown.plan_ingest_document(doc, store)
	commit_markdown_artifacts(mut store, ref.doc_root_id, plan)!
	occurrences := build_markdown_occurrences(ref.doc_root_id, doc)
	persist_markdown_occurrences(database.root_dir, ref.doc_root_id, occurrences)!
	persist_markdown_source(database.root_dir, ref.doc_root_id, raw)!
	database.cache_markdown_source(ref.doc_root_id, raw)
	return ref
}

pub fn (mut database PersistentDatabase) ingest_markdown_source_only(raw string) !MarkdownRef {
	_ = database.markdown_file_store()!
	ref := markdown_ref_for_source(raw)
	persist_markdown_source(database.root_dir, ref.doc_root_id, raw)!
	database.cache_markdown_source(ref.doc_root_id, raw)
	database.cache_markdown_fts_text(ref.doc_root_id, FtsTextMode.raw_markdown.str(), raw)
	database.cache_markdown_fts_text(ref.doc_root_id, 'visible_text', extract_markdown_visible_text_fast(raw,
		false))
	database.cache_markdown_fts_text(ref.doc_root_id, 'visible_text_with_code', extract_markdown_visible_text_fast(raw,
		true))
	return ref
}

pub fn (database &PersistentDatabase) markdown_artifacts_ready(ref MarkdownRef) bool {
	if ref.is_zero() {
		return true
	}
	return markdown_artifacts_ready_at(database.root_dir, ref.doc_root_id)
}

pub fn (mut database PersistentDatabase) rebuild_markdown_artifacts(ref MarkdownRef) ! {
	if ref.is_zero() {
		return
	}
	raw := database.load_markdown(ref)!
	if markdown_source_hash(raw) != ref.source_hash {
		return error('markdown source hash mismatch for ${ref.doc_root_id}')
	}
	mut store := database.markdown_file_store()!
	doc := vmarkdown.parse(raw)!
	plan := vmarkdown.plan_ingest_document(doc, store)
	commit_markdown_artifacts(mut store, ref.doc_root_id, plan)!
	occurrences := build_markdown_occurrences(ref.doc_root_id, doc)
	persist_markdown_occurrences(database.root_dir, ref.doc_root_id, occurrences)!
}

pub fn (mut database PersistentDatabase) rebuild_markdown_artifacts_for_table(branch_name string, table_name string, column_name string, limit int) !MarkdownArtifactRebuildResult {
	session := database.begin_session(SessionOptions.for_branch(branch_name))!
	spec := session.table_spec(table_name)!
	column := spec.table.column(column_name)!
	if column.typ != .markdown_ {
		return error('column is not markdown: ${column_name}')
	}
	rows := session.scan_table(mut database, table_name, 0)!
	mut result := MarkdownArtifactRebuildResult{}
	for row in rows {
		if limit > 0 && result.rebuilt >= limit {
			break
		}
		result.scanned++
		ref := get_markdown_ref_from_row(row, column, column_name) or {
			result.failed++
			result.errors << '${row.primary_key.bytestr()}: ${err}'
			continue
		}
		if ref.is_zero() {
			continue
		}
		result.markdown_refs++
		if database.markdown_artifacts_ready(ref) {
			result.skipped_ready++
			continue
		}
		result.pending++
		database.rebuild_markdown_artifacts(ref) or {
			result.failed++
			result.errors << '${row.primary_key.bytestr()}: ${err}'
			continue
		}
		result.rebuilt++
	}
	return result
}

pub fn (database &PersistentDatabase) load_markdown(ref MarkdownRef) !string {
	if ref.is_zero() {
		return ''
	}
	if raw := database.markdown_sources[ref.doc_root_id] {
		return raw
	}
	return load_markdown_source(database.root_dir, ref.doc_root_id)
}

pub fn (database &PersistentDatabase) diff_markdown_refs(left MarkdownRef, right MarkdownRef) !MarkdownDiff {
	left_occurrences := load_markdown_occurrences(database.root_dir, left.doc_root_id)!
	right_occurrences := load_markdown_occurrences(database.root_dir, right.doc_root_id)!
	return MarkdownDiff{
		left_root_id:  left.doc_root_id
		right_root_id: right.doc_root_id
		entries:       markdown_diff_entries(left_occurrences, right_occurrences)
	}
}

pub fn (mut database PersistentDatabase) preview_markdown_merge_refs(base MarkdownRef, ours MarkdownRef, theirs MarkdownRef) !MarkdownMergePreview {
	base_to_ours := database.diff_markdown_refs(base, ours)!
	base_to_theirs := database.diff_markdown_refs(base, theirs)!
	merged_ref := database.try_merge_markdown_refs(base, ours, theirs) or { MarkdownRef{} }
	merged_source := if merged_ref.doc_root_id.len > 0 {
		database.load_markdown(merged_ref) or { '' }
	} else {
		''
	}
	return MarkdownMergePreview{
		base_ref:       base
		ours_ref:       ours
		theirs_ref:     theirs
		base_to_ours:   base_to_ours
		base_to_theirs: base_to_theirs
		mergeable:      merged_ref.doc_root_id.len > 0
		merged_ref:     merged_ref
		merged_source:  merged_source
	}
}

pub fn (mut database PersistentDatabase) merge_markdown_refs(base MarkdownRef, ours MarkdownRef, theirs MarkdownRef) !MarkdownRef {
	return database.try_merge_markdown_refs(base, ours, theirs) or {
		return error('markdown refs could not be merged automatically')
	}
}

fn markdown_docs_equal(left vmarkdown.Document, right vmarkdown.Document) bool {
	return left.stable_id() == right.stable_id()
}

fn markdown_block_equal(left vmarkdown.BlockNode, right vmarkdown.BlockNode) bool {
	return left.stable_id() == right.stable_id()
}

fn markdown_item_equal(left vmarkdown.ListItemNode, right vmarkdown.ListItemNode) bool {
	return left.encode() == right.encode()
}

fn markdown_block_reorder_mapping(base []vmarkdown.BlockNode, candidate []vmarkdown.BlockNode, base_lookup MarkdownOccurrenceLookup, candidate_lookup MarkdownOccurrenceLookup, path_prefix string) ?[]int {
	if base.len != candidate.len {
		return none
	}
	mut positions := map[string][]int{}
	for idx, block in base {
		id := block.stable_id()
		mut bucket := positions[id] or { []int{} }
		bucket << idx
		positions[id] = bucket
	}
	base_hints := markdown_block_context_hints(base, base_lookup, path_prefix)
	candidate_hints := markdown_block_context_hints(candidate, candidate_lookup, path_prefix)
	mut mapping := []int{len: candidate.len, init: -1}
	mut used := map[int]bool{}
	for idx, block in candidate {
		id := block.stable_id()
		base_positions := positions[id] or { return none }
		mut best_idx := -1
		mut best_score := 1 << 30
		for base_idx in base_positions {
			if used[base_idx] {
				continue
			}
			score := markdown_block_mapping_score(base, candidate, base_hints, candidate_hints,
				base_idx, idx)
			if score < best_score {
				best_score = score
				best_idx = base_idx
			}
		}
		if best_idx < 0 {
			return none
		}
		used[best_idx] = true
		mapping[idx] = best_idx
	}
	return mapping
}

fn markdown_item_reorder_mapping(base []vmarkdown.ListItemNode, candidate []vmarkdown.ListItemNode, base_lookup MarkdownOccurrenceLookup, candidate_lookup MarkdownOccurrenceLookup, path_prefix string) ?[]int {
	if base.len != candidate.len {
		return none
	}
	mut positions := map[string][]int{}
	for idx, item in base {
		id := item.encode().hex()
		mut bucket := positions[id] or { []int{} }
		bucket << idx
		positions[id] = bucket
	}
	base_hints := markdown_item_context_hints(base, base_lookup, path_prefix)
	candidate_hints := markdown_item_context_hints(candidate, candidate_lookup, path_prefix)
	mut mapping := []int{len: candidate.len, init: -1}
	mut used := map[int]bool{}
	for idx, item in candidate {
		id := item.encode().hex()
		base_positions := positions[id] or { return none }
		mut best_idx := -1
		mut best_score := 1 << 30
		for base_idx in base_positions {
			if used[base_idx] {
				continue
			}
			score := markdown_item_mapping_score(base, candidate, base_hints, candidate_hints,
				base_idx, idx)
			if score < best_score {
				best_score = score
				best_idx = base_idx
			}
		}
		if best_idx < 0 {
			return none
		}
		used[best_idx] = true
		mapping[idx] = best_idx
	}
	return mapping
}

fn markdown_occurrence_hint(lookup MarkdownOccurrenceLookup, path string) string {
	entry := lookup.by_path[path] or { return '' }
	return '${entry.anchor}|${entry.parent_id}|${entry.kind}'
}

fn markdown_block_path(path_prefix string, idx int) string {
	return '${path_prefix}[${idx}]'
}

fn markdown_item_path(path_prefix string, idx int) string {
	return '${path_prefix}[${idx}]'
}

fn markdown_block_context_hints(blocks []vmarkdown.BlockNode, lookup MarkdownOccurrenceLookup, path_prefix string) []string {
	mut hints := []string{len: blocks.len}
	mut heading_context := ''
	for idx, block in blocks {
		if block is vmarkdown.HeadingNode {
			heading_context = vmarkdown.BlockNode(block).stable_id()
		}
		prev_id := if idx > 0 { blocks[idx - 1].stable_id() } else { '' }
		next_id := if idx + 1 < blocks.len { blocks[idx + 1].stable_id() } else { '' }
		path := markdown_block_path(path_prefix, idx)
		hints[idx] = '${markdown_occurrence_hint(lookup, path)}|${heading_context}|${prev_id}|${next_id}|${markdown_block_shape(block)}'
	}
	return hints
}

fn markdown_item_context_hints(items []vmarkdown.ListItemNode, lookup MarkdownOccurrenceLookup, path_prefix string) []string {
	mut hints := []string{len: items.len}
	for idx, item in items {
		prev_id := if idx > 0 { items[idx - 1].encode().hex() } else { '' }
		next_id := if idx + 1 < items.len { items[idx + 1].encode().hex() } else { '' }
		item_path := markdown_item_path(path_prefix, idx)
		first_child_path := '${item_path}.children[0]'
		hints[idx] = '${markdown_occurrence_hint(lookup, first_child_path)}|${prev_id}|${next_id}|${markdown_item_shape(item)}'
	}
	return hints
}

fn markdown_block_shape(block vmarkdown.BlockNode) string {
	return match block {
		vmarkdown.HeadingNode { 'h:${block.level}' }
		vmarkdown.ParagraphNode { 'p:${block.children.len}' }
		vmarkdown.CodeBlockNode { 'c:${block.lang}:${block.content.len}' }
		vmarkdown.HorizontalRuleNode { 'hr' }
		vmarkdown.MetaNode { 'm:${block.data.len}' }
		vmarkdown.BlockquoteNode { 'q:${block.children.len}' }
		vmarkdown.ListNode { 'l:${block.is_ordered}:${block.items.len}' }
	}
}

fn markdown_item_shape(item vmarkdown.ListItemNode) string {
	first_child := if item.children.len > 0 { markdown_block_shape(item.children[0]) } else { '' }
	return '${item.level}|${item.number}|${item.children.len}|${first_child}'
}

fn markdown_neighbor_match_score(left string, right string) int {
	if left.len == 0 || right.len == 0 {
		return 2
	}
	return if left == right { 0 } else { 12 }
}

fn markdown_abs_int(value int) int {
	return if value < 0 { -value } else { value }
}

fn markdown_block_mapping_score(base []vmarkdown.BlockNode, candidate []vmarkdown.BlockNode, base_hints []string, candidate_hints []string, base_idx int, candidate_idx int) int {
	mut score := markdown_abs_int(base_idx - candidate_idx)
	if base_hints[base_idx] != candidate_hints[candidate_idx] {
		score += 40
	}
	prev_base := if base_idx > 0 { base[base_idx - 1].stable_id() } else { '' }
	prev_candidate := if candidate_idx > 0 { candidate[candidate_idx - 1].stable_id() } else { '' }
	next_base := if base_idx + 1 < base.len { base[base_idx + 1].stable_id() } else { '' }
	next_candidate := if candidate_idx + 1 < candidate.len {
		candidate[candidate_idx + 1].stable_id()
	} else {
		''
	}
	score += markdown_neighbor_match_score(prev_base, prev_candidate)
	score += markdown_neighbor_match_score(next_base, next_candidate)
	return score
}

fn markdown_item_mapping_score(base []vmarkdown.ListItemNode, candidate []vmarkdown.ListItemNode, base_hints []string, candidate_hints []string, base_idx int, candidate_idx int) int {
	mut score := markdown_abs_int(base_idx - candidate_idx)
	if base_hints[base_idx] != candidate_hints[candidate_idx] {
		score += 40
	}
	prev_base := if base_idx > 0 { base[base_idx - 1].encode().hex() } else { '' }
	prev_candidate := if candidate_idx > 0 {
		candidate[candidate_idx - 1].encode().hex()
	} else {
		''
	}
	next_base := if base_idx + 1 < base.len { base[base_idx + 1].encode().hex() } else { '' }
	next_candidate := if candidate_idx + 1 < candidate.len {
		candidate[candidate_idx + 1].encode().hex()
	} else {
		''
	}
	score += markdown_neighbor_match_score(prev_base, prev_candidate)
	score += markdown_neighbor_match_score(next_base, next_candidate)
	return score
}

fn markdown_doc_prefix_matches(base vmarkdown.Document, candidate vmarkdown.Document) bool {
	if candidate.children.len < base.children.len {
		return false
	}
	for idx, block in base.children {
		if !markdown_block_equal(block, candidate.children[idx]) {
			return false
		}
	}
	return true
}

fn markdown_block_prefix_matches(base []vmarkdown.BlockNode, candidate []vmarkdown.BlockNode) bool {
	if candidate.len < base.len {
		return false
	}
	for idx, block in base {
		if !markdown_block_equal(block, candidate[idx]) {
			return false
		}
	}
	return true
}

fn markdown_item_prefix_matches(base []vmarkdown.ListItemNode, candidate []vmarkdown.ListItemNode) bool {
	if candidate.len < base.len {
		return false
	}
	for idx, item in base {
		if !markdown_item_equal(item, candidate[idx]) {
			return false
		}
	}
	return true
}

fn resolve_markdown_int(base int, ours int, theirs int) ?int {
	if ours == theirs {
		return ours
	}
	if ours == base {
		return theirs
	}
	if theirs == base {
		return ours
	}
	return none
}

fn resolve_markdown_bool(base bool, ours bool, theirs bool) ?bool {
	if ours == theirs {
		return ours
	}
	if ours == base {
		return theirs
	}
	if theirs == base {
		return ours
	}
	return none
}

fn merge_markdown_block_sequence(base []vmarkdown.BlockNode, ours []vmarkdown.BlockNode, theirs []vmarkdown.BlockNode, ctx MarkdownMergeContext, path_prefix string) ?[]vmarkdown.BlockNode {
	if ours_reorder := markdown_block_reorder_mapping(base, ours, ctx.base_lookup, ctx.ours_lookup,
		path_prefix)
	{
		if theirs_reorder := markdown_block_reorder_mapping(base, theirs, ctx.base_lookup,
			ctx.theirs_lookup, path_prefix)
		{
			if ours_reorder == theirs_reorder {
				return ours
			}
		} else {
			mut merged := []vmarkdown.BlockNode{cap: ours.len}
			for idx, base_idx in ours_reorder {
				merged << merge_markdown_block(base[base_idx], ours[idx], theirs[base_idx], ctx,
					markdown_block_path(path_prefix, idx))?
			}
			return merged
		}
	}
	if theirs_reorder := markdown_block_reorder_mapping(base, theirs, ctx.base_lookup,
		ctx.theirs_lookup, path_prefix)
	{
		mut merged := []vmarkdown.BlockNode{cap: theirs.len}
		for idx, base_idx in theirs_reorder {
			merged << merge_markdown_block(base[base_idx], ours[base_idx], theirs[idx], ctx,
				markdown_block_path(path_prefix, idx))?
		}
		return merged
	}
	if ours.len == base.len && theirs.len == base.len {
		mut merged := []vmarkdown.BlockNode{cap: base.len}
		for idx in 0 .. base.len {
			merged << merge_markdown_block(base[idx], ours[idx], theirs[idx], ctx,
				markdown_block_path(path_prefix, idx))?
		}
		return merged
	}
	if !markdown_block_prefix_matches(base, ours) || !markdown_block_prefix_matches(base, theirs) {
		return none
	}
	mut merged := base.clone()
	ours_tail := ours[base.len..]
	theirs_tail := theirs[base.len..]
	if ours_tail.len == theirs_tail.len {
		mut same := true
		for idx in 0 .. ours_tail.len {
			if !markdown_block_equal(ours_tail[idx], theirs_tail[idx]) {
				same = false
				break
			}
		}
		if same {
			merged << ours_tail
			return merged
		}
	}
	merged << ours_tail
	merged << theirs_tail
	return merged
}

fn merge_markdown_item_sequence(base []vmarkdown.ListItemNode, ours []vmarkdown.ListItemNode, theirs []vmarkdown.ListItemNode, ctx MarkdownMergeContext, path_prefix string) ?[]vmarkdown.ListItemNode {
	if ours_reorder := markdown_item_reorder_mapping(base, ours, ctx.base_lookup, ctx.ours_lookup,
		path_prefix)
	{
		if theirs_reorder := markdown_item_reorder_mapping(base, theirs, ctx.base_lookup,
			ctx.theirs_lookup, path_prefix)
		{
			if ours_reorder == theirs_reorder {
				return ours
			}
		} else {
			mut merged := []vmarkdown.ListItemNode{cap: ours.len}
			for idx, base_idx in ours_reorder {
				merged << merge_markdown_list_item(base[base_idx], ours[idx], theirs[base_idx],
					ctx, markdown_item_path(path_prefix, idx))?
			}
			return merged
		}
	}
	if theirs_reorder := markdown_item_reorder_mapping(base, theirs, ctx.base_lookup,
		ctx.theirs_lookup, path_prefix)
	{
		mut merged := []vmarkdown.ListItemNode{cap: theirs.len}
		for idx, base_idx in theirs_reorder {
			merged << merge_markdown_list_item(base[base_idx], ours[base_idx], theirs[idx], ctx,
				markdown_item_path(path_prefix, idx))?
		}
		return merged
	}
	if ours.len == base.len && theirs.len == base.len {
		mut merged := []vmarkdown.ListItemNode{cap: base.len}
		for idx in 0 .. base.len {
			merged << merge_markdown_list_item(base[idx], ours[idx], theirs[idx], ctx,
				markdown_item_path(path_prefix, idx))?
		}
		return merged
	}
	if !markdown_item_prefix_matches(base, ours) || !markdown_item_prefix_matches(base, theirs) {
		return none
	}
	mut merged := base.clone()
	ours_tail := ours[base.len..]
	theirs_tail := theirs[base.len..]
	if ours_tail.len == theirs_tail.len {
		mut same := true
		for idx in 0 .. ours_tail.len {
			if !markdown_item_equal(ours_tail[idx], theirs_tail[idx]) {
				same = false
				break
			}
		}
		if same {
			merged << ours_tail
			return merged
		}
	}
	merged << ours_tail
	merged << theirs_tail
	return merged
}

fn merge_markdown_list_item(base vmarkdown.ListItemNode, ours vmarkdown.ListItemNode, theirs vmarkdown.ListItemNode, ctx MarkdownMergeContext, path string) ?vmarkdown.ListItemNode {
	if markdown_item_equal(ours, theirs) {
		return ours
	}
	if markdown_item_equal(base, ours) {
		return theirs
	}
	if markdown_item_equal(base, theirs) {
		return ours
	}
	level := resolve_markdown_int(base.level, ours.level, theirs.level)?
	number := resolve_markdown_int(base.number, ours.number, theirs.number)?
	children := merge_markdown_block_sequence(base.children, ours.children, theirs.children, ctx,
		'${path}.children')?
	return vmarkdown.ListItemNode{
		level:    level
		number:   number
		children: children
	}
}

fn merge_markdown_block(base vmarkdown.BlockNode, ours vmarkdown.BlockNode, theirs vmarkdown.BlockNode, ctx MarkdownMergeContext, path string) ?vmarkdown.BlockNode {
	if markdown_block_equal(ours, theirs) {
		return ours
	}
	if markdown_block_equal(base, ours) {
		return theirs
	}
	if markdown_block_equal(base, theirs) {
		return ours
	}
	match base {
		vmarkdown.BlockquoteNode {
			if ours is vmarkdown.BlockquoteNode && theirs is vmarkdown.BlockquoteNode {
				children := merge_markdown_block_sequence(base.children, ours.children,
					theirs.children, ctx, '${path}.children')?
				return vmarkdown.BlockNode(vmarkdown.BlockquoteNode{
					children: children
				})
			}
		}
		vmarkdown.ListNode {
			if ours is vmarkdown.ListNode && theirs is vmarkdown.ListNode {
				is_ordered := resolve_markdown_bool(base.is_ordered, ours.is_ordered,
					theirs.is_ordered)?
				start := resolve_markdown_int(base.start, ours.start, theirs.start)?
				items := merge_markdown_item_sequence(base.items, ours.items, theirs.items, ctx,
					'${path}.items')?
				return vmarkdown.BlockNode(vmarkdown.ListNode{
					is_ordered: is_ordered
					start:      start
					items:      items
				})
			}
		}
		else {}
	}

	return none
}

fn merge_markdown_same_length(base vmarkdown.Document, ours vmarkdown.Document, theirs vmarkdown.Document) ?vmarkdown.Document {
	if base.children.len != ours.children.len || base.children.len != theirs.children.len {
		return none
	}
	mut merged := []vmarkdown.BlockNode{cap: base.children.len}
	ctx := MarkdownMergeContext{
		base_lookup:   occurrence_lookup(build_markdown_occurrences(base.stable_id(), base))
		ours_lookup:   occurrence_lookup(build_markdown_occurrences(ours.stable_id(), ours))
		theirs_lookup: occurrence_lookup(build_markdown_occurrences(theirs.stable_id(), theirs))
	}
	for idx in 0 .. base.children.len {
		merged << merge_markdown_block(base.children[idx], ours.children[idx],
			theirs.children[idx], ctx, markdown_block_path('blocks', idx))?
	}
	return vmarkdown.Document{
		children: merged
	}
}

fn merge_markdown_append_only(base vmarkdown.Document, ours vmarkdown.Document, theirs vmarkdown.Document) ?vmarkdown.Document {
	if !markdown_doc_prefix_matches(base, ours) || !markdown_doc_prefix_matches(base, theirs) {
		return none
	}
	mut merged := base.children.clone()
	ours_tail := ours.children[base.children.len..]
	theirs_tail := theirs.children[base.children.len..]
	if ours_tail.len == theirs_tail.len {
		mut same := true
		for idx in 0 .. ours_tail.len {
			if !markdown_block_equal(ours_tail[idx], theirs_tail[idx]) {
				same = false
				break
			}
		}
		if same {
			merged << ours_tail
			return vmarkdown.Document{
				children: merged
			}
		}
	}
	merged << ours_tail
	merged << theirs_tail
	return vmarkdown.Document{
		children: merged
	}
}

fn merge_markdown_documents(base vmarkdown.Document, ours vmarkdown.Document, theirs vmarkdown.Document) ?vmarkdown.Document {
	if markdown_docs_equal(ours, theirs) {
		return ours
	}
	if markdown_docs_equal(base, ours) {
		return theirs
	}
	if markdown_docs_equal(base, theirs) {
		return ours
	}
	ctx := MarkdownMergeContext{
		base_lookup:   occurrence_lookup(build_markdown_occurrences(base.stable_id(), base))
		ours_lookup:   occurrence_lookup(build_markdown_occurrences(ours.stable_id(), ours))
		theirs_lookup: occurrence_lookup(build_markdown_occurrences(theirs.stable_id(), theirs))
	}
	if merged_children := merge_markdown_block_sequence(base.children, ours.children,
		theirs.children, ctx, 'blocks')
	{
		return vmarkdown.Document{
			children: merged_children
		}
	}
	return none
}

pub fn (mut database PersistentDatabase) try_merge_markdown_refs(base MarkdownRef, ours MarkdownRef, theirs MarkdownRef) ?MarkdownRef {
	base_raw := database.load_markdown(base) or { return none }
	ours_raw := database.load_markdown(ours) or { return none }
	theirs_raw := database.load_markdown(theirs) or { return none }
	base_doc := vmarkdown.parse(base_raw) or { return none }
	ours_doc := vmarkdown.parse(ours_raw) or { return none }
	theirs_doc := vmarkdown.parse(theirs_raw) or { return none }
	merged_doc := merge_markdown_documents(base_doc, ours_doc, theirs_doc)?
	merged_raw := merged_doc.to_markdown()
	return database.ingest_markdown(merged_raw) or { return none }
}
