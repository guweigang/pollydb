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

fn sidecar_markdown_value_indexed_spec() !TypedTableSpec {
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.markdown_value('body_link_host_idx', 'body', 'link_host')!,
		SchemaIndexDef.markdown_value_covering('body_code_lang_cover', 'body', 'code_block_lang')!,
		SchemaIndexDef.markdown_value('body_heading_text_idx', 'body', 'heading_text:2')!,
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

fn sidecar_test_notes_spec() !TypedTableSpec {
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [])
}

fn test_sidecar_projector_value_returns_markdown_projector_value() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-projector-value-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-md')
	cfg := ChunkConfig.default()
	spec := sidecar_test_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_markdown_links('count(notes.body.links)',
		'notes', 'body') or { panic(err) }) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Links')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len: 0
	})
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body',
		'[a](https://example.com/a)\n\n[b](https://example.com/b)\n', cfg, CommitMeta{
		author: 'gwg'
		message: 'markdown'
		timestamp: 2
	}) or { panic(err) }
	_ = db.refresh_aggregate_projections('main', cfg, CommitMeta{
		author: 'gwg'
		message: 'refresh projector'
		timestamp: 3
	}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-md', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/projector-value?repo=team-md&branch=main&name=count(notes.body.links)'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarProjectorValueDto, response.body) or { panic(err) }
	value := SidecarProjectorValue{
		name: dto.name
		branch_name: dto.branch_name
		value: dto.value
		current_data_root_cid: dto.current_data_root_cid
		source_data_root_cid: dto.source_data_root_cid
		virtual_root_cid: dto.virtual_root_cid
		fresh: dto.fresh
		stale_reason: dto.stale_reason
		source_json_path: dto.source_json_path
		source_field_selector_meta: SidecarFieldSelectorMeta{
			plugin_name: dto.source_field_selector_meta.plugin_name
			selector: dto.source_field_selector_meta.selector
			value_type: dto.source_field_selector_meta.value_type
			stores_row: dto.source_field_selector_meta.stores_row
		}
		source_field_selector_plugin: dto.source_field_selector_plugin
		source_field_selector: dto.source_field_selector
		source_markdown_selector: dto.source_markdown_selector
	}
	assert value.value == i64(2)
	assert value.fresh
	assert value.source_field_selector_meta.plugin_name == 'markdown'
	assert value.source_field_selector_meta.selector == 'links'
	assert value.source_field_selector_meta.value_type == 'i64'
	assert !value.source_field_selector_meta.stores_row
	assert value.source_field_selector_plugin == 'markdown'
	assert value.source_field_selector == 'links'
	assert value.source_markdown_selector == 'links'
	assert value.virtual_root_cid.len > 0
}

fn test_sidecar_markdown_metric_returns_ad_hoc_markdown_count() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-markdown-metric-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-md-metric')
	cfg := ChunkConfig.default()
	spec := sidecar_test_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Doc')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len: 0
	})
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body',
		'# Intro\n\n```v\nprintln("ok")\n```\n\n```sql\nselect 1;\n```\n', cfg, CommitMeta{
		author: 'gwg'
		message: 'markdown'
		timestamp: 2
	}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-md-metric', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/markdown-metric?repo=team-md-metric&branch=main&table=notes&column=body&selector=code_blocks:v'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarMarkdownMetricDto, response.body) or { panic(err) }
	metric := SidecarMarkdownMetric{
		branch_name: dto.branch_name
		table_name: dto.table_name
		column_name: dto.column_name
		selector: dto.selector
		value: dto.value
	}
	assert metric.value == i64(1)
	assert metric.selector == 'code_blocks:v'
	assert metric.table_name == 'notes'
}

fn test_sidecar_index_lookup_returns_markdown_value_index_rows() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-index-lookup-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-md-index')
	cfg := ChunkConfig.default()
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Doc')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len: 0
	})
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body',
		'[docs](https://docs.example.com/a)\n', cfg, CommitMeta{
		author: 'gwg'
		message: 'markdown'
		timestamp: 2
	}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-md-index', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/index-lookup?repo=team-md-index&branch=main&table=notes&index=body_link_host_idx&value=docs.example.com&limit=10'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarIndexLookupDto, response.body) or { panic(err) }
	assert dto.field_selector_meta.plugin_name == 'markdown'
	assert dto.field_selector_meta.selector == 'link_host'
	assert dto.field_selector_meta.value_type == 'string'
	assert !dto.field_selector_meta.stores_row
	assert dto.rows.len == 1
	assert dto.rows[0].primary_key == 'note-1'
	assert dto.rows[0].values['title'] == 'Doc'
}

