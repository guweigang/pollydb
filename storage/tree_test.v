module storage

import os
import rand

fn test_serialize_leaf_node_is_deterministic_for_unsorted_input() {
	items_a := [
		KVPair{key: 'b'.bytes(), value: 'two'.bytes()},
		KVPair{key: 'a'.bytes(), value: 'one'.bytes()},
	]
	items_b := [
		KVPair{key: 'a'.bytes(), value: 'one'.bytes()},
		KVPair{key: 'b'.bytes(), value: 'two'.bytes()},
	]

	left := serialize_leaf_node(items_a) or { panic(err) }
	right := serialize_leaf_node(items_b) or { panic(err) }

	assert left == right
}

fn test_build_tree_creates_internal_root_when_leaf_level_splits() {
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 10 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := build_tree(items, cfg) or { panic(err) }
	root := tree.nodes[tree.root.cid]

	assert tree.nodes.len > 1
	assert root.kind == .internal
	assert root.item_count == 10
}

fn test_build_tree_single_leaf_root_for_small_input() {
	cfg := ChunkConfig{
		min_size: 256
		max_size: 512
		mask: 0
	}
	items := [
		KVPair{key: 'id:1'.bytes(), value: 'hello'.bytes()},
		KVPair{key: 'id:2'.bytes(), value: 'world'.bytes()},
	]

	tree := build_tree(items, cfg) or { panic(err) }
	root := tree.nodes[tree.root.cid]

	assert tree.nodes.len == 1
	assert root.kind == .leaf
	assert root.item_count == 2
}

fn test_build_tree_rejects_duplicate_keys() {
	items := [
		KVPair{key: 'dup'.bytes(), value: 'one'.bytes()},
		KVPair{key: 'dup'.bytes(), value: 'two'.bytes()},
	]

	if _ := build_tree(items, ChunkConfig{}) {
		assert false
	} else {
		assert err.msg().contains('duplicate key')
	}
}

fn shared_leaf_cid_count(left []NodeRef, right []NodeRef) int {
	mut right_set := map[string]bool{}
	for ref in right {
		right_set[ref.cid] = true
	}
	mut count := 0
	for ref in left {
		if ref.cid in right_set {
			count++
		}
	}
	return count
}

fn test_tree_put_reuses_unaffected_leaf_nodes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	before := tree.leaf_refs() or { panic(err) }
	updated := tree.put(KVPair{
		key: 'key-05'.bytes()
		value: 'value-05-updated'.bytes()
	}, cfg) or { panic(err) }
	after := updated.leaf_refs() or { panic(err) }

	assert before.len == after.len
	assert updated.root.cid != tree.root.cid
	assert shared_leaf_cid_count(before, after) == before.len - 1
}

fn test_tree_delete_reuses_unaffected_leaf_nodes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	before := tree.leaf_refs() or { panic(err) }
	updated := tree.delete('key-05'.bytes(), cfg) or { panic(err) }
	after := updated.leaf_refs() or { panic(err) }

	assert after.len == before.len
	assert updated.root.cid != tree.root.cid
	assert shared_leaf_cid_count(before, after) == before.len - 1
}

fn test_tree_apply_mutations_returns_updated_tree_and_diff() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	update := tree.apply_mutations([
		Mutation.put('key-05'.bytes(), 'value-05-updated'.bytes()),
		Mutation.delete('key-08'.bytes()),
	], cfg) or { panic(err) }

	leaf_refs := update.tree.leaf_refs() or { panic(err) }
	assert update.tree.root.cid != tree.root.cid
	assert update.diff.old_root_cid == tree.root.cid
	assert update.diff.new_root_cid == update.tree.root.cid
	assert update.diff.added_cids.len > 0
	assert update.diff.removed_cids.len > 0
	assert update.diff.reused_cids.len > 0
	assert leaf_refs.len > 0

	mut found_updated := false
	mut found_deleted := false
	for ref in leaf_refs {
		node := update.tree.nodes[ref.cid]
		for item in node.leaf_items() or { panic(err) } {
			if item.key.bytestr() == 'key-05' && item.value.bytestr() == 'value-05-updated' {
				found_updated = true
			}
			if item.key.bytestr() == 'key-08' {
				found_deleted = true
			}
		}
	}
	assert found_updated
	assert !found_deleted
}

fn test_tree_diff_reports_reused_and_replaced_nodes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	updated := tree.put(KVPair{
		key: 'key-05'.bytes()
		value: 'value-05-updated'.bytes()
	}, cfg) or { panic(err) }
	diff := tree.diff(updated)

	assert diff.old_root_cid == tree.root.cid
	assert diff.new_root_cid == updated.root.cid
	assert diff.added_cids.len >= 2
	assert diff.removed_cids.len >= 2
	assert diff.reused_cids.len > 0
}

