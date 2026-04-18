module storage

import time

pub struct SyncRequest {
pub:
	local_root_hash string
	branch_name     string
}

pub struct MissingNodesRequest {
pub:
	missing_cids []string
}

pub enum SyncObjectKind {
	node
	commit
}

pub struct DataPacket {
pub:
	kind SyncObjectKind = .node
	cid  string
	data []u8
}

pub struct SyncPlan {
pub:
	request             SyncRequest
	target_commit_cid   string
	target_root_cid     string
	missing_commit_cids []string
	missing_node_cids   []string
}

pub struct SyncSession {
pub:
	request                SyncRequest
	expected_old_commit_cid string
	target_commit_cid       string
}

pub struct SyncExchange {
pub:
	session SyncSession
	plan    SyncPlan
	packets []DataPacket
}

pub struct SyncOffer {
pub:
	request                SyncRequest
	expected_old_commit_cid string
	target_commit_cid       string
	target_root_cid         string
}

pub enum SyncNegotiationPolicy {
	regular
	manifest_depth1
	manifest_depth2
	auto
}

pub struct SyncManifest {
pub:
	offer          SyncOffer
	prediction_depth int
	level_1_hashes []string
	predicted_hashes []string
}

pub struct SyncMissingSet {
pub:
	missing_commit_cids []string
	missing_node_cids   []string
}

pub struct SyncPushResult {
pub:
	session SyncSession
	exchange SyncExchange
	branch Branch
	auto_merged bool
}

pub struct SyncPullResult {
pub:
	session SyncSession
	exchange SyncExchange
	branch Branch
}

pub struct SyncNegotiationDecision {
pub:
	policy            SyncNegotiationPolicy
	prediction_depth  int
	estimated_rtts    int
}

pub struct SyncPreparedExchange {
pub:
	session  SyncSession
	exchange SyncExchange
	policy   SyncNegotiationPolicy
}

pub struct SyncPolicyRecommendation {
pub:
	decision            SyncNegotiationDecision
	tree_depth          int
	regular_local_ms    i64
	manifest1_local_ms  i64
	manifest2_local_ms  i64
}

pub interface SyncCidPresence {
	has_cid(cid string) bool
}

pub struct SyncCidSet {
pub:
	known map[string]bool
}

pub fn (set SyncCidSet) has_cid(cid string) bool {
	return set.known[cid] or { false }
}

pub fn recommend_sync_negotiation_policy(tree_depth int, simulated_rtt_ms int, regular_local_ms i64, manifest_depth1_local_ms i64, manifest_depth2_local_ms i64) SyncNegotiationDecision {
	regular_rtts := if tree_depth < 1 { 1 } else { tree_depth }
	depth1_rtts := if tree_depth - 1 > 1 { tree_depth - 1 } else { 1 }
	depth2_rtts := if tree_depth - 2 > 1 { tree_depth - 2 } else { 1 }
	regular_total := regular_local_ms + i64(regular_rtts * simulated_rtt_ms)
	depth1_total := manifest_depth1_local_ms + i64(depth1_rtts * simulated_rtt_ms)
	depth2_total := manifest_depth2_local_ms + i64(depth2_rtts * simulated_rtt_ms)
	if depth1_total <= regular_total && depth1_total <= depth2_total {
		return SyncNegotiationDecision{
			policy: .manifest_depth1
			prediction_depth: 1
			estimated_rtts: depth1_rtts
		}
	}
	if depth2_total <= regular_total && depth2_total <= depth1_total {
		return SyncNegotiationDecision{
			policy: .manifest_depth2
			prediction_depth: 2
			estimated_rtts: depth2_rtts
		}
	}
	return SyncNegotiationDecision{
		policy: .regular
		prediction_depth: 0
		estimated_rtts: regular_rtts
	}
}

fn sync_known_sets_for_branch(mut repo PersistentRepository, branch_name string) !(SyncCidSet, SyncCidSet) {
	if !repo.has_branch(branch_name) {
		return SyncCidSet{
			known: map[string]bool{}
		}, SyncCidSet{
			known: map[string]bool{}
		}
	}
	branch := repo.branch(branch_name)!
	mut known_commit_map := map[string]bool{}
	mut known_node_map := map[string]bool{}
	for cid in collect_commit_lineage_cids(branch.commit_cid, mut repo.commit_store)! {
		known_commit_map[cid] = true
	}
	commit := repo.commit_store.get(branch.commit_cid)!
	for cid in collect_tree_cids(commit.root_cid, mut repo.node_store)! {
		known_node_map[cid] = true
	}
	return SyncCidSet{
		known: known_commit_map
	}, SyncCidSet{
		known: known_node_map
	}
}