fn test_sidecar_index_lookup_prefix_returns_markdown_heading_matches() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-index-prefix-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-md-prefix')
	cfg := ChunkConfig.default()
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Doc')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len: 0
	})
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body',
		'## Roadmap\n\nBody.\n', cfg, CommitMeta{
		author: 'gwg'
		message: 'markdown'
		timestamp: 2
	}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-md-prefix', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/index-lookup-prefix?repo=team-md-prefix&branch=main&table=notes&index=body_heading_text_idx&value=Road&limit=10'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarIndexLookupDto, response.body) or { panic(err) }
	assert dto.field_selector_meta.plugin_name == 'markdown'
	assert dto.field_selector_meta.selector == 'heading_text:2'
	assert dto.field_selector_meta.value_type == 'string'
	assert dto.query_kind == 'prefix'
	assert dto.rows.len == 1
	assert dto.rows[0].primary_key == 'note-1'
}

fn test_sidecar_markdown_query_metric_returns_metric_value() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-markdown-query-metric-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-md-query-metric')
	cfg := ChunkConfig.default()
	spec := sidecar_test_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Doc')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len: 0
	})
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body',
		'# Intro\n\n[docs](https://docs.example.com/a)\n', cfg, CommitMeta{
			author: 'gwg'
			message: 'markdown'
			timestamp: 2
		}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-md-query-metric', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/markdown-query?repo=team-md-query-metric&branch=main&table=notes&kind=metric&column=body&selector=links'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarMarkdownQueryDto, response.body) or { panic(err) }
	assert dto.field_selector_meta.plugin_name == 'markdown'
	assert dto.field_selector_meta.selector == 'links'
	assert dto.field_selector_meta.value_type == 'i64'
	assert !dto.field_selector_meta.stores_row
	assert dto.query_kind == 'metric'
	assert dto.metric_value == i64(1)
	assert dto.selector == 'links'
	assert dto.column_name == 'body'
}

fn test_sidecar_markdown_query_prefix_returns_markdown_index_rows() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-markdown-query-prefix-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-md-query-prefix')
	cfg := ChunkConfig.default()
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Doc')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len: 0
	})
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body',
		'## Roadmap\n\nBody.\n', cfg, CommitMeta{
			author: 'gwg'
			message: 'markdown'
			timestamp: 2
		}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-md-query-prefix', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/markdown-query?repo=team-md-query-prefix&branch=main&table=notes&kind=prefix&index=body_heading_text_idx&value=Road&limit=10'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarMarkdownQueryDto, response.body) or { panic(err) }
	assert dto.field_selector_meta.plugin_name == 'markdown'
	assert dto.field_selector_meta.selector == 'heading_text:2'
	assert dto.field_selector_meta.value_type == 'string'
	assert dto.query_kind == 'prefix'
	assert dto.index_name == 'body_heading_text_idx'
	assert dto.rows.len == 1
	assert dto.rows[0].primary_key == 'note-1'
}

fn test_sidecar_table_spec_returns_index_selector_meta() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-table-spec-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-md-spec')
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-md-spec', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/table-spec?repo=team-md-spec&branch=main&table=notes'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarTableSpecDto, response.body) or { panic(err) }
	assert dto.table_name == 'notes'
	assert dto.primary_key == ['id']
	assert dto.columns.len == 3
	assert dto.indexes.len == 3
	assert dto.indexes[0].field_selector_meta.plugin_name == 'markdown'
	assert dto.indexes[0].field_selector_meta.selector == 'link_host'
	assert dto.indexes[0].field_selector_meta.value_type == 'string'
}

