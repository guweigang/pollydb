module storage

import os
import rand

fn test_discover_missing_tree_cids_skips_known_subtrees() {
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	mut pairs := []KVPair{}
	for idx in 0 .. 12 {
		pairs << KVPair{
			key: 'key-${idx:02d}'.bytes()
			value: 'value-${idx:02d}'.bytes()
		}
	}
	tree := Tree.build(pairs, cfg) or { panic(err) }
	assert tree.nodes.len > 1
	root := tree.root_node() or { panic(err) }
	root_layout := NodeLayout.from_bytes(root.data) or { panic(err) }
	assert root_layout.kind == .internal
	left_child_cid := root_layout.child_cid_view(0) or { panic(err) }
	mut store := MemoryNodeStore.new()
	store.put_tree(tree) or { panic(err) }
	presence := SyncCidSet{
		known: {
			left_child_cid.bytestr(): true
		}
	}
	missing := discover_missing_tree_cids(tree.root.cid, mut store, presence) or { panic(err) }
	assert tree.root.cid in missing
	assert left_child_cid.bytestr() !in missing
	assert missing.len < tree.nodes.len
}

fn test_collect_sync_packets_returns_requested_payloads() {
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], cfg) or { panic(err) }
	mut store := MemoryNodeStore.new()
	store.put_tree(tree) or { panic(err) }
	cids := [tree.root.cid]
	packets := collect_sync_packets(cids, mut store) or { panic(err) }
	assert packets.len == 1
	assert packets[0].cid == tree.root.cid
	assert packets[0].data.len > 0
}

fn test_discover_missing_commit_cids_skips_known_ancestors() {
	mut commits := MemoryCommitStore.new()
	base := Commit.new('root-a', []string{}, CommitMeta{
		author: 'gwg'
		message: 'base'
		timestamp: 1
	})
	head := Commit.new('root-b', [base.cid], CommitMeta{
		author: 'gwg'
		message: 'head'
		timestamp: 2
	})
	commits.put(base) or { panic(err) }
	commits.put(head) or { panic(err) }
	presence := SyncCidSet{
		known: {
			base.cid: true
		}
	}
	missing := discover_missing_commit_cids(head.cid, mut commits, presence) or { panic(err) }
	assert missing == [head.cid]
}

fn test_plan_sync_for_commit_combines_commit_and_tree_missing_sets() {
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], cfg) or { panic(err) }
	mut nodes := MemoryNodeStore.new()
	nodes.put_tree(tree) or { panic(err) }
	mut commits := MemoryCommitStore.new()
	commit := Commit.new(tree.root.cid, []string{}, CommitMeta{
		author: 'gwg'
		message: 'sync'
		timestamp: 1
	})
	commits.put(commit) or { panic(err) }
	plan := plan_sync_for_commit(SyncRequest{
		local_root_hash: tree.root.cid
		branch_name: 'main'
	}, commit.cid, mut commits, mut nodes, SyncCidSet{known: map[string]bool{}}, SyncCidSet{known: map[string]bool{}}) or { panic(err) }
	assert plan.target_commit_cid == commit.cid
	assert plan.target_root_cid == tree.root.cid
	assert commit.cid in plan.missing_commit_cids
	assert tree.root.cid in plan.missing_node_cids
}

fn test_sync_session_exchange_roundtrip_attaches_branch() {
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
		KVPair{key: 'c'.bytes(), value: '3'.bytes()},
	], cfg) or { panic(err) }
	mut source_nodes := MemoryNodeStore.new()
	source_nodes.put_tree(tree) or { panic(err) }
	mut source_commits := MemoryCommitStore.new()
	commit := Commit.new(tree.root.cid, []string{}, CommitMeta{
		author: 'gwg'
		message: 'sync roundtrip'
		timestamp: 1
	})
	source_commits.put(commit) or { panic(err) }
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: tree.root.cid
		branch_name: 'main'
	}, '', commit.cid)
	exchange := session.build_exchange(mut source_commits, mut source_nodes, SyncCidSet{
		known: map[string]bool{}
	}, SyncCidSet{
		known: map[string]bool{}
	}) or { panic(err) }
	assert exchange.plan.target_commit_cid == commit.cid
	assert exchange.packets.len >= 2
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sync-roundtrip-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := PersistentRepository.init(root_dir, 'main') or { panic(err) }
	exchange.apply(mut repo.node_store, mut repo.commit_store) or { panic(err) }
	branch := exchange.attach(mut repo) or { panic(err) }
	assert branch.name == 'main'
	assert branch.commit_cid == commit.cid
	loaded := repo.commit_store.get(commit.cid) or { panic(err) }
	assert loaded.root_cid == tree.root.cid
	loaded_tree := repo.tree_at_branch('main') or { panic(err) }
	assert loaded_tree.root.cid == tree.root.cid
	repo.close() or { panic(err) }
}

