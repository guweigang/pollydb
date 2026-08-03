module storage

import time

const node_magic = [u8(`P`), `T`, `R`, `E`]
const node_version = u8(1)
const node_header_base_len = 12

pub enum NodeKind {
	leaf
	internal
}

pub struct KVPair {
pub:
	key   []u8
	value []u8
}

pub struct NodeRef {
pub:
	key        []u8
	cid        string
	item_count int
}

pub struct Node {
pub:
	kind       NodeKind
	level      int
	item_count int
	cid        string
	data       []u8
	min_key    []u8
	max_key    []u8
}

pub fn Node.new_leaf(data []u8, item_count int, min_key []u8, max_key []u8) Node {
	return Node{
		kind:       .leaf
		level:      0
		item_count: item_count
		cid:        cid_for_bytes(data)
		data:       data
		min_key:    min_key.clone()
		max_key:    max_key.clone()
	}
}

pub fn Node.new_internal(level int, data []u8, item_count int, min_key []u8, max_key []u8) Node {
	return Node{
		kind:       .internal
		level:      level
		item_count: item_count
		cid:        cid_for_bytes(data)
		data:       data
		min_key:    min_key.clone()
		max_key:    max_key.clone()
	}
}

pub fn (n Node) to_ref() NodeRef {
	return NodeRef{
		key:        n.min_key.clone()
		cid:        n.cid
		item_count: n.item_count
	}
}

pub struct Tree {
pub:
	root  NodeRef
	nodes map[string]Node
}

pub enum MutationOp {
	put
	delete
}

pub struct Mutation {
pub:
	op    MutationOp
	key   []u8
	value []u8
}

pub struct TreeDiff {
pub:
	old_root_cid string
	new_root_cid string
	added_cids   []string
	removed_cids []string
	reused_cids  []string
}

pub struct TreeUpdate {
pub:
	tree Tree
	diff TreeDiff
}

pub struct TreeBuildStageTimings {
pub:
	leaf_ms                i64
	leaf_chunk_ms          i64
	leaf_node_ms           i64
	leaf_node_serialize_ms i64
	leaf_node_cid_ms       i64
	leaf_node_add_ms       i64
	internal_ms            i64
}

pub struct TreeBuildResult {
pub:
	tree    Tree
	timings TreeBuildStageTimings
}

struct TreeLeafBuildTimings {
	chunk_ms          i64
	node_ms           i64
	node_serialize_ms i64
	node_cid_ms       i64
	node_add_ms       i64
}

struct TreeLeafBuildResult {
	refs    []NodeRef
	timings TreeLeafBuildTimings
}

pub struct TreeIterator {
pub:
	tree  Tree
	end   []u8
	limit int
mut:
	path             []TreePathStep
	leaf_items       []KVPair
	item_idx         int
	yielded          int
	started          bool
	current_item     KVPair
	has_current_item bool
}

pub struct TreeReverseIterator {
pub:
	tree  Tree
	start []u8
	limit int
mut:
	path             []TreePathStep
	leaf_items       []KVPair
	item_idx         int
	yielded          int
	started          bool
	current_item     KVPair
	has_current_item bool
}

pub struct TreePrefixIterator {
pub:
	tree  Tree
	limit int
mut:
	prefix           []u8
	iter             TreeIterator
	current_item     KVPair
	has_current_item bool
}

pub enum TreeCursorMode {
	forward
	reverse
	prefix
}

pub struct TreeCursor {
pub:
	mode  TreeCursorMode
	tree  Tree
	limit int
mut:
	forward_iter TreeIterator
	reverse_iter TreeReverseIterator
	prefix_iter  TreePrefixIterator
}

pub struct TreeRawIterator {
pub:
	tree  Tree
	end   []u8
	limit int
mut:
	path             []TreePathStep
	leaf_layout      NodeLayout
	item_idx         int
	yielded          int
	started          bool
	current_item     KVPair
	has_current_item bool
}

pub struct TreeRawCursor {
pub:
	tree  Tree
	end   []u8
	limit int
mut:
	iter TreeRawIterator
}

struct TreePathStep {
	node         Node
	child_refs   []NodeRef
	selected_idx int
}

struct MutationLeafGroup {
mut:
	anchor_key []u8
	mutations  []Mutation
}

struct TreeBoundMatch {
	item KVPair
}

pub struct TreeKeyStats {
pub:
	path_depth      int
	leaf_item_count int
}

pub struct StoreLookupStats {
pub:
	path_depth      int
	nodes_read      int
	leaf_item_count int
}

pub struct StoreLookupResult {
pub:
	item  KVPair
	stats StoreLookupStats
}

pub struct OrderedScanStats {
mut:
	nodes_read     int
	leaves_visited int
	items_examined int
}

pub struct TreeBuilder {
pub:
	cfg ChunkConfig
mut:
	nodes map[string]Node
}

pub fn TreeBuilder.new(cfg ChunkConfig) TreeBuilder {
	return TreeBuilder{
		cfg:   cfg
		nodes: map[string]Node{}
	}
}

pub fn Tree.build(items []KVPair, cfg ChunkConfig) !Tree {
	mut builder := TreeBuilder.new(cfg)
	return builder.build(items)
}

struct ByteWriter {
mut:
	buf []u8
}

fn (mut w ByteWriter) write_u8(v u8) {
	w.buf << v
}

fn (mut w ByteWriter) write_u16(v u16) {
	w.buf << u8(v & 0xff)
	w.buf << u8((v >> 8) & 0xff)
}

fn (mut w ByteWriter) write_u32(v u32) {
	w.buf << u8(v & 0xff)
	w.buf << u8((v >> 8) & 0xff)
	w.buf << u8((v >> 16) & 0xff)
	w.buf << u8((v >> 24) & 0xff)
}

fn (mut w ByteWriter) write_u64(v u64) {
	w.buf << u8((v >> 56) & 0xff)
	w.buf << u8((v >> 48) & 0xff)
	w.buf << u8((v >> 40) & 0xff)
	w.buf << u8((v >> 32) & 0xff)
	w.buf << u8((v >> 24) & 0xff)
	w.buf << u8((v >> 16) & 0xff)
	w.buf << u8((v >> 8) & 0xff)
	w.buf << u8(v & 0xff)
}

fn (mut w ByteWriter) write_bytes(data []u8) {
	w.buf << data
}

fn (w ByteWriter) bytes() []u8 {
	return w.buf.clone()
}

fn (w ByteWriter) owned_bytes() []u8 {
	return w.buf
}

fn rolling_hash_u32(hash u64, v u32) u64 {
	mut next := hash
	next = rolling_hash(next, u8(v & 0xff))
	next = rolling_hash(next, u8((v >> 8) & 0xff))
	next = rolling_hash(next, u8((v >> 16) & 0xff))
	next = rolling_hash(next, u8((v >> 24) & 0xff))
	return next
}

struct ChunkGroup {
	start int
	end   int
}

struct NodeHeader {
	kind        NodeKind
	level       int
	item_count  int
	key_offsets []u32
	val_offsets []u32
	raw         []u8
}

struct NodeLayout {
	kind             NodeKind
	level            int
	item_count       int
	data             []u8
	key_offsets_base int
	val_offsets_base int
	raw_base         int
}

struct ByteStorePathStep {
	layout       NodeLayout
	child_cids   [][]u8
	selected_idx int
}

fn compare_key_bytes(a []u8, b []u8) int {
	limit := if a.len < b.len { a.len } else { b.len }
	for idx in 0 .. limit {
		if a[idx] < b[idx] {
			return -1
		}
		if a[idx] > b[idx] {
			return 1
		}
	}
	if a.len < b.len {
		return -1
	}
	if a.len > b.len {
		return 1
	}
	return 0
}

fn choose_child_index(key []u8, children []NodeRef) int {
	if children.len == 0 {
		return 0
	}
	mut idx := 0
	for i, child in children {
		if compare_key_bytes(key, child.key) >= 0 {
			idx = i
		} else {
			break
		}
	}
	return idx
}

fn read_u32_le(data []u8) u32 {
	return u32(data[0]) | (u32(data[1]) << 8) | (u32(data[2]) << 16) | (u32(data[3]) << 24)
}

fn has_prefix_bytes(data []u8, prefix []u8) bool {
	if prefix.len > data.len {
		return false
	}
	for idx, b in prefix {
		if data[idx] != b {
			return false
		}
	}
	return true
}

pub fn (item KVPair) record_bytes() []u8 {
	mut out := ByteWriter{}
	out.write_u32(u32(item.key.len))
	out.write_u32(u32(item.value.len))
	out.write_bytes(item.key)
	out.write_bytes(item.value)
	return out.owned_bytes()
}

pub fn KVPair.from_leaf_record(data []u8) !KVPair {
	if data.len < 8 {
		return error('leaf record too short')
	}
	key_len := int(read_u32_le(data[..4]))
	val_len := int(read_u32_le(data[4..8]))
	if data.len != 8 + key_len + val_len {
		return error('leaf record length mismatch')
	}
	return KVPair{
		key:   data[8..8 + key_len].clone()
		value: data[8 + key_len..].clone()
	}
}

fn sorted_pairs(items []KVPair) ![]KVPair {
	mut sorted := items.clone()
	sorted.sort_with_compare(fn (a &KVPair, b &KVPair) int {
		return compare_key_bytes(a.key, b.key)
	})
	for idx in 1 .. sorted.len {
		if compare_key_bytes(sorted[idx - 1].key, sorted[idx].key) == 0 {
			return error('duplicate key at index ${idx}')
		}
	}
	return sorted
}

fn serialize_records(kind NodeKind, level int, keys [][]u8, values [][]u8) ![]u8 {
	if keys.len != values.len {
		return error('keys and values length mismatch')
	}

	mut total_key_len := 0
	for key in keys {
		total_key_len += key.len
	}
	mut total_value_len := 0
	for value in values {
		total_value_len += value.len
	}
	header_len := node_header_base_len + (keys.len * 8)
	mut out := ByteWriter{
		buf: []u8{cap: header_len + total_key_len + total_value_len}
	}
	out.write_bytes(node_magic)
	out.write_u8(node_version)
	out.write_u8(u8(kind))
	out.write_u16(u16(level))
	out.write_u32(u32(keys.len))
	mut raw_offset := 0
	for key in keys {
		out.write_u32(u32(raw_offset))
		raw_offset += key.len
	}
	raw_offset = total_key_len
	for value in values {
		out.write_u32(u32(raw_offset))
		raw_offset += value.len
	}
	for key in keys {
		out.write_bytes(key)
	}
	for value in values {
		out.write_bytes(value)
	}

	return out.owned_bytes()
}

fn NodeHeader.from_bytes(data []u8) !NodeHeader {
	if data.len < node_header_base_len {
		return error('node data too short')
	}
	if data[..4] != node_magic {
		return error('invalid node magic')
	}
	if data[4] != node_version {
		return error('unsupported node version')
	}
	kind := unsafe { NodeKind(data[5]) }
	level := int(u32(data[6]) | (u32(data[7]) << 8))
	item_count := int(u32(data[8]) | (u32(data[9]) << 8) | (u32(data[10]) << 16) | (u32(data[11]) << 24))
	offsets_len := item_count * 8
	header_len := node_header_base_len + offsets_len
	if data.len < header_len {
		return error('node offsets truncated')
	}
	mut key_offsets := []u32{cap: item_count}
	mut val_offsets := []u32{cap: item_count}
	mut cursor := node_header_base_len
	for _ in 0 .. item_count {
		key_offsets << read_u32_le(data[cursor..cursor + 4])
		cursor += 4
	}
	for _ in 0 .. item_count {
		val_offsets << read_u32_le(data[cursor..cursor + 4])
		cursor += 4
	}
	return NodeHeader{
		kind:        kind
		level:       level
		item_count:  item_count
		key_offsets: key_offsets
		val_offsets: val_offsets
		raw:         data[header_len..].clone()
	}
}