fn test_tree_put_preserves_all_keys_when_rebuild_path_recascades_root() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 256 {
		items << KVPair{
			key: 'key-${idx:04}'.bytes()
			value: 'value-${idx:04}-payload'.bytes()
		}
	}

	mut tree := Tree.build(items, cfg) or { panic(err) }
	for idx in 0 .. 32 {
		tree = tree.put(KVPair{
			key: 'key-${idx:04}'.bytes()
			value: 'value-${idx:04}-updated'.bytes()
		}, cfg) or { panic(err) }
	}

	for idx in 0 .. 256 {
		item := tree.get('key-${idx:04}'.bytes()) or { panic(err) }
		if idx < 32 {
			assert item.value.bytestr() == 'value-${idx:04}-updated'
		} else {
			assert item.value.bytestr() == 'value-${idx:04}-payload'
		}
	}
}

fn test_tree_get_finds_single_key_without_flattening_callsite() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	item := tree.get('key-05'.bytes()) or { panic(err) }

	assert item.key.bytestr() == 'key-05'
	assert item.value.bytestr() == 'value-${5:02}-payload'
	assert tree.has('key-05'.bytes())
	assert !tree.has('missing'.bytes())
}

fn test_tree_lower_and_upper_bound_find_neighboring_keys() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	lower_exact := tree.lower_bound('key-05'.bytes()) or { panic(err) }
	lower_gap := tree.lower_bound('key-05.5'.bytes()) or { panic(err) }
	upper_exact := tree.upper_bound('key-05'.bytes()) or { panic(err) }

	assert lower_exact.key.bytestr() == 'key-05'
	assert lower_gap.key.bytestr() == 'key-06'
	assert upper_exact.key.bytestr() == 'key-06'
}

fn test_tree_bounds_fail_when_key_is_past_tail() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 4 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	if _ := tree.lower_bound('zzz'.bytes()) {
		assert false
	} else {
		assert err.msg().contains('lower bound not found')
	}
	if _ := tree.upper_bound('key-03'.bytes()) {
		assert false
	} else {
		assert err.msg().contains('upper bound not found')
	}
}

fn test_tree_range_scan_returns_ordered_slice_between_bounds() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	scanned := tree.range_scan('key-03'.bytes(), 'key-07'.bytes(), 0) or { panic(err) }

	assert scanned.len == 4
	assert scanned[0].key.bytestr() == 'key-03'
	assert scanned[1].key.bytestr() == 'key-04'
	assert scanned[2].key.bytestr() == 'key-05'
	assert scanned[3].key.bytestr() == 'key-06'
}

fn test_tree_range_scan_respects_limit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	scanned := tree.range_scan('key-03'.bytes(), []u8{}, 2) or { panic(err) }

	assert scanned.len == 2
	assert scanned[0].key.bytestr() == 'key-03'
	assert scanned[1].key.bytestr() == 'key-04'
}

fn test_tree_iterator_seek_and_next_walks_ordered_keys() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut iter := TreeIterator.new(tree, 'key-04'.bytes(), 'key-08'.bytes(), 0) or { panic(err) }

	first := iter.next() or { panic(err) }
	second := iter.next() or { panic(err) }
	third := iter.next() or { panic(err) }

	assert first.key.bytestr() == 'key-04'
	assert second.key.bytestr() == 'key-05'
	assert third.key.bytestr() == 'key-06'
}

fn test_tree_iterator_stops_at_end_or_limit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut iter := TreeIterator.new(tree, 'key-04'.bytes(), 'key-06'.bytes(), 1) or { panic(err) }
	first := iter.next() or { panic(err) }

	assert first.key.bytestr() == 'key-04'
	if _ := iter.next() {
		assert false
	} else {
		assert err.msg().contains('iterator exhausted')
	}
}

fn test_tree_iterator_peek_does_not_advance_position() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut iter := TreeIterator.new(tree, 'key-04'.bytes(), 'key-08'.bytes(), 0) or { panic(err) }
	first_peek := iter.peek() or { panic(err) }
	second_peek := iter.peek() or { panic(err) }
	first_next := iter.next() or { panic(err) }

	assert first_peek.key.bytestr() == 'key-04'
	assert second_peek.key.bytestr() == 'key-04'
	assert first_next.key.bytestr() == 'key-04'
}