fn test_sidecar_query_schema_returns_selector_and_projection_metadata() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-schema-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-schema')
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_field_selector('count(notes.body.links)',
		'notes', 'body', 'markdown', 'links') or { panic(err) }) or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-schema', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/query-schema?repo=team-query-schema&branch=main&table=notes'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarQuerySchemaDto, response.body) or { panic(err) }
	assert dto.table_name == 'notes'
	assert dto.default_result_shape == 'page'
	assert dto.supports_continuation_token
	assert dto.supports_select_projection
	assert dto.supported_filter_ops == ['eq', 'prefix', 'after', 'before', 'between']

	mut body_column := SidecarQuerySchemaColumnDto{}
	for column in dto.columns {
		if column.name == 'body' {
			body_column = column
			break
		}
	}
	assert body_column.name == 'body'
	assert body_column.typ == 'markdown'
	assert body_column.filter_ops == ['eq']
	assert body_column.planner_hints.len == 0
	assert body_column.filter_shapes.len == 1
	assert body_column.filter_shapes[0].op == 'eq'
	assert !body_column.filter_shapes[0].indexed
	assert body_column.filter_shapes[0].planner_strategy == 'table_scan'
	assert body_column.filter_shapes[0].sample_explain.strategy == 'table_scan'
	assert body_column.filter_shapes[0].sample_explain.warnings.len >= 1
	assert body_column.filter_shapes[0].sample_explain.warnings[0].contains('table scan')

	mut heading_selector := SidecarQuerySchemaFieldSelectorDto{}
	mut links_selector := SidecarQuerySchemaFieldSelectorDto{}
	for selector in dto.field_selectors {
		if selector.selector == 'heading_text:2' {
			heading_selector = selector
		}
		if selector.selector == 'links' {
			links_selector = selector
		}
	}
	assert heading_selector.plugin_name == 'markdown'
	assert heading_selector.value_type == 'string'
	assert heading_selector.index_names == ['body_heading_text_idx']
	assert heading_selector.projection_names.len == 0
	assert heading_selector.filter_ops == ['eq', 'prefix', 'after', 'before', 'between']
	assert heading_selector.planner_hints.len == 5
	assert heading_selector.planner_hints[0].op == 'eq'
	assert heading_selector.planner_hints[0].strategy == 'index_exact'
	assert heading_selector.planner_hints[0].index_name == 'body_heading_text_idx'
	assert heading_selector.filter_shapes.len == 5
	assert heading_selector.filter_shapes[1].op == 'prefix'
	assert heading_selector.filter_shapes[1].indexed
	assert heading_selector.filter_shapes[1].index_name == 'body_heading_text_idx'
	assert heading_selector.filter_shapes[1].continuation_anchor
	assert heading_selector.filter_shapes[1].sample_explain.strategy == 'index_prefix'
	assert heading_selector.filter_shapes[1].sample_explain.index_name == 'body_heading_text_idx'
	assert heading_selector.filter_shapes[1].sample_explain.warnings.len == 0

	assert links_selector.plugin_name == 'markdown'
	assert links_selector.value_type == 'i64'
	assert links_selector.projection_names == ['count(notes.body.links)']
	assert links_selector.filter_ops == ['eq', 'after', 'before', 'between']
	assert links_selector.planner_hints.len == 0
	assert links_selector.filter_shapes.len == 4
	assert links_selector.filter_shapes[0].op == 'eq'
	assert !links_selector.filter_shapes[0].indexed
	assert links_selector.filter_shapes[0].projection_only
	assert links_selector.filter_shapes[0].sample_explain.strategy == 'table_scan'
	assert links_selector.filter_shapes[0].sample_explain.warnings.any(it.contains('projection-only'))

	assert dto.projection_metrics.len == 1
	assert dto.projection_metrics[0].name == 'count(notes.body.links)'
	assert dto.projection_metrics[0].plugin_name == 'markdown'
	assert dto.projection_metrics[0].selector == 'links'
	assert dto.projection_metrics[0].value_type == 'i64'
	assert dto.projection_metrics[0].aggregate == 'sum'
}

