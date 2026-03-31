module storage

import os
import rand
import json
import net.http

fn sidecar_test_items_spec() !TypedTableSpec {
	table := TableDef.new('items', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.enum_string('status', ['active', 'draft', 'done'], false)!,
		ColumnDef.new('meta', .json_, false)!,
		ColumnDef.new('enabled', .bool_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.new('status_idx', 'status')!,
		SchemaIndexDef.json_path('kind_idx', 'meta', 'kind', .string_)!,
		SchemaIndexDef.json_path_covering('kind_cover', 'meta', 'kind', .string_)!,
		SchemaIndexDef.json_path_covering('enabled_idx', 'meta', 'enabled', .bool_)!,
	])
}

fn test_sidecar_repo_root_dir_uses_namespace_when_present() {
	assert sidecar_repo_root_dir('/tmp/hub', '') == '/tmp/hub'
	assert sidecar_repo_root_dir('/tmp/hub', '.') == '/tmp/hub'
	assert sidecar_repo_root_dir('/tmp/hub', 'team-a') == os.join_path('/tmp/hub', 'team-a')
}

fn test_open_sidecar_repository_initializes_namespaced_repo() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-namespace-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := open_sidecar_repository(root_dir, 'team-a', 'main') or { panic(err) }
	assert repo.path == os.join_path(root_dir, 'team-a', '.pollydb', 'repo.meta')
	assert os.exists(os.join_path(root_dir, 'team-a', '.pollydb', 'repo.meta'))
	info := sidecar_repository_info(root_dir, mut repo, 'team-a')
	assert info.repo_name == 'team-a'
	assert info.default_branch == 'main'
	assert info.branch_count == 0
	repo.close() or { panic(err) }
}

fn test_list_sidecar_repositories_includes_root_and_namespaced_repos() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-repos-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut root_repo := open_sidecar_repository(root_dir, '', 'main') or { panic(err) }
	root_repo.close() or { panic(err) }
	mut team_repo := open_sidecar_repository(root_dir, 'team-a', 'main') or { panic(err) }
	team_repo.close() or { panic(err) }
	repos := list_sidecar_repositories(root_dir) or { panic(err) }
	assert repos.contains('.')
	assert repos.contains('team-a')
}

fn test_sidecar_branch_log_returns_recent_commits_for_namespaced_repo() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-branch-log-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := open_sidecar_repository(root_dir, 'team-a', 'main') or { panic(err) }
	cfg := ChunkConfig.default()
	tree1 := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], cfg) or { panic(err) }
	tree2 := Tree.build([
		KVPair{key: 'a'.bytes(), value: '2'.bytes()},
	], cfg) or { panic(err) }
	repo.commit_to_branch('main', tree1, CommitMeta{
		author: 'gwg'
		message: 'first'
		timestamp: 1
	}) or { panic(err) }
	repo.commit_to_branch('main', tree2, CommitMeta{
		author: 'gwg'
		message: 'second'
		timestamp: 2
	}) or { panic(err) }
	repo.close() or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/branch-log?repo=team-a&branch=main&limit=2'
	}) 
	assert response.status_code == 200
	payload := json.decode(SidecarBranchLogDto, response.body) or { panic(err) }
	assert payload.commits.len == 2
	assert payload.commits[0].message == 'second'
	assert payload.commits[1].message == 'first'
}

