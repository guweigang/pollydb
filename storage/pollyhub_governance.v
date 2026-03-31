module storage

import crypto.sha256
import json
import os
import time

pub enum PollyHubRepoRole {
	reader
	writer
	admin
}

pub struct PollyHubTokenRecord {
pub mut:
	actor        string
	token_hash   string
	global_admin bool
}

pub struct PollyHubRepoMembership {
pub mut:
	repo_name string
	actor     string
	role      PollyHubRepoRole
}

pub struct PollyHubRepoPolicy {
pub mut:
	repo_name              string
	allow_push_to_default  bool = true
	require_auto_merge     bool
	default_sync_policy    string = 'auto'
}

pub struct PollyHubBranchPolicy {
pub mut:
	repo_name           string
	branch_name         string
	allow_push          bool = true
	require_auto_merge  bool
	default_sync_policy string = 'auto'
}

pub struct PollyHubRateLimitPolicy {
pub mut:
	requests_per_minute int
}

struct PollyHubGovernanceFile {
pub mut:
	tokens      []PollyHubTokenRecord
	memberships []PollyHubRepoMembership
	policies    []PollyHubRepoPolicy
	branch_policies []PollyHubBranchPolicy
	rate_limit PollyHubRateLimitPolicy
}

pub struct PollyHubAuditEntry {
pub:
	timestamp  i64
	actor      string
	action     string
	repo_name  string
	branch_name string
	allowed    bool
	detail     string
}

pub struct PollyHubActionAuditSummary {
pub:
	action string
	total  int
	denies int
}

pub struct PollyHubAuditCategorySummary {
pub:
	category string
	total    int
	denies   int
}

pub struct PollyHubActorAuditSummary {
pub:
	actor  string
	total  int
	denies int
}

pub struct PollyHubRequestIdentity {
pub:
	auth_enabled bool
	actor        string
	global_admin bool
}

fn pollyhub_layout_dir(root_dir string) string {
	return os.join_path(root_dir, '.pollyhub')
}

fn pollyhub_governance_path(root_dir string) string {
	return os.join_path(pollyhub_layout_dir(root_dir), 'governance.json')
}

fn pollyhub_audit_log_path(root_dir string) string {
	return os.join_path(pollyhub_layout_dir(root_dir), 'audit.log')
}

fn pollyhub_hash_token(token string) string {
	return sha256.sum(token.bytes()).hex()
}

fn pollyhub_normalize_repo_name(repo_name string) string {
	name := repo_name.trim_space()
	if name.len == 0 || name == '.' {
		return '.'
	}
	return name
}

pub fn load_pollyhub_governance(root_dir string) !PollyHubGovernanceFile {
	path := pollyhub_governance_path(root_dir)
	if !os.exists(path) {
		return PollyHubGovernanceFile{}
	}
	return json.decode(PollyHubGovernanceFile, os.read_file(path)!)
}

pub fn save_pollyhub_governance(root_dir string, governance PollyHubGovernanceFile) ! {
	os.mkdir_all(pollyhub_layout_dir(root_dir))!
	os.write_file(pollyhub_governance_path(root_dir), json.encode(governance))!
}

pub fn pollyhub_auth_enabled(root_dir string) !bool {
	governance := load_pollyhub_governance(root_dir)!
	return governance.tokens.len > 0
}

pub fn init_pollyhub_governance(root_dir string, actor string, token string) ! {
	mut governance := PollyHubGovernanceFile{}
	governance.tokens << PollyHubTokenRecord{
		actor: actor
		token_hash: pollyhub_hash_token(token)
		global_admin: true
	}
	save_pollyhub_governance(root_dir, governance)!
}

pub fn grant_pollyhub_repo_access(root_dir string, repo_name string, actor string, role PollyHubRepoRole) ! {
	mut governance := load_pollyhub_governance(root_dir)!
	normalized_repo := pollyhub_normalize_repo_name(repo_name)
	for idx, membership in governance.memberships {
		if membership.repo_name == normalized_repo && membership.actor == actor {
			governance.memberships[idx].role = role
			save_pollyhub_governance(root_dir, governance)!
			return
		}
	}
	governance.memberships << PollyHubRepoMembership{
		repo_name: normalized_repo
		actor: actor
		role: role
	}
	save_pollyhub_governance(root_dir, governance)!
}