fn test_sidecar_query_plan_preview_returns_expected_index_strategy() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-plan-preview-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-plan-preview')
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	db.register_table(spec) or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-plan-preview', 'alice', .reader) or {
		panic(err)
	}
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-plan-preview'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-plan-preview'
			branch_name: 'main'
			table_name: 'notes'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'body'
					plugin_name: 'markdown'
					selector: 'heading_text:2'
					query_kind: 'prefix'
					value: 'Road'
				},
				SidecarQueryFilterDto{
					column_name: 'title'
					query_kind: 'eq'
					value: 'Doc'
				},
			]
			select_columns: ['title']
			limit: 10
		})
	})
	assert response.status_code == 200
	dto := json.decode(SidecarQueryPlanPreviewDto, response.body) or { panic(err) }
	assert dto.table_name == 'notes'
	assert dto.default_result_shape == 'page'
	assert dto.supports_continuation_token
	assert dto.plan.strategy == 'index_prefix'
	assert dto.plan.index_name == 'body_heading_text_idx'
	assert dto.plan.index_filter.column_name == 'body'
	assert dto.plan.index_filter.plugin_name == 'markdown'
	assert dto.plan.index_filter.selector == 'heading_text:2'
	assert dto.plan.post_filter_count == 1
	assert dto.plan.post_filters.len == 1
	assert dto.plan.post_filters[0].column_name == 'title'
	assert dto.warnings.len == 0
	assert dto.notes.len >= 1
	assert dto.notes.any(it.contains('post-filters'))
	assert dto.explain.strategy == dto.plan.strategy
	assert dto.explain.index_name == dto.plan.index_name
	assert dto.explain.notes == dto.notes
}

fn test_sidecar_query_plan_preview_reports_projection_only_warning() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-plan-preview-projection-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-plan-preview-projection')
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_field_selector('count(notes.body.links)',
		'notes', 'body', 'markdown', 'links') or { panic(err) }) or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-plan-preview-projection', 'alice', .reader) or {
		panic(err)
	}
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-plan-preview'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-plan-preview-projection'
			branch_name: 'main'
			table_name: 'notes'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'body'
					plugin_name: 'markdown'
					selector: 'links'
					query_kind: 'eq'
					value: '1'
				},
			]
			select_columns: []string{}
			limit: 10
		})
	})
	assert response.status_code == 200
	dto := json.decode(SidecarQueryPlanPreviewDto, response.body) or { panic(err) }
	assert dto.plan.strategy == 'table_scan'
	assert dto.warnings.len >= 2
	assert dto.warnings.any(it.contains('table scan'))
	assert dto.warnings.any(it.contains('projection-only'))
	assert dto.explain.strategy == 'table_scan'
	assert dto.explain.warnings == dto.warnings
}

fn test_sidecar_query_returns_plain_index_query_plan_and_projection() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-rows-plain-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-plain')
	cfg := ChunkConfig.default()
	table := TableDef.new('users', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('name', .string_, false)!,
		ColumnDef.new('email', .string_, false)!,
	], ['id'])!
	spec := TypedTableSpec.new(table, [
		SchemaIndexDef.new('email', 'email')!,
	]) or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'seed')
	seed_row.set('name', 'Seed')
	seed_row.set('email', 'seed@example.com')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('seed'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', 'u1')
	row.set('name', 'Ada')
	row.set('email', 'ada@example.com')
	_ = session.put_row(mut db, 'users', 'u1'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'seed user'
		timestamp: 1
	}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-plain', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/query-rows?repo=team-query-plain&branch=main&table=users&column=email&kind=eq&value=ada@example.com&select=name'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarQueryRowsDto, response.body) or { panic(err) }
	assert dto.plan.strategy == 'index_exact'
	assert dto.plan.index_name == 'email'
	assert dto.plan.index_filter.column_name == 'email'
	assert dto.plan.index_filter.query_kind == 'eq'
	assert dto.plan.post_filters.len == 0
	assert dto.query_kind == 'eq'
	assert dto.rows.len == 1
	assert dto.rows[0].primary_key == 'u1'
	assert dto.rows[0].values['name'] == 'Ada'
	assert 'email' !in dto.rows[0].values
}