pub fn prepare_sync_exchange_for_policy(mut source_repo PersistentRepository, source_branch string, mut target_repo PersistentRepository, target_branch string, policy SyncNegotiationPolicy) !SyncPreparedExchange {
	source_branch_head := source_repo.branch(source_branch)!
	source_commit := source_repo.commit_store.get(source_branch_head.commit_cid)!
	expected_old_commit_cid := if target_repo.has_branch(target_branch) {
		(target_repo.branch(target_branch)!).commit_cid
	} else {
		''
	}
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: source_commit.root_cid
		branch_name: target_branch
	}, expected_old_commit_cid, source_commit.cid)
	offer := session.offer(mut source_repo.commit_store)!
	known_commits, known_nodes := sync_known_sets_for_branch(mut target_repo, target_branch)!
	exchange := match policy {
		.regular {
			build_exchange_from_offer(offer, mut source_repo.commit_store, mut source_repo.node_store, known_commits, known_nodes)!
		}
		.manifest_depth1 {
			manifest := offer.manifest_with_depth(1, mut source_repo.node_store)!
			build_exchange_from_manifest(manifest, mut source_repo.commit_store, mut source_repo.node_store, known_commits, known_nodes)!
		}
		.manifest_depth2 {
			manifest := offer.manifest_with_depth(2, mut source_repo.node_store)!
			build_exchange_from_manifest(manifest, mut source_repo.commit_store, mut source_repo.node_store, known_commits, known_nodes)!
		}
		.auto {
			return error('auto policy must be resolved before preparing a sync exchange')
		}
	}
	return SyncPreparedExchange{
		session: session
		exchange: exchange
		policy: policy
	}
}

pub fn recommend_sync_policy_for_repos(mut source_repo PersistentRepository, source_branch string, mut target_repo PersistentRepository, target_branch string, simulated_rtt_ms int) !SyncPolicyRecommendation {
	tree := source_repo.tree_at_branch(source_branch)!
	root := tree.root_node()!
	tree_depth := root.level + 1
	source_branch_head := source_repo.branch(source_branch)!
	source_commit := source_repo.commit_store.get(source_branch_head.commit_cid)!
	expected_old_commit_cid := if target_repo.has_branch(target_branch) {
		(target_repo.branch(target_branch)!).commit_cid
	} else {
		''
	}
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: source_commit.root_cid
		branch_name: target_branch
	}, expected_old_commit_cid, source_commit.cid)
	offer := session.offer(mut source_repo.commit_store)!
	known_commits, known_nodes := sync_known_sets_for_branch(mut target_repo, target_branch)!
	mut sw_regular := time.new_stopwatch()
	_ = build_exchange_from_offer(offer, mut source_repo.commit_store, mut source_repo.node_store, known_commits, known_nodes)!
	regular_local_ms := sw_regular.elapsed().milliseconds()
	mut sw_manifest1 := time.new_stopwatch()
	manifest1 := offer.manifest_with_depth(1, mut source_repo.node_store)!
	_ = build_exchange_from_manifest(manifest1, mut source_repo.commit_store, mut source_repo.node_store, known_commits, known_nodes)!
	manifest1_local_ms := sw_manifest1.elapsed().milliseconds()
	mut sw_manifest2 := time.new_stopwatch()
	manifest2 := offer.manifest_with_depth(2, mut source_repo.node_store)!
	_ = build_exchange_from_manifest(manifest2, mut source_repo.commit_store, mut source_repo.node_store, known_commits, known_nodes)!
	manifest2_local_ms := sw_manifest2.elapsed().milliseconds()
	decision := recommend_sync_negotiation_policy(tree_depth, simulated_rtt_ms, regular_local_ms, manifest1_local_ms, manifest2_local_ms)
	return SyncPolicyRecommendation{
		decision: decision
		tree_depth: tree_depth
		regular_local_ms: regular_local_ms
		manifest1_local_ms: manifest1_local_ms
		manifest2_local_ms: manifest2_local_ms
	}
}

pub fn discover_missing_tree_cids(root_cid string, mut source NodeByteStore, presence SyncCidPresence) ![]string {
	if root_cid.len == 0 {
		return []string{}
	}
	return discover_missing_tree_cids_from_roots([root_cid], mut source, presence)
}