fn test_sync_offer_negotiates_zero_transfer_when_peer_has_commit_and_root() {
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], cfg) or { panic(err) }
	mut nodes := MemoryNodeStore.new()
	nodes.put_tree(tree) or { panic(err) }
	mut commits := MemoryCommitStore.new()
	commit := Commit.new(tree.root.cid, []string{}, CommitMeta{
		author: 'gwg'
		message: 'sync offer'
		timestamp: 1
	})
	commits.put(commit) or { panic(err) }
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: tree.root.cid
		branch_name: 'main'
	}, '', commit.cid)
	offer := session.offer(mut commits) or { panic(err) }
	assert offer.target_commit_cid == commit.cid
	assert offer.target_root_cid == tree.root.cid
	missing := offer.negotiate_missing(mut commits, mut nodes, SyncCidSet{
		known: {
			commit.cid: true
		}
	}, SyncCidSet{
		known: {
			tree.root.cid: true
		}
	}) or { panic(err) }
	assert missing.missing_commit_cids.len == 0
	assert missing.missing_node_cids.len == 0
	exchange := session.build_exchange_from_missing(mut commits, mut nodes, missing) or { panic(err) }
	assert exchange.packets.len == 0
}

fn test_begin_sync_session_for_branch_uses_branch_head_commit() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sync-session-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := PersistentRepository.init(root_dir, 'main') or { panic(err) }
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], cfg) or { panic(err) }
	update := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'head'
		timestamp: 1
	}) or { panic(err) }
	session := begin_sync_session_for_branch(mut repo, 'main') or { panic(err) }
	assert session.request.branch_name == 'main'
	assert session.request.local_root_hash == update.snapshot.commit.root_cid
	assert session.target_commit_cid == update.snapshot.commit.cid
	repo.close() or { panic(err) }
}

fn test_sync_manifest_negotiates_missing_from_root_and_level_1_hashes() {
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	mut pairs := []KVPair{}
	for idx in 0 .. 12 {
		pairs << KVPair{
			key: 'manifest-${idx:02d}'.bytes()
			value: 'value-${idx:02d}'.bytes()
		}
	}
	tree := Tree.build(pairs, cfg) or { panic(err) }
	assert tree.nodes.len > 1
	mut nodes := MemoryNodeStore.new()
	nodes.put_tree(tree) or { panic(err) }
	mut commits := MemoryCommitStore.new()
	commit := Commit.new(tree.root.cid, []string{}, CommitMeta{
		author: 'gwg'
		message: 'manifest'
		timestamp: 1
	})
	commits.put(commit) or { panic(err) }
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: tree.root.cid
		branch_name: 'main'
	}, '', commit.cid)
	offer := session.offer(mut commits) or { panic(err) }
	manifest := offer.manifest(mut nodes) or { panic(err) }
	assert manifest.offer.target_root_cid == tree.root.cid
	assert manifest.level_1_hashes.len > 0
	missing_from_offer := offer.negotiate_missing(mut commits, mut nodes, SyncCidSet{
		known: map[string]bool{}
	}, SyncCidSet{
		known: map[string]bool{}
	}) or { panic(err) }
	missing_from_manifest := manifest.negotiate_missing(mut commits, mut nodes, SyncCidSet{
		known: map[string]bool{}
	}, SyncCidSet{
		known: map[string]bool{}
	}) or { panic(err) }
	assert missing_from_manifest.missing_commit_cids == missing_from_offer.missing_commit_cids
	assert missing_from_manifest.missing_node_cids == missing_from_offer.missing_node_cids
}