fn test_sidecar_query_returns_markdown_selector_query_plan() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-rows-markdown-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-markdown')
	cfg := ChunkConfig.default()
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Doc')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len: 0
	})
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body',
		'## Roadmap\n\nBody.\n', cfg, CommitMeta{
			author: 'gwg'
			message: 'markdown'
			timestamp: 2
		}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-markdown', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .get
		url: '/v1/query-rows?repo=team-query-markdown&branch=main&table=notes&column=body&plugin=markdown&selector=heading_text:2&kind=prefix&value=Road&limit=10'
		header: auth_header
	})
	assert response.status_code == 200
	dto := json.decode(SidecarQueryRowsDto, response.body) or { panic(err) }
	assert dto.plan.strategy == 'index_prefix'
	assert dto.plan.index_name == 'body_heading_text_idx'
	assert dto.plan.index_filter.column_name == 'body'
	assert dto.plan.index_filter.plugin_name == 'markdown'
	assert dto.plan.index_filter.selector == 'heading_text:2'
	assert dto.plan.index_filter.query_kind == 'prefix'
	assert dto.field_selector_meta.plugin_name == 'markdown'
	assert dto.field_selector_meta.selector == 'heading_text:2'
	assert dto.field_selector_meta.value_type == 'string'
	assert dto.query_kind == 'prefix'
	assert dto.rows.len == 1
	assert dto.rows[0].primary_key == 'note-1'
}

fn test_sidecar_query_post_supports_multiple_plain_filters() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-rows-post-plain-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-post-plain')
	cfg := ChunkConfig.default()
	table := TableDef.new('users', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('name', .string_, false)!,
		ColumnDef.new('email', .string_, false)!,
	], ['id'])!
	spec := TypedTableSpec.new(table, [
		SchemaIndexDef.new('email', 'email')!,
	]) or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'seed')
	seed_row.set('name', 'Seed')
	seed_row.set('email', 'seed@example.com')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('seed'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row1 := TypedRowData.new()
	row1.set('id', 'u1')
	row1.set('name', 'Ada')
	row1.set('email', 'ada@example.com')
	_ = session.put_row(mut db, 'users', 'u1'.bytes(), row1, cfg, CommitMeta{
		author: 'gwg'
		message: 'seed user 1'
		timestamp: 1
	}) or { panic(err) }
	mut row2 := TypedRowData.new()
	row2.set('id', 'u2')
	row2.set('name', 'Grace')
	row2.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', 'u2'.bytes(), row2, cfg, CommitMeta{
		author: 'gwg'
		message: 'seed user 2'
		timestamp: 2
	}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-post-plain', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-rows'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-post-plain'
			branch_name: 'main'
			table_name: 'users'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'email'
					query_kind: 'eq'
					value: 'ada@example.com'
				},
				SidecarQueryFilterDto{
					column_name: 'name'
					query_kind: 'eq'
					value: 'Ada'
				},
			]
			select_columns: ['name']
			limit: 10
		})
	})
	assert response.status_code == 200
	dto := json.decode(SidecarQueryRowsDto, response.body) or { panic(err) }
	assert dto.plan.strategy == 'index_exact'
	assert dto.plan.index_name == 'email'
	assert dto.plan.index_filter.column_name == 'email'
	assert dto.plan.index_filter.query_kind == 'eq'
	assert dto.plan.post_filters.len == 1
	assert dto.plan.post_filters[0].column_name == 'name'
	assert dto.plan.post_filters[0].query_kind == 'eq'
	assert dto.plan.post_filter_count == 1
	assert dto.rows.len == 1
	assert dto.rows[0].primary_key == 'u1'
	assert dto.rows[0].values['name'] == 'Ada'
}

fn test_sidecar_query_post_supports_mixed_selector_and_plain_filters() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-rows-post-mixed-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-post-mixed')
	cfg := ChunkConfig.default()
	spec := sidecar_markdown_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Doc')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len: 0
	})
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body',
		'## Roadmap\n\nBody.\n', cfg, CommitMeta{
			author: 'gwg'
			message: 'markdown'
			timestamp: 2
		}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-post-mixed', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-rows'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-post-mixed'
			branch_name: 'main'
			table_name: 'notes'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'body'
					plugin_name: 'markdown'
					selector: 'heading_text:2'
					query_kind: 'prefix'
					value: 'Road'
				},
				SidecarQueryFilterDto{
					column_name: 'title'
					query_kind: 'eq'
					value: 'Doc'
				},
			]
			select_columns: ['title']
			limit: 10
		})
	})
	assert response.status_code == 200
	dto := json.decode(SidecarQueryRowsDto, response.body) or { panic(err) }
	assert dto.plan.strategy == 'index_prefix'
	assert dto.plan.index_name == 'body_heading_text_idx'
	assert dto.plan.index_filter.column_name == 'body'
	assert dto.plan.index_filter.plugin_name == 'markdown'
	assert dto.plan.index_filter.selector == 'heading_text:2'
	assert dto.plan.index_filter.query_kind == 'prefix'
	assert dto.plan.post_filters.len == 1
	assert dto.plan.post_filters[0].column_name == 'title'
	assert dto.plan.post_filters[0].query_kind == 'eq'
	assert dto.plan.post_filter_count == 1
	assert dto.field_selector_meta.plugin_name == 'markdown'
	assert dto.field_selector_meta.selector == 'heading_text:2'
	assert dto.rows.len == 1
	assert dto.rows[0].primary_key == 'note-1'
	assert dto.rows[0].values['title'] == 'Doc'
}