fn NodeLayout.from_bytes(data []u8) !NodeLayout {
	if data.len < node_header_base_len {
		return error('node data too short')
	}
	if data[..4] != node_magic {
		return error('invalid node magic')
	}
	if data[4] != node_version {
		return error('unsupported node version')
	}
	kind := unsafe { NodeKind(data[5]) }
	level := int(u32(data[6]) | (u32(data[7]) << 8))
	item_count := int(u32(data[8]) | (u32(data[9]) << 8) | (u32(data[10]) << 16) | (u32(data[11]) << 24))
	offsets_len := item_count * 8
	header_len := node_header_base_len + offsets_len
	if data.len < header_len {
		return error('node offsets truncated')
	}
	return NodeLayout{
		kind:             kind
		level:            level
		item_count:       item_count
		data:             data
		key_offsets_base: node_header_base_len
		val_offsets_base: node_header_base_len + item_count * 4
		raw_base:         header_len
	}
}

fn (layout NodeLayout) key_offset(idx int) int {
	base := layout.key_offsets_base + idx * 4
	return int(read_u32_le(layout.data[base..base + 4]))
}

fn (layout NodeLayout) value_offset(idx int) int {
	base := layout.val_offsets_base + idx * 4
	return int(read_u32_le(layout.data[base..base + 4]))
}

fn (layout NodeLayout) key_view(idx int) []u8 {
	start := layout.raw_base + layout.key_offset(idx)
	end := if idx + 1 < layout.item_count {
		layout.raw_base + layout.key_offset(idx + 1)
	} else {
		layout.raw_base + layout.value_offset(0)
	}
	return layout.data[start..end]
}

fn (layout NodeLayout) value_view(idx int) []u8 {
	start := layout.raw_base + layout.value_offset(idx)
	end := if idx + 1 < layout.item_count {
		layout.raw_base + layout.value_offset(idx + 1)
	} else {
		layout.data.len
	}
	return layout.data[start..end]
}

fn (layout NodeLayout) child_cid_view(idx int) ![]u8 {
	record := layout.value_view(idx)
	if record.len < 12 {
		return error('internal record too short')
	}
	key_len := int(read_u32_le(record[..4]))
	cid_len := int(read_u32_le(record[4..8]))
	if record.len != 12 + key_len + cid_len {
		return error('internal record length mismatch')
	}
	return record[12 + key_len..]
}

fn (layout NodeLayout) child_item_count(idx int) !int {
	record := layout.value_view(idx)
	if record.len < 12 {
		return error('internal record too short')
	}
	return int(read_u32_le(record[8..12]))
}

fn (layout NodeLayout) choose_child_index_for_key(key []u8) int {
	if layout.item_count <= 0 {
		return 0
	}
	mut idx := 0
	for i in 0 .. layout.item_count {
		child_key := layout.key_view(i)
		if compare_key_bytes(key, child_key) >= 0 {
			idx = i
		} else {
			break
		}
	}
	return idx
}

fn (layout NodeLayout) find_leaf_item(key []u8) !KVPair {
	if layout.kind != .leaf {
		return error('node is not a leaf')
	}
	for idx in 0 .. layout.item_count {
		item_key := layout.key_view(idx)
		cmp := compare_key_bytes(item_key, key)
		if cmp == 0 {
			return KVPair{
				key:   item_key.clone()
				value: layout.value_view(idx).clone()
			}
		}
		if cmp > 0 {
			break
		}
	}
	return error('key not found: ${key.bytestr()}')
}

fn (layout NodeLayout) lower_bound_leaf_item(key []u8) !KVPair {
	if layout.kind != .leaf {
		return error('node is not a leaf')
	}
	for idx in 0 .. layout.item_count {
		item_key := layout.key_view(idx)
		if compare_key_bytes(item_key, key) >= 0 {
			return KVPair{
				key:   item_key.clone()
				value: layout.value_view(idx).clone()
			}
		}
	}
	return error('lower bound not found: ${key.bytestr()}')
}

fn (header NodeHeader) key_at(idx int) []u8 {
	start := int(header.key_offsets[idx])
	end := if idx + 1 < header.key_offsets.len {
		int(header.key_offsets[idx + 1])
	} else {
		int(header.val_offsets[0])
	}
	return header.raw[start..end].clone()
}

fn (header NodeHeader) value_at(idx int) []u8 {
	start := int(header.val_offsets[idx])
	end := if idx + 1 < header.val_offsets.len {
		int(header.val_offsets[idx + 1])
	} else {
		header.raw.len
	}
	return header.raw[start..end].clone()
}

pub fn (child NodeRef) record_bytes() []u8 {
	cid := child.cid.bytes()
	mut out := ByteWriter{}
	out.write_u32(u32(child.key.len))
	out.write_u32(u32(cid.len))
	out.write_u32(u32(child.item_count))
	out.write_bytes(child.key)
	out.write_bytes(cid)
	return out.owned_bytes()
}

pub fn NodeRef.from_record(data []u8) !NodeRef {
	if data.len < 12 {
		return error('internal record too short')
	}
	key_len := int(read_u32_le(data[..4]))
	cid_len := int(read_u32_le(data[4..8]))
	item_count := int(read_u32_le(data[8..12]))
	if data.len != 12 + key_len + cid_len {
		return error('internal record length mismatch')
	}
	return NodeRef{
		key:        data[12..12 + key_len].clone()
		cid:        data[12 + key_len..].bytestr()
		item_count: item_count
	}
}

fn (cfg ChunkConfig) chunk_record_stream(records [][]u8) ![]ChunkGroup {
	cfg.validate()!
	if records.len == 0 {
		return []ChunkGroup{}
	}

	mut groups := []ChunkGroup{}
	mut hash := u64(0)
	mut bytes_since_cut := 0
	mut group_start := 0

	for record_idx, record in records {
		mut should_split := false
		for b in record {
			hash = rolling_hash(hash, b)
			bytes_since_cut++
			if bytes_since_cut < cfg.min_size {
				continue
			}
			if bytes_since_cut >= cfg.max_size || (hash & cfg.mask) == 0 {
				should_split = true
			}
		}
		if should_split {
			groups << ChunkGroup{
				start: group_start
				end:   record_idx + 1
			}
			group_start = record_idx + 1
			hash = 0
			bytes_since_cut = 0
		}
	}

	if group_start < records.len {
		groups << ChunkGroup{
			start: group_start
			end:   records.len
		}
	}

	return groups
}

fn (cfg ChunkConfig) chunk_kvpair_stream(items []KVPair) ![]ChunkGroup {
	cfg.validate()!
	if items.len == 0 {
		return []ChunkGroup{}
	}
	mut groups := []ChunkGroup{}
	mut hash := u64(0)
	mut bytes_since_cut := 0
	mut group_start := 0
	for item_idx, item in items {
		mut should_split := false
		hash = rolling_hash_u32(hash, u32(item.key.len))
		bytes_since_cut += 4
		if bytes_since_cut >= cfg.min_size
			&& (bytes_since_cut >= cfg.max_size || (hash & cfg.mask) == 0) {
			should_split = true
		}
		hash = rolling_hash_u32(hash, u32(item.value.len))
		bytes_since_cut += 4
		if bytes_since_cut >= cfg.min_size
			&& (bytes_since_cut >= cfg.max_size || (hash & cfg.mask) == 0) {
			should_split = true
		}
		if !should_split {
			for b in item.key {
				hash = rolling_hash(hash, b)
				bytes_since_cut++
				if bytes_since_cut < cfg.min_size {
					continue
				}
				if bytes_since_cut >= cfg.max_size || (hash & cfg.mask) == 0 {
					should_split = true
				}
			}
		}
		if !should_split {
			for b in item.value {
				hash = rolling_hash(hash, b)
				bytes_since_cut++
				if bytes_since_cut < cfg.min_size {
					continue
				}
				if bytes_since_cut >= cfg.max_size || (hash & cfg.mask) == 0 {
					should_split = true
				}
			}
		}
		if should_split {
			groups << ChunkGroup{
				start: group_start
				end:   item_idx + 1
			}
			group_start = item_idx + 1
			hash = 0
			bytes_since_cut = 0
		}
	}
	if group_start < items.len {
		groups << ChunkGroup{
			start: group_start
			end:   items.len
		}
	}
	return groups
}

fn (cfg ChunkConfig) chunk_kvpair_stream_bulk(items []KVPair) ![]ChunkGroup {
	cfg.validate()!
	if items.len == 0 {
		return []ChunkGroup{}
	}
	target_size := if cfg.max_size > cfg.min_size {
		(cfg.min_size + cfg.max_size) / 2
	} else {
		cfg.max_size
	}
	mut groups := []ChunkGroup{}
	mut group_start := 0
	mut bytes_since_cut := 0
	for item_idx, item in items {
		bytes_since_cut += 8 + item.key.len + item.value.len
		if bytes_since_cut < target_size && item_idx + 1 < items.len {
			continue
		}
		groups << ChunkGroup{
			start: group_start
			end:   item_idx + 1
		}
		group_start = item_idx + 1
		bytes_since_cut = 0
	}
	if group_start < items.len {
		groups << ChunkGroup{
			start: group_start
			end:   items.len
		}
	}
	return groups
}

fn pairwise_groups(count int) []ChunkGroup {
	mut groups := []ChunkGroup{}
	mut start := 0
	for start < count {
		end := if start + 2 < count { start + 2 } else { count }
		groups << ChunkGroup{
			start: start
			end:   end
		}
		start = end
	}
	return groups
}

fn cid_for_bytes(data []u8) string {
	return chunk_cid_hex(data)
}

pub fn Node.from_data(data []u8) !Node {
	cid := cid_for_bytes(data)
	return Node.from_data_with_cid(data, cid)
}

pub fn Node.from_data_with_cid(data []u8, cid string) !Node {
	header := NodeHeader.from_bytes(data)!
	if header.item_count <= 0 {
		return error('node requires at least one item')
	}
	min_key := header.key_at(0)
	max_key := header.key_at(header.item_count - 1)
	return Node{
		kind:       header.kind
		level:      header.level
		item_count: header.item_count
		cid:        cid
		data:       data
		min_key:    min_key
		max_key:    max_key
	}
}

pub fn (node Node) leaf_items() ![]KVPair {
	header := NodeHeader.from_bytes(node.data)!
	if header.kind != .leaf {
		return error('node is not a leaf')
	}
	mut items := []KVPair{cap: header.item_count}
	for idx in 0 .. header.item_count {
		items << KVPair{
			key:   header.key_at(idx)
			value: header.value_at(idx)
		}
	}
	return items
}

pub fn (node Node) child_refs() ![]NodeRef {
	header := NodeHeader.from_bytes(node.data)!
	if header.kind != .internal {
		return error('node is not internal')
	}
	mut children := []NodeRef{cap: header.item_count}
	for idx in 0 .. header.item_count {
		children << NodeRef.from_record(header.value_at(idx))!
	}
	return children
}

pub fn serialize_leaf_node(items []KVPair) ![]u8 {
	if items.len == 0 {
		return error('leaf node requires at least one item')
	}
	sorted := sorted_pairs(items)!
	return serialize_leaf_node_sorted(sorted)
}