pub fn pollyhub_repo_policy(root_dir string, repo_name string) !PollyHubRepoPolicy {
	governance := load_pollyhub_governance(root_dir)!
	normalized_repo := pollyhub_normalize_repo_name(repo_name)
	for policy in governance.policies {
		if policy.repo_name == normalized_repo {
			return policy
		}
	}
	return PollyHubRepoPolicy{
		repo_name: normalized_repo
		allow_push_to_default: true
		require_auto_merge: false
		default_sync_policy: 'auto'
	}
}

pub fn set_pollyhub_repo_policy(root_dir string, repo_name string, allow_push_to_default bool, require_auto_merge bool, default_sync_policy string) ! {
	mut governance := load_pollyhub_governance(root_dir)!
	normalized_repo := pollyhub_normalize_repo_name(repo_name)
	for idx, policy in governance.policies {
		if policy.repo_name == normalized_repo {
			governance.policies[idx].allow_push_to_default = allow_push_to_default
			governance.policies[idx].require_auto_merge = require_auto_merge
			governance.policies[idx].default_sync_policy = default_sync_policy
			save_pollyhub_governance(root_dir, governance)!
			return
		}
	}
	governance.policies << PollyHubRepoPolicy{
		repo_name: normalized_repo
		allow_push_to_default: allow_push_to_default
		require_auto_merge: require_auto_merge
		default_sync_policy: default_sync_policy
	}
	save_pollyhub_governance(root_dir, governance)!
}

pub fn find_pollyhub_branch_policy(root_dir string, repo_name string, branch_name string) ?PollyHubBranchPolicy {
	governance := load_pollyhub_governance(root_dir) or {
		return none
	}
	normalized_repo := pollyhub_normalize_repo_name(repo_name)
	for policy in governance.branch_policies {
		if policy.repo_name == normalized_repo && policy.branch_name == branch_name {
			return policy
		}
	}
	return none
}

pub fn set_pollyhub_branch_policy(root_dir string, repo_name string, branch_name string, allow_push bool, require_auto_merge bool, default_sync_policy string) ! {
	mut governance := load_pollyhub_governance(root_dir)!
	normalized_repo := pollyhub_normalize_repo_name(repo_name)
	for idx, policy in governance.branch_policies {
		if policy.repo_name == normalized_repo && policy.branch_name == branch_name {
			governance.branch_policies[idx].allow_push = allow_push
			governance.branch_policies[idx].require_auto_merge = require_auto_merge
			governance.branch_policies[idx].default_sync_policy = default_sync_policy
			save_pollyhub_governance(root_dir, governance)!
			return
		}
	}
	governance.branch_policies << PollyHubBranchPolicy{
		repo_name: normalized_repo
		branch_name: branch_name
		allow_push: allow_push
		require_auto_merge: require_auto_merge
		default_sync_policy: default_sync_policy
	}
	save_pollyhub_governance(root_dir, governance)!
}

pub fn pollyhub_rate_limit_policy(root_dir string) !PollyHubRateLimitPolicy {
	governance := load_pollyhub_governance(root_dir)!
	return governance.rate_limit
}

pub fn set_pollyhub_rate_limit_policy(root_dir string, requests_per_minute int) ! {
	mut governance := load_pollyhub_governance(root_dir)!
	governance.rate_limit = PollyHubRateLimitPolicy{
		requests_per_minute: if requests_per_minute > 0 { requests_per_minute } else { 0 }
	}
	save_pollyhub_governance(root_dir, governance)!
}