pub fn discover_missing_tree_cids_from_roots(root_cids []string, mut source NodeByteStore, presence SyncCidPresence) ![]string {
	if root_cids.len == 0 {
		return []string{}
	}
	mut visited := map[string]bool{}
	mut missing := []string{}
	for root_cid in root_cids {
		discover_missing_tree_cids_recursive(root_cid, mut source, presence, mut visited, mut missing)!
	}
	return missing
}

fn discover_missing_tree_cids_recursive(cid string, mut source NodeByteStore, presence SyncCidPresence, mut visited map[string]bool, mut missing []string) ! {
	if cid.len == 0 || cid in visited {
		return
	}
	visited[cid] = true
	if presence.has_cid(cid) {
		return
	}
	missing << cid
	data := source.get_bytes(cid.bytes())!
	layout := NodeLayout.from_bytes(data)!
	if layout.kind != .internal {
		return
	}
	for idx in 0 .. layout.item_count {
		child_cid := layout.child_cid_view(idx)!.bytestr()
		discover_missing_tree_cids_recursive(child_cid, mut source, presence, mut visited, mut missing)!
	}
}

pub fn collect_sync_packets(cids []string, mut source NodeByteStore) ![]DataPacket {
	mut packets := []DataPacket{cap: cids.len}
	for cid in cids {
		packets << DataPacket{
			kind: .node
			cid: cid
			data: source.get_bytes(cid.bytes())!
		}
	}
	return packets
}

pub fn discover_missing_commit_cids(head_commit_cid string, mut source CommitStore, presence SyncCidPresence) ![]string {
	if head_commit_cid.len == 0 {
		return []string{}
	}
	mut visited := map[string]bool{}
	mut missing := []string{}
	discover_missing_commit_cids_recursive(head_commit_cid, mut source, presence, mut visited, mut missing)!
	return missing
}

fn discover_missing_commit_cids_recursive(cid string, mut source CommitStore, presence SyncCidPresence, mut visited map[string]bool, mut missing []string) ! {
	if cid.len == 0 || cid in visited {
		return
	}
	visited[cid] = true
	if presence.has_cid(cid) {
		return
	}
	missing << cid
	commit := source.get(cid)!
	for parent_cid in commit.parent_cids {
		discover_missing_commit_cids_recursive(parent_cid, mut source, presence, mut visited, mut missing)!
	}
}

pub fn collect_commit_packets(cids []string, mut source CommitStore) ![]DataPacket {
	mut packets := []DataPacket{cap: cids.len}
	for cid in cids {
		commit := source.get(cid)!
		packets << DataPacket{
			kind: .commit
			cid: cid
			data: commit.data()
		}
	}
	return packets
}

pub fn collect_tree_cids(root_cid string, mut source NodeByteStore) ![]string {
	if root_cid.len == 0 {
		return []string{}
	}
	mut visited := map[string]bool{}
	mut ordered := []string{}
	collect_tree_cids_recursive(root_cid, mut source, mut visited, mut ordered)!
	return ordered
}

fn collect_tree_cids_recursive(cid string, mut source NodeByteStore, mut visited map[string]bool, mut ordered []string) ! {
	if cid.len == 0 || cid in visited {
		return
	}
	visited[cid] = true
	ordered << cid
	data := source.get_bytes(cid.bytes())!
	layout := NodeLayout.from_bytes(data)!
	if layout.kind != .internal {
		return
	}
	for idx in 0 .. layout.item_count {
		child_cid := layout.child_cid_view(idx)!.bytestr()
		collect_tree_cids_recursive(child_cid, mut source, mut visited, mut ordered)!
	}
}

pub fn collect_commit_lineage_cids(head_commit_cid string, mut source CommitStore) ![]string {
	if head_commit_cid.len == 0 {
		return []string{}
	}
	mut visited := map[string]bool{}
	mut ordered := []string{}
	collect_commit_lineage_cids_recursive(head_commit_cid, mut source, mut visited, mut ordered)!
	return ordered
}

fn collect_commit_lineage_cids_recursive(cid string, mut source CommitStore, mut visited map[string]bool, mut ordered []string) ! {
	if cid.len == 0 || cid in visited {
		return
	}
	visited[cid] = true
	ordered << cid
	commit := source.get(cid)!
	for parent_cid in commit.parent_cids {
		collect_commit_lineage_cids_recursive(parent_cid, mut source, mut visited, mut ordered)!
	}
}