fn serialize_leaf_node_sorted(sorted []KVPair) ![]u8 {
	if sorted.len == 0 {
		return error('leaf node requires at least one item')
	}
	mut total_key_len := 0
	mut raw_len := 0
	for item in sorted {
		total_key_len += item.key.len
		raw_len += item.key.len + item.value.len
	}
	header_len := node_header_base_len + (sorted.len * 8)
	mut out := ByteWriter{
		buf: []u8{cap: header_len + raw_len}
	}
	out.write_bytes(node_magic)
	out.write_u8(node_version)
	out.write_u8(u8(NodeKind.leaf))
	out.write_u16(0)
	out.write_u32(u32(sorted.len))
	mut raw_offset := 0
	for item in sorted {
		out.write_u32(u32(raw_offset))
		raw_offset += item.key.len
	}
	raw_offset = total_key_len
	for item in sorted {
		out.write_u32(u32(raw_offset))
		raw_offset += item.value.len
	}
	for item in sorted {
		out.write_bytes(item.key)
	}
	for item in sorted {
		out.write_bytes(item.value)
	}
	return out.owned_bytes()
}

pub fn serialize_internal_node(level int, children []NodeRef) ![]u8 {
	if children.len == 0 {
		return error('internal node requires at least one child')
	}
	mut keys := [][]u8{cap: children.len}
	mut values := [][]u8{cap: children.len}
	for child in children {
		keys << child.key.clone()
		values << child.record_bytes()
	}
	return serialize_records(.internal, level, keys, values)
}

fn (mut builder TreeBuilder) add_node(node Node) NodeRef {
	builder.nodes[node.cid] = node
	return node.to_ref()
}

fn (mut builder TreeBuilder) build_leaf_level(items []KVPair) ![]NodeRef {
	result := builder.build_leaf_level_with_timings(items)!
	return result.refs
}

fn (mut builder TreeBuilder) build_leaf_level_with_timings(items []KVPair) !TreeLeafBuildResult {
	return builder.build_leaf_level_with_chunker(items, false)
}

fn (mut builder TreeBuilder) build_leaf_level_bulk_with_timings(items []KVPair) !TreeLeafBuildResult {
	return builder.build_leaf_level_with_chunker(items, true)
}

fn (mut builder TreeBuilder) build_leaf_level_with_chunker(items []KVPair, bulk bool) !TreeLeafBuildResult {
	detailed := builder.cfg.detailed_timings
	mut groups := if bulk {
		builder.cfg.chunk_kvpair_stream_bulk(items)!
	} else {
		builder.cfg.chunk_kvpair_stream(items)!
	}
	mut chunk_ms := i64(0)
	if detailed {
		mut chunk_sw := time.new_stopwatch()
		groups = if bulk {
			builder.cfg.chunk_kvpair_stream_bulk(items)!
		} else {
			builder.cfg.chunk_kvpair_stream(items)!
		}
		chunk_ms = chunk_sw.elapsed().milliseconds()
	}
	mut node_serialize_ms := i64(0)
	mut node_cid_ms := i64(0)
	mut node_add_ms := i64(0)
	mut refs := []NodeRef{cap: groups.len}
	for group in groups {
		chunk_items := items[group.start..group.end]
		mut data := []u8{}
		if detailed {
			mut serialize_sw := time.new_stopwatch()
			data = serialize_leaf_node_sorted(chunk_items)!
			node_serialize_ms += serialize_sw.elapsed().milliseconds()
		} else {
			data = serialize_leaf_node_sorted(chunk_items)!
		}
		mut cid := ''
		if detailed {
			mut cid_sw := time.new_stopwatch()
			cid = cid_for_bytes(data)
			node_cid_ms += cid_sw.elapsed().milliseconds()
		} else {
			cid = cid_for_bytes(data)
		}
		node := Node{
			kind:       .leaf
			level:      0
			item_count: chunk_items.len
			cid:        cid
			data:       data
			min_key:    chunk_items[0].key.clone()
			max_key:    chunk_items[chunk_items.len - 1].key.clone()
		}
		if detailed {
			mut add_sw := time.new_stopwatch()
			refs << builder.add_node(node)
			node_add_ms += add_sw.elapsed().milliseconds()
		} else {
			refs << builder.add_node(node)
		}
	}
	return TreeLeafBuildResult{
		refs:    refs
		timings: TreeLeafBuildTimings{
			chunk_ms:          chunk_ms
			node_ms:           node_serialize_ms + node_cid_ms + node_add_ms
			node_serialize_ms: node_serialize_ms
			node_cid_ms:       node_cid_ms
			node_add_ms:       node_add_ms
		}
	}
}

fn (mut builder TreeBuilder) build_internal_level(level int, children []NodeRef) ![]NodeRef {
	mut records := [][]u8{cap: children.len}
	for child in children {
		records << child.record_bytes()
	}
	mut groups := builder.cfg.chunk_record_stream(records)!
	if groups.len == children.len && children.len > 1 {
		groups = pairwise_groups(children.len)
	}
	mut refs := []NodeRef{cap: groups.len}
	for group in groups {
		chunk_children := children[group.start..group.end]
		data := serialize_internal_node(level, chunk_children)!
		mut total_items := 0
		for child in chunk_children {
			total_items += child.item_count
		}
		node := Node.new_internal(level, data, total_items, chunk_children[0].key,
			chunk_children[chunk_children.len - 1].key)
		refs << builder.add_node(node)
	}
	return refs
}

pub fn (mut builder TreeBuilder) build(items []KVPair) !Tree {
	if items.len == 0 {
		return error('tree requires at least one item')
	}
	sorted := sorted_pairs(items)!
	return builder.build_sorted(sorted)
}

fn (mut builder TreeBuilder) build_sorted(sorted []KVPair) !Tree {
	result := builder.build_sorted_with_timings(sorted)!
	return result.tree
}

fn (mut builder TreeBuilder) build_sorted_bulk(sorted []KVPair) !Tree {
	result := builder.build_sorted_bulk_with_timings(sorted)!
	return result.tree
}

fn (mut builder TreeBuilder) build_sorted_with_timings(sorted []KVPair) !TreeBuildResult {
	return builder.build_sorted_with_timings_mode(sorted, false)
}

fn (mut builder TreeBuilder) build_sorted_bulk_with_timings(sorted []KVPair) !TreeBuildResult {
	return builder.build_sorted_with_timings_mode(sorted, true)
}

fn (mut builder TreeBuilder) build_sorted_with_timings_mode(sorted []KVPair, bulk bool) !TreeBuildResult {
	if sorted.len == 0 {
		return error('tree requires at least one item')
	}
	leaf_result := if bulk {
		builder.build_leaf_level_bulk_with_timings(sorted)!
	} else {
		builder.build_leaf_level_with_timings(sorted)!
	}
	mut refs := leaf_result.refs.clone()
	leaf_ms := leaf_result.timings.chunk_ms + leaf_result.timings.node_ms
	mut level := 1
	mut internal_ms := i64(0)
	for refs.len > 1 {
		if builder.cfg.detailed_timings {
			mut internal_sw := time.new_stopwatch()
			refs = builder.build_internal_level(level, refs)!
			internal_ms += internal_sw.elapsed().milliseconds()
		} else {
			refs = builder.build_internal_level(level, refs)!
		}
		level++
	}
	return TreeBuildResult{
		tree:    Tree{
			root:  refs[0]
			nodes: builder.nodes
		}
		timings: TreeBuildStageTimings{
			leaf_ms:                leaf_ms
			leaf_chunk_ms:          leaf_result.timings.chunk_ms
			leaf_node_ms:           leaf_result.timings.node_ms
			leaf_node_serialize_ms: leaf_result.timings.node_serialize_ms
			leaf_node_cid_ms:       leaf_result.timings.node_cid_ms
			leaf_node_add_ms:       leaf_result.timings.node_add_ms
			internal_ms:            internal_ms
		}
	}
}

pub fn Tree.build_sorted(items []KVPair, cfg ChunkConfig) !Tree {
	mut builder := TreeBuilder.new(cfg)
	return builder.build_sorted(items)
}

pub fn Tree.build_sorted_bulk(items []KVPair, cfg ChunkConfig) !Tree {
	mut builder := TreeBuilder.new(cfg)
	return builder.build_sorted_bulk(items)
}

pub fn Tree.build_sorted_with_timings(items []KVPair, cfg ChunkConfig) !TreeBuildResult {
	mut builder := TreeBuilder.new(cfg)
	return builder.build_sorted_with_timings(items)
}

pub fn Tree.build_sorted_bulk_with_timings(items []KVPair, cfg ChunkConfig) !TreeBuildResult {
	mut builder := TreeBuilder.new(cfg)
	return builder.build_sorted_bulk_with_timings(items)
}

pub fn (tree Tree) append_sorted_bulk_with_timings(items []KVPair, cfg ChunkConfig) !TreeBuildResult {
	if items.len == 0 {
		return TreeBuildResult{
			tree:    tree
			timings: TreeBuildStageTimings{}
		}
	}
	if tree.root.cid.len == 0 {
		return Tree.build_sorted_bulk_with_timings(items, cfg)
	}
	root_node := tree.root_node()!
	if compare_key_bytes(root_node.max_key, items[0].key) >= 0 {
		return error('append items must be greater than the current tree max key')
	}
	mut builder := TreeBuilder{
		cfg:   cfg
		nodes: tree.nodes.clone()
	}
	leaf_result := builder.build_leaf_level_bulk_with_timings(items)!
	mut refs := tree.leaf_refs()!
	refs << leaf_result.refs
	leaf_ms := leaf_result.timings.chunk_ms + leaf_result.timings.node_ms
	mut level := 1
	mut internal_ms := i64(0)
	for refs.len > 1 {
		if builder.cfg.detailed_timings {
			mut internal_sw := time.new_stopwatch()
			refs = builder.build_internal_level(level, refs)!
			internal_ms += internal_sw.elapsed().milliseconds()
		} else {
			refs = builder.build_internal_level(level, refs)!
		}
		level++
	}
	return TreeBuildResult{
		tree:    Tree{
			root:  refs[0]
			nodes: builder.nodes
		}
		timings: TreeBuildStageTimings{
			leaf_ms:                leaf_ms
			leaf_chunk_ms:          leaf_result.timings.chunk_ms
			leaf_node_ms:           leaf_result.timings.node_ms
			leaf_node_serialize_ms: leaf_result.timings.node_serialize_ms
			leaf_node_cid_ms:       leaf_result.timings.node_cid_ms
			leaf_node_add_ms:       leaf_result.timings.node_add_ms
			internal_ms:            internal_ms
		}
	}
}

pub fn build_tree(items []KVPair, cfg ChunkConfig) !Tree {
	return Tree.build(items, cfg)
}

pub fn Tree.load(root_cid string, mut node_store NodeStore) !Tree {
	mut nodes := map[string]Node{}
	root := node_store.get(root_cid)!
	Tree.load_reachable(root, mut node_store, mut nodes)!
	return Tree{
		root:  root.to_ref()
		nodes: nodes
	}
}

fn Tree.load_reachable(node Node, mut node_store NodeStore, mut nodes map[string]Node) ! {
	if node.cid in nodes {
		return
	}
	nodes[node.cid] = node
	if node.kind == .leaf {
		return
	}
	for child in node.child_refs()! {
		child_node := node_store.get(child.cid)!
		Tree.load_reachable(child_node, mut node_store, mut nodes)!
	}
}

pub fn (tree Tree) root_node() !Node {
	node := tree.nodes[tree.root.cid] or { return error('root node not found: ${tree.root.cid}') }
	return node
}

pub fn Mutation.put(key []u8, value []u8) Mutation {
	return Mutation{
		op:    .put
		key:   key.clone()
		value: value.clone()
	}
}

pub fn Mutation.delete(key []u8) Mutation {
	return Mutation{
		op:    .delete
		key:   key.clone()
		value: []u8{}
	}
}

pub fn (tree Tree) leaf_refs() ![]NodeRef {
	root := tree.root_node()!
	return tree.collect_leaf_refs(root)
}