fn test_sidecar_query_post_supports_between_filters() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-rows-post-between-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-post-between')
	cfg := ChunkConfig.default()
	table := TableDef.new('events', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.datetime('created_at', false)!,
	], ['id'])!
	spec := TypedTableSpec.new(table, [
		SchemaIndexDef.new('created_at_idx', 'created_at')!,
	]) or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'seed')
	seed_row.set('title', 'Seed')
	seed_row.set('created_at', '2026-01-01T00:00:00.000000Z')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'events').key_for('seed'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row1 := TypedRowData.new()
	row1.set('id', 'e1')
	row1.set('title', 'One')
	row1.set('created_at', '2026-01-01T00:00:00.000000Z')
	_ = session.put_row(mut db, 'events', 'e1'.bytes(), row1, cfg, CommitMeta{
		author: 'gwg'
		message: 'insert e1'
		timestamp: 1
	}) or { panic(err) }
	mut row2 := TypedRowData.new()
	row2.set('id', 'e2')
	row2.set('title', 'Two')
	row2.set('created_at', '2026-01-02T00:00:00.000000Z')
	_ = session.put_row(mut db, 'events', 'e2'.bytes(), row2, cfg, CommitMeta{
		author: 'gwg'
		message: 'insert e2'
		timestamp: 2
	}) or { panic(err) }
	mut row3 := TypedRowData.new()
	row3.set('id', 'e3')
	row3.set('title', 'Three')
	row3.set('created_at', '2026-01-03T00:00:00.000000Z')
	_ = session.put_row(mut db, 'events', 'e3'.bytes(), row3, cfg, CommitMeta{
		author: 'gwg'
		message: 'insert e3'
		timestamp: 3
	}) or { panic(err) }
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-post-between', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')
	response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-rows'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-post-between'
			branch_name: 'main'
			table_name: 'events'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'created_at'
					query_kind: 'between'
					value: '2026-01-02T00:00:00.000000Z'
					second_value: '2026-01-03T00:00:00.000000Z'
				},
			]
			select_columns: ['title']
			limit: 10
		})
	})
	assert response.status_code == 200
	dto := json.decode(SidecarQueryRowsDto, response.body) or { panic(err) }
	assert dto.plan.strategy == 'index_between'
	assert dto.plan.index_name == 'created_at_idx'
	assert dto.plan.index_filter.column_name == 'created_at'
	assert dto.plan.index_filter.query_kind == 'between'
	assert dto.plan.index_filter.second_value == '2026-01-03T00:00:00.000000Z'
	assert dto.plan.post_filters.len == 0
	assert dto.rows.len == 2
	assert dto.rows[0].primary_key == 'e2'
	assert dto.rows[1].primary_key == 'e3'
}