pub fn plan_sync_for_commit(req SyncRequest, target_commit_cid string, mut commit_source CommitStore, mut node_source NodeByteStore, commit_presence SyncCidPresence, node_presence SyncCidPresence) !SyncPlan {
	target_commit := commit_source.get(target_commit_cid)!
	missing_commit_cids := discover_missing_commit_cids(target_commit_cid, mut commit_source, commit_presence)!
	missing_node_cids := discover_missing_tree_cids(target_commit.root_cid, mut node_source, node_presence)!
	return SyncPlan{
		request: req
		target_commit_cid: target_commit_cid
		target_root_cid: target_commit.root_cid
		missing_commit_cids: missing_commit_cids
		missing_node_cids: missing_node_cids
	}
}

pub fn SyncSession.for_commit(req SyncRequest, expected_old_commit_cid string, target_commit_cid string) SyncSession {
	return SyncSession{
		request: req
		expected_old_commit_cid: expected_old_commit_cid
		target_commit_cid: target_commit_cid
	}
}

pub fn (session SyncSession) plan(mut commit_source CommitStore, mut node_source NodeByteStore, commit_presence SyncCidPresence, node_presence SyncCidPresence) !SyncPlan {
	return plan_sync_for_commit(session.request, session.target_commit_cid, mut commit_source, mut node_source, commit_presence, node_presence)
}

pub fn (session SyncSession) offer(mut commit_source CommitStore) !SyncOffer {
	target_commit := commit_source.get(session.target_commit_cid)!
	return SyncOffer{
		request: session.request
		expected_old_commit_cid: session.expected_old_commit_cid
		target_commit_cid: session.target_commit_cid
		target_root_cid: target_commit.root_cid
	}
}

pub fn (offer SyncOffer) negotiate_missing(mut commit_source CommitStore, mut node_source NodeByteStore, commit_presence SyncCidPresence, node_presence SyncCidPresence) !SyncMissingSet {
	missing_commit_cids := discover_missing_commit_cids(offer.target_commit_cid, mut commit_source, commit_presence)!
	missing_node_cids := discover_missing_tree_cids(offer.target_root_cid, mut node_source, node_presence)!
	return SyncMissingSet{
		missing_commit_cids: missing_commit_cids
		missing_node_cids: missing_node_cids
	}
}

pub fn (offer SyncOffer) manifest(mut node_source NodeByteStore) !SyncManifest {
	return offer.manifest_with_depth(1, mut node_source)
}

pub fn (offer SyncOffer) manifest_with_depth(depth int, mut node_source NodeByteStore) !SyncManifest {
	actual_depth := if depth < 1 { 1 } else { depth }
	mut level_1_hashes := []string{}
	mut predicted_hashes := []string{}
	if offer.target_root_cid.len > 0 {
		root_data := node_source.get_bytes(offer.target_root_cid.bytes())!
		layout := NodeLayout.from_bytes(root_data)!
		if layout.kind == .internal {
			level_1_hashes = []string{cap: layout.item_count}
			for idx in 0 .. layout.item_count {
				level_1_hashes << layout.child_cid_view(idx)!.bytestr()
			}
			predicted_hashes = collect_manifest_predicted_cids(offer.target_root_cid, actual_depth, mut node_source)!
		}
	}
	return SyncManifest{
		offer: offer
		prediction_depth: actual_depth
		level_1_hashes: level_1_hashes
		predicted_hashes: predicted_hashes
	}
}

pub fn (manifest SyncManifest) negotiate_missing(mut commit_source CommitStore, mut node_source NodeByteStore, commit_presence SyncCidPresence, node_presence SyncCidPresence) !SyncMissingSet {
	missing_commit_cids := discover_missing_commit_cids(manifest.offer.target_commit_cid, mut commit_source, commit_presence)!
	if node_presence.has_cid(manifest.offer.target_root_cid) {
		return SyncMissingSet{
			missing_commit_cids: missing_commit_cids
			missing_node_cids: []string{}
		}
	}
	mut missing_node_cids := []string{}
	if manifest.offer.target_root_cid.len > 0 {
		missing_node_cids << manifest.offer.target_root_cid
	}
	frontier_cids := if manifest.predicted_hashes.len > 0 {
		manifest.predicted_hashes
	} else {
		manifest.level_1_hashes
	}
	if frontier_cids.len == 0 && manifest.offer.target_root_cid.len > 0 {
		missing_node_cids = discover_missing_tree_cids(manifest.offer.target_root_cid, mut node_source, node_presence)!
	} else if frontier_cids.len > 0 {
		subtree_missing := discover_missing_tree_cids_from_roots(frontier_cids, mut node_source, node_presence)!
		for cid in subtree_missing {
			if cid !in missing_node_cids {
				missing_node_cids << cid
			}
		}
	}
	return SyncMissingSet{
		missing_commit_cids: missing_commit_cids
		missing_node_cids: missing_node_cids
	}
}