fn test_tree_iterator_current_returns_last_consumed_item() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut iter := TreeIterator.new(tree, 'key-04'.bytes(), 'key-08'.bytes(), 0) or { panic(err) }
	if _ := iter.current() {
		assert false
	} else {
		assert err.msg().contains('no current item')
	}

	first := iter.next() or { panic(err) }
	current_after_first := iter.current() or { panic(err) }
	second := iter.next() or { panic(err) }
	current_after_second := iter.current() or { panic(err) }

	assert first.key.bytestr() == 'key-04'
	assert current_after_first.key.bytestr() == 'key-04'
	assert second.key.bytestr() == 'key-05'
	assert current_after_second.key.bytestr() == 'key-05'
}

fn test_tree_cursor_forward_delegates_to_tree_iterator() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut cursor := tree.cursor('key-04'.bytes(), 'key-08'.bytes(), 0) or { panic(err) }
	assert (cursor.peek() or { panic(err) }).key.bytestr() == 'key-04'
	assert (cursor.next() or { panic(err) }).key.bytestr() == 'key-04'
	assert (cursor.current() or { panic(err) }).key.bytestr() == 'key-04'
	cursor.seek('key-06'.bytes()) or { panic(err) }
	assert (cursor.next() or { panic(err) }).key.bytestr() == 'key-06'
}

fn test_tree_cursor_skip_and_collect_work_for_forward_cursor() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut cursor := tree.cursor('key-02'.bytes(), 'key-09'.bytes(), 0) or { panic(err) }
	skipped := cursor.skip(2) or { panic(err) }
	collected := cursor.collect(3) or { panic(err) }

	assert skipped == 2
	assert collected.len == 3
	assert collected[0].key.bytestr() == 'key-04'
	assert collected[1].key.bytestr() == 'key-05'
	assert collected[2].key.bytestr() == 'key-06'
}

fn test_tree_prefix_scan_returns_only_matching_prefix() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{key: 'acct:001'.bytes(), value: 'a'.bytes()},
		KVPair{key: 'acct:002'.bytes(), value: 'b'.bytes()},
		KVPair{key: 'acct:003'.bytes(), value: 'c'.bytes()},
		KVPair{key: 'user:001'.bytes(), value: 'x'.bytes()},
		KVPair{key: 'user:002'.bytes(), value: 'y'.bytes()},
	]

	tree := Tree.build(items, cfg) or { panic(err) }
	scanned := tree.prefix_scan('acct:'.bytes(), 0) or { panic(err) }

	assert scanned.len == 3
	assert scanned[0].key.bytestr() == 'acct:001'
	assert scanned[1].key.bytestr() == 'acct:002'
	assert scanned[2].key.bytestr() == 'acct:003'
}

fn test_tree_prefix_scan_respects_limit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{key: 'acct:001'.bytes(), value: 'a'.bytes()},
		KVPair{key: 'acct:002'.bytes(), value: 'b'.bytes()},
		KVPair{key: 'acct:003'.bytes(), value: 'c'.bytes()},
		KVPair{key: 'user:001'.bytes(), value: 'x'.bytes()},
		KVPair{key: 'user:002'.bytes(), value: 'y'.bytes()},
	]

	tree := Tree.build(items, cfg) or { panic(err) }
	scanned := tree.prefix_scan('acct:'.bytes(), 2) or { panic(err) }

	assert scanned.len == 2
	assert scanned[0].key.bytestr() == 'acct:001'
	assert scanned[1].key.bytestr() == 'acct:002'
}

fn test_tree_prefix_iterator_peek_and_current_work() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{key: 'acct:001'.bytes(), value: 'a'.bytes()},
		KVPair{key: 'acct:002'.bytes(), value: 'b'.bytes()},
		KVPair{key: 'acct:003'.bytes(), value: 'c'.bytes()},
		KVPair{key: 'user:001'.bytes(), value: 'x'.bytes()},
		KVPair{key: 'user:002'.bytes(), value: 'y'.bytes()},
	]

	tree := Tree.build(items, cfg) or { panic(err) }
	mut iter := TreePrefixIterator.new(tree, 'acct:'.bytes(), 0) or { panic(err) }
	first_peek := iter.peek() or { panic(err) }
	first_next := iter.next() or { panic(err) }
	current := iter.current() or { panic(err) }

	assert first_peek.key.bytestr() == 'acct:001'
	assert first_next.key.bytestr() == 'acct:001'
	assert current.key.bytestr() == 'acct:001'
}