pub fn (tree Tree) items() ![]KVPair {
	if tree.root.cid.len == 0 {
		return []KVPair{}
	}
	mut cursor := tree.raw_cursor([]u8{}, []u8{}, 0)!
	mut items := []KVPair{cap: tree.root.item_count}
	for {
		item := cursor.next() or {
			if err.msg().contains('iterator exhausted') {
				break
			}
			return err
		}
		items << item
	}
	return items
}

pub fn (tree Tree) get(key []u8) !KVPair {
	path := tree.path_to_leaf(key)!
	bound := tree.bound_match(path, key, true)!
	if compare_key_bytes(bound.item.key, key) != 0 {
		return error('key not found: ${key.bytestr()}')
	}
	return bound.item
}

pub fn Tree.lookup_in_store(root_cid string, key []u8, mut node_store NodeStore) !KVPair {
	return Tree.lookup_in_store_with_stats(root_cid, key, mut node_store)!.item
}

pub fn Tree.lookup_in_store_with_stats(root_cid string, key []u8, mut node_store NodeStore) !StoreLookupResult {
	mut current := node_store.get(root_cid)!
	mut path_depth := 1
	mut nodes_read := 1
	for current.kind == .internal {
		children := current.child_refs()!
		if children.len == 0 {
			return error('internal node has no children: ${current.cid}')
		}
		idx := choose_child_index(key, children)
		current = node_store.get(children[idx].cid)!
		nodes_read++
		path_depth++
	}
	items := current.leaf_items()!
	for item in items {
		if compare_key_bytes(item.key, key) == 0 {
			return StoreLookupResult{
				item:  item
				stats: StoreLookupStats{
					path_depth:      path_depth
					nodes_read:      nodes_read
					leaf_item_count: items.len
				}
			}
		}
	}
	return error('key not found: ${key.bytestr()}')
}

pub fn Tree.lookup_in_byte_store(root_cid string, key []u8, mut node_store NodeByteStore) !KVPair {
	return Tree.lookup_in_byte_store_with_stats(root_cid, key, mut node_store)!.item
}

pub fn Tree.total_count_in_byte_store(root_cid string, mut node_store NodeByteStore) !int {
	node_data := node_store.get_bytes(root_cid.bytes())!
	layout := NodeLayout.from_bytes(node_data)!
	return layout.item_count
}

pub fn Tree.lookup_in_byte_store_with_stats(root_cid string, key []u8, mut node_store NodeByteStore) !StoreLookupResult {
	mut current_cid := root_cid.bytes()
	mut path_depth := 0
	mut nodes_read := 0
	for {
		node_data := node_store.get_bytes(current_cid)!
		layout := NodeLayout.from_bytes(node_data)!
		nodes_read++
		path_depth++
		if layout.kind == .leaf {
			item := layout.find_leaf_item(key)!
			return StoreLookupResult{
				item:  item
				stats: StoreLookupStats{
					path_depth:      path_depth
					nodes_read:      nodes_read
					leaf_item_count: layout.item_count
				}
			}
		}
		if layout.item_count == 0 {
			return error('internal node has no children: ${current_cid.bytestr()}')
		}
		idx := layout.choose_child_index_for_key(key)
		current_cid = layout.child_cid_view(idx)!.clone()
	}
	return error('unreachable persistent store lookup state')
}

fn Tree.byte_store_path_to_leaf(root_cid []u8, key []u8, mut node_store NodeByteStore) !([]ByteStorePathStep, int) {
	mut current_cid := root_cid.clone()
	mut path := []ByteStorePathStep{}
	mut nodes_read := 0
	for {
		node_data := node_store.get_bytes(current_cid)!
		layout := NodeLayout.from_bytes(node_data)!
		nodes_read++
		if layout.kind == .leaf {
			path << ByteStorePathStep{
				layout:       layout
				child_cids:   [][]u8{}
				selected_idx: -1
			}
			return path, nodes_read
		}
		mut child_cids := [][]u8{cap: layout.item_count}
		for idx in 0 .. layout.item_count {
			child_cids << layout.child_cid_view(idx)!.clone()
		}
		selected_idx := layout.choose_child_index_for_key(key)
		path << ByteStorePathStep{
			layout:       layout
			child_cids:   child_cids
			selected_idx: selected_idx
		}
		current_cid = child_cids[selected_idx].clone()
	}
	return error('unreachable byte store path state')
}

fn Tree.byte_store_descend_leftmost(root_cid []u8, prefix []ByteStorePathStep, mut node_store NodeByteStore) !([]ByteStorePathStep, int) {
	mut current_cid := root_cid.clone()
	mut path := prefix.clone()
	mut nodes_read := 0
	for {
		node_data := node_store.get_bytes(current_cid)!
		layout := NodeLayout.from_bytes(node_data)!
		nodes_read++
		if layout.kind == .leaf {
			path << ByteStorePathStep{
				layout:       layout
				child_cids:   [][]u8{}
				selected_idx: -1
			}
			return path, nodes_read
		}
		mut child_cids := [][]u8{cap: layout.item_count}
		for idx in 0 .. layout.item_count {
			child_cids << layout.child_cid_view(idx)!.clone()
		}
		path << ByteStorePathStep{
			layout:       layout
			child_cids:   child_cids
			selected_idx: 0
		}
		current_cid = child_cids[0].clone()
	}
	return error('unreachable byte store descend state')
}

fn Tree.byte_store_descend_leftmost_append(root_cid []u8, mut path []ByteStorePathStep, mut node_store NodeByteStore) !int {
	mut current_cid := root_cid.clone()
	mut nodes_read := 0
	for {
		node_data := node_store.get_bytes(current_cid)!
		layout := NodeLayout.from_bytes(node_data)!
		nodes_read++
		if layout.kind == .leaf {
			path << ByteStorePathStep{
				layout:       layout
				child_cids:   [][]u8{}
				selected_idx: -1
			}
			return nodes_read
		}
		mut child_cids := [][]u8{cap: layout.item_count}
		for idx in 0 .. layout.item_count {
			child_cids << layout.child_cid_view(idx)!.clone()
		}
		path << ByteStorePathStep{
			layout:       layout
			child_cids:   child_cids
			selected_idx: 0
		}
		current_cid = child_cids[0].clone()
	}
	return error('unreachable byte store descend state')
}

fn Tree.byte_store_descend_rightmost(root_cid []u8, prefix []ByteStorePathStep, mut node_store NodeByteStore) !([]ByteStorePathStep, int) {
	mut current_cid := root_cid.clone()
	mut path := prefix.clone()
	mut nodes_read := 0
	for {
		node_data := node_store.get_bytes(current_cid)!
		layout := NodeLayout.from_bytes(node_data)!
		nodes_read++
		if layout.kind == .leaf {
			path << ByteStorePathStep{
				layout:       layout
				child_cids:   [][]u8{}
				selected_idx: -1
			}
			return path, nodes_read
		}
		mut child_cids := [][]u8{cap: layout.item_count}
		for idx in 0 .. layout.item_count {
			child_cids << layout.child_cid_view(idx)!.clone()
		}
		last_idx := child_cids.len - 1
		path << ByteStorePathStep{
			layout:       layout
			child_cids:   child_cids
			selected_idx: last_idx
		}
		current_cid = child_cids[last_idx].clone()
	}
	return error('unreachable byte store descend state')
}

fn Tree.byte_store_descend_rightmost_append(root_cid []u8, mut path []ByteStorePathStep, mut node_store NodeByteStore) !int {
	mut current_cid := root_cid.clone()
	mut nodes_read := 0
	for {
		node_data := node_store.get_bytes(current_cid)!
		layout := NodeLayout.from_bytes(node_data)!
		nodes_read++
		if layout.kind == .leaf {
			path << ByteStorePathStep{
				layout:       layout
				child_cids:   [][]u8{}
				selected_idx: -1
			}
			return nodes_read
		}
		mut child_cids := [][]u8{cap: layout.item_count}
		for idx in 0 .. layout.item_count {
			child_cids << layout.child_cid_view(idx)!.clone()
		}
		last_idx := child_cids.len - 1
		path << ByteStorePathStep{
			layout:       layout
			child_cids:   child_cids
			selected_idx: last_idx
		}
		current_cid = child_cids[last_idx].clone()
	}
	return error('unreachable byte store descend state')
}

fn Tree.byte_store_next_leaf_path(mut path []ByteStorePathStep, mut node_store NodeByteStore) !int {
	for depth := path.len - 2; depth >= 0; depth-- {
		step := path[depth]
		next_idx := step.selected_idx + 1
		if next_idx >= step.child_cids.len {
			continue
		}
		path[depth] = ByteStorePathStep{
			layout:       step.layout
			child_cids:   step.child_cids
			selected_idx: next_idx
		}
		path = unsafe { path[..depth + 1] }
		return Tree.byte_store_descend_leftmost_append(step.child_cids[next_idx], mut path, mut
			node_store)
	}
	return error('no next leaf')
}

fn Tree.byte_store_prev_leaf_path(mut path []ByteStorePathStep, mut node_store NodeByteStore) !int {
	for depth := path.len - 2; depth >= 0; depth-- {
		step := path[depth]
		prev_idx := step.selected_idx - 1
		if prev_idx < 0 {
			continue
		}
		path[depth] = ByteStorePathStep{
			layout:       step.layout
			child_cids:   step.child_cids
			selected_idx: prev_idx
		}
		path = unsafe { path[..depth + 1] }
		return Tree.byte_store_descend_rightmost_append(step.child_cids[prev_idx], mut path, mut
			node_store)
	}
	return error('no previous leaf')
}

pub fn Tree.lower_bound_in_byte_store_with_stats(root_cid string, key []u8, mut node_store NodeByteStore) !StoreLookupResult {
	mut path, mut nodes_read := Tree.byte_store_path_to_leaf(root_cid.bytes(), key, mut node_store)!
	for {
		leaf := path[path.len - 1].layout
		item := leaf.lower_bound_leaf_item(key) or {
			extra_reads := Tree.byte_store_next_leaf_path(mut path, mut node_store) or {
				return error('lower bound not found: ${key.bytestr()}')
			}
			nodes_read += extra_reads
			continue
		}
		return StoreLookupResult{
			item:  item
			stats: StoreLookupStats{
				path_depth:      path.len
				nodes_read:      nodes_read
				leaf_item_count: leaf.item_count
			}
		}
	}
	return error('unreachable byte store lower bound state')
}

pub fn Tree.ordered_scan_in_byte_store(root_cid string, start_key []u8, end_key []u8, limit int, reverse bool, mut node_store NodeByteStore) ![]KVPair {
	items, _ := Tree.ordered_scan_in_byte_store_with_stats(root_cid, start_key, end_key, limit,
		reverse, mut node_store)!
	return items
}