fn collect_manifest_predicted_cids(root_cid string, depth int, mut node_source NodeByteStore) ![]string {
	if root_cid.len == 0 {
		return []string{}
	}
	mut predicted := []string{}
	mut visited := map[string]bool{}
	mut predicted_set := map[string]bool{}
	collect_manifest_predicted_cids_recursive(root_cid, 0, if depth < 1 { 1 } else { depth }, mut node_source, mut visited, mut predicted, mut predicted_set)!
	return predicted
}

fn collect_manifest_predicted_cids_recursive(cid string, level int, target_depth int, mut node_source NodeByteStore, mut visited map[string]bool, mut predicted []string, mut predicted_set map[string]bool) ! {
	if cid.len == 0 || cid in visited {
		return
	}
	visited[cid] = true
	data := node_source.get_bytes(cid.bytes())!
	layout := NodeLayout.from_bytes(data)!
	if layout.kind != .internal {
		return
	}
	if level >= target_depth {
		return
	}
	for idx in 0 .. layout.item_count {
		child_cid := layout.child_cid_view(idx)!.bytestr()
		if child_cid !in predicted_set {
			predicted << child_cid
			predicted_set[child_cid] = true
		}
		collect_manifest_predicted_cids_recursive(child_cid, level + 1, target_depth, mut node_source, mut visited, mut predicted, mut predicted_set)!
	}
}

pub fn (session SyncSession) build_exchange_from_missing(mut commit_source CommitStore, mut node_source NodeByteStore, missing SyncMissingSet) !SyncExchange {
	plan := SyncPlan{
		request: session.request
		target_commit_cid: session.target_commit_cid
		target_root_cid: session.request.local_root_hash
		missing_commit_cids: missing.missing_commit_cids.clone()
		missing_node_cids: missing.missing_node_cids.clone()
	}
	packets := collect_commit_packets(plan.missing_commit_cids, mut commit_source)!
	mut node_packets := collect_sync_packets(plan.missing_node_cids, mut node_source)!
	mut all_packets := packets.clone()
	all_packets << node_packets
	return SyncExchange{
		session: session
		plan: plan
		packets: all_packets
	}
}

pub fn build_exchange_from_offer(offer SyncOffer, mut commit_source CommitStore, mut node_source NodeByteStore, commit_presence SyncCidPresence, node_presence SyncCidPresence) !SyncExchange {
	session := SyncSession.for_commit(offer.request, offer.expected_old_commit_cid, offer.target_commit_cid)
	missing := offer.negotiate_missing(mut commit_source, mut node_source, commit_presence, node_presence)!
	return session.build_exchange_from_missing(mut commit_source, mut node_source, missing)
}

pub fn build_exchange_from_manifest(manifest SyncManifest, mut commit_source CommitStore, mut node_source NodeByteStore, commit_presence SyncCidPresence, node_presence SyncCidPresence) !SyncExchange {
	session := SyncSession.for_commit(manifest.offer.request, manifest.offer.expected_old_commit_cid, manifest.offer.target_commit_cid)
	missing := manifest.negotiate_missing(mut commit_source, mut node_source, commit_presence, node_presence)!
	return session.build_exchange_from_missing(mut commit_source, mut node_source, missing)
}

pub fn (session SyncSession) build_exchange(mut commit_source CommitStore, mut node_source NodeByteStore, commit_presence SyncCidPresence, node_presence SyncCidPresence) !SyncExchange {
	missing := session.offer(mut commit_source)!.negotiate_missing(mut commit_source, mut node_source, commit_presence, node_presence)!
	return session.build_exchange_from_missing(mut commit_source, mut node_source, missing)
}

pub fn sync_offer_for_branch(mut repo PersistentRepository, branch_name string) !SyncOffer {
	session := begin_sync_session_for_branch(mut repo, branch_name)!
	return session.offer(mut repo.commit_store)
}

pub fn sync_manifest_for_branch(mut repo PersistentRepository, branch_name string, depth int) !SyncManifest {
	offer := sync_offer_for_branch(mut repo, branch_name)!
	return offer.manifest_with_depth(depth, mut repo.node_store)
}

pub fn sync_missing_for_offer(mut repo PersistentRepository, offer SyncOffer) !SyncMissingSet {
	known_commits, known_nodes := sync_known_sets_for_branch(mut repo, offer.request.branch_name)!
	return offer.negotiate_missing(mut repo.commit_store, mut repo.node_store, known_commits, known_nodes)
}