fn test_sidecar_query_rows_post_supports_primary_key_pagination() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-rows-pagination-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-pagination')
	cfg := ChunkConfig.default()
	table := TableDef.new('users', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('name', .string_, false)!,
		ColumnDef.new('email', .string_, false)!,
	], ['id'])!
	spec := TypedTableSpec.new(table, [
		SchemaIndexDef.new('email', 'email')!,
	]) or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'seed')
	seed_row.set('name', 'Seed')
	seed_row.set('email', 'seed@example.com')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('seed'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	for pair in [
		['001', 'Ada'],
		['002', 'Grace'],
		['003', 'Linus'],
	] {
		id := pair[0]
		name := pair[1]
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('name', name)
		row.set('email', '${name.to_lower()}@example.com')
		_ = session.put_row(mut db, 'users', id.bytes(), row, cfg, CommitMeta{
			author: 'gwg'
			message: 'insert ${id}'
			timestamp: 1
		}) or { panic(err) }
	}
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-pagination', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')

	first_response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-rows'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-pagination'
			branch_name: 'main'
			table_name: 'users'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'email'
					query_kind: 'prefix'
					value: ''
				},
			]
			limit: 2
		})
	})
	assert first_response.status_code == 200
	first_dto := json.decode(SidecarQueryRowsDto, first_response.body) or { panic(err) }
	assert first_dto.rows.len == 2
	assert first_dto.cursor.has_more
	assert first_dto.cursor.next_primary_key == '002'
	assert first_dto.cursor.next_index_value == 'grace@example.com'
	assert first_dto.has_more
	assert first_dto.next_primary_key == '002'
	assert first_dto.next_index_value == 'grace@example.com'

	second_response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-rows'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-pagination'
			branch_name: 'main'
			table_name: 'users'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'email'
					query_kind: 'prefix'
					value: ''
				},
			]
			start_primary_key: '002'
			start_index_value: 'grace@example.com'
			limit: 2
		})
	})
	assert second_response.status_code == 200
	second_dto := json.decode(SidecarQueryRowsDto, second_response.body) or { panic(err) }
	assert second_dto.rows.len == 1
	assert !second_dto.cursor.has_more
	assert !second_dto.has_more
	assert second_dto.rows[0].primary_key == '003'
}

fn test_sidecar_query_rows_post_supports_continuation_token() {
	root_dir := os.join_path(os.vtmp_dir(), 'polly-sidecar-query-rows-token-${rand.uuid_v4()}')
	defer {
		os.rmdir_all(root_dir) or {}
	}
	repo_root := sidecar_repo_root_dir(root_dir, 'team-query-token')
	cfg := ChunkConfig.default()
	table := TableDef.new('users', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('name', .string_, false)!,
		ColumnDef.new('email', .string_, false)!,
	], ['id'])!
	spec := TypedTableSpec.new(table, [
		SchemaIndexDef.new('email', 'email')!,
	]) or { panic(err) }
	mut db := PersistentDatabase.init(repo_root, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'seed')
	seed_row.set('name', 'Seed')
	seed_row.set('email', 'seed@example.com')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('seed'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	for pair in [
		['001', 'Ada'],
		['002', 'Grace'],
		['003', 'Linus'],
	] {
		id := pair[0]
		name := pair[1]
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('name', name)
		row.set('email', '${name.to_lower()}@example.com')
		_ = session.put_row(mut db, 'users', id.bytes(), row, cfg, CommitMeta{
			author: 'gwg'
			message: 'insert ${id}'
			timestamp: 1
		}) or { panic(err) }
	}
	db.close() or { panic(err) }

	init_pollyhub_governance(root_dir, 'alice', 'secret-token') or { panic(err) }
	grant_pollyhub_repo_access(root_dir, 'team-query-token', 'alice', .reader) or { panic(err) }
	handler := PollyLinkSidecarHandler{
		root_dir: root_dir
		default_branch: 'main'
	}
	mut auth_header := http.new_header()
	auth_header.add(.authorization, 'Bearer secret-token')

	first_response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-rows'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-token'
			branch_name: 'main'
			table_name: 'users'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'email'
					query_kind: 'prefix'
					value: ''
				},
			]
			limit: 2
		})
	})
	assert first_response.status_code == 200
	first_dto := json.decode(SidecarQueryRowsDto, first_response.body) or { panic(err) }
	assert first_dto.has_more
	assert first_dto.cursor.has_more
	assert first_dto.next_continuation_token.len > 0
	assert first_dto.cursor.next_continuation_token == first_dto.next_continuation_token

	second_response := handler.handle(http.Request{
		method: .post
		url: '/v1/query-rows'
		header: auth_header
		data: json.encode(SidecarQueryRowsPostRequestDto{
			repo_name: 'team-query-token'
			branch_name: 'main'
			table_name: 'users'
			filters: [
				SidecarQueryFilterDto{
					column_name: 'email'
					query_kind: 'prefix'
					value: ''
				},
			]
			continuation_token: first_dto.next_continuation_token
			limit: 2
		})
	})
	assert second_response.status_code == 200
	second_dto := json.decode(SidecarQueryRowsDto, second_response.body) or { panic(err) }
	assert second_dto.rows.len == 1
	assert second_dto.rows[0].primary_key == '003'
}