pub fn Tree.ordered_scan_in_byte_store_with_stats(root_cid string, start_key []u8, end_key []u8, limit int, reverse bool, mut node_store NodeByteStore) !([]KVPair, OrderedScanStats) {
	mut matches := []KVPair{}
	mut stats := OrderedScanStats{}
	if root_cid.len == 0 {
		return matches, stats
	}
	if reverse {
		mut path := []ByteStorePathStep{}
		if end_key.len == 0 {
			path, stats.nodes_read = Tree.byte_store_descend_rightmost(root_cid.bytes(),
				[]ByteStorePathStep{}, mut node_store)!
		} else {
			path, stats.nodes_read = Tree.byte_store_path_to_leaf(root_cid.bytes(), end_key, mut
				node_store)!
		}
		mut seek_key := end_key.clone()
		mut started := end_key.len == 0
		for {
			leaf := path[path.len - 1].layout
			stats.leaves_visited++
			for idx := leaf.item_count - 1; idx >= 0; idx-- {
				stats.items_examined++
				item_key := leaf.key_view(idx)
				if !started {
					if compare_key_bytes(item_key, seek_key) >= 0 {
						continue
					}
					started = true
				}
				if start_key.len > 0 && compare_key_bytes(item_key, start_key) < 0 {
					return matches, stats
				}
				matches << KVPair{
					key:   item_key.clone()
					value: leaf.value_view(idx).clone()
				}
				if limit > 0 && matches.len >= limit {
					return matches, stats
				}
			}
			stats.nodes_read += Tree.byte_store_prev_leaf_path(mut path, mut node_store) or {
				return matches, stats
			}
			started = true
		}
	}
	mut path := []ByteStorePathStep{}
	if start_key.len == 0 {
		path, stats.nodes_read = Tree.byte_store_descend_leftmost(root_cid.bytes(),
			[]ByteStorePathStep{}, mut node_store)!
	} else {
		path, stats.nodes_read = Tree.byte_store_path_to_leaf(root_cid.bytes(), start_key, mut
			node_store)!
	}
	mut seek_key := start_key.clone()
	mut started := start_key.len == 0
	for {
		leaf := path[path.len - 1].layout
		stats.leaves_visited++
		for idx in 0 .. leaf.item_count {
			stats.items_examined++
			item_key := leaf.key_view(idx)
			if !started {
				if compare_key_bytes(item_key, seek_key) < 0 {
					continue
				}
				started = true
			}
			if end_key.len > 0 && compare_key_bytes(item_key, end_key) >= 0 {
				return matches, stats
			}
			matches << KVPair{
				key:   item_key.clone()
				value: leaf.value_view(idx).clone()
			}
			if limit > 0 && matches.len >= limit {
				return matches, stats
			}
		}
		stats.nodes_read += Tree.byte_store_next_leaf_path(mut path, mut node_store) or {
			return matches, stats
		}
		started = true
	}
	return matches, stats
}

pub fn Tree.prefix_scan_in_byte_store(root_cid string, start_key []u8, prefix []u8, limit int, mut node_store NodeByteStore) ![]KVPair {
	mut matches := []KVPair{}
	mut path, _ := Tree.byte_store_path_to_leaf(root_cid.bytes(), start_key, mut node_store)!
	mut seek_key := start_key.clone()
	for {
		leaf := path[path.len - 1].layout
		mut started := false
		for idx in 0 .. leaf.item_count {
			item_key := leaf.key_view(idx)
			if !started {
				if compare_key_bytes(item_key, seek_key) < 0 {
					continue
				}
				started = true
			}
			if !has_prefix_bytes(item_key, prefix) {
				return matches
			}
			matches << KVPair{
				key:   item_key.clone()
				value: leaf.value_view(idx).clone()
			}
			if limit > 0 && matches.len >= limit {
				return matches
			}
		}
		_ = Tree.byte_store_next_leaf_path(mut path, mut node_store) or { return matches }
		seek_key = prefix.clone()
	}
	return matches
}

pub fn Tree.suffix_scan_in_byte_store(root_cid string, start_key []u8, prefix []u8, limit int, mut node_store NodeByteStore) ![][]u8 {
	mut matches := [][]u8{}
	mut path, _ := Tree.byte_store_path_to_leaf(root_cid.bytes(), start_key, mut node_store)!
	mut seek_key := start_key.clone()
	for {
		leaf := path[path.len - 1].layout
		mut started := false
		for idx in 0 .. leaf.item_count {
			item_key := leaf.key_view(idx)
			if !started {
				if compare_key_bytes(item_key, seek_key) < 0 {
					continue
				}
				started = true
			}
			if !has_prefix_bytes(item_key, prefix) {
				return matches
			}
			matches << item_key[prefix.len..].clone()
			if limit > 0 && matches.len >= limit {
				return matches
			}
		}
		_ = Tree.byte_store_next_leaf_path(mut path, mut node_store) or { return matches }
		seek_key = prefix.clone()
	}
	return matches
}

pub fn Tree.count_range_in_byte_store(root_cid string, start_key []u8, end_key []u8, mut node_store NodeByteStore) !int {
	return Tree.count_range_node_in_byte_store(root_cid.bytes(), start_key, end_key, []u8{}, mut
		node_store)
}

pub fn Tree.sum_i64_column_range_in_byte_store(root_cid string, start_key []u8, end_key []u8, codec TypedRowCodec, column_name string, mut node_store NodeByteStore) !i64 {
	mut path := []ByteStorePathStep{}
	if start_key.len == 0 {
		path, _ = Tree.byte_store_descend_leftmost(root_cid.bytes(), []ByteStorePathStep{}, mut
			node_store)!
	} else {
		path, _ = Tree.byte_store_path_to_leaf(root_cid.bytes(), start_key, mut node_store)!
	}
	mut seek_key := start_key.clone()
	mut total := i64(0)
	for {
		leaf := path[path.len - 1].layout
		mut started := start_key.len == 0
		for idx in 0 .. leaf.item_count {
			item_key := leaf.key_view(idx)
			if !started {
				if compare_key_bytes(item_key, seek_key) < 0 {
					continue
				}
				started = true
			}
			if end_key.len > 0 && compare_key_bytes(item_key, end_key) >= 0 {
				return total
			}
			total += codec.decode_i64_column(leaf.value_view(idx), column_name)!
		}
		_ = Tree.byte_store_next_leaf_path(mut path, mut node_store) or { return total }
		seek_key = []u8{}
	}
	return total
}

fn Tree.count_range_node_in_byte_store(current_cid []u8, start_key []u8, end_key []u8, subtree_upper []u8, mut node_store NodeByteStore) !int {
	node_data := node_store.get_bytes(current_cid)!
	layout := NodeLayout.from_bytes(node_data)!
	if layout.kind == .leaf {
		mut started := start_key.len == 0
		mut start_idx := 0
		if !started {
			for start_idx < layout.item_count
				&& compare_key_bytes(layout.key_view(start_idx), start_key) < 0 {
				start_idx++
			}
		}
		if start_idx >= layout.item_count {
			return 0
		}
		if end_key.len == 0 {
			return layout.item_count - start_idx
		}
		last_key := layout.key_view(layout.item_count - 1)
		if compare_key_bytes(last_key, end_key) < 0 {
			return layout.item_count - start_idx
		}
		mut count := 0
		for idx in start_idx .. layout.item_count {
			if compare_key_bytes(layout.key_view(idx), end_key) >= 0 {
				break
			}
			count++
		}
		return count
	}
	mut total := 0
	for idx in 0 .. layout.item_count {
		child_lower := layout.key_view(idx)
		child_upper := if idx + 1 < layout.item_count {
			layout.key_view(idx + 1)
		} else {
			subtree_upper
		}
		if end_key.len > 0 && compare_key_bytes(child_lower, end_key) >= 0 {
			break
		}
		if child_upper.len > 0 && compare_key_bytes(child_upper, start_key) <= 0 {
			continue
		}
		if compare_key_bytes(child_lower, start_key) >= 0 && (end_key.len == 0
			|| (child_upper.len > 0 && compare_key_bytes(child_upper, end_key) <= 0)) {
			total += layout.child_item_count(idx)!
			continue
		}
		total += Tree.count_range_node_in_byte_store(layout.child_cid_view(idx)!, start_key,
			end_key, child_upper.clone(), mut node_store)!
	}
	return total
}

pub fn Tree.next_leaf_start_keys_in_byte_store(root_cid string, start_key []u8, end_key []u8, mut node_store NodeByteStore) ![][]u8 {
	if end_key.len > 0 && compare_key_bytes(start_key, end_key) >= 0 {
		return [][]u8{}
	}
	mut path := []ByteStorePathStep{}
	if start_key.len == 0 {
		path, _ = Tree.byte_store_descend_leftmost(root_cid.bytes(), []ByteStorePathStep{}, mut
			node_store)!
	} else {
		path, _ = Tree.byte_store_path_to_leaf(root_cid.bytes(), start_key, mut node_store)!
	}
	mut starts := [][]u8{}
	for {
		_ = Tree.byte_store_next_leaf_path(mut path, mut node_store) or { return starts }
		leaf := path[path.len - 1].layout
		if leaf.item_count == 0 {
			continue
		}
		first_key := leaf.key_view(0)
		if end_key.len > 0 && compare_key_bytes(first_key, end_key) >= 0 {
			return starts
		}
		starts << first_key.clone()
	}
	return starts
}

pub fn Tree.lookup_in_persistent_store_with_stats(root_cid string, key []u8, mut node_store PersistentNodeStore) !StoreLookupResult {
	return Tree.lookup_in_byte_store_with_stats(root_cid, key, mut node_store)
}

pub fn (tree Tree) has(key []u8) bool {
	_ := tree.get(key) or { return false }
	return true
}

pub fn (tree Tree) lower_bound(key []u8) !KVPair {
	path := tree.path_to_leaf(key)!
	return tree.bound_match(path, key, true)!.item
}

pub fn (tree Tree) upper_bound(key []u8) !KVPair {
	path := tree.path_to_leaf(key)!
	return tree.bound_match(path, key, false)!.item
}

pub fn (tree Tree) key_stats(key []u8) !TreeKeyStats {
	path := tree.path_to_leaf(key)!
	leaf_items := path[path.len - 1].node.leaf_items()!
	return TreeKeyStats{
		path_depth:      path.len
		leaf_item_count: leaf_items.len
	}
}

pub fn TreeIterator.new(tree Tree, start []u8, end []u8, limit int) !TreeIterator {
	mut iter := TreeIterator{
		tree:             tree
		end:              end.clone()
		limit:            limit
		path:             []TreePathStep{}
		leaf_items:       []KVPair{}
		item_idx:         0
		yielded:          0
		started:          false
		current_item:     KVPair{}
		has_current_item: false
	}
	iter.seek(start)!
	return iter
}

pub fn (mut iter TreeIterator) seek(start []u8) ! {
	iter.path = if start.len == 0 {
		iter.tree.leftmost_leaf_path()!
	} else {
		iter.tree.path_to_leaf(start)!
	}
	iter.leaf_items = iter.path[iter.path.len - 1].node.leaf_items()!
	iter.item_idx = 0
	iter.yielded = 0
	iter.started = true
	iter.current_item = KVPair{}
	iter.has_current_item = false
	if start.len > 0 {
		for iter.item_idx < iter.leaf_items.len
			&& compare_key_bytes(iter.leaf_items[iter.item_idx].key, start) < 0 {
			iter.item_idx++
		}
	}
}

pub fn (iter TreeIterator) current() !KVPair {
	if !iter.has_current_item {
		return error('iterator has no current item')
	}
	return iter.current_item
}

pub fn (mut iter TreeIterator) peek() !KVPair {
	if !iter.started {
		iter.seek([]u8{})!
	}
	if iter.limit > 0 && iter.yielded >= iter.limit {
		return error('iterator exhausted')
	}
	mut path := iter.path.clone()
	mut leaf_items := iter.leaf_items.clone()
	mut item_idx := iter.item_idx
	for {
		if item_idx >= leaf_items.len {
			path = iter.tree.next_leaf_path(path) or { return error('iterator exhausted') }
			leaf_items = path[path.len - 1].node.leaf_items()!
			item_idx = 0
			continue
		}
		item := leaf_items[item_idx]
		if iter.end.len > 0 && compare_key_bytes(item.key, iter.end) >= 0 {
			return error('iterator exhausted')
		}
		return item
	}
	return error('iterator exhausted')
}