fn test_sync_manifest_with_depth_collects_deeper_frontier_hashes() {
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	mut pairs := []KVPair{}
	for idx in 0 .. 64 {
		pairs << KVPair{
			key: 'depth-${idx:03d}'.bytes()
			value: 'value-${idx:03d}'.bytes()
		}
	}
	tree := Tree.build(pairs, cfg) or { panic(err) }
	mut nodes := MemoryNodeStore.new()
	nodes.put_tree(tree) or { panic(err) }
	mut commits := MemoryCommitStore.new()
	commit := Commit.new(tree.root.cid, []string{}, CommitMeta{
		author: 'gwg'
		message: 'manifest depth'
		timestamp: 1
	})
	commits.put(commit) or { panic(err) }
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: tree.root.cid
		branch_name: 'main'
	}, '', commit.cid)
	offer := session.offer(mut commits) or { panic(err) }
	manifest1 := offer.manifest_with_depth(1, mut nodes) or { panic(err) }
	manifest2 := offer.manifest_with_depth(2, mut nodes) or { panic(err) }
	assert manifest1.prediction_depth == 1
	assert manifest2.prediction_depth == 2
	assert manifest1.level_1_hashes.len > 0
	assert manifest1.predicted_hashes.len > 0
	assert manifest2.predicted_hashes.len > 0
	assert manifest2.predicted_hashes.len >= manifest1.predicted_hashes.len
}

fn test_build_exchange_from_offer_roundtrip_and_push_branch_to_repo() {
	source_dir := os.join_path(os.vtmp_dir(), 'polly-sync-source-${rand.uuid_v4()}')
	target_dir := os.join_path(os.vtmp_dir(), 'polly-sync-target-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(source_dir) or {}
		os.rmdir_all(target_dir) or {}
	}
	mut source_repo := PersistentRepository.init(source_dir, 'main') or { panic(err) }
	mut target_repo := PersistentRepository.init(target_dir, 'main') or { panic(err) }
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
		KVPair{key: 'c'.bytes(), value: '3'.bytes()},
	], cfg) or { panic(err) }
	update := source_repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'push'
		timestamp: 1
	}) or { panic(err) }
	session := begin_sync_session_for_branch(mut source_repo, 'main') or { panic(err) }
	offer := session.offer(mut source_repo.commit_store) or { panic(err) }
	exchange := build_exchange_from_offer(offer, mut source_repo.commit_store, mut source_repo.node_store, SyncCidSet{
		known: map[string]bool{}
	}, SyncCidSet{
		known: map[string]bool{}
	}) or { panic(err) }
	assert exchange.plan.target_commit_cid == update.snapshot.commit.cid
	assert exchange.packets.len > 0
	branch := apply_exchange_to_repo(mut target_repo, exchange) or { panic(err) }
	assert branch.commit_cid == update.snapshot.commit.cid
	pushed := push_branch_to_repo(mut source_repo, mut target_repo, 'main') or { panic(err) }
	assert pushed.branch.commit_cid == update.snapshot.commit.cid
	assert pushed.exchange.plan.target_commit_cid == update.snapshot.commit.cid
	assert pushed.exchange.packets.len == 0
	source_repo.close() or { panic(err) }
	target_repo.close() or { panic(err) }
}