fn test_sidecar_repository_info_tracks_latest_branch_activity() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-summary-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := open_sidecar_repository(root_dir, 'team-b', 'main') or { panic(err) }
	repo.create_branch('feature', 'main') or { panic(err) }
	tree_main := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	tree_feature := Tree.build([
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	repo.commit_to_branch('main', tree_main, CommitMeta{
		author: 'gwg'
		message: 'main-update'
		timestamp: 10
	}) or { panic(err) }
	repo.commit_to_branch('feature', tree_feature, CommitMeta{
		author: 'gwg'
		message: 'feature-update'
		timestamp: 20
	}) or { panic(err) }
	info := sidecar_repository_info(root_dir, mut repo, 'team-b')
	assert info.branch_count == 2
	assert info.latest_branch == 'feature'
	assert info.latest_commit_cid.len > 0
	assert info.latest_timestamp == 20
	repo.close() or { panic(err) }
}

fn test_sidecar_repo_activity_returns_branches_sorted_by_latest_commit() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-repo-activity-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := open_sidecar_repository(root_dir, 'team-c', 'main') or { panic(err) }
	repo.create_branch('feature', 'main') or { panic(err) }
	main_tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	feature_tree := Tree.build([
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	repo.commit_to_branch('main', main_tree, CommitMeta{
		author: 'gwg'
		message: 'main-update'
		timestamp: 10
	}) or { panic(err) }
	repo.commit_to_branch('feature', feature_tree, CommitMeta{
		author: 'gwg'
		message: 'feature-update'
		timestamp: 20
	}) or { panic(err) }
	repo.close() or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/repo-activity?repo=team-c&limit=2'
	})
	assert response.status_code == 200
	payload := json.decode(SidecarRepoActivityDto, response.body) or { panic(err) }
	assert payload.entries.len == 2
	assert payload.entries[0].branch.name == 'feature'
	assert payload.entries[0].message == 'feature-update'
	assert payload.entries[1].branch.name == 'main'
}

fn test_list_sidecar_repository_infos_sorts_by_latest_timestamp() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-repo-summaries-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo_a := open_sidecar_repository(root_dir, 'team-a', 'main') or { panic(err) }
	tree_a := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	repo_a.commit_to_branch('main', tree_a, CommitMeta{
		author: 'gwg'
		message: 'older'
		timestamp: 10
	}) or { panic(err) }
	repo_a.close() or { panic(err) }
	mut repo_b := open_sidecar_repository(root_dir, 'team-b', 'main') or { panic(err) }
	tree_b := Tree.build([
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	repo_b.commit_to_branch('main', tree_b, CommitMeta{
		author: 'gwg'
		message: 'newer'
		timestamp: 20
	}) or { panic(err) }
	repo_b.close() or { panic(err) }
	infos := list_sidecar_repository_infos(root_dir, 'main') or { panic(err) }
	assert infos.len == 2
	assert infos[0].repo_name == 'team-b'
	assert infos[1].repo_name == 'team-a'
}

fn test_list_sidecar_global_activity_sorts_across_repositories() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-global-activity-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo_a := open_sidecar_repository(root_dir, 'team-a', 'main') or { panic(err) }
	tree_a := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	repo_a.commit_to_branch('main', tree_a, CommitMeta{
		author: 'gwg'
		message: 'older'
		timestamp: 10
	}) or { panic(err) }
	repo_a.close() or { panic(err) }
	mut repo_b := open_sidecar_repository(root_dir, 'team-b', 'main') or { panic(err) }
	tree_b := Tree.build([
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	repo_b.commit_to_branch('main', tree_b, CommitMeta{
		author: 'gwg'
		message: 'newer'
		timestamp: 20
	}) or { panic(err) }
	repo_b.close() or { panic(err) }
	entries := list_sidecar_global_activity(root_dir, 'main', 10) or { panic(err) }
	assert entries.len == 2
	assert entries[0].repo_name == 'team-b'
	assert entries[0].message == 'newer'
	assert entries[1].repo_name == 'team-a'
}

fn test_pollyhub_governance_enforces_bearer_and_repo_acl() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-governance-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := open_sidecar_repository(root_dir, 'team-a', 'main') or { panic(err) }
	repo.close() or { panic(err) }
	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-a', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	unauthorized := handler.handle(http.Request{
		method: .get
		url: '/v1/repos'
		header: http.new_header()
	})
	assert unauthorized.status_code == 401
	mut ok_header := http.new_header()
	ok_header.add(.authorization, 'Bearer secret-token')
	authorized := handler.handle(http.Request{
		method: .get
		url: '/v1/repos'
		header: ok_header
	})
	assert authorized.status_code == 200
	payload := json.decode(SidecarRepoListDto, authorized.body) or { panic(err) }
	assert payload.repos == ['team-a']
	entries := read_pollyhub_audit_entries(root_dir, 10) or { panic(err) }
	assert entries.len >= 2
	assert entries[0].action == 'list_repos'
	assert entries[0].allowed == true
	assert entries[1].action == 'list_repos'
	assert entries[1].allowed == false
}

