module pollyhub

import crypto.sha256
import json
import os

pub enum RepoRole {
	reader
	writer
	admin
}

pub struct TokenRecord {
pub mut:
	actor        string
	token_hash   string
	global_admin bool
}

pub struct RepoMembership {
pub mut:
	repo_name string
	actor     string
	role      RepoRole
}

pub struct RepoPolicy {
pub mut:
	repo_name             string
	allow_push_to_default bool = true
	require_auto_merge    bool
	default_sync_policy   string = 'auto'
}

pub struct BranchPolicy {
pub mut:
	repo_name           string
	branch_name         string
	allow_push          bool = true
	require_auto_merge  bool
	default_sync_policy string = 'auto'
}

pub struct RateLimitPolicy {
pub mut:
	requests_per_minute int
}

pub struct GovernanceFile {
pub mut:
	tokens          []TokenRecord
	memberships     []RepoMembership
	policies        []RepoPolicy
	branch_policies []BranchPolicy
	rate_limit      RateLimitPolicy
}

pub struct AuditEntry {
pub:
	timestamp   i64
	actor       string
	action      string
	repo_name   string
	branch_name string
	allowed     bool
	detail      string
}

pub struct ActionAuditSummary {
pub:
	action string
	total  int
	denies int
}

pub struct AuditCategorySummary {
pub:
	category string
	total    int
	denies   int
}

pub struct ActorAuditSummary {
pub:
	actor  string
	total  int
	denies int
}

pub struct RequestIdentity {
pub:
	auth_enabled bool
	actor        string
	global_admin bool
}

pub fn layout_dir(root_dir string) string {
	return os.join_path(root_dir, '.pollyhub')
}

pub fn governance_path(root_dir string) string {
	return os.join_path(layout_dir(root_dir), 'governance.json')
}

pub fn audit_log_path(root_dir string) string {
	return os.join_path(layout_dir(root_dir), 'audit.log')
}

pub fn hash_token(token string) string {
	return sha256.sum(token.bytes()).hex()
}

pub fn normalize_repo_name(repo_name string) string {
	name := repo_name.trim_space()
	if name.len == 0 || name == '.' {
		return '.'
	}
	return name
}

pub fn load_governance(root_dir string) !GovernanceFile {
	path := governance_path(root_dir)
	if !os.exists(path) {
		return GovernanceFile{}
	}
	return json.decode(GovernanceFile, os.read_file(path)!)
}

pub fn save_governance(root_dir string, governance GovernanceFile) ! {
	os.mkdir_all(layout_dir(root_dir))!
	os.write_file(governance_path(root_dir), json.encode(governance))!
}

pub fn auth_enabled(root_dir string) !bool {
	governance := load_governance(root_dir)!
	return governance.tokens.len > 0
}

pub fn init_governance(root_dir string, actor string, token string) ! {
	mut governance := GovernanceFile{}
	governance.tokens << TokenRecord{
		actor:        actor
		token_hash:   hash_token(token)
		global_admin: true
	}
	save_governance(root_dir, governance)!
}

pub fn grant_repo_access(root_dir string, repo_name string, actor string, role RepoRole) ! {
	mut governance := load_governance(root_dir)!
	normalized_repo := normalize_repo_name(repo_name)
	for idx, membership in governance.memberships {
		if membership.repo_name == normalized_repo && membership.actor == actor {
			governance.memberships[idx].role = role
			save_governance(root_dir, governance)!
			return
		}
	}
	governance.memberships << RepoMembership{
		repo_name: normalized_repo
		actor:     actor
		role:      role
	}
	save_governance(root_dir, governance)!
}

pub fn repo_policy(root_dir string, repo_name string) !RepoPolicy {
	governance := load_governance(root_dir)!
	normalized_repo := normalize_repo_name(repo_name)
	for policy in governance.policies {
		if policy.repo_name == normalized_repo {
			return policy
		}
	}
	return RepoPolicy{
		repo_name:             normalized_repo
		allow_push_to_default: true
		require_auto_merge:    false
		default_sync_policy:   'auto'
	}
}

pub fn set_repo_policy(root_dir string, repo_name string, allow_push_to_default bool, require_auto_merge bool, default_sync_policy string) ! {
	mut governance := load_governance(root_dir)!
	normalized_repo := normalize_repo_name(repo_name)
	for idx, policy in governance.policies {
		if policy.repo_name == normalized_repo {
			governance.policies[idx].allow_push_to_default = allow_push_to_default
			governance.policies[idx].require_auto_merge = require_auto_merge
			governance.policies[idx].default_sync_policy = default_sync_policy
			save_governance(root_dir, governance)!
			return
		}
	}
	governance.policies << RepoPolicy{
		repo_name:             normalized_repo
		allow_push_to_default: allow_push_to_default
		require_auto_merge:    require_auto_merge
		default_sync_policy:   default_sync_policy
	}
	save_governance(root_dir, governance)!
}

pub fn find_branch_policy(root_dir string, repo_name string, branch_name string) ?BranchPolicy {
	governance := load_governance(root_dir) or {
		return none
	}
	normalized_repo := normalize_repo_name(repo_name)
	for policy in governance.branch_policies {
		if policy.repo_name == normalized_repo && policy.branch_name == branch_name {
			return policy
		}
	}
	return none
}