pub fn sync_missing_for_manifest(mut repo PersistentRepository, manifest SyncManifest) !SyncMissingSet {
	known_commits, known_nodes := sync_known_sets_for_branch(mut repo, manifest.offer.request.branch_name)!
	return manifest.negotiate_missing(mut repo.commit_store, mut repo.node_store, known_commits, known_nodes)
}

pub fn sync_exchange_for_missing(mut repo PersistentRepository, offer SyncOffer, missing SyncMissingSet) !SyncExchange {
	session := SyncSession.for_commit(offer.request, offer.expected_old_commit_cid, offer.target_commit_cid)
	return session.build_exchange_from_missing(mut repo.commit_store, mut repo.node_store, missing)
}

pub fn full_sync_exchange_for_offer(mut repo PersistentRepository, offer SyncOffer) !SyncExchange {
	return build_exchange_from_offer(offer, mut repo.commit_store, mut repo.node_store, SyncCidSet{
		known: map[string]bool{}
	}, SyncCidSet{
		known: map[string]bool{}
	})
}

pub fn build_auto_merge_offer_for_remote_offer(mut source_repo PersistentRepository, source_branch string, target_branch string, remote_offer SyncOffer) !SyncOffer {
	source_branch_head := source_repo.branch(source_branch)!
	source_commit := source_repo.commit_store.get(source_branch_head.commit_cid)!
	base_commit := source_repo.repo.merge_base_commit(source_commit.cid, remote_offer.target_commit_cid, mut source_repo.commit_store)!
	merge_result := auto_merge_by_roots(base_commit.root_cid, source_commit.root_cid,
		remote_offer.target_root_cid, ChunkConfig.default(), mut source_repo.node_store)!
	if merge_result.conflicts.len > 0 {
		return error('auto-merge required manual resolution: ${merge_result.conflicts.len} conflicts')
	}
	merge_meta := CommitMeta{
		author:    'pollylink'
		message:   'auto-merge ${source_branch} into ${target_branch}'
		timestamp: 0
	}
	snapshot := Snapshot.new(merge_result.tree, [source_commit.cid, remote_offer.target_commit_cid],
		merge_meta)
	snapshot.persist(mut source_repo.node_store, mut source_repo.commit_store)!
	return SyncOffer{
		request:                 SyncRequest{
			local_root_hash: snapshot.commit.root_cid
			branch_name:     target_branch
		}
		expected_old_commit_cid: remote_offer.target_commit_cid
		target_commit_cid:       snapshot.commit.cid
		target_root_cid:         snapshot.commit.root_cid
	}
}

pub fn collect_sync_packets_for_plan(plan SyncPlan, mut commit_source CommitStore, mut node_source NodeByteStore) ![]DataPacket {
	mut packets := []DataPacket{}
	packets << collect_commit_packets(plan.missing_commit_cids, mut commit_source)!
	packets << collect_sync_packets(plan.missing_node_cids, mut node_source)!
	return packets
}

pub fn begin_sync_session_for_branch(mut repo PersistentRepository, branch_name string) !SyncSession {
	branch := repo.branch(branch_name)!
	commit := repo.commit_store.get(branch.commit_cid)!
	return SyncSession.for_commit(SyncRequest{
		local_root_hash: commit.root_cid
		branch_name: branch_name
	}, '', commit.cid)
}

pub fn apply_sync_packets(mut node_store PersistentNodeStore, mut commit_store PersistentCommitStore, packets []DataPacket) ! {
	for packet in packets {
		match packet.kind {
			.node {
				node := Node.from_data_with_cid(packet.data, packet.cid)!
				node_store.put(node)!
			}
			.commit {
				commit := Commit.from_data(packet.data)!
				if commit.cid != packet.cid {
					return error('sync commit packet cid mismatch: expected ${packet.cid}, got ${commit.cid}')
				}
				commit_store.put(commit)!
			}
		}
	}
}

pub fn attach_synced_commit(mut repo PersistentRepository, branch_name string, expected_old_commit_cid string, new_commit_cid string) !Branch {
	return repo.compare_and_swap_branch_head(branch_name, expected_old_commit_cid, new_commit_cid)
}

pub fn (exchange SyncExchange) apply(mut node_store PersistentNodeStore, mut commit_store PersistentCommitStore) ! {
	apply_sync_packets(mut node_store, mut commit_store, exchange.packets)!
}

pub fn (exchange SyncExchange) attach(mut repo PersistentRepository) !Branch {
	return attach_synced_commit(mut repo, exchange.session.request.branch_name, exchange.session.expected_old_commit_cid, exchange.plan.target_commit_cid)
}