fn pollyhub_find_identity(governance PollyHubGovernanceFile, token string) ?PollyHubRequestIdentity {
	hashed := pollyhub_hash_token(token)
	for record in governance.tokens {
		if record.token_hash == hashed {
			return PollyHubRequestIdentity{
				auth_enabled: true
				actor: record.actor
				global_admin: record.global_admin
			}
		}
	}
	return none
}

fn pollyhub_extract_bearer_token(authorization string) string {
	value := authorization.trim_space()
	if value.len == 0 {
		return ''
	}
	lower := value.to_lower()
	if !lower.starts_with('bearer ') {
		return ''
	}
	return value[7..].trim_space()
}

pub fn authenticate_pollyhub_request(root_dir string, authorization string) !PollyHubRequestIdentity {
	governance := load_pollyhub_governance(root_dir)!
	if governance.tokens.len == 0 {
		return PollyHubRequestIdentity{
			auth_enabled: false
			actor: 'anonymous'
			global_admin: true
		}
	}
	token := pollyhub_extract_bearer_token(authorization)
	if token.len == 0 {
		return error('missing bearer token')
	}
	identity := pollyhub_find_identity(governance, token) or {
		return error('invalid bearer token')
	}
	return identity
}

fn pollyhub_role_allows(role PollyHubRepoRole, action PollyHubRepoRole) bool {
	return match action {
		.reader { true }
		.writer { role in [.writer, .admin] }
		.admin { role == .admin }
	}
}

pub fn authorize_pollyhub_repo_access(root_dir string, identity PollyHubRequestIdentity, repo_name string, action PollyHubRepoRole) ! {
	if !identity.auth_enabled || identity.global_admin {
		return
	}
	governance := load_pollyhub_governance(root_dir)!
	normalized_repo := pollyhub_normalize_repo_name(repo_name)
	for membership in governance.memberships {
		if membership.repo_name == normalized_repo && membership.actor == identity.actor {
			if pollyhub_role_allows(membership.role, action) {
				return
			}
			return error('repo access denied')
		}
	}
	return error('repo access denied')
}

pub fn list_pollyhub_authorized_repositories(root_dir string, identity PollyHubRequestIdentity) ![]string {
	names := list_sidecar_repositories(root_dir)!
	if !identity.auth_enabled || identity.global_admin {
		return names
	}
	governance := load_pollyhub_governance(root_dir)!
	mut allowed := []string{}
	for name in names {
		normalized_name := pollyhub_normalize_repo_name(name)
		for membership in governance.memberships {
			if membership.actor == identity.actor && membership.repo_name == normalized_name {
				allowed << name
				break
			}
		}
	}
	allowed.sort()
	return allowed
}

pub fn append_pollyhub_audit_entry(root_dir string, entry PollyHubAuditEntry) ! {
	os.mkdir_all(pollyhub_layout_dir(root_dir))!
	line := json.encode(entry) + '\n'
	mut file := os.open_append(pollyhub_audit_log_path(root_dir))!
	defer {
		file.close()
	}
	file.write_string(line)!
}

pub fn read_pollyhub_audit_entries(root_dir string, limit int) ![]PollyHubAuditEntry {
	path := pollyhub_audit_log_path(root_dir)
	if !os.exists(path) {
		return []PollyHubAuditEntry{}
	}
	lines := os.read_lines(path)!
	mut entries := []PollyHubAuditEntry{}
	for line in lines {
		if line.trim_space().len == 0 {
			continue
		}
		entries << json.decode(PollyHubAuditEntry, line)!
	}
	entries.sort(a.timestamp > b.timestamp)
	if limit > 0 && entries.len > limit {
		return entries[..limit].clone()
	}
	return entries
}

pub fn summarize_pollyhub_audit_since(root_dir string, since i64) ! (int, int) {
	entries := read_pollyhub_audit_entries(root_dir, 0)!
	mut total := 0
	mut denies := 0
	for entry in entries {
		if entry.timestamp < since {
			continue
		}
		total++
		if !entry.allowed {
			denies++
		}
	}
	return total, denies
}