pub fn (mut iter TreeIterator) next() !KVPair {
	if !iter.started {
		iter.seek([]u8{})!
	}
	if iter.limit > 0 && iter.yielded >= iter.limit {
		return error('iterator exhausted')
	}
	for {
		if iter.item_idx >= iter.leaf_items.len {
			iter.path = iter.tree.next_leaf_path(iter.path) or {
				return error('iterator exhausted')
			}
			iter.leaf_items = iter.path[iter.path.len - 1].node.leaf_items()!
			iter.item_idx = 0
			continue
		}
		item := iter.leaf_items[iter.item_idx]
		if iter.end.len > 0 && compare_key_bytes(item.key, iter.end) >= 0 {
			return error('iterator exhausted')
		}
		iter.item_idx++
		iter.yielded++
		iter.current_item = item
		iter.has_current_item = true
		return item
	}
	return error('iterator exhausted')
}

pub fn (tree Tree) range_scan(start []u8, end []u8, limit int) ![]KVPair {
	mut iter := TreeIterator.new(tree, start, end, limit)!
	mut items := []KVPair{}
	for {
		item := iter.next() or { break }
		items << item
	}
	return items
}

pub fn (tree Tree) cursor(start []u8, end []u8, limit int) !TreeCursor {
	return TreeCursor.forward(tree, start, end, limit)
}

pub fn TreeCursor.forward(tree Tree, start []u8, end []u8, limit int) !TreeCursor {
	return TreeCursor{
		mode:         .forward
		tree:         tree
		limit:        limit
		forward_iter: TreeIterator.new(tree, start, end, limit)!
	}
}

pub fn TreeCursor.reverse(tree Tree, start []u8, end []u8, limit int) !TreeCursor {
	return TreeCursor{
		mode:         .reverse
		tree:         tree
		limit:        limit
		reverse_iter: TreeReverseIterator.new(tree, start, end, limit)!
	}
}

pub fn TreeCursor.prefix(tree Tree, prefix []u8, limit int) !TreeCursor {
	return TreeCursor{
		mode:        .prefix
		tree:        tree
		limit:       limit
		prefix_iter: TreePrefixIterator.new(tree, prefix, limit)!
	}
}

pub fn TreeRawIterator.new(tree Tree, start []u8, end []u8, limit int) !TreeRawIterator {
	mut iter := TreeRawIterator{
		tree:             tree
		end:              end.clone()
		limit:            limit
		path:             []TreePathStep{}
		leaf_layout:      NodeLayout{}
		item_idx:         0
		yielded:          0
		started:          false
		current_item:     KVPair{}
		has_current_item: false
	}
	iter.seek(start)!
	return iter
}

pub fn (mut iter TreeRawIterator) seek(start []u8) ! {
	iter.path = if start.len == 0 {
		iter.tree.leftmost_leaf_path()!
	} else {
		iter.tree.path_to_leaf(start)!
	}
	iter.leaf_layout = NodeLayout.from_bytes(iter.path[iter.path.len - 1].node.data)!
	iter.item_idx = 0
	iter.yielded = 0
	iter.started = true
	iter.current_item = KVPair{}
	iter.has_current_item = false
	if start.len > 0 {
		for iter.item_idx < iter.leaf_layout.item_count
			&& compare_key_bytes(iter.leaf_layout.key_view(iter.item_idx), start) < 0 {
			iter.item_idx++
		}
	}
}

pub fn (iter TreeRawIterator) current() !KVPair {
	if !iter.has_current_item {
		return error('iterator has no current item')
	}
	return iter.current_item
}

pub fn (mut iter TreeRawIterator) next() !KVPair {
	if !iter.started {
		iter.seek([]u8{})!
	}
	if iter.limit > 0 && iter.yielded >= iter.limit {
		return error('iterator exhausted')
	}
	for {
		if iter.item_idx >= iter.leaf_layout.item_count {
			iter.path = iter.tree.next_leaf_path(iter.path) or {
				return error('iterator exhausted')
			}
			iter.leaf_layout = NodeLayout.from_bytes(iter.path[iter.path.len - 1].node.data)!
			iter.item_idx = 0
			continue
		}
		item_key := iter.leaf_layout.key_view(iter.item_idx)
		if iter.end.len > 0 && compare_key_bytes(item_key, iter.end) >= 0 {
			return error('iterator exhausted')
		}
		item := KVPair{
			key:   item_key
			value: iter.leaf_layout.value_view(iter.item_idx)
		}
		iter.item_idx++
		iter.yielded++
		iter.current_item = item
		iter.has_current_item = true
		return item
	}
	return error('iterator exhausted')
}

pub fn (tree Tree) raw_cursor(start []u8, end []u8, limit int) !TreeRawCursor {
	return TreeRawCursor{
		tree:  tree
		end:   end.clone()
		limit: limit
		iter:  TreeRawIterator.new(tree, start, end, limit)!
	}
}

pub fn (mut cursor TreeRawCursor) seek(key []u8) ! {
	cursor.iter.seek(key)!
}

pub fn (cursor TreeRawCursor) current() !KVPair {
	return cursor.iter.current()
}

pub fn (mut cursor TreeRawCursor) next() !KVPair {
	return cursor.iter.next()
}

pub fn (mut cursor TreeRawCursor) skip(count int) !int {
	if count <= 0 {
		return 0
	}
	mut skipped := 0
	for skipped < count {
		_ = cursor.next() or { return skipped }
		skipped++
	}
	return skipped
}

pub fn (mut cursor TreeCursor) seek(key []u8) ! {
	match cursor.mode {
		.forward {
			cursor.forward_iter.seek(key)!
		}
		.reverse {
			cursor.reverse_iter.seek(key)!
		}
		.prefix {
			cursor.prefix_iter.seek(key)!
		}
	}
}

pub fn (cursor TreeCursor) current() !KVPair {
	return match cursor.mode {
		.forward { cursor.forward_iter.current() }
		.reverse { cursor.reverse_iter.current() }
		.prefix { cursor.prefix_iter.current() }
	}
}

pub fn (mut cursor TreeCursor) peek() !KVPair {
	return match cursor.mode {
		.forward { cursor.forward_iter.peek() }
		.reverse { cursor.reverse_iter.peek() }
		.prefix { cursor.prefix_iter.peek() }
	}
}

pub fn (mut cursor TreeCursor) next() !KVPair {
	return match cursor.mode {
		.forward { cursor.forward_iter.next() }
		.reverse { cursor.reverse_iter.next() }
		.prefix { cursor.prefix_iter.next() }
	}
}

pub fn (mut cursor TreeCursor) skip(count int) !int {
	if count <= 0 {
		return 0
	}
	mut skipped := 0
	for skipped < count {
		_ = cursor.next() or { return skipped }
		skipped++
	}
	return skipped
}

pub fn (mut cursor TreeCursor) collect(count int) ![]KVPair {
	mut items := []KVPair{}
	mut remaining := count
	for {
		if count > 0 && remaining <= 0 {
			break
		}
		item := cursor.next() or { break }
		items << item
		if count > 0 {
			remaining--
		}
	}
	return items
}

pub fn (tree Tree) reverse_cursor(start []u8, end []u8, limit int) !TreeCursor {
	return TreeCursor.reverse(tree, start, end, limit)
}

pub fn (tree Tree) prefix_cursor(prefix []u8, limit int) !TreeCursor {
	return TreeCursor.prefix(tree, prefix, limit)
}

pub fn (tree Tree) prefix_scan(prefix []u8, limit int) ![]KVPair {
	mut iter := TreePrefixIterator.new(tree, prefix, limit)!
	mut items := []KVPair{}
	for {
		items << (iter.next() or { break })
	}
	return items
}

pub fn TreePrefixIterator.new(tree Tree, prefix []u8, limit int) !TreePrefixIterator {
	return TreePrefixIterator{
		tree:             tree
		prefix:           prefix.clone()
		limit:            limit
		iter:             TreeIterator.new(tree, prefix, []u8{}, limit)!
		current_item:     KVPair{}
		has_current_item: false
	}
}

pub fn (mut iter TreePrefixIterator) seek(prefix []u8) ! {
	iter.prefix = prefix.clone()
	iter.iter = TreeIterator.new(iter.tree, prefix, []u8{}, iter.limit)!
	iter.current_item = KVPair{}
	iter.has_current_item = false
}

pub fn (iter TreePrefixIterator) current() !KVPair {
	if !iter.has_current_item {
		return error('iterator has no current item')
	}
	return iter.current_item
}

pub fn (mut iter TreePrefixIterator) peek() !KVPair {
	item := iter.iter.peek()!
	if !has_prefix_bytes(item.key, iter.prefix) {
		return error('iterator exhausted')
	}
	return item
}

pub fn (mut iter TreePrefixIterator) next() !KVPair {
	item := iter.peek()!
	_ = iter.iter.next()!
	iter.current_item = item
	iter.has_current_item = true
	return item
}

pub fn TreeReverseIterator.new(tree Tree, start []u8, end []u8, limit int) !TreeReverseIterator {
	mut iter := TreeReverseIterator{
		tree:             tree
		start:            start.clone()
		limit:            limit
		path:             []TreePathStep{}
		leaf_items:       []KVPair{}
		item_idx:         -1
		yielded:          0
		started:          false
		current_item:     KVPair{}
		has_current_item: false
	}
	iter.seek(end)!
	return iter
}

pub fn (mut iter TreeReverseIterator) seek(end []u8) ! {
	iter.path = if end.len == 0 {
		iter.tree.rightmost_leaf_path()!
	} else {
		iter.tree.path_to_leaf(end)!
	}
	iter.leaf_items = iter.path[iter.path.len - 1].node.leaf_items()!
	iter.item_idx = iter.leaf_items.len - 1
	iter.yielded = 0
	iter.started = true
	iter.current_item = KVPair{}
	iter.has_current_item = false
	if end.len > 0 {
		for iter.item_idx >= 0 && compare_key_bytes(iter.leaf_items[iter.item_idx].key, end) >= 0 {
			iter.item_idx--
		}
	}
}

pub fn (iter TreeReverseIterator) current() !KVPair {
	if !iter.has_current_item {
		return error('iterator has no current item')
	}
	return iter.current_item
}

pub fn (mut iter TreeReverseIterator) peek() !KVPair {
	if !iter.started {
		iter.seek([]u8{})!
	}
	if iter.limit > 0 && iter.yielded >= iter.limit {
		return error('iterator exhausted')
	}
	mut path := iter.path.clone()
	mut leaf_items := iter.leaf_items.clone()
	mut item_idx := iter.item_idx
	for {
		if item_idx < 0 {
			path = iter.tree.prev_leaf_path(path) or { return error('iterator exhausted') }
			leaf_items = path[path.len - 1].node.leaf_items()!
			item_idx = leaf_items.len - 1
			continue
		}
		item := leaf_items[item_idx]
		if iter.start.len > 0 && compare_key_bytes(item.key, iter.start) < 0 {
			return error('iterator exhausted')
		}
		return item
	}
	return error('iterator exhausted')
}

pub fn (mut iter TreeReverseIterator) next() !KVPair {
	if !iter.started {
		iter.seek([]u8{})!
	}
	if iter.limit > 0 && iter.yielded >= iter.limit {
		return error('iterator exhausted')
	}
	for {
		if iter.item_idx < 0 {
			iter.path = iter.tree.prev_leaf_path(iter.path) or {
				return error('iterator exhausted')
			}
			iter.leaf_items = iter.path[iter.path.len - 1].node.leaf_items()!
			iter.item_idx = iter.leaf_items.len - 1
			continue
		}
		item := iter.leaf_items[iter.item_idx]
		if iter.start.len > 0 && compare_key_bytes(item.key, iter.start) < 0 {
			return error('iterator exhausted')
		}
		iter.item_idx--
		iter.yielded++
		iter.current_item = item
		iter.has_current_item = true
		return item
	}
	return error('iterator exhausted')
}