fn test_pull_branch_to_repo_roundtrip() {
	source_dir := os.join_path(os.vtmp_dir(), 'polly-sync-pull-source-${rand.uuid_v4()}')
	relay_dir := os.join_path(os.vtmp_dir(), 'polly-sync-pull-relay-${rand.uuid_v4()}')
	target_dir := os.join_path(os.vtmp_dir(), 'polly-sync-pull-target-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(source_dir) or {}
		os.rmdir_all(relay_dir) or {}
		os.rmdir_all(target_dir) or {}
	}
	mut source_repo := PersistentRepository.init(source_dir, 'main') or { panic(err) }
	mut relay_repo := PersistentRepository.init(relay_dir, 'main') or { panic(err) }
	mut target_repo := PersistentRepository.init(target_dir, 'main') or { panic(err) }
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'alpha'.bytes(), value: '1'.bytes()},
		KVPair{key: 'beta'.bytes(), value: '2'.bytes()},
		KVPair{key: 'gamma'.bytes(), value: '3'.bytes()},
	], cfg) or { panic(err) }
	update := source_repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'pull'
		timestamp: 1
	}) or { panic(err) }
	_ = push_branch_to_repo(mut source_repo, mut relay_repo, 'main') or { panic(err) }
	pulled := pull_branch_to_repo(mut target_repo, mut relay_repo, 'main') or { panic(err) }
	assert pulled.branch.commit_cid == update.snapshot.commit.cid
	assert pulled.exchange.plan.target_commit_cid == update.snapshot.commit.cid
	loaded_tree := target_repo.tree_at_branch('main') or { panic(err) }
	assert loaded_tree.root.cid == tree.root.cid
	source_repo.close() or { panic(err) }
	relay_repo.close() or { panic(err) }
	target_repo.close() or { panic(err) }
}

fn test_push_and_pull_with_manifest_match_regular_sync_heads() {
	source_dir := os.join_path(os.vtmp_dir(), 'polly-sync-manifest-source-${rand.uuid_v4()}')
	target_dir := os.join_path(os.vtmp_dir(), 'polly-sync-manifest-target-${rand.uuid_v4()}')
	target2_dir := os.join_path(os.vtmp_dir(), 'polly-sync-manifest-target2-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(source_dir) or {}
		os.rmdir_all(target_dir) or {}
		os.rmdir_all(target2_dir) or {}
	}
	mut source_repo := PersistentRepository.init(source_dir, 'main') or { panic(err) }
	mut target_repo := PersistentRepository.init(target_dir, 'main') or { panic(err) }
	mut target2_repo := PersistentRepository.init(target2_dir, 'main') or { panic(err) }
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'alpha'.bytes(), value: '1'.bytes()},
		KVPair{key: 'beta'.bytes(), value: '2'.bytes()},
		KVPair{key: 'gamma'.bytes(), value: '3'.bytes()},
		KVPair{key: 'delta'.bytes(), value: '4'.bytes()},
	], cfg) or { panic(err) }
	update := source_repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'manifest sync'
		timestamp: 1
	}) or { panic(err) }
	regular_push := push_branch_to_repo(mut source_repo, mut target_repo, 'main') or { panic(err) }
	manifest_push := push_branch_to_repo_with_manifest(mut source_repo, mut target2_repo, 'main') or {
		panic(err)
	}
	assert regular_push.branch.commit_cid == update.snapshot.commit.cid
	assert manifest_push.branch.commit_cid == update.snapshot.commit.cid
	assert manifest_push.exchange.plan.target_commit_cid == regular_push.exchange.plan.target_commit_cid
	assert manifest_push.exchange.plan.target_root_cid == regular_push.exchange.plan.target_root_cid
	mut pulled_repo := PersistentRepository.init(os.join_path(os.vtmp_dir(),
		'polly-sync-manifest-pull-${rand.uuid_v4()}'), 'main') or { panic(err) }
	defer {
		os.rmdir_all(pulled_repo.path) or {}
	}
	manifest_pull := pull_branch_to_repo_with_manifest(mut pulled_repo, mut target2_repo, 'main') or {
		panic(err)
	}
	assert manifest_pull.branch.commit_cid == update.snapshot.commit.cid
	source_repo.close() or { panic(err) }
	target_repo.close() or { panic(err) }
	target2_repo.close() or { panic(err) }
	pulled_repo.close() or { panic(err) }
}