fn test_sidecar_governance_status_reports_auth_and_rate_limit() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-governance-status-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := open_sidecar_repository(root_dir, 'team-a', 'main') or { panic(err) }
	repo.close() or { panic(err) }
	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	set_pollyhub_rate_limit_policy(root_dir, 120) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut header := http.new_header()
	header.add(.authorization, 'Bearer secret-token')
	_ = handler.handle(http.Request{
		method: .get
		url: '/v1/repos'
		header: header
	})
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/governance-status'
		header: header
	})
	assert response.status_code == 200
	payload := json.decode(SidecarGovernanceStatusDto, response.body) or { panic(err) }
	assert payload.auth_enabled == true
	assert payload.token_count == 1
	assert payload.repo_count == 1
	assert payload.requests_per_minute == 120
	assert payload.recent_requests_1m >= 1
	assert payload.recent_categories.len >= 1
	assert payload.recent_categories[0].category == 'control-plane'
	assert payload.recent_categories[0].recent_requests_1m >= 1
	assert payload.recent_actors.len >= 1
	assert payload.recent_actors[0].actor == 'alice'
	assert payload.recent_actors[0].recent_requests_1m >= 1
	assert payload.recent_actions.len >= 1
	assert payload.recent_actions[0].action == 'list_repos'
	assert payload.recent_actions[0].recent_requests_1m >= 1
}

fn test_sidecar_rate_limit_denies_when_actor_exceeds_budget() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-rate-limit-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := open_sidecar_repository(root_dir, 'team-a', 'main') or { panic(err) }
	repo.close() or { panic(err) }
	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-a', 'alice', .reader) or { panic(err) }
	set_pollyhub_rate_limit_policy(root_dir, 1) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut header := http.new_header()
	header.add(.authorization, 'Bearer secret-token')
	first := handler.handle(http.Request{
		method: .get
		url: '/v1/repos'
		header: header
	})
	assert first.status_code == 200
	second := handler.handle(http.Request{
		method: .get
		url: '/v1/repos'
		header: header
	})
	assert second.status_code == 429
	payload := json.decode(ErrorDto, second.body) or { panic(err) }
	assert payload.error.contains('rate limit exceeded')
	entries := read_pollyhub_audit_entries(root_dir, 10) or { panic(err) }
	assert entries.len >= 2
	assert entries[0].action == 'list_repos'
	assert entries[0].allowed == false
	assert entries[0].detail.contains('rate limit exceeded')
}

fn test_pollyhub_repo_policy_roundtrip_and_sidecar_repo_info() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-policy-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	mut repo := open_sidecar_repository(root_dir, 'team-policy', 'main') or { panic(err) }
	repo.close() or { panic(err) }
	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	set_pollyhub_repo_policy(root_dir, 'team-policy', false, true, 'manifest_depth1') or { panic(err) }
	policy := pollyhub_repo_policy(root_dir, 'team-policy') or { panic(err) }
	assert policy.allow_push_to_default == false
	assert policy.require_auto_merge == true
	assert policy.default_sync_policy == 'manifest_depth1'
	mut reopened := open_sidecar_repository(root_dir, 'team-policy', 'main') or { panic(err) }
	info := sidecar_repository_info(root_dir, mut reopened, 'team-policy')
	assert info.auth_enabled == true
	assert info.allow_push_to_default == false
	assert info.require_auto_merge == true
	assert info.default_sync_policy == 'manifest_depth1'
	reopened.close() or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/repo-info?repo=team-policy'
		header: auth_header
	})
	assert response.status_code == 200
	payload := json.decode(SidecarRepoInfoQueryDto, response.body) or { panic(err) }
	assert payload.repo.default_sync_policy == 'manifest_depth1'
	assert payload.repo.require_auto_merge == true
}