pub fn summarize_pollyhub_actor_audit_since(root_dir string, actor string, since i64) ! (int, int) {
	entries := read_pollyhub_audit_entries(root_dir, 0)!
	mut total := 0
	mut denies := 0
	for entry in entries {
		if entry.timestamp < since || entry.actor != actor {
			continue
		}
		total++
		if !entry.allowed {
			denies++
		}
	}
	return total, denies
}

pub fn summarize_pollyhub_audit_by_action_since(root_dir string, since i64) ![]PollyHubActionAuditSummary {
	entries := read_pollyhub_audit_entries(root_dir, 0)!
	mut totals := map[string]int{}
	mut denies := map[string]int{}
	for entry in entries {
		if entry.timestamp < since {
			continue
		}
		totals[entry.action] = totals[entry.action] + 1
		if !entry.allowed {
			denies[entry.action] = denies[entry.action] + 1
		}
	}
	mut rows := []PollyHubActionAuditSummary{}
	for action, total in totals {
		rows << PollyHubActionAuditSummary{
			action: action
			total: total
			denies: denies[action]
		}
	}
	rows.sort_with_compare(fn (a &PollyHubActionAuditSummary, b &PollyHubActionAuditSummary) int {
		if a.total != b.total {
			return if a.total > b.total { -1 } else { 1 }
		}
		if a.denies != b.denies {
			return if a.denies > b.denies { -1 } else { 1 }
		}
		return if a.action < b.action { -1 } else if a.action > b.action { 1 } else { 0 }
	})
	return rows
}

fn pollyhub_audit_category_for_action(action string) string {
	return if action.starts_with('sync_') {
		'sync'
	} else {
		'control-plane'
	}
}

pub fn summarize_pollyhub_audit_by_category_since(root_dir string, since i64) ![]PollyHubAuditCategorySummary {
	entries := read_pollyhub_audit_entries(root_dir, 0)!
	mut totals := map[string]int{}
	mut denies := map[string]int{}
	for entry in entries {
		if entry.timestamp < since {
			continue
		}
		category := pollyhub_audit_category_for_action(entry.action)
		totals[category] = totals[category] + 1
		if !entry.allowed {
			denies[category] = denies[category] + 1
		}
	}
	mut rows := []PollyHubAuditCategorySummary{}
	for category, total in totals {
		rows << PollyHubAuditCategorySummary{
			category: category
			total: total
			denies: denies[category]
		}
	}
	rows.sort_with_compare(fn (a &PollyHubAuditCategorySummary, b &PollyHubAuditCategorySummary) int {
		if a.total != b.total {
			return if a.total > b.total { -1 } else { 1 }
		}
		if a.denies != b.denies {
			return if a.denies > b.denies { -1 } else { 1 }
		}
		return if a.category < b.category { -1 } else if a.category > b.category { 1 } else { 0 }
	})
	return rows
}

pub fn summarize_pollyhub_audit_by_actor_since(root_dir string, since i64) ![]PollyHubActorAuditSummary {
	entries := read_pollyhub_audit_entries(root_dir, 0)!
	mut totals := map[string]int{}
	mut denies := map[string]int{}
	for entry in entries {
		if entry.timestamp < since {
			continue
		}
		totals[entry.actor] = totals[entry.actor] + 1
		if !entry.allowed {
			denies[entry.actor] = denies[entry.actor] + 1
		}
	}
	mut rows := []PollyHubActorAuditSummary{}
	for actor, total in totals {
		rows << PollyHubActorAuditSummary{
			actor: actor
			total: total
			denies: denies[actor]
		}
	}
	rows.sort_with_compare(fn (a &PollyHubActorAuditSummary, b &PollyHubActorAuditSummary) int {
		if a.total != b.total {
			return if a.total > b.total { -1 } else { 1 }
		}
		if a.denies != b.denies {
			return if a.denies > b.denies { -1 } else { 1 }
		}
		return if a.actor < b.actor { -1 } else if a.actor > b.actor { 1 } else { 0 }
	})
	return rows
}

fn pollyhub_now_unix() i64 {
	return time.now().unix()
}