pub fn (tree Tree) reverse_range_scan(start []u8, end []u8, limit int) ![]KVPair {
	mut iter := TreeReverseIterator.new(tree, start, end, limit)!
	mut items := []KVPair{}
	for {
		item := iter.next() or { break }
		items << item
	}
	return items
}

pub fn (tree Tree) reachable_cids() ![]string {
	root := tree.root_node()!
	mut seen := map[string]bool{}
	tree.collect_reachable_cids(root, mut seen)!
	mut cids := seen.keys()
	cids.sort()
	return cids
}

pub fn (tree Tree) reachable_node_count() !int {
	return tree.reachable_cids()!.len
}

pub fn (tree Tree) reachable_node_bytes() !int {
	return tree.bytes_for_cids(tree.reachable_cids()!)
}

pub fn (tree Tree) bytes_for_cids(cids []string) int {
	mut total := 0
	for cid in cids {
		node := tree.nodes[cid] or { continue }
		total += node.data.len
	}
	return total
}

fn (tree Tree) collect_leaf_refs(node Node) ![]NodeRef {
	if node.kind == .leaf {
		return [node.to_ref()]
	}
	mut refs := []NodeRef{}
	for child in node.child_refs()! {
		child_node := tree.nodes[child.cid] or {
			return error('child node not found: ${child.cid}')
		}
		refs << tree.collect_leaf_refs(child_node)!
	}
	return refs
}

fn (tree Tree) collect_items(node Node) ![]KVPair {
	if node.kind == .leaf {
		return node.leaf_items()
	}
	mut items := []KVPair{}
	for child in node.child_refs()! {
		child_node := tree.nodes[child.cid] or {
			return error('child node not found: ${child.cid}')
		}
		items << tree.collect_items(child_node)!
	}
	return items
}

fn (tree Tree) collect_reachable_cids(node Node, mut seen map[string]bool) ! {
	if node.cid in seen {
		return
	}
	seen[node.cid] = true
	if node.kind == .leaf {
		return
	}
	for child in node.child_refs()! {
		child_node := tree.nodes[child.cid] or {
			return error('child node not found: ${child.cid}')
		}
		tree.collect_reachable_cids(child_node, mut seen)!
	}
}

fn (tree Tree) leftmost_leaf_path() ![]TreePathStep {
	root := tree.root_node()!
	return tree.descend_leftmost(root, []TreePathStep{})
}

fn (tree Tree) rightmost_leaf_path() ![]TreePathStep {
	root := tree.root_node()!
	return tree.descend_rightmost(root, []TreePathStep{})
}

fn (tree Tree) descend_leftmost(node Node, prefix []TreePathStep) ![]TreePathStep {
	mut path := prefix.clone()
	mut current := node
	for current.kind != .leaf {
		children := current.child_refs()!
		path << TreePathStep{
			node:         current
			child_refs:   children
			selected_idx: 0
		}
		next_cid := children[0].cid
		current = tree.nodes[next_cid] or { return error('child node not found: ${next_cid}') }
	}
	path << TreePathStep{
		node:         current
		child_refs:   []NodeRef{}
		selected_idx: -1
	}
	return path
}

fn (tree Tree) descend_rightmost(node Node, prefix []TreePathStep) ![]TreePathStep {
	mut path := prefix.clone()
	mut current := node
	for current.kind != .leaf {
		children := current.child_refs()!
		last_idx := children.len - 1
		path << TreePathStep{
			node:         current
			child_refs:   children
			selected_idx: last_idx
		}
		next_cid := children[last_idx].cid
		current = tree.nodes[next_cid] or { return error('child node not found: ${next_cid}') }
	}
	path << TreePathStep{
		node:         current
		child_refs:   []NodeRef{}
		selected_idx: -1
	}
	return path
}

fn (tree Tree) next_leaf_path(path []TreePathStep) ![]TreePathStep {
	for depth := path.len - 2; depth >= 0; depth-- {
		step := path[depth]
		next_idx := step.selected_idx + 1
		if next_idx >= step.child_refs.len {
			continue
		}
		mut next_path := path[..depth].clone()
		next_path << TreePathStep{
			node:         step.node
			child_refs:   step.child_refs
			selected_idx: next_idx
		}
		next_cid := step.child_refs[next_idx].cid
		next_node := tree.nodes[next_cid] or { return error('child node not found: ${next_cid}') }
		return tree.descend_leftmost(next_node, next_path)
	}
	return error('no next leaf')
}

fn (tree Tree) prev_leaf_path(path []TreePathStep) ![]TreePathStep {
	for depth := path.len - 2; depth >= 0; depth-- {
		step := path[depth]
		prev_idx := step.selected_idx - 1
		if prev_idx < 0 {
			continue
		}
		mut prev_path := path[..depth].clone()
		prev_path << TreePathStep{
			node:         step.node
			child_refs:   step.child_refs
			selected_idx: prev_idx
		}
		prev_cid := step.child_refs[prev_idx].cid
		prev_node := tree.nodes[prev_cid] or { return error('child node not found: ${prev_cid}') }
		return tree.descend_rightmost(prev_node, prev_path)
	}
	return error('no previous leaf')
}

fn (tree Tree) path_to_leaf(key []u8) ![]TreePathStep {
	mut path := []TreePathStep{}
	mut node := tree.root_node()!
	for {
		if node.kind == .leaf {
			path << TreePathStep{
				node:         node
				child_refs:   []NodeRef{}
				selected_idx: -1
			}
			return path
		}
		children := node.child_refs()!
		idx := choose_child_index(key, children)
		path << TreePathStep{
			node:         node
			child_refs:   children
			selected_idx: idx
		}
		next_cid := children[idx].cid
		node = tree.nodes[next_cid] or { return error('path node not found: ${next_cid}') }
	}
	return error('unreachable tree path state')
}

fn (tree Tree) bound_match(path []TreePathStep, key []u8, inclusive bool) !TreeBoundMatch {
	mut current_path := path.clone()
	for {
		leaf := current_path[current_path.len - 1].node
		items := leaf.leaf_items()!
		for item in items {
			cmp := compare_key_bytes(item.key, key)
			if inclusive {
				if cmp >= 0 {
					return TreeBoundMatch{
						item: item
					}
				}
			} else if cmp > 0 {
				return TreeBoundMatch{
					item: item
				}
			}
		}
		current_path = tree.next_leaf_path(current_path) or {
			bound_name := if inclusive { 'lower bound' } else { 'upper bound' }
			return error('${bound_name} not found: ${key.bytestr()}')
		}
	}
	return error('unreachable tree bound state')
}

pub fn (tree Tree) put(item KVPair, cfg ChunkConfig) !Tree {
	path := tree.path_to_leaf(item.key)!
	leaf_step := path[path.len - 1]
	mut items := leaf_step.node.leaf_items()!
	mut inserted := false
	for idx, existing in items {
		cmp := compare_key_bytes(item.key, existing.key)
		if cmp == 0 {
			items[idx] = item
			inserted = true
			break
		}
		if cmp < 0 {
			items.insert(idx, item)
			inserted = true
			break
		}
	}
	if !inserted {
		items << item
	}
	return tree.rebuild_path(path, items, cfg)
}

pub fn (tree Tree) diff(next Tree) TreeDiff {
	mut added := []string{}
	mut removed := []string{}
	mut reused := []string{}
	old_cids := tree.reachable_cids() or { []string{} }
	new_cids := next.reachable_cids() or { []string{} }
	mut old_set := map[string]bool{}
	mut new_set := map[string]bool{}
	for cid in old_cids {
		old_set[cid] = true
	}
	for cid in new_cids {
		new_set[cid] = true
		if cid in old_set {
			reused << cid
		} else {
			added << cid
		}
	}
	for cid in old_cids {
		if cid !in new_set {
			removed << cid
		}
	}

	added.sort()
	removed.sort()
	reused.sort()

	return TreeDiff{
		old_root_cid: tree.root.cid
		new_root_cid: next.root.cid
		added_cids:   added
		removed_cids: removed
		reused_cids:  reused
	}
}

fn (tree Tree) diff_for_write(next Tree, cfg ChunkConfig) TreeDiff {
	if cfg.enable_write_diff {
		return tree.diff(next)
	}
	return TreeDiff{
		old_root_cid: tree.root.cid
		new_root_cid: next.root.cid
	}
}

pub fn (tree Tree) delete(key []u8, cfg ChunkConfig) !Tree {
	path := tree.path_to_leaf(key)!
	leaf_step := path[path.len - 1]
	mut items := leaf_step.node.leaf_items()!
	mut target_idx := -1
	for idx, item in items {
		if compare_key_bytes(key, item.key) == 0 {
			target_idx = idx
			break
		}
	}
	if target_idx < 0 {
		return tree
	}
	items.delete(target_idx)
	if items.len == 0 {
		return tree.remove_path_leaf(path, cfg)
	}
	return tree.rebuild_path(path, items, cfg)
}

pub fn (tree Tree) apply_mutations(mutations []Mutation, cfg ChunkConfig) !TreeUpdate {
	if mutations.len == 0 {
		return TreeUpdate{
			tree: tree
			diff: tree.diff(tree)
		}
	}
	if tree.root.cid.len == 0 {
		mut item_map := map[string][]u8{}
		for mutation in mutations {
			match mutation.op {
				.put {
					item_map[mutation.key.bytestr()] = mutation.value.clone()
				}
				.delete {
					return error('cannot delete from an empty tree')
				}
			}
		}
		if item_map.len == 0 {
			return error('empty-tree mutation batch produced no items')
		}
		mut keys := item_map.keys()
		keys.sort()
		mut items := []KVPair{cap: keys.len}
		for key in keys {
			items << KVPair{
				key:   key.bytes()
				value: item_map[key].clone()
			}
		}
		next_tree := Tree.build(items, cfg)!
		return TreeUpdate{
			tree: next_tree
			diff: tree.diff_for_write(next_tree, cfg)
		}
	}
	mut groups := map[string]MutationLeafGroup{}
	mut group_order := []string{}
	for mutation in mutations {
		path := tree.path_to_leaf(mutation.key)!
		leaf := path[path.len - 1].node
		group_id := leaf.cid
		if group_id !in groups {
			groups[group_id] = MutationLeafGroup{
				anchor_key: mutation.key.clone()
				mutations:  []Mutation{}
			}
			group_order << group_id
		}
		mut group := groups[group_id]
		group.mutations << mutation
		groups[group_id] = group
	}
	group_order.sort_with_compare(fn [groups] (a &string, b &string) int {
		return compare_key_bytes(groups[*a].anchor_key, groups[*b].anchor_key)
	})

	mut current := tree
	for group_id in group_order {
		group := groups[group_id]
		mut op_map := map[string]Mutation{}
		for mutation in group.mutations {
			op_map[mutation.key.hex()] = mutation
		}
		path := current.path_to_leaf(group.anchor_key)!
		leaf := path[path.len - 1].node
		mut leaf_items := leaf.leaf_items()!
		mut keys := op_map.keys()
		keys.sort()
		for key_id in keys {
			mutation := op_map[key_id]
			match mutation.op {
				.put {
					apply_put_to_items_mut(mut leaf_items, KVPair{
						key:   mutation.key.clone()
						value: mutation.value.clone()
					})
				}
				.delete {
					apply_delete_to_items_mut(mut leaf_items, mutation.key)
				}
			}
		}
		current = if leaf_items.len == 0 {
			current.remove_path_leaf(path, cfg)!
		} else {
			current.replace_leaf_path_items(path, leaf_items, cfg)!
		}
	}
	return TreeUpdate{
		tree: current
		diff: tree.diff_for_write(current, cfg)
	}
}