fn test_sidecar_apply_respects_repo_policy_for_default_branch() {
	source_root := os.join_path(os.vtmp_dir(), 'polly-sidecar-policy-source-${rand.uuid_v4()}')
	target_root := os.join_path(os.vtmp_dir(), 'polly-sidecar-policy-target-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(source_root) or {}
		os.rmdir_all(target_root) or {}
	}
	mut source_repo := open_sidecar_repository(source_root, 'team-policy', 'main') or { panic(err) }
	tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], ChunkConfig.default()) or { panic(err) }
	commit_result := source_repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	offer := sync_offer_for_branch(mut source_repo, 'main') or { panic(err) }
	exchange := full_sync_exchange_for_offer(mut source_repo, offer) or { panic(err) }
	source_repo.close() or { panic(err) }

	mut target_repo := open_sidecar_repository(target_root, 'team-policy', 'main') or { panic(err) }
	target_repo.close() or { panic(err) }
	init_pollyhub_governance(target_root, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(target_root, 'team-policy', 'alice', .writer) or { panic(err) }
	set_pollyhub_repo_policy(target_root, 'team-policy', false, false, 'auto') or { panic(err) }

	handler := PollyLinkSidecarHandler{
		root_dir: target_root
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .post
		url: '/v1/sync/apply'
		header: auth_header
		data: json.encode(SyncApplyRequestDto{
			repo_name: 'team-policy'
			exchange: sync_exchange_to_dto(exchange)
		})
	})
	assert response.status_code == 401
	payload := json.decode(ErrorDto, response.body) or { panic(err) }
	assert payload.error.contains('push to branch disabled')
	entries := read_pollyhub_audit_entries(target_root, 10) or { panic(err) }
	assert entries.len >= 1
	assert entries[0].action == 'sync_apply'
	assert entries[0].allowed == false
	assert entries[0].repo_name == 'team-policy'
	assert commit_result.branch.name == 'main'
}