pub fn apply_exchange_to_repo(mut repo PersistentRepository, exchange SyncExchange) !Branch {
	exchange.apply(mut repo.node_store, mut repo.commit_store)!
	return exchange.attach(mut repo)
}

pub fn import_sync_exchange_objects(mut repo PersistentRepository, exchange SyncExchange) ! {
	exchange.apply(mut repo.node_store, mut repo.commit_store)!
}

pub fn push_branch_to_repo(mut source_repo PersistentRepository, mut target_repo PersistentRepository, branch_name string) !SyncPushResult {
	source_branch := source_repo.branch(branch_name)!
	source_commit := source_repo.commit_store.get(source_branch.commit_cid)!
	expected_old_commit_cid := if target_repo.has_branch(branch_name) {
		(target_repo.branch(branch_name)!).commit_cid
	} else {
		''
	}
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: source_commit.root_cid
		branch_name: branch_name
	}, expected_old_commit_cid, source_commit.cid)
	offer := session.offer(mut source_repo.commit_store)!
	mut known_commit_map := map[string]bool{}
	mut known_node_map := map[string]bool{}
	if target_repo.has_branch(branch_name) {
		current_branch := target_repo.branch(branch_name)!
		for cid in collect_commit_lineage_cids(current_branch.commit_cid, mut target_repo.commit_store)! {
			known_commit_map[cid] = true
		}
		current_commit := target_repo.commit_store.get(current_branch.commit_cid)!
		for cid in collect_tree_cids(current_commit.root_cid, mut target_repo.node_store)! {
			known_node_map[cid] = true
		}
	}
	exchange := build_exchange_from_offer(offer, mut source_repo.commit_store, mut source_repo.node_store, SyncCidSet{
		known: known_commit_map
	}, SyncCidSet{
		known: known_node_map
	})!
	branch := apply_exchange_to_repo(mut target_repo, exchange)!
	return SyncPushResult{
		session: session
		exchange: exchange
		branch: branch
	}
}

pub fn push_branch_to_repo_with_manifest(mut source_repo PersistentRepository, mut target_repo PersistentRepository, branch_name string) !SyncPushResult {
	return push_branch_to_repo_with_manifest_depth(mut source_repo, mut target_repo, branch_name, 1)
}

pub fn push_branch_to_repo_with_policy(mut source_repo PersistentRepository, mut target_repo PersistentRepository, branch_name string, policy SyncNegotiationPolicy) !SyncPushResult {
	match policy {
		.regular {
			return push_branch_to_repo(mut source_repo, mut target_repo, branch_name)
		}
		.manifest_depth1 {
			return push_branch_to_repo_with_manifest_depth(mut source_repo, mut target_repo, branch_name, 1)
		}
		.manifest_depth2 {
			return push_branch_to_repo_with_manifest_depth(mut source_repo, mut target_repo, branch_name, 2)
		}
		.auto {
			return push_branch_to_repo_with_manifest_depth(mut source_repo, mut target_repo, branch_name, 1)
		}
	}
}

pub fn push_branch_to_repo_with_manifest_depth(mut source_repo PersistentRepository, mut target_repo PersistentRepository, branch_name string, prediction_depth int) !SyncPushResult {
	source_branch := source_repo.branch(branch_name)!
	source_commit := source_repo.commit_store.get(source_branch.commit_cid)!
	expected_old_commit_cid := if target_repo.has_branch(branch_name) {
		(target_repo.branch(branch_name)!).commit_cid
	} else {
		''
	}
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: source_commit.root_cid
		branch_name: branch_name
	}, expected_old_commit_cid, source_commit.cid)
	offer := session.offer(mut source_repo.commit_store)!
	manifest := offer.manifest_with_depth(prediction_depth, mut source_repo.node_store)!
	mut known_commit_map := map[string]bool{}
	mut known_node_map := map[string]bool{}
	if target_repo.has_branch(branch_name) {
		current_branch := target_repo.branch(branch_name)!
		for cid in collect_commit_lineage_cids(current_branch.commit_cid, mut target_repo.commit_store)! {
			known_commit_map[cid] = true
		}
		current_commit := target_repo.commit_store.get(current_branch.commit_cid)!
		for cid in collect_tree_cids(current_commit.root_cid, mut target_repo.node_store)! {
			known_node_map[cid] = true
		}
	}
	exchange := build_exchange_from_manifest(manifest, mut source_repo.commit_store, mut source_repo.node_store, SyncCidSet{
		known: known_commit_map
	}, SyncCidSet{
		known: known_node_map
	})!
	branch := apply_exchange_to_repo(mut target_repo, exchange)!
	return SyncPushResult{
		session: session
		exchange: exchange
		branch: branch
	}
}