fn test_recommend_sync_negotiation_policy_prefers_lower_effective_total() {
	decision_low_rtt := recommend_sync_negotiation_policy(4, 0, 10, 20, 30)
	assert decision_low_rtt.policy == .regular
	assert decision_low_rtt.prediction_depth == 0
	decision_mid_rtt := recommend_sync_negotiation_policy(4, 40, 313, 311, 534)
	assert decision_mid_rtt.policy == .manifest_depth1
	assert decision_mid_rtt.prediction_depth == 1
	decision_high_rtt := recommend_sync_negotiation_policy(3, 120, 2, 2, 4)
	assert decision_high_rtt.policy == .manifest_depth2
	assert decision_high_rtt.prediction_depth == 2
}

fn test_build_auto_merge_offer_for_remote_offer_merges_non_conflicting_divergence() {
	source_dir := os.join_path(os.vtmp_dir(), 'polly-sync-diverge-source-${rand.uuid_v4()}')
	remote_dir := os.join_path(os.vtmp_dir(), 'polly-sync-diverge-remote-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(source_dir) or {}
		os.rmdir_all(remote_dir) or {}
	}
	mut source_repo := PersistentRepository.init(source_dir, 'main') or { panic(err) }
	mut remote_repo := PersistentRepository.init(remote_dir, 'main') or { panic(err) }
	cfg := ChunkConfig{
		min_size: 32
		max_size: 64
		mask: 0
	}
	base_tree := Tree.build([
		KVPair{key: 'alpha'.bytes(), value: '1'.bytes()},
		KVPair{key: 'beta'.bytes(), value: '2'.bytes()},
		KVPair{key: 'gamma'.bytes(), value: '3'.bytes()},
	], cfg) or { panic(err) }
	base_update := source_repo.commit_to_branch('main', base_tree, CommitMeta{
		author: 'gwg'
		message: 'base'
		timestamp: 1
	}) or { panic(err) }
	_ = push_branch_to_repo(mut source_repo, mut remote_repo, 'main') or { panic(err) }
	source_tree := base_tree.put(KVPair{
		key: 'alpha'.bytes()
		value: 'ours'.bytes()
	}, cfg) or { panic(err) }
	source_update := source_repo.commit_to_branch('main', source_tree, CommitMeta{
		author: 'gwg'
		message: 'ours'
		timestamp: 2
	}) or { panic(err) }
	remote_tree := base_tree.put(KVPair{
		key: 'gamma'.bytes()
		value: 'theirs'.bytes()
	}, cfg) or { panic(err) }
	remote_update := remote_repo.commit_to_branch('main', remote_tree, CommitMeta{
		author: 'gwg'
		message: 'theirs'
		timestamp: 3
	}) or { panic(err) }
	remote_offer := sync_offer_for_branch(mut remote_repo, 'main') or { panic(err) }
	remote_exchange := full_sync_exchange_for_offer(mut remote_repo, remote_offer) or { panic(err) }
	import_sync_exchange_objects(mut source_repo, remote_exchange) or {
		panic(err)
	}
	merged_offer := build_auto_merge_offer_for_remote_offer(mut source_repo, 'main', 'main', remote_offer) or {
		panic(err)
	}
	assert merged_offer.expected_old_commit_cid == remote_update.snapshot.commit.cid
	assert merged_offer.target_commit_cid != source_update.snapshot.commit.cid
	merged_exchange := full_sync_exchange_for_offer(mut source_repo, merged_offer) or {
		panic(err)
	}
	merged_branch := apply_exchange_to_repo(mut remote_repo, merged_exchange) or { panic(err) }
	assert merged_branch.name == 'main'
	merged_commit := remote_repo.commit_store.get(merged_branch.commit_cid) or { panic(err) }
	assert merged_commit.parent_cids.len == 2
	merged_tree := remote_repo.tree_at_branch('main') or { panic(err) }
	alpha := merged_tree.get('alpha'.bytes()) or { panic(err) }
	gamma := merged_tree.get('gamma'.bytes()) or { panic(err) }
	assert alpha.value.bytestr() == 'ours'
	assert gamma.value.bytestr() == 'theirs'
	assert remote_repo.repo.merge_base_commit(source_update.snapshot.commit.cid, remote_update.snapshot.commit.cid, mut remote_repo.commit_store)!.cid == base_update.snapshot.commit.cid
	source_repo.close() or { panic(err) }
	remote_repo.close() or { panic(err) }
}