fn test_sidecar_apply_requires_merge_commit_when_repo_policy_enabled() {
	source_root := os.join_path(os.vtmp_dir(), 'polly-sidecar-merge-policy-source-${rand.uuid_v4()}')
	target_root := os.join_path(os.vtmp_dir(), 'polly-sidecar-merge-policy-target-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(source_root) or {}
		os.rmdir_all(target_root) or {}
	}
	cfg := ChunkConfig.default()
	mut source_repo := open_sidecar_repository(source_root, 'team-merge', 'main') or { panic(err) }
	base_tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], cfg) or { panic(err) }
	base_update := source_repo.commit_to_branch('main', base_tree, CommitMeta{
		author: 'gwg'
		message: 'base'
		timestamp: 1
	}) or { panic(err) }
	source_repo.create_branch('feature', base_update.branch.commit_cid) or { panic(err) }
	main_tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], cfg) or { panic(err) }
	feature_tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
		KVPair{key: 'c'.bytes(), value: '3'.bytes()},
	], cfg) or { panic(err) }
	main_update := source_repo.commit_to_branch('main', main_tree, CommitMeta{
		author: 'gwg'
		message: 'main-update'
		timestamp: 2
	}) or { panic(err) }
	feature_update := source_repo.commit_to_branch('feature', feature_tree, CommitMeta{
		author: 'gwg'
		message: 'feature-update'
		timestamp: 3
	}) or { panic(err) }
	merge_result := source_repo.repo.merge_branches('main', 'feature', cfg, mut source_repo.node_store, mut source_repo.commit_store) or {
		panic(err)
	}
	assert merge_result.conflicts.len == 0
	merge_snapshot := Snapshot.new(merge_result.tree, [main_update.branch.commit_cid, feature_update.branch.commit_cid], CommitMeta{
		author: 'gwg'
		message: 'merge feature'
		timestamp: 4
	})
	merge_snapshot.persist(mut source_repo.node_store, mut source_repo.commit_store) or { panic(err) }
	single_parent_offer := sync_offer_for_branch(mut source_repo, 'main') or { panic(err) }
	single_parent_exchange := full_sync_exchange_for_offer(mut source_repo, single_parent_offer) or { panic(err) }
	merge_offer := SyncOffer{
		request: SyncRequest{
			local_root_hash: merge_snapshot.commit.root_cid
			branch_name: 'main'
		}
		expected_old_commit_cid: ''
		target_commit_cid: merge_snapshot.commit.cid
		target_root_cid: merge_snapshot.commit.root_cid
	}
	merge_exchange := full_sync_exchange_for_offer(mut source_repo, merge_offer) or { panic(err) }
	source_repo.close() or { panic(err) }
	assert base_update.branch.name == 'main'

	mut target_repo := open_sidecar_repository(target_root, 'team-merge', 'main') or { panic(err) }
	target_repo.close() or { panic(err) }
	init_pollyhub_governance(target_root, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(target_root, 'team-merge', 'alice', .writer) or { panic(err) }
	set_pollyhub_repo_policy(target_root, 'team-merge', true, true, 'auto') or { panic(err) }

	handler := PollyLinkSidecarHandler{
		root_dir: target_root
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	rejected := handler.handle(http.Request{
		method: .post
		url: '/v1/sync/apply'
		header: auth_header
		data: json.encode(SyncApplyRequestDto{
			repo_name: 'team-merge'
			exchange: sync_exchange_to_dto(single_parent_exchange)
		})
	})
	assert rejected.status_code == 401
	rejected_payload := json.decode(ErrorDto, rejected.body) or { panic(err) }
	assert rejected_payload.error.contains('requires merge commit')

	accepted := handler.handle(http.Request{
		method: .post
		url: '/v1/sync/apply'
		header: auth_header
		data: json.encode(SyncApplyRequestDto{
			repo_name: 'team-merge'
			exchange: sync_exchange_to_dto(merge_exchange)
		})
	})
	assert accepted.status_code == 200
	applied_branch := json.decode(BranchDto, accepted.body) or { panic(err) }
	assert applied_branch.name == 'main'
	entries := read_pollyhub_audit_entries(target_root, 10) or { panic(err) }
	assert entries.len >= 2
	assert entries[0].action == 'sync_apply'
	assert entries[0].allowed == true
	assert entries[1].action == 'sync_apply'
	assert entries[1].allowed == false
}

fn test_sidecar_branch_statuses_include_merge_and_projector_state() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-branch-statuses-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-status')
	cfg := ChunkConfig.default()
	spec := sidecar_test_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount)', 'items', 'meta', 'amount') or {
		panic(err)
	}).with_priority(200).with_cost_hint(.low)) or {
		panic(err)
	}
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '001')
	seed_row.set('status', 'active')
	seed_row.set('enabled', true)
	seed_row.set('meta', '{"amount":4,"kind":"seed"}')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'items').key_for('001'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	base := db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 10
	}) or { panic(err) }
	db.create_branch('feature', base.branch.commit_cid) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut next_row := TypedRowData.new()
	next_row.set('id', '002')
	next_row.set('status', 'active')
	next_row.set('enabled', true)
	next_row.set('meta', '{"amount":6,"kind":"next"}')
	writes.put('items', '002'.bytes(), next_row)
	_ = db.apply_typed_write_set('feature', writes, cfg, CommitMeta{
		author: 'gwg'
		message: 'feature change'
		timestamp: 20
	}) or { panic(err) }
	db.close() or { panic(err) }
	set_pollyhub_branch_policy(root_dir, 'team-status', 'feature', false, true, 'manifest_depth2') or { panic(err) }

	statuses := list_sidecar_branch_statuses(root_dir, 'team-status', 'main') or { panic(err) }
	assert statuses.len == 2
	assert statuses[0].branch.name == 'feature'
	assert statuses[0].merge_relation == 'ahead_of_default'
	assert statuses[0].policy_scope == 'branch'
	assert statuses[0].allow_push == false
	assert statuses[0].require_auto_merge == true
	assert statuses[0].default_sync_policy == 'manifest_depth2'
	assert statuses[0].projector_stale == 1
	assert statuses[0].stale_projectors == ['sum(items.meta.amount)']
	assert statuses[1].branch.name == 'main'
	assert statuses[1].merge_relation == 'default'
	assert statuses[1].policy_scope == 'repo_default'
	assert statuses[1].projector_stale == 1
}