pub fn pull_branch_to_repo(mut target_repo PersistentRepository, mut source_repo PersistentRepository, branch_name string) !SyncPullResult {
	source_branch := source_repo.branch(branch_name)!
	source_commit := source_repo.commit_store.get(source_branch.commit_cid)!
	expected_old_commit_cid := if target_repo.has_branch(branch_name) {
		(target_repo.branch(branch_name)!).commit_cid
	} else {
		''
	}
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: source_commit.root_cid
		branch_name: branch_name
	}, expected_old_commit_cid, source_commit.cid)
	offer := session.offer(mut source_repo.commit_store)!
	mut known_commit_map := map[string]bool{}
	mut known_node_map := map[string]bool{}
	if target_repo.has_branch(branch_name) {
		current_branch := target_repo.branch(branch_name)!
		for cid in collect_commit_lineage_cids(current_branch.commit_cid, mut target_repo.commit_store)! {
			known_commit_map[cid] = true
		}
		current_commit := target_repo.commit_store.get(current_branch.commit_cid)!
		for cid in collect_tree_cids(current_commit.root_cid, mut target_repo.node_store)! {
			known_node_map[cid] = true
		}
	}
	exchange := build_exchange_from_offer(offer, mut source_repo.commit_store, mut source_repo.node_store, SyncCidSet{
		known: known_commit_map
	}, SyncCidSet{
		known: known_node_map
	})!
	branch := apply_exchange_to_repo(mut target_repo, exchange)!
	return SyncPullResult{
		session: session
		exchange: exchange
		branch: branch
	}
}

pub fn pull_branch_to_repo_with_manifest(mut target_repo PersistentRepository, mut source_repo PersistentRepository, branch_name string) !SyncPullResult {
	return pull_branch_to_repo_with_manifest_depth(mut target_repo, mut source_repo, branch_name, 1)
}

pub fn pull_branch_to_repo_with_policy(mut target_repo PersistentRepository, mut source_repo PersistentRepository, branch_name string, policy SyncNegotiationPolicy) !SyncPullResult {
	match policy {
		.regular {
			return pull_branch_to_repo(mut target_repo, mut source_repo, branch_name)
		}
		.manifest_depth1 {
			return pull_branch_to_repo_with_manifest_depth(mut target_repo, mut source_repo, branch_name, 1)
		}
		.manifest_depth2 {
			return pull_branch_to_repo_with_manifest_depth(mut target_repo, mut source_repo, branch_name, 2)
		}
		.auto {
			return pull_branch_to_repo_with_manifest_depth(mut target_repo, mut source_repo, branch_name, 1)
		}
	}
}

pub fn pull_branch_to_repo_with_manifest_depth(mut target_repo PersistentRepository, mut source_repo PersistentRepository, branch_name string, prediction_depth int) !SyncPullResult {
	source_branch := source_repo.branch(branch_name)!
	source_commit := source_repo.commit_store.get(source_branch.commit_cid)!
	expected_old_commit_cid := if target_repo.has_branch(branch_name) {
		(target_repo.branch(branch_name)!).commit_cid
	} else {
		''
	}
	session := SyncSession.for_commit(SyncRequest{
		local_root_hash: source_commit.root_cid
		branch_name: branch_name
	}, expected_old_commit_cid, source_commit.cid)
	offer := session.offer(mut source_repo.commit_store)!
	manifest := offer.manifest_with_depth(prediction_depth, mut source_repo.node_store)!
	mut known_commit_map := map[string]bool{}
	mut known_node_map := map[string]bool{}
	if target_repo.has_branch(branch_name) {
		current_branch := target_repo.branch(branch_name)!
		for cid in collect_commit_lineage_cids(current_branch.commit_cid, mut target_repo.commit_store)! {
			known_commit_map[cid] = true
		}
		current_commit := target_repo.commit_store.get(current_branch.commit_cid)!
		for cid in collect_tree_cids(current_commit.root_cid, mut target_repo.node_store)! {
			known_node_map[cid] = true
		}
	}
	exchange := build_exchange_from_manifest(manifest, mut source_repo.commit_store, mut source_repo.node_store, SyncCidSet{
		known: known_commit_map
	}, SyncCidSet{
		known: known_node_map
	})!
	branch := apply_exchange_to_repo(mut target_repo, exchange)!
	return SyncPullResult{
		session: session
		exchange: exchange
		branch: branch
	}
}