fn test_sidecar_query_page_struct_exposes_cursor() {
	rows := SidecarQueryRows{
		rows: [
			SidecarTypedRow{
				primary_key: '001'
				values: {
					'name': 'Ada'
				}
			},
		]
		plan: SidecarQueryPlan{
			strategy: 'index_exact'
			index_name: 'email'
			index_filter: SidecarQueryFilter{
				column_name: 'email'
				query_kind: 'eq'
				value: 'ada@example.com'
			}
			post_filters: []SidecarQueryFilter{}
			post_filter_count: 0
			limit: 10
		}
		cursor: SidecarQueryCursor{
			has_more: false
			next_primary_key: ''
			next_index_value: ''
			next_continuation_token: ''
		}
	}
	page := rows.page()
	assert page.rows.len == 1
	assert page.plan.index_name == 'email'
	assert !page.cursor.has_more
}

fn test_sidecar_query_page_struct_preserves_field_selector_meta() {
	rows := SidecarQueryRows{
		field_selector_meta: SidecarFieldSelectorMeta{
			plugin_name: 'markdown'
			selector: 'heading_text:2'
			value_type: 'string'
			stores_row: false
		}
		rows: [
			SidecarTypedRow{
				primary_key: 'note-1'
				values: {
					'title': 'Roadmap'
				}
			},
		]
		plan: SidecarQueryPlan{
			strategy: 'index_prefix'
			index_name: 'body_heading_text_idx'
			index_filter: SidecarQueryFilter{
				column_name: 'body'
				plugin_name: 'markdown'
				selector: 'heading_text:2'
				query_kind: 'prefix'
				value: 'Road'
			}
			post_filters: []SidecarQueryFilter{}
			post_filter_count: 0
			limit: 10
		}
		cursor: SidecarQueryCursor{
			has_more: false
			next_primary_key: ''
			next_index_value: ''
			next_continuation_token: ''
		}
	}
	page := rows.page()
	assert page.field_selector_meta.plugin_name == 'markdown'
	assert page.field_selector_meta.selector == 'heading_text:2'
	assert page.field_selector_meta.value_type == 'string'
}

fn test_sidecar_query_page_from_dto_exposes_cursor_and_selector_meta() {
	page := sidecar_query_page_from_dto(SidecarQueryRowsDto{
		branch_name: 'main'
		table_name: 'notes'
		column_name: 'body'
		plugin_name: 'markdown'
		selector: 'heading_text:2'
		field_selector_meta: SidecarFieldSelectorMetaDto{
			plugin_name: 'markdown'
			selector: 'heading_text:2'
			value_type: 'string'
			stores_row: false
		}
		query_kind: 'prefix'
		value: 'Road'
		plan: SidecarQueryPlanDto{
			strategy: 'index_prefix'
			index_name: 'body_heading_text_idx'
			index_filter: SidecarQueryFilterDto{
				column_name: 'body'
				plugin_name: 'markdown'
				selector: 'heading_text:2'
				query_kind: 'prefix'
				value: 'Road'
			}
			post_filters: []SidecarQueryFilterDto{}
			post_filter_count: 0
			limit: 10
		}
		cursor: SidecarQueryCursorDto{
			has_more: true
			next_primary_key: 'note-1'
			next_index_value: 'Roadmap'
			next_continuation_token: 'token'
		}
		rows: [
			SidecarTypedRowDto{
				primary_key: 'note-1'
				values: {
					'title': 'Roadmap'
				}
			},
		]
	})
	assert page.rows.len == 1
	assert page.plan.index_name == 'body_heading_text_idx'
	assert page.cursor.has_more
	assert page.cursor.next_primary_key == 'note-1'
	assert page.field_selector_meta.plugin_name == 'markdown'
	assert page.field_selector_meta.selector == 'heading_text:2'
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