pub fn (tree Tree) apply_mutations_no_duplicates(mutations []Mutation, cfg ChunkConfig) !TreeUpdate {
	if mutations.len == 0 {
		return TreeUpdate{
			tree: tree
			diff: tree.diff(tree)
		}
	}
	if tree.root.cid.len == 0 {
		mut sorted := mutations.clone()
		sorted.sort_with_compare(fn (a &Mutation, b &Mutation) int {
			return compare_key_bytes(a.key, b.key)
		})
		mut items := []KVPair{cap: sorted.len}
		for mutation in sorted {
			match mutation.op {
				.put {
					items << KVPair{
						key:   mutation.key.clone()
						value: mutation.value.clone()
					}
				}
				.delete {
					return error('cannot delete from an empty tree')
				}
			}
		}
		next_tree := Tree.build(items, cfg)!
		return TreeUpdate{
			tree: next_tree
			diff: tree.diff_for_write(next_tree, cfg)
		}
	}
	mut sorted := mutations.clone()
	sorted.sort_with_compare(fn (a &Mutation, b &Mutation) int {
		return compare_key_bytes(a.key, b.key)
	})
	mut groups := []MutationLeafGroup{}
	mut mutation_idx := 0
	mut path := tree.path_to_leaf(sorted[0].key)!
	for mutation_idx < sorted.len {
		next_path := tree.next_leaf_path(path) or { []TreePathStep{} }
		has_upper := next_path.len > 0
		mut upper_key := []u8{}
		if has_upper {
			next_leaf_items := next_path[next_path.len - 1].node.leaf_items()!
			if next_leaf_items.len > 0 {
				upper_key = next_leaf_items[0].key.clone()
			}
		}
		mut group_mutations := []Mutation{}
		for mutation_idx < sorted.len {
			mutation := sorted[mutation_idx]
			if has_upper && upper_key.len > 0 && compare_key_bytes(mutation.key, upper_key) >= 0 {
				break
			}
			group_mutations << mutation
			mutation_idx++
		}
		if group_mutations.len > 0 {
			groups << MutationLeafGroup{
				anchor_key: group_mutations[0].key.clone()
				mutations:  group_mutations
			}
		}
		if mutation_idx >= sorted.len {
			break
		}
		if next_path.len > 0 {
			path = next_path.clone()
		} else {
			path = tree.path_to_leaf(sorted[mutation_idx].key)!
		}
	}
	mut current := tree
	for group in groups {
		group_path := current.path_to_leaf(group.anchor_key)!
		leaf := group_path[group_path.len - 1].node
		leaf_items := apply_sorted_mutations_to_leaf_items(leaf.leaf_items()!, group.mutations)
		current = if leaf_items.len == 0 {
			current.remove_path_leaf(group_path, cfg)!
		} else {
			current.replace_leaf_path_items(group_path, leaf_items, cfg)!
		}
	}
	return TreeUpdate{
		tree: current
		diff: tree.diff_for_write(current, cfg)
	}
}

pub fn (tree Tree) apply_insert_mutations_no_existing(mutations []Mutation, cfg ChunkConfig) ?TreeUpdate {
	if mutations.len == 0 {
		return TreeUpdate{
			tree: tree
			diff: tree.diff(tree)
		}
	}
	mut sorted := mutations.clone()
	sorted.sort_with_compare(fn (a &Mutation, b &Mutation) int {
		return compare_key_bytes(a.key, b.key)
	})
	for idx, mutation in sorted {
		if mutation.op != .put {
			return none
		}
		if idx > 0 && compare_key_bytes(sorted[idx - 1].key, mutation.key) == 0 {
			return none
		}
	}
	if tree.root.cid.len == 0 {
		mut items := []KVPair{cap: sorted.len}
		for mutation in sorted {
			items << KVPair{
				key:   mutation.key.clone()
				value: mutation.value.clone()
			}
		}
		next_tree := Tree.build(items, cfg) or { return none }
		return TreeUpdate{
			tree: next_tree
			diff: tree.diff_for_write(next_tree, cfg)
		}
	}
	mut groups := []MutationLeafGroup{}
	mut mutation_idx := 0
	mut path := tree.path_to_leaf(sorted[0].key) or { return none }
	for mutation_idx < sorted.len {
		next_path := tree.next_leaf_path(path) or { []TreePathStep{} }
		has_upper := next_path.len > 0
		mut upper_key := []u8{}
		if has_upper {
			next_leaf_items := next_path[next_path.len - 1].node.leaf_items() or { return none }
			if next_leaf_items.len > 0 {
				upper_key = next_leaf_items[0].key.clone()
			}
		}
		mut group_mutations := []Mutation{}
		for mutation_idx < sorted.len {
			mutation := sorted[mutation_idx]
			if has_upper && upper_key.len > 0 && compare_key_bytes(mutation.key, upper_key) >= 0 {
				break
			}
			group_mutations << mutation
			mutation_idx++
		}
		if group_mutations.len > 0 {
			groups << MutationLeafGroup{
				anchor_key: group_mutations[0].key.clone()
				mutations:  group_mutations
			}
		}
		if mutation_idx >= sorted.len {
			break
		}
		if next_path.len > 0 {
			path = next_path.clone()
		} else {
			path = tree.path_to_leaf(sorted[mutation_idx].key) or { return none }
		}
	}
	mut current := tree
	for group in groups {
		group_path := current.path_to_leaf(group.anchor_key) or { return none }
		leaf := group_path[group_path.len - 1].node
		leaf_items := apply_sorted_insert_mutations_to_leaf_items(leaf.leaf_items() or {
			return none
		}, group.mutations) or {
			return none
		}
		current = current.replace_leaf_path_items(group_path, leaf_items, cfg) or { return none }
	}
	return TreeUpdate{
		tree: current
		diff: tree.diff_for_write(current, cfg)
	}
}

fn apply_sorted_mutations_to_leaf_items(items []KVPair, mutations []Mutation) []KVPair {
	mut out := []KVPair{cap: items.len + mutations.len}
	mut item_idx := 0
	mut mutation_idx := 0
	for item_idx < items.len || mutation_idx < mutations.len {
		if mutation_idx >= mutations.len {
			for item_idx < items.len {
				out << items[item_idx]
				item_idx++
			}
			break
		}
		if item_idx >= items.len {
			for mutation_idx < mutations.len {
				mutation := mutations[mutation_idx]
				if mutation.op == .put {
					out << KVPair{
						key:   mutation.key.clone()
						value: mutation.value.clone()
					}
				}
				mutation_idx++
			}
			break
		}
		item := items[item_idx]
		mutation := mutations[mutation_idx]
		cmp := compare_key_bytes(item.key, mutation.key)
		if cmp < 0 {
			out << item
			item_idx++
			continue
		}
		if cmp > 0 {
			if mutation.op == .put {
				out << KVPair{
					key:   mutation.key.clone()
					value: mutation.value.clone()
				}
			}
			mutation_idx++
			continue
		}
		if mutation.op == .put {
			out << KVPair{
				key:   mutation.key.clone()
				value: mutation.value.clone()
			}
		}
		item_idx++
		mutation_idx++
	}
	return out
}

fn apply_sorted_insert_mutations_to_leaf_items(items []KVPair, mutations []Mutation) ?[]KVPair {
	mut out := []KVPair{cap: items.len + mutations.len}
	mut item_idx := 0
	mut mutation_idx := 0
	for item_idx < items.len || mutation_idx < mutations.len {
		if mutation_idx >= mutations.len {
			for item_idx < items.len {
				out << items[item_idx]
				item_idx++
			}
			break
		}
		if item_idx >= items.len {
			for mutation_idx < mutations.len {
				mutation := mutations[mutation_idx]
				out << KVPair{
					key:   mutation.key.clone()
					value: mutation.value.clone()
				}
				mutation_idx++
			}
			break
		}
		item := items[item_idx]
		mutation := mutations[mutation_idx]
		cmp := compare_key_bytes(item.key, mutation.key)
		if cmp < 0 {
			out << item
			item_idx++
			continue
		}
		if cmp > 0 {
			out << KVPair{
				key:   mutation.key.clone()
				value: mutation.value.clone()
			}
			mutation_idx++
			continue
		}
		return none
	}
	return out
}

fn apply_put_to_items_mut(mut items []KVPair, item KVPair) {
	mut inserted := false
	for idx, existing in items {
		cmp := compare_key_bytes(item.key, existing.key)
		if cmp == 0 {
			items[idx] = item
			inserted = true
			break
		}
		if cmp < 0 {
			items.insert(idx, item)
			inserted = true
			break
		}
	}
	if !inserted {
		items << item
	}
}

fn apply_put_to_items(items []KVPair, item KVPair) []KVPair {
	mut next := items.clone()
	apply_put_to_items_mut(mut next, item)
	return next
}

fn apply_delete_to_items_mut(mut items []KVPair, key []u8) {
	for idx, item in items {
		if compare_key_bytes(key, item.key) == 0 {
			items.delete(idx)
			break
		}
	}
}

fn apply_delete_to_items(items []KVPair, key []u8) []KVPair {
	mut next := items.clone()
	apply_delete_to_items_mut(mut next, key)
	return next
}

fn (tree Tree) rebuild_path(path []TreePathStep, leaf_items []KVPair, cfg ChunkConfig) !Tree {
	mut builder := TreeBuilder{
		cfg:   cfg
		nodes: tree.nodes.clone()
	}
	mut refs := builder.build_leaf_level(leaf_items)!
	if path.len == 1 {
		mut level := 1
		for refs.len > 1 {
			refs = builder.build_internal_level(level, refs)!
			level++
		}
		return Tree{
			root:  refs[0]
			nodes: builder.nodes
		}
	}
	for depth := path.len - 2; depth >= 0; depth-- {
		step := path[depth]
		mut children := []NodeRef{}
		children << step.child_refs[..step.selected_idx]
		children << refs
		children << step.child_refs[step.selected_idx + 1..]
		refs = builder.build_internal_level(step.node.level, children)!
	}
	mut level := path[0].node.level + 1
	for refs.len > 1 {
		refs = builder.build_internal_level(level, refs)!
		level++
	}
	return Tree{
		root:  refs[0]
		nodes: builder.nodes
	}
}

fn (tree Tree) remove_path_leaf(path []TreePathStep, cfg ChunkConfig) !Tree {
	if path.len == 1 {
		return error('deleting the last key would produce an empty tree')
	}
	mut builder := TreeBuilder{
		cfg:   cfg
		nodes: tree.nodes.clone()
	}
	mut refs := []NodeRef{}
	for depth := path.len - 2; depth >= 0; depth-- {
		step := path[depth]
		mut children := []NodeRef{}
		children << step.child_refs[..step.selected_idx]
		children << refs
		children << step.child_refs[step.selected_idx + 1..]
		if children.len == 0 {
			if depth == 0 {
				return error('deleting the last key would produce an empty tree')
			}
			refs = []NodeRef{}
			continue
		}
		if children.len == 1 {
			refs = children.clone()
			continue
		}
		refs = builder.build_internal_level(step.node.level, children)!
	}
	if refs.len == 0 {
		return error('deleting the last key would produce an empty tree')
	}
	mut level := path[0].node.level + 1
	for refs.len > 1 {
		refs = builder.build_internal_level(level, refs)!
		level++
	}
	return Tree{
		root:  refs[0]
		nodes: builder.nodes
	}
}

fn (tree Tree) replace_leaf_items(anchor_key []u8, leaf_items []KVPair, cfg ChunkConfig) !Tree {
	path := tree.path_to_leaf(anchor_key)!
	return tree.replace_leaf_path_items(path, leaf_items, cfg)
}

fn (tree Tree) replace_leaf_path_items(path []TreePathStep, leaf_items []KVPair, cfg ChunkConfig) !Tree {
	return tree.rebuild_path(path, leaf_items, cfg)
}