fn test_pollyhub_branch_policy_roundtrip_and_status_projection() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-branch-policy-status-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-branch')
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	cfg := ChunkConfig.default()
	tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], cfg) or { panic(err) }
	base := db.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	db.create_branch('feature', base.branch.commit_cid) or { panic(err) }
	db.close() or { panic(err) }
	set_pollyhub_branch_policy(root_dir, 'team-branch', 'feature', false, true, 'manifest_depth2') or { panic(err) }
	policy := find_pollyhub_branch_policy(root_dir, 'team-branch', 'feature') or { panic(err) }
	assert policy.allow_push == false
	assert policy.require_auto_merge == true
	assert policy.default_sync_policy == 'manifest_depth2'
	statuses := list_sidecar_branch_statuses(root_dir, 'team-branch', 'main') or { panic(err) }
	assert statuses.len == 2
	for status in statuses {
		if status.branch.name == 'feature' {
			assert status.policy_scope == 'branch'
			assert status.allow_push == false
			assert status.require_auto_merge == true
			assert status.default_sync_policy == 'manifest_depth2'
			return
		}
	}
	panic('expected feature branch status')
}

fn test_sidecar_apply_respects_branch_policy_override() {
	source_root := os.join_path(os.vtmp_dir(), 'polly-sidecar-branch-policy-source-${rand.uuid_v4()}')
	target_root := os.join_path(os.vtmp_dir(), 'polly-sidecar-branch-policy-target-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(source_root) or {}
		os.rmdir_all(target_root) or {}
	}
	cfg := ChunkConfig.default()
	mut source_repo := open_sidecar_repository(source_root, 'team-branch-policy', 'main') or { panic(err) }
	base_tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
	], cfg) or { panic(err) }
	base_update := source_repo.commit_to_branch('main', base_tree, CommitMeta{
		author: 'gwg'
		message: 'base'
		timestamp: 1
	}) or { panic(err) }
	source_repo.create_branch('feature', base_update.branch.commit_cid) or { panic(err) }
	feature_tree := Tree.build([
		KVPair{key: 'a'.bytes(), value: '1'.bytes()},
		KVPair{key: 'b'.bytes(), value: '2'.bytes()},
	], cfg) or { panic(err) }
	feature_offer := source_repo.commit_to_branch('feature', feature_tree, CommitMeta{
		author: 'gwg'
		message: 'feature-update'
		timestamp: 2
	}) or { panic(err) }
	feature_sync_offer := sync_offer_for_branch(mut source_repo, 'feature') or { panic(err) }
	feature_exchange := full_sync_exchange_for_offer(mut source_repo, feature_sync_offer) or { panic(err) }
	source_repo.close() or { panic(err) }
	assert feature_offer.branch.name == 'feature'

	mut target_repo := open_sidecar_repository(target_root, 'team-branch-policy', 'main') or { panic(err) }
	target_repo.create_branch('feature', base_update.branch.commit_cid) or { panic(err) }
	target_repo.close() or { panic(err) }
	init_pollyhub_governance(target_root, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(target_root, 'team-branch-policy', 'alice', .writer) or { panic(err) }
	set_pollyhub_branch_policy(target_root, 'team-branch-policy', 'feature', false, false, 'manifest_depth2') or { panic(err) }

	handler := PollyLinkSidecarHandler{
		root_dir: target_root
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	rejected := handler.handle(http.Request{
		method: .post
		url: '/v1/sync/apply'
		header: auth_header
		data: json.encode(SyncApplyRequestDto{
			repo_name: 'team-branch-policy'
			exchange: sync_exchange_to_dto(feature_exchange)
		})
	})
	assert rejected.status_code == 401
	payload := json.decode(ErrorDto, rejected.body) or { panic(err) }
	assert payload.error.contains('push to branch disabled')
	entries := read_pollyhub_audit_entries(target_root, 10) or { panic(err) }
	assert entries.len >= 1
	assert entries[0].action == 'sync_apply'
	assert entries[0].allowed == false
	assert entries[0].branch_name == 'feature'
}