fn test_tree_prefix_iterator_seek_updates_prefix() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{key: 'acct:001'.bytes(), value: 'a'.bytes()},
		KVPair{key: 'acct:002'.bytes(), value: 'b'.bytes()},
		KVPair{key: 'user:001'.bytes(), value: 'x'.bytes()},
		KVPair{key: 'user:002'.bytes(), value: 'y'.bytes()},
	]

	tree := Tree.build(items, cfg) or { panic(err) }
	mut iter := TreePrefixIterator.new(tree, 'acct:'.bytes(), 0) or { panic(err) }
	_ = iter.next() or { panic(err) }
	iter.seek('user:'.bytes()) or { panic(err) }
	first_user := iter.next() or { panic(err) }

	assert first_user.key.bytestr() == 'user:001'
}

fn test_tree_prefix_iterator_respects_limit_and_stops_at_prefix_boundary() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{key: 'acct:001'.bytes(), value: 'a'.bytes()},
		KVPair{key: 'acct:002'.bytes(), value: 'b'.bytes()},
		KVPair{key: 'acct:003'.bytes(), value: 'c'.bytes()},
		KVPair{key: 'user:001'.bytes(), value: 'x'.bytes()},
		KVPair{key: 'user:002'.bytes(), value: 'y'.bytes()},
	]

	tree := Tree.build(items, cfg) or { panic(err) }
	mut limited := TreePrefixIterator.new(tree, 'acct:'.bytes(), 2) or { panic(err) }
	assert (limited.next() or { panic(err) }).key.bytestr() == 'acct:001'
	assert (limited.next() or { panic(err) }).key.bytestr() == 'acct:002'
	if _ := limited.next() {
		assert false
	} else {
		assert err.msg().contains('iterator exhausted')
	}

	mut boundary := TreePrefixIterator.new(tree, 'user:'.bytes(), 0) or { panic(err) }
	assert (boundary.next() or { panic(err) }).key.bytestr() == 'user:001'
	assert (boundary.peek() or { panic(err) }).key.bytestr() == 'user:002'
	assert (boundary.next() or { panic(err) }).key.bytestr() == 'user:002'
	if _ := boundary.next() {
		assert false
	} else {
		assert err.msg().contains('iterator exhausted')
	}
}

fn test_tree_cursor_prefix_delegates_to_prefix_iterator() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{key: 'acct:001'.bytes(), value: 'a'.bytes()},
		KVPair{key: 'acct:002'.bytes(), value: 'b'.bytes()},
		KVPair{key: 'user:001'.bytes(), value: 'x'.bytes()},
	]

	tree := Tree.build(items, cfg) or { panic(err) }
	mut cursor := tree.prefix_cursor('acct:'.bytes(), 0) or { panic(err) }
	assert (cursor.peek() or { panic(err) }).key.bytestr() == 'acct:001'
	assert (cursor.next() or { panic(err) }).key.bytestr() == 'acct:001'
	cursor.seek('user:'.bytes()) or { panic(err) }
	assert (cursor.next() or { panic(err) }).key.bytestr() == 'user:001'
}

fn test_tree_cursor_collect_honors_prefix_boundary() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{key: 'acct:001'.bytes(), value: 'a'.bytes()},
		KVPair{key: 'acct:002'.bytes(), value: 'b'.bytes()},
		KVPair{key: 'acct:003'.bytes(), value: 'c'.bytes()},
		KVPair{key: 'user:001'.bytes(), value: 'x'.bytes()},
	]

	tree := Tree.build(items, cfg) or { panic(err) }
	mut cursor := tree.prefix_cursor('acct:'.bytes(), 0) or { panic(err) }
	collected := cursor.collect(0) or { panic(err) }

	assert collected.len == 3
	assert collected[0].key.bytestr() == 'acct:001'
	assert collected[2].key.bytestr() == 'acct:003'
}

fn test_tree_reverse_range_scan_returns_descending_keys() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	scanned := tree.reverse_range_scan('key-03'.bytes(), 'key-07'.bytes(), 0) or { panic(err) }

	assert scanned.len == 4
	assert scanned[0].key.bytestr() == 'key-06'
	assert scanned[1].key.bytestr() == 'key-05'
	assert scanned[2].key.bytestr() == 'key-04'
	assert scanned[3].key.bytestr() == 'key-03'
}

fn test_tree_reverse_iterator_peek_and_current_work() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut iter := TreeReverseIterator.new(tree, 'key-03'.bytes(), 'key-07'.bytes(), 0) or { panic(err) }
	first_peek := iter.peek() or { panic(err) }
	first_next := iter.next() or { panic(err) }
	current := iter.current() or { panic(err) }

	assert first_peek.key.bytestr() == 'key-06'
	assert first_next.key.bytestr() == 'key-06'
	assert current.key.bytestr() == 'key-06'
}