pub fn set_branch_policy(root_dir string, repo_name string, branch_name string, allow_push bool, require_auto_merge bool, default_sync_policy string) ! {
	mut governance := load_governance(root_dir)!
	normalized_repo := normalize_repo_name(repo_name)
	for idx, policy in governance.branch_policies {
		if policy.repo_name == normalized_repo && policy.branch_name == branch_name {
			governance.branch_policies[idx].allow_push = allow_push
			governance.branch_policies[idx].require_auto_merge = require_auto_merge
			governance.branch_policies[idx].default_sync_policy = default_sync_policy
			save_governance(root_dir, governance)!
			return
		}
	}
	governance.branch_policies << BranchPolicy{
		repo_name:           normalized_repo
		branch_name:         branch_name
		allow_push:          allow_push
		require_auto_merge:  require_auto_merge
		default_sync_policy: default_sync_policy
	}
	save_governance(root_dir, governance)!
}

pub fn rate_limit_policy(root_dir string) !RateLimitPolicy {
	governance := load_governance(root_dir)!
	return governance.rate_limit
}

pub fn set_rate_limit_policy(root_dir string, requests_per_minute int) ! {
	mut governance := load_governance(root_dir)!
	governance.rate_limit = RateLimitPolicy{
		requests_per_minute: if requests_per_minute > 0 { requests_per_minute } else { 0 }
	}
	save_governance(root_dir, governance)!
}

fn find_identity(governance GovernanceFile, token string) ?RequestIdentity {
	hashed := hash_token(token)
	for record in governance.tokens {
		if record.token_hash == hashed {
			return RequestIdentity{
				auth_enabled: true
				actor:        record.actor
				global_admin: record.global_admin
			}
		}
	}
	return none
}

pub fn extract_bearer_token(authorization string) string {
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

pub fn authenticate_request(root_dir string, authorization string) !RequestIdentity {
	governance := load_governance(root_dir)!
	if governance.tokens.len == 0 {
		return RequestIdentity{
			auth_enabled: false
			actor:        'anonymous'
			global_admin: true
		}
	}
	token := extract_bearer_token(authorization)
	if token.len == 0 {
		return error('missing bearer token')
	}
	identity := find_identity(governance, token) or {
		return error('invalid bearer token')
	}
	return identity
}

pub fn role_allows(role RepoRole, action RepoRole) bool {
	return match action {
		.reader { true }
		.writer { role in [.writer, .admin] }
		.admin { role == .admin }
	}
}

pub fn authorize_repo_access(root_dir string, identity RequestIdentity, repo_name string, action RepoRole) ! {
	if !identity.auth_enabled || identity.global_admin {
		return
	}
	governance := load_governance(root_dir)!
	normalized_repo := normalize_repo_name(repo_name)
	for membership in governance.memberships {
		if membership.repo_name == normalized_repo && membership.actor == identity.actor {
			if role_allows(membership.role, action) {
				return
			}
			return error('repo access denied')
		}
	}
	return error('repo access denied')
}

pub fn append_audit_entry(root_dir string, entry AuditEntry) ! {
	os.mkdir_all(layout_dir(root_dir))!
	line := json.encode(entry) + '\n'
	mut file := os.open_append(audit_log_path(root_dir))!
	defer {
		file.close()
	}
	file.write_string(line)!
}

pub fn read_audit_entries(root_dir string, limit int) ![]AuditEntry {
	path := audit_log_path(root_dir)
	if !os.exists(path) {
		return []AuditEntry{}
	}
	lines := os.read_lines(path)!
	mut entries := []AuditEntry{}
	for line in lines {
		if line.trim_space().len == 0 {
			continue
		}
		entries << json.decode(AuditEntry, line)!
	}
	entries.sort(a.timestamp > b.timestamp)
	if limit > 0 && entries.len > limit {
		return entries[..limit].clone()
	}
	return entries
}

pub fn summarize_audit_since(root_dir string, since i64) ! (int, int) {
	entries := read_audit_entries(root_dir, 0)!
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

pub fn summarize_actor_audit_since(root_dir string, actor string, since i64) ! (int, int) {
	entries := read_audit_entries(root_dir, 0)!
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

pub fn summarize_audit_by_action_since(root_dir string, since i64) ![]ActionAuditSummary {
	entries := read_audit_entries(root_dir, 0)!
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
	mut rows := []ActionAuditSummary{}
	for action, total in totals {
		rows << ActionAuditSummary{
			action: action
			total:  total
			denies: denies[action]
		}
	}
	rows.sort_with_compare(fn (a &ActionAuditSummary, b &ActionAuditSummary) int {
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

fn audit_category_for_action(action string) string {
	return if action.starts_with('sync_') { 'sync' } else { 'control-plane' }
}

pub fn summarize_audit_by_category_since(root_dir string, since i64) ![]AuditCategorySummary {
	entries := read_audit_entries(root_dir, 0)!
	mut totals := map[string]int{}
	mut denies := map[string]int{}
	for entry in entries {
		if entry.timestamp < since {
			continue
		}
		category := audit_category_for_action(entry.action)
		totals[category] = totals[category] + 1
		if !entry.allowed {
			denies[category] = denies[category] + 1
		}
	}
	mut rows := []AuditCategorySummary{}
	for category, total in totals {
		rows << AuditCategorySummary{
			category: category
			total:    total
			denies:   denies[category]
		}
	}
	rows.sort_with_compare(fn (a &AuditCategorySummary, b &AuditCategorySummary) int {
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

pub fn summarize_audit_by_actor_since(root_dir string, since i64) ![]ActorAuditSummary {
	entries := read_audit_entries(root_dir, 0)!
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
	mut rows := []ActorAuditSummary{}
	for actor, total in totals {
		rows << ActorAuditSummary{
			actor:  actor
			total:  total
			denies: denies[actor]
		}
	}
	rows.sort_with_compare(fn (a &ActorAuditSummary, b &ActorAuditSummary) int {
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