fn test_tree_reverse_iterator_respects_limit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut iter := TreeReverseIterator.new(tree, 'key-03'.bytes(), 'key-07'.bytes(), 2) or { panic(err) }
	first := iter.next() or { panic(err) }
	second := iter.next() or { panic(err) }

	assert first.key.bytestr() == 'key-06'
	assert second.key.bytestr() == 'key-05'
	if _ := iter.next() {
		assert false
	} else {
		assert err.msg().contains('iterator exhausted')
	}
}

fn test_tree_cursor_reverse_delegates_to_reverse_iterator() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut cursor := tree.reverse_cursor('key-03'.bytes(), 'key-07'.bytes(), 0) or { panic(err) }
	assert (cursor.peek() or { panic(err) }).key.bytestr() == 'key-06'
	assert (cursor.next() or { panic(err) }).key.bytestr() == 'key-06'
	assert (cursor.current() or { panic(err) }).key.bytestr() == 'key-06'
	cursor.seek('key-05'.bytes()) or { panic(err) }
	assert (cursor.next() or { panic(err) }).key.bytestr() == 'key-04'
}

fn test_tree_cursor_skip_works_for_reverse_cursor() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}

	tree := Tree.build(items, cfg) or { panic(err) }
	mut cursor := tree.reverse_cursor('key-03'.bytes(), 'key-09'.bytes(), 0) or { panic(err) }
	skipped := cursor.skip(2) or { panic(err) }
	next_item := cursor.next() or { panic(err) }

	assert skipped == 2
	assert next_item.key.bytestr() == 'key-06'
}

fn test_tree_lookup_in_store_matches_tree_get() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{
			key: '001'.bytes()
			value: 'ada'.bytes()
		},
		KVPair{
			key: '002'.bytes()
			value: 'grace'.bytes()
		},
		KVPair{
			key: '003'.bytes()
			value: 'linus'.bytes()
		},
	]
	tree := Tree.build(items, cfg) or { panic(err) }
	mut store := MemoryNodeStore.new()
	store.put_tree(tree) or { panic(err) }
	expected := tree.get('002'.bytes()) or { panic(err) }
	lookup := Tree.lookup_in_store_with_stats(tree.root.cid, '002'.bytes(), mut store) or {
		panic(err)
	}
	assert lookup.item.key == expected.key
	assert lookup.item.value == expected.value
	assert lookup.stats.nodes_read >= 1
	assert lookup.stats.path_depth >= 1
	assert lookup.stats.leaf_item_count >= 1
}

fn test_tree_lookup_in_byte_store_matches_tree_get() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{
			key: '001'.bytes()
			value: 'ada'.bytes()
		},
		KVPair{
			key: '002'.bytes()
			value: 'grace'.bytes()
		},
		KVPair{
			key: '003'.bytes()
			value: 'linus'.bytes()
		},
	]
	tree := Tree.build(items, cfg) or { panic(err) }
	mut store := MemoryNodeStore.new()
	store.put_tree(tree) or { panic(err) }
	expected := tree.get('002'.bytes()) or { panic(err) }
	lookup := Tree.lookup_in_byte_store_with_stats(tree.root.cid, '002'.bytes(), mut store) or {
		panic(err)
	}
	assert lookup.item.key == expected.key
	assert lookup.item.value == expected.value
	assert lookup.stats.nodes_read >= 1
	assert lookup.stats.path_depth >= 1
	assert lookup.stats.leaf_item_count >= 1
}

fn test_tree_lookup_in_persistent_store_matches_tree_get() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	items := [
		KVPair{
			key: '001'.bytes()
			value: 'ada'.bytes()
		},
		KVPair{
			key: '002'.bytes()
			value: 'grace'.bytes()
		},
		KVPair{
			key: '003'.bytes()
			value: 'linus'.bytes()
		},
	]
	tree := Tree.build(items, cfg) or { panic(err) }
	path := os.join_path(os.temp_dir(), 'pollytree-fast-lookup-${rand.u32()}')
	mut store := PersistentNodeStore.open(path) or { panic(err) }
	defer {
		store.close()
		os.rm(path) or {}
		os.rm('${path}.idx') or {}
	}
	store.put_tree(tree) or { panic(err) }
	store.checkpoint() or { panic(err) }
	expected := tree.get('002'.bytes()) or { panic(err) }
	lookup := Tree.lookup_in_persistent_store_with_stats(tree.root.cid, '002'.bytes(), mut store) or {
		panic(err)
	}
	assert lookup.item.key == expected.key
	assert lookup.item.value == expected.value
	assert lookup.stats.nodes_read >= 1
	assert lookup.stats.path_depth >= 1
	assert lookup.stats.leaf_item_count >= 1
}
