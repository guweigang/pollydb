module main

import os
import memory
import pollylink
import query as queryapi
import storage
import term

struct PollyDbCli {
mut:
	args []string
}

struct CliRootContext {
	root_dir       string
	default_branch string
	branches       []string
	next_idx       int
}

struct CliDbContext {
	root_dir       string
	default_branch string
	branch         string
	next_idx       int
}

struct CliSyncPeerContext {
	root_dir       string
	default_branch string
	branch         string
	next_idx       int
}

struct CliField {
	label string
	value string
}

struct CliSyncExecution {
	session  storage.SyncSession
	exchange storage.SyncExchange
	policy   storage.SyncNegotiationPolicy
}

fn PollyDbCli.new(args []string) PollyDbCli {
	mut normalized := args.clone()
	if normalized.len > 0 && normalized[0] == '--' {
		normalized = normalized[1..].clone()
	}
	return PollyDbCli{
		args: normalized
	}
}

fn cli_repository_metadata_path(root_dir string) string {
	return os.join_path(root_dir, '.pollydb', 'repo.meta')
}

fn cli_repository_layout_dir(root_dir string) string {
	return os.join_path(root_dir, '.pollydb')
}

fn cli_has_repository(root_dir string) bool {
	return os.exists(cli_repository_metadata_path(root_dir))
}

fn cli_has_repository_layout(root_dir string) bool {
	return os.is_dir(cli_repository_layout_dir(root_dir))
}

fn cli_looks_like_path(raw string) bool {
	return raw.starts_with('/') || raw.starts_with('./') || raw.starts_with('../')
		|| raw.contains('/')
}

fn cli_looks_like_url(raw string) bool {
	return raw.starts_with('http://') || raw.starts_with('https://')
}

fn cli_sidecar_auth_token() string {
	return os.getenv('POLLYHUB_TOKEN')
}

fn cli_open_repository(root_dir string) !storage.Repository {
	return storage.Repository.open(cli_repository_metadata_path(root_dir))
}

fn cli_title(text string) string {
	cols, _ := term.get_terminal_size()
	width := if cols > 0 { cols } else { 80 }
	label := term.bold(term.bright_cyan(text))
	plain := term.strip_ansi(text)
	prefix := '── '
	suffix_gap := ' '
	mut remaining := width - prefix.len - suffix_gap.len - plain.len
	if remaining < 8 {
		remaining = 8
	}
	return '${cli_dim(prefix)}${label}${suffix_gap}${cli_dim('─'.repeat(remaining))}'
}

fn cli_dim(text string) string {
	return term.bright_black(text)
}

fn cli_success(text string) string {
	return term.bright_green(text)
}

fn cli_warn(text string) string {
	return term.bright_yellow(text)
}

fn cli_info(text string) string {
	return term.bright_blue(text)
}

fn cli_empty(label string, detail string) string {
	mut fields := [
		CliField{'status', cli_dim(label)},
	]
	if detail.len > 0 {
		fields << CliField{'detail', cli_dim(detail)}
	}
	return cli_render_fields('Empty', fields)
}

fn cli_pad_right(text string, width int) string {
	plain := term.strip_ansi(text)
	if plain.len >= width {
		return plain
	}
	return plain + ' '.repeat(width - plain.len)
}

fn cli_truncate(text string, width int) string {
	plain := term.strip_ansi(text)
	if width <= 0 {
		return ''
	}
	if plain.len <= width {
		return plain
	}
	if width <= 1 {
		return plain[..width]
	}
	if width <= 10 {
		return plain[..width - 1] + '…'
	}
	left := (width - 1) / 2
	right := width - 1 - left
	return plain[..left] + '…' + plain[plain.len - right..]
}

fn cli_fit_cell(text string, width int) string {
	return cli_pad_right(cli_truncate(text, width), width)
}

fn cli_render_table(headers []string, rows [][]string) string {
	if headers.len == 0 {
		return ''
	}
	cols, _ := term.get_terminal_size()
	max_width := if cols > 0 { cols } else { 100 }
	mut widths := []int{len: headers.len}
	for idx, header in headers {
		widths[idx] = term.strip_ansi(header).len
	}
	for row in rows {
		for idx, cell in row {
			plain_len := term.strip_ansi(cell).len
			if idx < widths.len && plain_len > widths[idx] {
				widths[idx] = plain_len
			}
		}
	}
	min_col_width := 6
	mut total_width := 1
	for width in widths {
		total_width += width + 3
	}
	for total_width > max_width {
		mut widest_idx := -1
		mut widest := 0
		for idx, width in widths {
			if width > widest && width > min_col_width {
				widest = width
				widest_idx = idx
			}
		}
		if widest_idx < 0 {
			break
		}
		widths[widest_idx]--
		total_width--
	}
	mut segments := []string{cap: widths.len}
	for width in widths {
		segments << '─'.repeat(width + 2)
	}
	top := '┌' + segments.join('┬') + '┐'
	sep := '├' + segments.join('┼') + '┤'
	bottom := '└' + segments.join('┴') + '┘'
	mut lines := []string{}
	lines << cli_dim(top)
	mut header_cells := []string{cap: headers.len}
	for idx, header in headers {
		header_cells << ' ' + term.bold(cli_fit_cell(header, widths[idx])) + ' '
	}
	lines << '│' + header_cells.join('│') + '│'
	lines << cli_dim(sep)
	for row in rows {
		mut cells := []string{cap: headers.len}
		for idx in 0 .. headers.len {
			cell := if idx < row.len { row[idx] } else { '' }
			cells << ' ' + cli_fit_cell(cell, widths[idx]) + ' '
		}
		lines << '│' + cells.join('│') + '│'
	}
	lines << cli_dim(bottom)
	return lines.join('\n')
}

fn cli_render_fields(title string, fields []CliField) string {
	mut width := 0
	for field in fields {
		if field.label.len > width {
			width = field.label.len
		}
	}
	mut lines := []string{}
	if title.len > 0 {
		lines << cli_title(title)
	}
	for field in fields {
		lines << '${term.bold(cli_pad_right(field.label, width))}  ${field.value}'
	}
	return lines.join('\n')
}

fn cli_render_field_card(title string, fields []CliField) string {
	if fields.len == 0 {
		return cli_render_fields(title, fields)
	}
	mut label_width := 0
	mut value_width := 0
	for field in fields {
		if field.label.len > label_width {
			label_width = field.label.len
		}
		value_len := term.strip_ansi(field.value).len
		if value_len > value_width {
			value_width = value_len
		}
	}
	label_width = if label_width < 10 { 10 } else { label_width }
	value_width = if value_width < 8 { 8 } else { value_width }
	mut lines := []string{}
	if title.len > 0 {
		lines << cli_title(title)
	}
	top := '┌' + '─'.repeat(label_width + 2) + '┬' + '─'.repeat(value_width + 2) + '┐'
	sep := '├' + '─'.repeat(label_width + 2) + '┼' + '─'.repeat(value_width + 2) + '┤'
	bottom := '└' + '─'.repeat(label_width + 2) + '┴' + '─'.repeat(value_width + 2) + '┘'
	lines << cli_dim(top)
	for idx, field in fields {
		label := term.bold(cli_pad_right(field.label, label_width))
		value := cli_fit_cell(field.value, value_width)
		lines << '│ ${label} │ ${value} │'
		if idx < fields.len - 1 {
			lines << cli_dim(sep)
		}
	}
	lines << cli_dim(bottom)
	return lines.join('\n')
}

fn cli_render_rows(title string, spec storage.TypedTableSpec, rows []storage.TypedSchemaRow) string {
	mut headers := ['pk']
	for column in spec.table.columns {
		headers << column.name
	}
	mut table_rows := [][]string{cap: rows.len}
	for row in rows {
		mut cells := []string{cap: headers.len}
		cells << row.primary_key.bytestr()
		for column in spec.table.columns {
			if !row.data.has(column.name) {
				cells << '<unset>'
				continue
			}
			value := row.data.get(column.name) or {
				cells << '<unset>'
				continue
			}
			cells << format_column_value(value)
		}
		table_rows << cells
	}
	mut lines := []string{}
	if title.len > 0 {
		lines << cli_title(title)
	}
	lines << cli_render_table(headers, table_rows)
	return lines.join('\n')
}

fn cli_render_query_rows(title string, spec storage.TypedTableSpec, rows []queryapi.QueryRow) string {
	mut headers := ['pk']
	for column in spec.table.columns {
		headers << column.name
	}
	mut table_rows := [][]string{cap: rows.len}
	for row in rows {
		mut cells := []string{cap: headers.len}
		cells << row.primary_key.bytestr()
		for column in spec.table.columns {
			if !row.data.has(column.name) {
				cells << '<unset>'
				continue
			}
			value := row.data.get(column.name) or {
				cells << '<unset>'
				continue
			}
			cells << value.display_string()
		}
		table_rows << cells
	}
	mut lines := []string{}
	if title.len > 0 {
		lines << cli_title(title)
	}
	lines << cli_render_table(headers, table_rows)
	return lines.join('\n')
}

fn cli_render_status_report(report storage.PersistentDatabaseStatusReport) string {
	mut lines := []string{}
	lines << cli_render_field_card('Repository', [
		CliField{'root', report.root_dir},
		CliField{'default_branch', report.default_branch},
		CliField{'catalog', if report.catalog_exists {
			cli_success('present')
		} else {
			cli_warn('missing')
		}},
		CliField{'repository', if report.repository_exists {
			cli_success('present')
		} else {
			cli_warn('missing')
		}},
		CliField{'branches', report.branch_count.str()},
		CliField{'tables', report.registered_tables.str()},
		CliField{'projectors', report.registered_projectors.str()},
	])
	lines << ''
	lines << cli_render_field_card('Durability', [
		CliField{'data_durable', if report.data_durable {
			cli_success('true')
		} else {
			cli_warn('false')
		}},
		CliField{'index_snapshots_fresh', if report.index_snapshots_fresh {
			cli_success('true')
		} else {
			cli_warn('false')
		}},
		CliField{'checkpoint_journal', if report.checkpoint_journal_exists {
			cli_warn('present')
		} else {
			cli_dim('none')
		}},
		CliField{'node_index_entries', report.node_index_entries.str()},
		CliField{'commit_index_entries', report.commit_index_entries.str()},
	])
	if report.branches.len > 0 {
		lines << ''
		mut branch_rows := [][]string{cap: report.branches.len}
		for branch in report.branches {
			branch_rows << [branch]
		}
		lines << cli_title('Branches')
		lines << cli_render_table(['name'], branch_rows)
	}
	return lines.join('\n')
}

fn cli_render_commit(title string, commit storage.Commit) string {
	return cli_render_field_card(title, [
		CliField{'commit', commit.cid},
		CliField{'root', commit.root_cid},
		CliField{'parents', commit.parent_cids.len.str()},
		CliField{'author', commit.meta.author},
		CliField{'message', commit.meta.message},
		CliField{'timestamp', commit.meta.timestamp.str()},
	])
}

fn cli_render_merge_preview(preview storage.RootHashMergePreview) string {
	mut lines := []string{}
	lines << cli_render_field_card('Merge Preview', [
		CliField{'ours_branch', preview.ours_branch},
		CliField{'theirs_branch', preview.theirs_branch},
		CliField{'base_commit', preview.base_commit_cid},
		CliField{'base_root', preview.base_root_cid},
		CliField{'ours_commit', preview.ours_commit_cid},
		CliField{'ours_root', preview.ours_root_cid},
		CliField{'theirs_commit', preview.theirs_commit_cid},
		CliField{'theirs_root', preview.theirs_root_cid},
		CliField{'fast_forward', preview.fast_forward.str()},
		CliField{'ours_unchanged', preview.ours_unchanged.str()},
		CliField{'theirs_unchanged', preview.theirs_unchanged.str()},
		CliField{'conflicts', preview.conflicts.str()},
		CliField{'changed_keys', preview.changed_keys.str()},
		CliField{'changed_subtrees', preview.changed_subtrees.str()},
	])
	return lines.join('\n')
}

fn cli_render_merge_report(report storage.RootHashMergeReport) string {
	mut lines := []string{}
	lines << cli_render_merge_preview(report.preview)
	if report.table_stats.len > 0 {
		mut table_rows := [][]string{cap: report.table_stats.len}
		for stat in report.table_stats {
			table_rows << [
				stat.table_name,
				stat.row_changes.str(),
				stat.index_changes.str(),
				stat.conflict_changes.str(),
			]
		}
		lines << ''
		lines << cli_title('Table Changes')
		lines << cli_render_table(['table', 'row_changes', 'index_changes', 'conflicts'],
			table_rows)
	}
	if report.conflict_keys.len > 0 {
		mut conflict_rows := [][]string{cap: report.conflict_keys.len}
		for conflict in report.conflict_keys {
			conflict_rows << [
				conflict.key,
				if conflict.table_name.len > 0 { conflict.table_name } else { '-' },
				if conflict.index_name.len > 0 { conflict.index_name } else { '-' },
			]
		}
		lines << ''
		lines << cli_title('Conflict Preview')
		lines << cli_render_table(['key', 'table', 'index'], conflict_rows)
	}
	return lines.join('\n')
}

fn (cli PollyDbCli) usage() string {
	return 'Usage:
  pollydb init [root_dir] [branch]
  pollydb checkpoint [root_dir] [branch] [mode]
  pollydb refresh-index-snapshots [root_dir] [branch]
  pollydb sync-push [root_dir] [branch] <peer_root_dir> [peer_branch] [policy]
  pollydb sync-pull [root_dir] [branch] <peer_root_dir> [peer_branch] [policy]
  pollydb recommend-sync-policy [root_dir] [branch] <peer_root_dir> [peer_branch] [simulated_rtt_ms]
  pollydb sync-push-sidecar [root_dir] [branch] <sidecar_url> [target_branch] [policy]
  pollydb sync-pull-sidecar [root_dir] [branch] <sidecar_url> [source_branch] [policy]
  pollydb sidecar-repos <sidecar_url>
  pollydb sidecar-repo-summaries <sidecar_url> [limit]
  pollydb sidecar-global-activity <sidecar_url> [limit]
  pollydb sidecar-open-repo <sidecar_url> <repo_name> [default_branch]
  pollydb sidecar-governance-status <sidecar_url>
  pollydb sidecar-branches <sidecar_url> [repo_name]
  pollydb sidecar-branch-status <sidecar_url> [repo_name] <branch>
  pollydb sidecar-init-governance <storage_root> <actor> <token>
  pollydb sidecar-grant-repo <storage_root> <repo_name> <actor> <role>
  pollydb sidecar-set-repo-policy <storage_root> <repo_name> <allow_push_to_default> <require_auto_merge> [default_sync_policy]
  pollydb sidecar-set-branch-policy <storage_root> <repo_name> <branch_name> <allow_push> <require_auto_merge> [default_sync_policy]
  pollydb sidecar-set-rate-limit <storage_root> <requests_per_minute>
  pollydb sidecar-audit-log <storage_root> [limit]
  pollydb sidecar-repo-activity <sidecar_url> [repo_name] [limit]
  pollydb sidecar-branch-activity <sidecar_url> [repo_name] <branch>
  pollydb sidecar-branch-log <sidecar_url> [repo_name] <branch> [limit]
  pollydb status [root_dir] [branch]
  pollydb inspect [root_dir] [branch]
  pollydb branches [root_dir] [branch]
  pollydb create-branch [root_dir] <new_branch> [from_branch]
  pollydb checkout [root_dir] [branch]
  pollydb show-branch [root_dir] [branch]
  pollydb log [root_dir] [branch] [limit]
  pollydb merge-base [root_dir] <left_branch> <right_branch>
  pollydb merge-preview [root_dir] <ours_branch> <theirs_branch>
  pollydb merge-report [root_dir] <ours_branch> <theirs_branch> [conflict_limit]
  pollydb merge-branch [root_dir] <ours_branch> <theirs_branch> [strategy]
  pollydb tables [root_dir] [branch]
  pollydb describe-table [root_dir] [branch] <table_name>
  pollydb export-catalog [root_dir] [branch]
  pollydb register-table [root_dir] [branch] <table_name> <primary_key_csv> <columns_csv> [indexes_csv]
  pollydb create-table [root_dir] [branch] <table_name> <primary_key_csv> <columns_csv> [indexes_csv]
  pollydb rebuild-indexes [root_dir] [branch] [tables_csv]
  pollydb projectors [root_dir] [branch]
  pollydb register-aggregate-projection [root_dir] [branch] <name> <table_name> <column_name> [json_path] [priority] [cost_hint]
  pollydb refresh-aggregate-projections [root_dir] [branch] [policy] [limit]
  pollydb put-row [root_dir] [branch] <table_name> <primary_key> <field_values_csv>
  pollydb set-json-path [root_dir] [branch] <table_name> <primary_key> <json_column> <json_path> <value_type> <value>
  pollydb null-json-path [root_dir] [branch] <table_name> <primary_key> <json_column> <json_path>
  pollydb delete-json-path [root_dir] [branch] <table_name> <primary_key> <json_column> <json_path>
  pollydb patch-json-paths [root_dir] [branch] <table_name> <primary_key> <json_column> <updates_csv>
  pollydb get-row [root_dir] [branch] <table_name> <primary_key>
  pollydb delete-row [root_dir] [branch] <table_name> <primary_key>
  pollydb count-rows [root_dir] [branch] <table_name>
  pollydb count-rows-range [root_dir] [branch] <table_name> <start_primary_key> <end_primary_key>
  pollydb sum-column [root_dir] [branch] <table_name> <column_name>
  pollydb sum-column-range [root_dir] [branch] <table_name> <column_name> <start_primary_key> <end_primary_key>
  pollydb scan-table [root_dir] [branch] <table_name> [limit]
  pollydb lookup-index [root_dir] [branch] <table_name> <index_name> <value> [limit]
  pollydb scan-index-between [root_dir] [branch] <table_name> <index_name> <start_value> <end_value> [limit]
  pollydb scan-index-after [root_dir] [branch] <table_name> <index_name> <value> [limit]
  pollydb scan-index-before [root_dir] [branch] <table_name> <index_name> <value> [limit]
  pollydb scan-index [root_dir] [branch] <table_name> <index_name> <value> [start_primary_key] [limit]
  pollydb prefix-index [root_dir] [branch] <table_name> <index_name> <prefix> [limit]
  pollydb prefix-index-projected [root_dir] [branch] <table_name> <index_name> <prefix> <columns_csv> [limit]
  pollydb query-fts-preview [root_dir] [branch] <table_name> <column_name> <scope> <kind> <terms_csv> [select_columns_csv] [limit]
  pollydb query-fts [root_dir] [branch] <table_name> <column_name> <scope> <kind> <terms_csv> [select_columns_csv] [limit]

Repository:
  init     Initialize a pollydb repository if needed and print its status.
  checkpoint  Persist the current durable boundary and print its status.
  refresh-index-snapshots  Publish the latest sidecar index snapshots without forcing a full checkpoint.
  sync-push  Push one branch into another local pollydb repository using Polly-Sync.
  sync-pull  Pull one branch from another local pollydb repository using Polly-Sync.
  recommend-sync-policy  Estimate the best Polly-Sync negotiation policy for a peer repository.
  sync-push-sidecar  Push one branch into a Polly-Link Sidecar-backed repository.
  sync-pull-sidecar  Pull one branch from a Polly-Link Sidecar-backed repository.
  sidecar-repos  List repositories currently hosted by one Polly-Link Sidecar.
  sidecar-repo-summaries  Show recent activity summaries for all repositories on one Polly-Link Sidecar.
  sidecar-global-activity  Show recent branch-head activity across all repositories on one Polly-Link Sidecar.
  sidecar-open-repo  Open or initialize one repository namespace on a Polly-Link Sidecar.
  sidecar-governance-status  Show auth, rate-limit skeleton, and recent audit activity for one Polly-Link Sidecar.
  sidecar-branches  List branches for one Sidecar repository namespace with merge/projector status.
  sidecar-branch-status  Show one branch status summary from a Sidecar repository namespace.
  sidecar-init-governance  Initialize local Polly-Hub governance with one global admin token.
  sidecar-grant-repo  Grant one actor reader|writer|admin access to one repo namespace.
  sidecar-set-repo-policy  Set one repo policy for default-branch push, auto-merge, and default sync negotiation.
  sidecar-set-branch-policy  Set one branch policy override for push, merge requirement, and default sync negotiation.
  sidecar-set-rate-limit  Set one Sidecar-wide request-per-minute limit skeleton.
  sidecar-audit-log  Show recent local Polly-Hub audit entries.
  sidecar-repo-activity  Show recent branch head activity for one Sidecar repository namespace.
  sidecar-branch-activity  Show one branch head summary from a Sidecar repository namespace.
  sidecar-branch-log  Show recent commits for one branch on a Sidecar repository namespace.
  status   Open a pollydb repository and print the current status report.
  inspect  Inspect a pollydb repository directory without keeping it open.

Branches and Merge:
  branches  List branches and their head commits.
  create-branch  Create a branch from another branch head.
  checkout  Print the current branch head commit.
  show-branch  Print the branch head and current status details.
  log  Print branch commit history, newest first.
  merge-base  Print the merge-base commit for two branches.
  merge-preview  Print a root-hash 3-way merge preview for two branches.
  merge-report  Print a merge preview plus per-table change and conflict summary.
  merge-branch  Merge one branch into another, optionally auto-resolving conflicts.

Catalog and Projectors:
  tables   List registered typed tables.
  describe-table  Print one registered table schema and indexes.
  export-catalog  Print all registered table schemas.
  register-table  Register or update a typed table in the catalog, including additive index updates.
  create-table  Alias for register-table.
  rebuild-indexes  Rebuild secondary indexes for all tables or one tables_csv subset.
  projectors  List registered aggregate projectors and their branch state.
  register-aggregate-projection  Register one aggregate projector in the catalog.
  refresh-aggregate-projections  Recompute aggregate projector virtual roots and advance branch metadata.

Data and Aggregates:
  put-row  Upsert one typed row using the registered table schema.
  set-json-path  Update one scalar json path inside one row.
  null-json-path  Set one json path to null.
  delete-json-path  Delete one json path.
  patch-json-paths  Apply multiple json path set/delete/null updates.
  get-row  Load one typed row by primary key.
  delete-row  Delete one row by primary key.
  count-rows  Count rows in one table, using aggregate metadata when available.
  count-rows-range  Count rows over a primary-key range.
  sum-column  Sum one i64 column, using declared aggregate metadata when available.
  sum-column-range  Sum one i64 column over a primary-key range.
  scan-table  Print rows from a table in primary-key order.
  lookup-index  Print rows matching one secondary-index value.
  scan-index-between  Scan rows whose secondary-index value falls between two sortable values.
  scan-index-after  Scan rows whose secondary-index value is greater than one sortable value.
  scan-index-before  Scan rows whose secondary-index value is less than one sortable value.
  scan-index  Scan rows for one index value with optional primary-key continuation.
  prefix-index  Scan rows for a string/bytes index prefix.
  prefix-index-projected  Scan rows for a covering string/bytes index prefix and decode only selected columns.
  query-fts-preview  Print planner preview for one lightweight Markdown FTS query.
  query-fts  Execute one lightweight Markdown FTS query and print ranked rows plus hit explanations.

Defaults:
  root_dir defaults to the current working directory.
  branch defaults to the repository default_branch from .pollydb/repo.meta.
  checkpoint mode defaults to full.
  high-throughput group commit defaults to aggregate projector policy stale_one.

Context resolution:
  For most data and catalog commands, you can omit root_dir and branch when you run inside a repository directory.
  Explicit command-line root_dir and branch still win over auto-resolved context.

Quick Start:
  pollydb init
  pollydb create-table users id "id:string,name:string,email:string?,created_at:datetime:current_timestamp,updated_at:datetime:current_timestamp:auto_update" "email_idx:email"
  pollydb put-row users u-001 "id=u-001,name=Ada,email=ada@example.com"
  pollydb get-row users u-001
  pollydb describe-table users

Branch Workflow:
  pollydb create-branch feature
  pollydb branches
  pollydb merge-preview main feature
  pollydb merge-report main feature

JSON Workflow:
  pollydb create-table items id "id:string,meta:json,updated_at:datetime:current_timestamp:auto_update" "kind_idx:meta.kind:string:covering"
  pollydb set-json-path items 001 meta kind string alpha
  pollydb patch-json-paths items 001 meta "kind=string:beta,enabled=bool:true,legacy=delete"
  pollydb prefix-index-projected items kind_idx al "meta" 10
  pollydb query-fts notes body heading prefix intro title 5

Formats:
  primary_key_csv: id or id,tenant_id
  columns_csv: id:string,status:enum(active|draft),meta:json or total:i64:sum
  datetime column modifiers: created_at:datetime:current_timestamp or updated_at:datetime:current_timestamp:auto_update
  indexes_csv: email_idx:email or meta_kind:meta.kind:string or meta_enabled:meta.enabled:bool:covering or -
  aggregate projector: register-aggregate-projection ... sum_metrics metrics id
  aggregate json projector: register-aggregate-projection ... sum_payload metrics payload amount.total
  aggregate projector priority: optional integer, larger means refresh earlier
  aggregate projector cost_hint: optional low|medium|high, lower means refresh earlier at same priority
  field_values_csv: id=001,name=Ada,meta={"kind":"alpha","enabled":true},active=true
  json path update: set-json-path ... meta kind.code string beta
  json patch updates_csv: kind.code=string:beta,enabled=null,legacy=delete

Merge strategy:
  ours | theirs

Checkpoint mode:
  full | data_only

Sync negotiation policy:
  regular | manifest_depth1 | manifest_depth2 | auto

Aggregate projection refresh policy:
  none | stale_one | stale_up_to | stale_all

Environment:
  POLLYHUB_TOKEN  Bearer token automatically used for sidecar-* and sync-*-sidecar commands.
'
}

fn (mut cli PollyDbCli) run() ! {
	if cli.args.len == 0 {
		println(cli.usage())
		return
	}
	command := cli.args[0]
	if command == 'init' {
		return cli.run_init()
	}
	if command == 'checkpoint' {
		return cli.run_checkpoint()
	}
	if command == 'refresh-index-snapshots' {
		return cli.run_refresh_index_snapshots()
	}
	if command == 'sync-push' {
		return cli.run_sync_push()
	}
	if command == 'sync-pull' {
		return cli.run_sync_pull()
	}
	if command == 'recommend-sync-policy' {
		return cli.run_recommend_sync_policy()
	}
	if command == 'sync-push-sidecar' {
		return cli.run_sync_push_sidecar()
	}
	if command == 'sync-pull-sidecar' {
		return cli.run_sync_pull_sidecar()
	}
	if command == 'sidecar-repos' {
		return cli.run_sidecar_repos()
	}
	if command == 'sidecar-repo-summaries' {
		return cli.run_sidecar_repo_summaries()
	}
	if command == 'sidecar-global-activity' {
		return cli.run_sidecar_global_activity()
	}
	if command == 'sidecar-open-repo' {
		return cli.run_sidecar_open_repo()
	}
	if command == 'sidecar-governance-status' {
		return cli.run_sidecar_governance_status()
	}
	if command == 'sidecar-branches' {
		return cli.run_sidecar_branches()
	}
	if command == 'sidecar-branch-status' {
		return cli.run_sidecar_branch_status()
	}
	if command == 'sidecar-init-governance' {
		return cli.run_sidecar_init_governance()
	}
	if command == 'sidecar-grant-repo' {
		return cli.run_sidecar_grant_repo()
	}
	if command == 'sidecar-set-repo-policy' {
		return cli.run_sidecar_set_repo_policy()
	}
	if command == 'sidecar-set-branch-policy' {
		return cli.run_sidecar_set_branch_policy()
	}
	if command == 'sidecar-set-rate-limit' {
		return cli.run_sidecar_set_rate_limit()
	}
	if command == 'sidecar-audit-log' {
		return cli.run_sidecar_audit_log()
	}
	if command == 'sidecar-repo-activity' {
		return cli.run_sidecar_repo_activity()
	}
	if command == 'sidecar-branch-activity' {
		return cli.run_sidecar_branch_activity()
	}
	if command == 'sidecar-branch-log' {
		return cli.run_sidecar_branch_log()
	}
	if command == 'status' {
		return cli.run_status()
	}
	if command == 'inspect' {
		return cli.run_inspect()
	}
	if command == 'branches' {
		return cli.run_branches()
	}
	if command == 'create-branch' {
		return cli.run_create_branch()
	}
	if command == 'checkout' {
		return cli.run_checkout()
	}
	if command == 'show-branch' {
		return cli.run_show_branch()
	}
	if command == 'log' {
		return cli.run_log()
	}
	if command == 'merge-base' {
		return cli.run_merge_base()
	}
	if command == 'merge-preview' {
		return cli.run_merge_preview()
	}
	if command == 'merge-report' {
		return cli.run_merge_report()
	}
	if command == 'merge-branch' {
		return cli.run_merge_branch()
	}
	if command == 'tables' {
		return cli.run_tables()
	}
	if command == 'describe-table' {
		return cli.run_describe_table()
	}
	if command == 'export-catalog' {
		return cli.run_export_catalog()
	}
	if command == 'register-table' {
		return cli.run_register_table()
	}
	if command == 'create-table' {
		return cli.run_register_table()
	}
	if command == 'rebuild-indexes' {
		return cli.run_rebuild_indexes()
	}
	if command == 'projectors' {
		return cli.run_projectors()
	}
	if command == 'register-aggregate-projection' {
		return cli.run_register_aggregate_projection()
	}
	if command == 'refresh-aggregate-projections' {
		return cli.run_refresh_aggregate_projections()
	}
	if command == 'put-row' {
		return cli.run_put_row()
	}
	if command == 'set-json-path' {
		return cli.run_set_json_path()
	}
	if command == 'null-json-path' {
		return cli.run_null_json_path()
	}
	if command == 'delete-json-path' {
		return cli.run_delete_json_path()
	}
	if command == 'patch-json-paths' {
		return cli.run_patch_json_paths()
	}
	if command == 'get-row' {
		return cli.run_get_row()
	}
	if command == 'delete-row' {
		return cli.run_delete_row()
	}
	if command == 'count-rows' {
		return cli.run_count_rows()
	}
	if command == 'count-rows-range' {
		return cli.run_count_rows_range()
	}
	if command == 'sum-column' {
		return cli.run_sum_column()
	}
	if command == 'sum-column-range' {
		return cli.run_sum_column_range()
	}
	if command == 'scan-table' {
		return cli.run_scan_table()
	}
	if command == 'lookup-index' {
		return cli.run_lookup_index()
	}
	if command == 'scan-index-between' {
		return cli.run_scan_index_between()
	}
	if command == 'scan-index-after' {
		return cli.run_scan_index_after()
	}
	if command == 'scan-index-before' {
		return cli.run_scan_index_before()
	}
	if command == 'scan-index' {
		return cli.run_scan_index()
	}
	if command == 'prefix-index' {
		return cli.run_prefix_index()
	}
	if command == 'prefix-index-projected' {
		return cli.run_prefix_index_projected()
	}
	if command == 'query-fts-preview' {
		return cli.run_query_fts_preview()
	}
	if command == 'query-fts' {
		return cli.run_query_fts()
	}
	if command in ['help', '--help', '-h'] {
		println(cli.usage())
		return
	}
	return error('unknown command: ${command}')
}

fn (cli PollyDbCli) checkpoint_mode() !storage.CheckpointMode {
	if cli.args.len >= 4 {
		return parse_checkpoint_mode(cli.args[3])
	}
	return .full
}

fn (cli PollyDbCli) resolve_root_context(start_idx int, require_repo bool) !CliRootContext {
	mut root_dir := os.getwd()
	mut next_idx := start_idx
	if cli.args.len > start_idx {
		raw := cli.args[start_idx]
		candidate := os.real_path(raw)
		if cli_has_repository(candidate) || cli_looks_like_path(raw) || os.is_dir(candidate) {
			root_dir = candidate
			next_idx++
		}
	}
	if !cli_has_repository(root_dir) {
		if cli_has_repository_layout(root_dir) {
			return CliRootContext{
				root_dir:       root_dir
				default_branch: 'main'
				branches:       []string{}
				next_idx:       next_idx
			}
		}
		if require_repo {
			return error('no .pollydb repository in current directory: ${root_dir}; pass <root_dir> explicitly or run `pollydb init`')
		}
		return CliRootContext{
			root_dir:       root_dir
			default_branch: 'main'
			branches:       []string{}
			next_idx:       next_idx
		}
	}
	repo := cli_open_repository(root_dir)!
	return CliRootContext{
		root_dir:       root_dir
		default_branch: repo.default_branch
		branches:       repo.branch_names()
		next_idx:       next_idx
	}
}

fn (cli PollyDbCli) resolve_db_context(start_idx int, require_repo bool) !CliDbContext {
	root := cli.resolve_root_context(start_idx, require_repo)!
	mut branch := root.default_branch
	mut next_idx := root.next_idx
	if root.branches.len > 0 && cli.args.len > next_idx && cli.args[next_idx] in root.branches {
		branch = cli.args[next_idx]
		next_idx++
	}
	return CliDbContext{
		root_dir:       root.root_dir
		default_branch: root.default_branch
		branch:         branch
		next_idx:       next_idx
	}
}

fn (cli PollyDbCli) resolve_sync_peer_context(start_idx int) !CliSyncPeerContext {
	if cli.args.len <= start_idx {
		return error('missing <peer_root_dir>')
	}
	root_dir := os.real_path(cli.args[start_idx])
	if !cli_has_repository(root_dir) {
		return error('peer repository metadata not found: ${root_dir}')
	}
	repo := cli_open_repository(root_dir)!
	mut branch := repo.default_branch
	mut next_idx := start_idx + 1
	branches := repo.branch_names()
	if cli.args.len > next_idx && cli.args[next_idx] in branches {
		branch = cli.args[next_idx]
		next_idx++
	}
	return CliSyncPeerContext{
		root_dir:       root_dir
		default_branch: repo.default_branch
		branch:         branch
		next_idx:       next_idx
	}
}

fn parse_checkpoint_mode(raw string) !storage.CheckpointMode {
	return match raw {
		'full' { .full }
		'data_only' { .data_only }
		else { error('invalid checkpoint mode: ${raw}') }
	}
}

fn parse_sidecar_sync_negotiation_policy(value string) !pollylink.SyncPolicy {
	return pollylink.sync_policy_from_string(value)
}

fn parse_sync_negotiation_policy(value string) !storage.SyncNegotiationPolicy {
	return match value {
		'regular' { .regular }
		'manifest_depth1' { .manifest_depth1 }
		'manifest_depth2' { .manifest_depth2 }
		'auto' { .auto }
		else { error('invalid sync negotiation policy: ${value}') }
	}
}

fn looks_like_sync_negotiation_policy(value string) bool {
	return value in ['regular', 'manifest_depth1', 'manifest_depth2', 'auto']
}

fn open_cli_persistent_repo(root_dir string) !storage.PersistentRepository {
	default_branch := if cli_has_repository(root_dir) {
		(cli_open_repository(root_dir)!).default_branch
	} else {
		'main'
	}
	return storage.PersistentRepository.open_default(root_dir, default_branch)
}

fn sidecar_sync_policy_label(policy pollylink.SyncPolicy) string {
	return policy.label()
}

fn sync_policy_label(policy storage.SyncNegotiationPolicy) string {
	return match policy {
		.regular { 'regular' }
		.manifest_depth1 { 'manifest_depth1' }
		.manifest_depth2 { 'manifest_depth2' }
		.auto { 'auto' }
	}
}

fn resolve_sidecar_default_sync_policy(client pollylink.Client) pollylink.SyncPolicy {
	info := client.repository_info() or { return pollylink.SyncPolicy.auto }
	return parse_sidecar_sync_negotiation_policy(info.default_sync_policy) or {
		pollylink.SyncPolicy.auto
	}
}

fn cli_render_sync_result(title string, direction string, source_root string, source_branch string, peer_root string, peer_branch string, policy string, packet_count int, packet_bytes int, branch_name string, branch_commit string, result_label string) string {
	return cli_render_field_card(title, [
		CliField{'direction', direction},
		CliField{'source', '${source_root}#${source_branch}'},
		CliField{'peer', '${peer_root}#${peer_branch}'},
		CliField{'policy', policy},
		CliField{'result', result_label},
		CliField{'packets', packet_count.str()},
		CliField{'bytes', packet_bytes.str()},
		CliField{'head_branch', branch_name},
		CliField{'head_commit', branch_commit},
	])
}

fn cli_render_sync_policy_recommendation(source_root string, source_branch string, peer_root string, peer_branch string, simulated_rtt_ms int, decision storage.SyncNegotiationDecision, tree_depth int, regular_local_ms i64, manifest1_local_ms i64, manifest2_local_ms i64) string {
	return cli_render_field_card('Sync Policy Recommendation', [
		CliField{'source', '${source_root}#${source_branch}'},
		CliField{'peer', '${peer_root}#${peer_branch}'},
		CliField{'simulated_rtt_ms', simulated_rtt_ms.str()},
		CliField{'tree_depth', tree_depth.str()},
		CliField{'recommended_policy', sync_policy_label(decision.policy)},
		CliField{'prediction_depth', decision.prediction_depth.str()},
		CliField{'estimated_rtts', decision.estimated_rtts.str()},
		CliField{'regular_local_ms', regular_local_ms.str()},
		CliField{'manifest1_local_ms', manifest1_local_ms.str()},
		CliField{'manifest2_local_ms', manifest2_local_ms.str()},
	])
}

fn cli_render_sidecar_repo_info(info pollylink.RepositoryInfo) string {
	return cli_render_field_card('Sidecar Repository', [
		CliField{'repo', info.repo_name},
		CliField{'default_branch', info.default_branch},
		CliField{'auth', if info.auth_enabled { cli_info('bearer') } else { cli_dim('disabled') }},
		CliField{'branches', info.branch_count.str()},
		CliField{'latest_branch', if info.latest_branch.len > 0 { info.latest_branch } else { '-' }},
		CliField{'latest_commit', if info.latest_commit_cid.len > 0 {
			info.latest_commit_cid
		} else {
			'-'
		}},
		CliField{'latest_timestamp', if info.latest_timestamp > 0 {
			info.latest_timestamp.str()
		} else {
			'-'
		}},
		CliField{'allow_push_to_default', if info.allow_push_to_default {
			cli_success('true')
		} else {
			cli_warn('false')
		}},
		CliField{'require_auto_merge', if info.require_auto_merge {
			cli_warn('true')
		} else {
			cli_dim('false')
		}},
		CliField{'default_sync_policy', info.default_sync_policy},
		CliField{'protection', info.protection_summary},
	])
}

fn cli_render_sidecar_repo_summaries(infos []pollylink.RepositoryInfo) string {
	if infos.len == 0 {
		return cli_empty('no repositories', 'open one with `pollydb sidecar-open-repo`')
	}
	mut rows := [][]string{cap: infos.len}
	for info in infos {
		rows << [
			info.repo_name,
			info.default_branch,
			if info.auth_enabled { 'bearer' } else { 'off' },
			info.branch_count.str(),
			if info.latest_branch.len > 0 { info.latest_branch } else { '-' },
			if info.allow_push_to_default { 'push' } else { 'protected' },
			if info.require_auto_merge { 'merge' } else { '-' },
			info.default_sync_policy,
			info.protection_summary,
			if info.latest_commit_cid.len > 0 { info.latest_commit_cid } else { '-' },
			if info.latest_timestamp > 0 { info.latest_timestamp.str() } else { '-' },
		]
	}
	mut lines := []string{}
	lines << cli_title('Sidecar Repository Summaries')
	lines << cli_render_table(['repo', 'default_branch', 'auth', 'branches', 'latest_branch',
		'push_default', 'auto_merge', 'sync_policy', 'protection', 'latest_commit',
		'latest_timestamp'], rows)
	return lines.join('\n')
}

fn cli_render_sidecar_branch_status(repo_name string, status pollylink.BranchStatus) string {
	return cli_render_field_card('Sidecar Branch Status', [
		CliField{'repo', if repo_name.len == 0 { '.' } else { repo_name }},
		CliField{'branch', status.branch.name},
		CliField{'head_commit', status.branch.commit_cid},
		CliField{'root', status.root_cid},
		CliField{'merge', status.merge_relation},
		CliField{'policy_scope', status.policy_scope},
		CliField{'allow_push', if status.allow_push {
			cli_success('true')
		} else {
			cli_warn('false')
		}},
		CliField{'require_auto_merge', if status.require_auto_merge {
			cli_warn('true')
		} else {
			cli_dim('false')
		}},
		CliField{'default_sync_policy', status.default_sync_policy},
		CliField{'protection', status.protection_summary},
		CliField{'projectors', '${status.projector_fresh} fresh / ${status.projector_stale} stale'},
		CliField{'stale_projectors', if status.stale_projectors.len > 0 {
			status.stale_projectors.join(',')
		} else {
			'-'
		}},
		CliField{'recommended_policy', status.recommended_projection_refresh_policy},
		CliField{'author', if status.author.len > 0 { status.author } else { '-' }},
		CliField{'message', if status.message.len > 0 { status.message } else { '-' }},
		CliField{'timestamp', status.timestamp.str()},
	])
}

fn cli_render_sidecar_branch_activity(repo_name string, activity pollylink.BranchActivity) string {
	return cli_render_field_card('Sidecar Branch Activity', [
		CliField{'repo', if repo_name.len == 0 { '.' } else { repo_name }},
		CliField{'branch', activity.branch.name},
		CliField{'head_commit', activity.branch.commit_cid},
		CliField{'root', activity.root_cid},
		CliField{'parents', activity.parent_count.str()},
		CliField{'author', activity.author},
		CliField{'message', activity.message},
		CliField{'timestamp', activity.timestamp.str()},
	])
}

fn cli_render_sidecar_branch_log(repo_name string, branch_name string, entries []pollylink.BranchLogEntry) string {
	mut lines := []string{}
	lines << cli_render_field_card('Sidecar Branch Log', [
		CliField{'repo', if repo_name.len == 0 { '.' } else { repo_name }},
		CliField{'branch', branch_name},
		CliField{'commits', entries.len.str()},
	])
	if entries.len == 0 {
		lines << ''
		lines << cli_empty('no commits', 'push or commit something first')
		return lines.join('\n')
	}
	mut rows := [][]string{cap: entries.len}
	for entry in entries {
		rows << [
			entry.cid,
			entry.root_cid,
			entry.parent_count.str(),
			if entry.author.len > 0 { entry.author } else { '-' },
			if entry.message.len > 0 { entry.message } else { '-' },
			entry.timestamp.str(),
		]
	}
	lines << ''
	lines << cli_render_table(['commit', 'root', 'parents', 'author', 'message', 'timestamp'],
		rows)
	return lines.join('\n')
}

fn cli_render_sidecar_repo_activity(repo_name string, entries []pollylink.RepoActivityEntry) string {
	mut lines := []string{}
	lines << cli_render_field_card('Sidecar Repository Activity', [
		CliField{'repo', if repo_name.len == 0 { '.' } else { repo_name }},
		CliField{'branches', entries.len.str()},
	])
	if entries.len == 0 {
		lines << ''
		lines << cli_empty('no activity', 'push or commit something first')
		return lines.join('\n')
	}
	mut rows := [][]string{cap: entries.len}
	for entry in entries {
		rows << [
			entry.branch.name,
			entry.branch.commit_cid,
			entry.root_cid,
			entry.parent_count.str(),
			if entry.author.len > 0 { entry.author } else { '-' },
			if entry.message.len > 0 { entry.message } else { '-' },
			entry.timestamp.str(),
		]
	}
	lines << ''
	lines << cli_render_table(['branch', 'head_commit', 'root', 'parents', 'author', 'message',
		'timestamp'], rows)
	return lines.join('\n')
}

fn cli_render_sidecar_global_activity(entries []pollylink.RepoActivityEntry) string {
	if entries.len == 0 {
		return cli_empty('no activity', 'push or commit something first')
	}
	mut rows := [][]string{cap: entries.len}
	for entry in entries {
		rows << [
			if entry.repo_name.len == 0 { '.' } else { entry.repo_name },
			entry.branch.name,
			entry.branch.commit_cid,
			entry.root_cid,
			entry.parent_count.str(),
			if entry.author.len > 0 { entry.author } else { '-' },
			if entry.message.len > 0 { entry.message } else { '-' },
			entry.timestamp.str(),
		]
	}
	mut lines := []string{}
	lines << cli_title('Sidecar Global Activity')
	lines << cli_render_table(['repo', 'branch', 'head_commit', 'root', 'parents', 'author',
		'message', 'timestamp'], rows)
	return lines.join('\n')
}

fn cli_render_sidecar_audit(entries []pollylink.AuditEntry) string {
	if entries.len == 0 {
		return cli_empty('no audit entries', 'perform one sidecar action first')
	}
	mut rows := [][]string{cap: entries.len}
	for entry in entries {
		rows << [
			entry.timestamp.str(),
			if entry.actor.len > 0 { entry.actor } else { '-' },
			entry.action,
			if entry.repo_name.len > 0 { entry.repo_name } else { '.' },
			if entry.branch_name.len > 0 { entry.branch_name } else { '-' },
			if entry.allowed { 'allow' } else { 'deny' },
			if entry.detail.len > 0 { entry.detail } else { '-' },
		]
	}
	mut lines := []string{}
	lines << cli_title('Sidecar Audit Log')
	lines << cli_render_table(['timestamp', 'actor', 'action', 'repo', 'branch', 'result', 'detail'],
		rows)
	return lines.join('\n')
}

fn cli_render_sidecar_branch_statuses(repo_name string, statuses []pollylink.BranchStatus) string {
	if statuses.len == 0 {
		return cli_empty('no branches', 'push or create one first')
	}
	mut rows := [][]string{cap: statuses.len}
	for status in statuses {
		rows << [
			if repo_name.len == 0 { '.' } else { repo_name },
			status.branch.name,
			status.branch.commit_cid,
			status.merge_relation,
			status.policy_scope,
			if status.allow_push { 'push' } else { 'blocked' },
			if status.require_auto_merge { 'merge' } else { '-' },
			status.default_sync_policy,
			status.protection_summary,
			'${status.projector_fresh}/${status.projector_stale}',
			if status.stale_projectors.len > 0 { status.stale_projectors.join(',') } else { '-' },
			status.timestamp.str(),
		]
	}
	mut lines := []string{}
	lines << cli_title('Sidecar Branch Statuses')
	lines << cli_render_table(['repo', 'branch', 'head_commit', 'merge', 'scope', 'push',
		'auto_merge', 'sync_policy', 'protection', 'projectors', 'stale_projectors', 'timestamp'],
		rows)
	return lines.join('\n')
}

fn cli_render_sidecar_governance_status(status pollylink.GovernanceStatus) string {
	mut lines := []string{}
	lines << cli_render_field_card('Sidecar Governance', [
		CliField{'auth', if status.auth_enabled { cli_info('bearer') } else { cli_dim('disabled') }},
		CliField{'tokens', status.token_count.str()},
		CliField{'repos', status.repo_count.str()},
		CliField{'requests_per_minute', if status.requests_per_minute > 0 {
			status.requests_per_minute.str()
		} else {
			cli_dim('unlimited')
		}},
		CliField{'recent_requests_1m', status.recent_requests_1m.str()},
		CliField{'recent_denies_1m', status.recent_denies_1m.str()},
	])
	if status.recent_categories.len > 0 {
		mut rows := [][]string{}
		for row in status.recent_categories {
			rows << [
				row.category,
				row.recent_requests_1m.str(),
				row.recent_denies_1m.str(),
			]
		}
		lines << ''
		lines << cli_title('Recent Groups')
		lines << cli_render_table(['group', 'requests_1m', 'denies_1m'], rows)
	}
	if status.recent_actors.len > 0 {
		mut rows := [][]string{}
		for row in status.recent_actors {
			rows << [
				row.actor,
				row.recent_requests_1m.str(),
				row.recent_denies_1m.str(),
			]
		}
		lines << ''
		lines << cli_title('Recent Actors')
		lines << cli_render_table(['actor', 'requests_1m', 'denies_1m'], rows)
	}
	if status.recent_actions.len > 0 {
		mut rows := [][]string{}
		for row in status.recent_actions {
			rows << [
				row.action,
				row.recent_requests_1m.str(),
				row.recent_denies_1m.str(),
			]
		}
		lines << ''
		lines << cli_title('Recent Actions')
		lines << cli_render_table(['action', 'requests_1m', 'denies_1m'], rows)
	}
	return lines.join('\n')
}

fn sync_packet_bytes(packets []storage.DataPacket) int {
	mut total := 0
	for packet in packets {
		total += packet.data.len
	}
	return total
}

fn build_sync_execution_for_policy(mut source_repo storage.PersistentRepository, source_branch string, mut target_repo storage.PersistentRepository, target_branch string, policy storage.SyncNegotiationPolicy) !CliSyncExecution {
	prepared := storage.prepare_sync_exchange_for_policy(mut source_repo, source_branch, mut
		target_repo, target_branch, policy)!
	return CliSyncExecution{
		session:  prepared.session
		exchange: prepared.exchange
		policy:   prepared.policy
	}
}

fn recommend_sync_policy_for_branches(mut source_repo storage.PersistentRepository, source_branch string, mut target_repo storage.PersistentRepository, target_branch string, simulated_rtt_ms int) !(storage.SyncNegotiationDecision, int, i64, i64, i64) {
	recommendation := storage.recommend_sync_policy_for_repos(mut source_repo, source_branch, mut
		target_repo, target_branch, simulated_rtt_ms)!
	return recommendation.decision, recommendation.tree_depth, recommendation.regular_local_ms, recommendation.manifest1_local_ms, recommendation.manifest2_local_ms
}

fn (mut cli PollyDbCli) run_status() ! {
	ctx := cli.resolve_db_context(1, true)!
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	report := db.status_report()!
	println(cli_render_status_report(report))
}

fn (mut cli PollyDbCli) run_inspect() ! {
	ctx := cli.resolve_db_context(1, false)!
	report := storage.PersistentDatabase.inspect(ctx.root_dir, ctx.branch)!
	println(cli_render_status_report(report))
}

fn format_commit(commit storage.Commit) string {
	return 'commit=${commit.cid} root=${commit.root_cid} parents=${commit.parent_cids.len} author=${commit.meta.author} message=${commit.meta.message} timestamp=${commit.meta.timestamp}'
}

fn format_merge_preview(preview storage.RootHashMergePreview) string {
	mut lines := []string{cap: 10}
	lines << 'ours_branch=${preview.ours_branch}'
	lines << 'theirs_branch=${preview.theirs_branch}'
	lines << 'base_commit=${preview.base_commit_cid}'
	lines << 'base_root=${preview.base_root_cid}'
	lines << 'ours_commit=${preview.ours_commit_cid}'
	lines << 'ours_root=${preview.ours_root_cid}'
	lines << 'theirs_commit=${preview.theirs_commit_cid}'
	lines << 'theirs_root=${preview.theirs_root_cid}'
	lines << 'fast_forward=${preview.fast_forward}'
	lines << 'ours_unchanged=${preview.ours_unchanged}'
	lines << 'theirs_unchanged=${preview.theirs_unchanged}'
	lines << 'conflicts=${preview.conflicts}'
	lines << 'changed_keys=${preview.changed_keys}'
	lines << 'changed_subtrees=${preview.changed_subtrees}'
	return lines.join('\n')
}

fn format_merge_report(report storage.RootHashMergeReport) string {
	mut lines := []string{}
	lines << format_merge_preview(report.preview)
	lines << 'tables=${report.table_stats.len}'
	for stat in report.table_stats {
		lines << 'table=${stat.table_name} row_changes=${stat.row_changes} index_changes=${stat.index_changes} conflicts=${stat.conflict_changes}'
	}
	lines << 'conflict_preview=${report.conflict_keys.len}/${report.preview.conflicts}'
	for conflict in report.conflict_keys {
		mut rendered := 'conflict_key=${conflict.key}'
		if conflict.table_name.len > 0 {
			rendered += ' table=${conflict.table_name}'
		}
		if conflict.index_name.len > 0 {
			rendered += ' index=${conflict.index_name}'
		}
		lines << rendered
		if conflict.base_row.len > 0 {
			lines << '  base=${conflict.base_row}'
		}
		if conflict.ours_row.len > 0 {
			lines << '  ours=${conflict.ours_row}'
		}
		if conflict.theirs_row.len > 0 {
			lines << '  theirs=${conflict.theirs_row}'
		}
	}
	return lines.join('\n')
}

fn format_column_type(column storage.ColumnDef) string {
	return match column.typ {
		.bool_ { 'bool' }
		.i64_ { 'i64' }
		.string_ { 'string' }
		.bytes_ { 'bytes' }
		.enum_ { 'enum(${column.enum_values.join('|')})' }
		.json_ { 'json' }
		.datetime_ { 'datetime' }
		.markdown_ { 'markdown' }
	}
}

fn format_column_aggregate(aggregate storage.ColumnAggregate) string {
	return match aggregate {
		.none { '' }
		.sum { ':sum' }
	}
}

fn format_column_datetime_behaviors(column storage.ColumnDef) string {
	mut rendered := ''
	if column.default_current_timestamp {
		rendered += ':current_timestamp'
	}
	if column.auto_update_current_timestamp {
		rendered += ':auto_update'
	}
	return rendered
}

fn format_table_spec(spec storage.TypedTableSpec) string {
	mut lines := []string{}
	lines << 'table=${spec.name()}'
	lines << 'primary_key=${spec.table.primary_key.join(',')}'
	mut columns := []string{cap: spec.table.columns.len}
	for column in spec.table.columns {
		mut rendered := '${column.name}:${format_column_type(column)}'
		if column.nullable {
			rendered += '?'
		}
		rendered += format_column_aggregate(column.aggregate)
		rendered += format_column_datetime_behaviors(column)
		columns << rendered
	}
	lines << 'columns=${columns.join(',')}'
	if spec.indexes.len == 0 {
		lines << 'indexes=(none)'
	} else {
		mut indexes := []string{cap: spec.indexes.len}
		for index in spec.indexes {
			target := index.target_label()
			indexes << if index.stores_row {
				if index.is_field_selector() {
					'${index.name}:${target}:${format_column_type(storage.ColumnDef.new(index.field_selector(),
						index.json_field_type, true) or { panic(err) })}:covering'
				} else if index.is_json_path() {
					'${index.name}:${target}:${format_column_type(storage.ColumnDef.new(index.json_field,
						index.json_field_type, true) or { panic(err) })}:covering'
				} else if index.is_embedding() {
					'${index.name}:${target}:covering'
				} else {
					'${index.name}:${target}:covering'
				}
			} else {
				if index.is_field_selector() {
					'${index.name}:${target}:${format_column_type(storage.ColumnDef.new(index.field_selector(),
						index.json_field_type, true) or { panic(err) })}'
				} else if index.is_json_path() {
					'${index.name}:${target}:${format_column_type(storage.ColumnDef.new(index.json_field,
						index.json_field_type, true) or { panic(err) })}'
				} else if index.is_embedding() {
					'${index.name}:${target}'
				} else {
					'${index.name}:${target}'
				}
			}
		}
		lines << 'indexes=${indexes.join(',')}'
	}
	return lines.join('\n')
}

fn format_projector_state(state storage.AggregateProjectorState) string {
	mut rendered := 'projector=${state.projection.name} table=${state.projection.table_name} column=${state.projection.column_name} aggregate=${state.projection.aggregate} priority=${state.projection.priority} cost_hint=${state.projection.cost_hint}'
	if state.projection.source_json_path.len > 0 {
		rendered += ' json_path=${state.projection.source_json_path}'
	}
	rendered += ' current_data_root=${state.current_data_root_cid}'
	rendered += ' source_data_root=${state.source_data_root_cid}'
	rendered += ' virtual_root=${if state.virtual_root_cid.len > 0 {
		state.virtual_root_cid
	} else {
		'(pending)'
	}}'
	rendered += ' fresh=${state.fresh}'
	if state.stale_reason.len > 0 {
		rendered += ' stale_reason=${state.stale_reason}'
	}
	return rendered
}

fn parse_aggregate_projection_refresh_policy(value string) !storage.AggregateProjectionRefreshPolicy {
	return match value {
		'none' { .none }
		'stale_one' { .stale_one }
		'stale_up_to' { .stale_up_to }
		'stale_all' { .stale_all }
		else { error('unknown aggregate projection refresh policy: ${value}') }
	}
}

fn parse_aggregate_projection_cost_hint(value string) !storage.AggregateProjectionCostHint {
	return match value {
		'low' { .low }
		'medium' { .medium }
		'high' { .high }
		else { error('unknown aggregate projection cost hint: ${value}') }
	}
}

fn parse_merge_strategy(value string) !storage.ConflictResolutionStrategy {
	return match value {
		'ours' { .ours }
		'theirs' { .theirs }
		else { error('unsupported merge strategy: ${value}') }
	}
}

fn parse_column_type(value string) !storage.ColumnType {
	return match value {
		'bool' { .bool_ }
		'i64' { .i64_ }
		'string' { .string_ }
		'bytes' { .bytes_ }
		'json' { .json_ }
		'datetime' { .datetime_ }
		'markdown' { .markdown_ }
		else { error('unsupported column type: ${value}') }
	}
}

fn parse_enum_values(type_name string) ![]string {
	if !type_name.starts_with('enum(') || !type_name.ends_with(')') {
		return error('invalid enum type syntax: ${type_name}')
	}
	body := type_name[5..type_name.len - 1]
	values := parse_csv_values(body.replace('|', ','))
	if values.len == 0 {
		return error('enum type requires values')
	}
	return values
}

fn parse_fts_scope(value string) !queryapi.FtsScope {
	return match value.trim_space().to_lower() {
		'any' { .any }
		'heading' { .heading }
		'paragraph' { .paragraph }
		'code_block' { .code_block }
		'list_item' { .list_item }
		else { error('unknown fts scope: ${value}') }
	}
}

fn parse_fts_query_kind(value string) !queryapi.FtsKind {
	return match value.trim_space().to_lower() {
		'term' { .term }
		'prefix' { .prefix }
		'all' { .all }
		'any' { .any }
		else { error('unknown fts query kind: ${value}') }
	}
}

fn parse_csv_values(value string) []string {
	if value.len == 0 {
		return []string{}
	}
	mut parts := []string{}
	mut current := []u8{}
	mut brace_depth := 0
	mut bracket_depth := 0
	mut paren_depth := 0
	mut in_string := false
	mut quote := u8(0)
	mut escaped := false
	for ch in value.bytes() {
		if in_string {
			current << ch
			if escaped {
				escaped = false
				continue
			}
			if ch == `\\` {
				escaped = true
				continue
			}
			if ch == quote {
				in_string = false
				quote = u8(0)
			}
			continue
		}
		match ch {
			`"`, `'` {
				in_string = true
				quote = ch
				current << ch
			}
			`{` {
				brace_depth++
				current << ch
			}
			`}` {
				if brace_depth > 0 {
					brace_depth--
				}
				current << ch
			}
			`[` {
				bracket_depth++
				current << ch
			}
			`]` {
				if bracket_depth > 0 {
					bracket_depth--
				}
				current << ch
			}
			`(` {
				paren_depth++
				current << ch
			}
			`)` {
				if paren_depth > 0 {
					paren_depth--
				}
				current << ch
			}
			`,` {
				if brace_depth == 0 && bracket_depth == 0 && paren_depth == 0 {
					trimmed := current.bytestr().trim_space()
					if trimmed.len > 0 {
						parts << trimmed
					}
					current = []u8{}
				} else {
					current << ch
				}
			}
			else {
				current << ch
			}
		}
	}
	trimmed := current.bytestr().trim_space()
	if trimmed.len > 0 {
		parts << trimmed
	}
	return parts
}

fn parse_column_defs(spec string) ![]storage.ColumnDef {
	parts := parse_csv_values(spec)
	if parts.len == 0 {
		return error('columns_csv cannot be empty')
	}
	mut columns := []storage.ColumnDef{cap: parts.len}
	for part in parts {
		field := part.split(':')
		if field.len < 2 {
			return error('invalid column spec: ${part}')
		}
		name := field[0].trim_space()
		mut typ_name := field[1].trim_space()
		mut nullable := false
		mut aggregate := storage.ColumnAggregate.none
		mut default_current_timestamp := false
		mut auto_update_current_timestamp := false
		if typ_name.ends_with('?') {
			nullable = true
			typ_name = typ_name[..typ_name.len - 1]
		}
		for modifier in field[2..] {
			mode := modifier.trim_space()
			match mode {
				'sum' {
					aggregate = .sum
				}
				'current_timestamp' {
					default_current_timestamp = true
				}
				'auto_update' {
					auto_update_current_timestamp = true
				}
				else {
					return error('unsupported column modifier: ${mode}')
				}
			}
		}
		columns << if typ_name.starts_with('enum(') {
			mut column := storage.ColumnDef.enum_string(name, parse_enum_values(typ_name)!,
				nullable)!
			if aggregate != .none || default_current_timestamp || auto_update_current_timestamp {
				return error('enum columns do not support modifiers: ${name}')
			}
			column
		} else {
			storage.ColumnDef.new_with_options(name, parse_column_type(typ_name)!, nullable,
				aggregate, default_current_timestamp, auto_update_current_timestamp)!
		}
	}
	return columns
}

fn parse_index_defs(spec string) ![]storage.SchemaIndexDef {
	if spec.len == 0 || spec == '-' {
		return []storage.SchemaIndexDef{}
	}
	parts := parse_csv_values(spec)
	mut indexes := []storage.SchemaIndexDef{cap: parts.len}
	for part in parts {
		name_and_rest := part.split_nth(':', 2)
		if name_and_rest.len != 2 {
			return error('invalid index spec: ${part}')
		}
		name := name_and_rest[0].trim_space()
		mut rest := name_and_rest[1].trim_space()
		mut stores_row := false
		if rest.ends_with(':covering') {
			stores_row = true
			rest = rest[..rest.len - ':covering'.len]
		}
		if !rest.contains(':') {
			if rest.contains('#') {
				target_parts := rest.split_nth('#', 2)
				if target_parts.len == 2 && target_parts[1].starts_with('embedding(')
					&& target_parts[1].ends_with(')') {
					if stores_row {
						return error('embedding indexes cannot be covering indexes: ${part}')
					}
					inner := target_parts[1]['embedding('.len..target_parts[1].len - 1]
					embed_parts := parse_csv_values(inner)
					if embed_parts.len == 1 {
						indexes << storage.SchemaIndexDef.embedding_text(name, target_parts[0],
							embed_parts[0])!
						continue
					}
					if embed_parts.len == 2 {
						scope := match embed_parts[0] {
							'block' { memory.MarkdownEmbeddingScope.block }
							'path' { memory.MarkdownEmbeddingScope.path }
							else { return error('embedding scope must be block or path: ${part}') }
						}
						indexes << storage.SchemaIndexDef.embedding_markdown(name, target_parts[0],
							scope, embed_parts[1])!
						continue
					}
					return error('embedding target must be embedding(profile) or embedding(scope,profile): ${part}')
				}
			}
			if stores_row {
				indexes << storage.SchemaIndexDef.covering(name, rest)!
			} else {
				indexes << storage.SchemaIndexDef.new(name, rest)!
			}
			continue
		}
		split_at := rest.last_index(':') or { return error('invalid index spec: ${part}') }
		target := rest[..split_at].trim_space()
		value_type_name := rest[split_at + 1..].trim_space()
		if target.contains('#') {
			target_parts := target.split_nth('#', 2)
			if target_parts.len != 2 {
				return error('markdown selector index target must be column#selector: ${target}')
			}
			value_type := parse_column_type(value_type_name)!
			match value_type {
				.string_, .i64_ {}
				else { return error('markdown selector index type must be string or i64: ${part}') }
			}
			indexes << storage.SchemaIndexDef.field_selector(name, target_parts[0], 'markdown',
				target_parts[1], value_type, stores_row)!
			continue
		}
		if !target.contains('.') {
			return error('unsupported index mode: ${value_type_name}')
		}
		target_parts := target.split_nth('.', 2)
		if target_parts.len != 2 {
			return error('json-path index target must be column.field: ${target}')
		}
		json_type := parse_column_type(value_type_name)!
		if stores_row {
			indexes << storage.SchemaIndexDef.json_path_covering(name, target_parts[0],
				target_parts[1], json_type)!
		} else {
			indexes << storage.SchemaIndexDef.json_path(name, target_parts[0], target_parts[1],
				json_type)!
		}
	}
	return indexes
}

fn parse_register_table_spec(table_name string, primary_key_csv string, columns_csv string, indexes_csv string) !storage.TypedTableSpec {
	primary_key := parse_csv_values(primary_key_csv)
	if primary_key.len == 0 {
		return error('primary_key_csv cannot be empty')
	}
	table := storage.TableDef.new(table_name, parse_column_defs(columns_csv)!, primary_key)!
	return storage.TypedTableSpec.new(table, parse_index_defs(indexes_csv)!)
}

fn parse_field_assignments(spec string) !map[string]string {
	parts := parse_csv_values(spec)
	if parts.len == 0 {
		return error('field_values_csv cannot be empty')
	}
	mut values := map[string]string{}
	for part in parts {
		field := part.split_nth('=', 2)
		if field.len != 2 {
			return error('invalid field assignment: ${part}')
		}
		values[field[0].trim_space()] = field[1].trim_space()
	}
	return values
}

fn cli_looks_like_int(raw string) bool {
	value := raw.trim_space()
	if value.len == 0 {
		return false
	}
	start := if value[0] == `-` || value[0] == `+` { 1 } else { 0 }
	if start >= value.len {
		return false
	}
	for idx in start .. value.len {
		if value[idx] < `0` || value[idx] > `9` {
			return false
		}
	}
	return true
}

fn parse_optional_columns_and_limit(args []string, start_idx int) !([]string, int) {
	if args.len <= start_idx {
		return []string{}, 0
	}
	extra := args[start_idx]
	if cli_looks_like_int(extra) {
		return []string{}, extra.int()
	}
	columns := parse_csv_values(extra)
	if columns.len == 0 {
		return error('select_columns_csv cannot be empty')
	}
	limit := if args.len > start_idx + 1 { args[start_idx + 1].int() } else { 0 }
	return columns, limit
}

fn parse_bytes_value(value string) ![]u8 {
	if value.starts_with('hex:') {
		hex := value[4..]
		if hex.len % 2 != 0 {
			return error('hex bytes must have even length')
		}
		mut out := []u8{cap: hex.len / 2}
		for idx := 0; idx < hex.len; idx += 2 {
			pair := hex[idx..idx + 2]
			out << parse_hex_byte(pair)!
		}
		return out
	}
	return value.bytes()
}

fn parse_hex_nibble(ch u8) !u8 {
	if ch >= `0` && ch <= `9` {
		return u8(ch - `0`)
	}
	if ch >= `a` && ch <= `f` {
		return u8(ch - `a` + 10)
	}
	if ch >= `A` && ch <= `F` {
		return u8(ch - `A` + 10)
	}
	return error('invalid hex nibble')
}

fn parse_hex_byte(pair string) !u8 {
	if pair.len != 2 {
		return error('invalid hex byte: ${pair}')
	}
	high := parse_hex_nibble(pair[0])!
	low := parse_hex_nibble(pair[1])!
	return (high << 4) | low
}

fn parse_typed_value(column storage.ColumnDef, raw string) !storage.ColumnValue {
	if raw == 'null' {
		if !column.nullable {
			return error('column is not nullable: ${column.name}')
		}
		return storage.NullValue{}
	}
	return match column.typ {
		.bool_ {
			match raw {
				'true', '1' { true }
				'false', '0' { false }
				else { return error('invalid bool value for ${column.name}: ${raw}') }
			}
		}
		.i64_ {
			raw.i64()
		}
		.string_ {
			raw
		}
		.bytes_ {
			parse_bytes_value(raw)!
		}
		.enum_, .json_ {
			raw
		}
		.datetime_ {
			if raw == 'CURRENT_TIMESTAMP' {
				storage.current_datetime_string()
			} else {
				storage.TypedValueEncoder.validate(column, raw)!
				raw
			}
		}
		.markdown_ {
			raw
		}
	}
}

fn parse_json_scalar_value(type_name string, raw string) !storage.ColumnValue {
	column := storage.ColumnDef.new('json_path', parse_column_type(type_name)!, true)!
	match column.typ {
		.bytes_, .enum_, .json_, .datetime_ {
			return error('json path updates only support bool, i64, string, or null')
		}
		else {}
	}
	return parse_typed_value(column, raw)
}

fn parse_json_path_updates(spec string) ![]storage.JsonPathUpdate {
	parts := parse_csv_values(spec)
	if parts.len == 0 {
		return error('updates_csv cannot be empty')
	}
	mut updates := []storage.JsonPathUpdate{cap: parts.len}
	for part in parts {
		field := part.split_nth('=', 2)
		if field.len != 2 {
			return error('invalid json path update: ${part}')
		}
		path := field[0].trim_space()
		payload := field[1].trim_space()
		if payload == 'delete' {
			updates << storage.JsonPathUpdate{
				path:  path
				op:    .delete
				value: storage.NullValue{}
			}
			continue
		}
		if payload == 'null' {
			updates << storage.JsonPathUpdate{
				path:  path
				op:    .set
				value: storage.NullValue{}
			}
			continue
		}
		value_parts := payload.split_nth(':', 2)
		if value_parts.len != 2 {
			return error('json path update must be delete, null, or type:value: ${part}')
		}
		updates << storage.JsonPathUpdate{
			path:  path
			op:    .set
			value: parse_json_scalar_value(value_parts[0].trim_space(), value_parts[1].trim_space())!
		}
	}
	return updates
}

fn build_typed_row(spec storage.TypedTableSpec, field_values_csv string) !storage.TypedRowData {
	assignments := parse_field_assignments(field_values_csv)!
	mut row := storage.TypedRowData.new()
	for column in spec.table.columns {
		if column.name !in assignments {
			continue
		}
		value := parse_typed_value(column, assignments[column.name])!
		match value {
			storage.NullValue {
				row.set_null(column.name)
			}
			else {
				row.set(column.name, value)
			}
		}
	}
	return row
}

fn ingest_external_columns(mut db storage.PersistentDatabase, spec storage.TypedTableSpec, row storage.TypedRowData) !storage.TypedRowData {
	mut next_row := row.clone()
	for column in spec.table.columns {
		if column.typ != .markdown_ || !next_row.has(column.name) {
			continue
		}
		value := next_row.get(column.name)!
		match value {
			storage.NullValue, storage.MarkdownRef {}
			string {
				stored := storage.ingest_external_field_value(mut db, column, value)!
				next_row.set(column.name, stored)
			}
			else {
				return error('unsupported external field payload for ${column.name}')
			}
		}
	}
	return next_row
}

fn apply_insert_defaults(spec storage.TypedTableSpec, row storage.TypedRowData) storage.TypedRowData {
	mut next_row := row.clone()
	current_timestamp := storage.current_datetime_string()
	for column in spec.table.columns {
		if !next_row.has(column.name)
			&& (column.default_current_timestamp || column.auto_update_current_timestamp) {
			next_row.set(column.name, current_timestamp)
		}
	}
	return next_row
}

fn detect_auto_filled_columns(spec storage.TypedTableSpec, original storage.TypedRowData, with_defaults storage.TypedRowData) []string {
	mut names := []string{}
	for column in spec.table.columns {
		if original.has(column.name) {
			continue
		}
		if !with_defaults.has(column.name) {
			continue
		}
		if column.default_current_timestamp || column.auto_update_current_timestamp {
			names << column.name
		}
	}
	return names
}

fn index_column(spec storage.TypedTableSpec, index_name string) !storage.ColumnDef {
	for index in spec.indexes {
		if index.name == index_name {
			return index.value_column(spec.table)
		}
	}
	return error('index not found: ${index_name}')
}

fn table_index_def(spec storage.TypedTableSpec, index_name string) !storage.SchemaIndexDef {
	for index in spec.indexes {
		if index.name == index_name {
			return index
		}
	}
	return error('index not found: ${index_name}')
}

fn format_column_value(value storage.ColumnValue) string {
	return match value {
		storage.NullValue {
			'null'
		}
		bool {
			if value {
				'true'
			} else {
				'false'
			}
		}
		i64 {
			value.str()
		}
		string {
			value
		}
		[]u8 {
			'hex:${value.hex()}'
		}
		storage.MarkdownRef {
			'markdown:${value.doc_root_id}'
		}
	}
}

fn cli_render_fts_hits(hits []queryapi.FtsHit) string {
	if hits.len == 0 {
		return cli_empty('no hits', 'no ranked FTS matches were produced')
	}
	mut rows := [][]string{cap: hits.len}
	for hit in hits {
		rows << [
			hit.primary_key.bytestr(),
			hit.score.str(),
			hit.matched_terms.join(','),
			hit.matched_scopes.map(queryapi.fts_scope_name(it)).join(','),
			hit.summary,
		]
	}
	mut lines := []string{}
	lines << cli_title('FTS Hits')
	lines << cli_render_table(['pk', 'score', 'terms', 'scopes', 'summary'], rows)
	return lines.join('\n')
}

fn format_typed_row(row storage.TypedSchemaRow, spec storage.TypedTableSpec) string {
	mut parts := []string{cap: spec.table.columns.len + 1}
	parts << 'pk=${row.primary_key.bytestr()}'
	for column in spec.table.columns {
		if !row.data.has(column.name) {
			parts << '${column.name}=<unset>'
			continue
		}
		value := row.data.get(column.name) or { continue }
		parts << '${column.name}=${format_column_value(value)}'
	}
	return parts.join(', ')
}

fn branch_exists(mut db storage.PersistentDatabase, branch string) bool {
	return branch in db.branch_names()
}

fn (mut cli PollyDbCli) run_init() ! {
	ctx := cli.resolve_root_context(1, false)!
	branch := if cli.args.len > ctx.next_idx { cli.args[ctx.next_idx] } else { ctx.default_branch }
	status := storage.PersistentDatabase.inspect(ctx.root_dir, branch) or {
		storage.PersistentDatabaseStatusReport{}
	}
	mut db := if status.repository_exists || status.catalog_exists {
		storage.PersistentDatabase.open(ctx.root_dir, branch)!
	} else {
		storage.PersistentDatabase.init(ctx.root_dir, branch)!
	}
	defer {
		db.close() or {}
	}
	db.checkpoint()!
	report := db.status_report()!
	println(cli_render_status_report(report))
}

fn (mut cli PollyDbCli) run_checkpoint() ! {
	ctx := cli.resolve_db_context(1, true)!
	mode := if cli.args.len > ctx.next_idx {
		parse_checkpoint_mode(cli.args[ctx.next_idx])!
	} else {
		storage.CheckpointMode.full
	}
	mode_label := if cli.args.len > ctx.next_idx { cli.args[ctx.next_idx] } else { 'full' }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	db.checkpoint_mode(mode)!
	report := db.status_report()!
	println(cli_render_status_report(report))
	println('')
	println(cli_render_fields('Checkpoint', [
		CliField{'mode', mode_label},
	]))
}

fn (mut cli PollyDbCli) run_refresh_index_snapshots() ! {
	ctx := cli.resolve_db_context(1, true)!
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	db.refresh_index_snapshots()!
	report := db.status_report()!
	println(cli_render_status_report(report))
	println('')
	println(cli_render_fields('Index Snapshots', [
		CliField{'status', 'done'},
	]))
}

fn (mut cli PollyDbCli) run_sync_push() ! {
	ctx := cli.resolve_db_context(1, true)!
	peer := cli.resolve_sync_peer_context(ctx.next_idx)!
	policy := if cli.args.len > peer.next_idx {
		parse_sync_negotiation_policy(cli.args[peer.next_idx])!
	} else {
		storage.SyncNegotiationPolicy.auto
	}
	mut source_repo := open_cli_persistent_repo(ctx.root_dir)!
	defer {
		source_repo.close() or {}
	}
	mut peer_repo := open_cli_persistent_repo(peer.root_dir)!
	defer {
		peer_repo.close() or {}
	}
	mut effective_policy := policy
	if effective_policy == .auto {
		decision, _, _, _, _ := recommend_sync_policy_for_branches(mut source_repo, ctx.branch, mut
			peer_repo, peer.branch, 40)!
		effective_policy = decision.policy
	}
	execution := build_sync_execution_for_policy(mut source_repo, ctx.branch, mut peer_repo,
		peer.branch, effective_policy)!
	branch := storage.apply_exchange_to_repo(mut peer_repo, execution.exchange)!
	policy_label := if policy == .auto {
		'auto -> ${sync_policy_label(effective_policy)}'
	} else {
		sync_policy_label(effective_policy)
	}
	println(cli_render_sync_result('Sync Push', 'push', ctx.root_dir, ctx.branch, peer.root_dir,
		peer.branch, policy_label, execution.exchange.packets.len, sync_packet_bytes(execution.exchange.packets),
		branch.name, branch.commit_cid, 'applied'))
}

fn (mut cli PollyDbCli) run_sync_pull() ! {
	ctx := cli.resolve_db_context(1, true)!
	peer := cli.resolve_sync_peer_context(ctx.next_idx)!
	policy := if cli.args.len > peer.next_idx {
		parse_sync_negotiation_policy(cli.args[peer.next_idx])!
	} else {
		storage.SyncNegotiationPolicy.auto
	}
	mut target_repo := open_cli_persistent_repo(ctx.root_dir)!
	defer {
		target_repo.close() or {}
	}
	mut source_repo := open_cli_persistent_repo(peer.root_dir)!
	defer {
		source_repo.close() or {}
	}
	mut effective_policy := policy
	if effective_policy == .auto {
		decision, _, _, _, _ := recommend_sync_policy_for_branches(mut source_repo, peer.branch, mut
			target_repo, ctx.branch, 40)!
		effective_policy = decision.policy
	}
	execution := build_sync_execution_for_policy(mut source_repo, peer.branch, mut target_repo,
		ctx.branch, effective_policy)!
	branch := storage.apply_exchange_to_repo(mut target_repo, execution.exchange)!
	policy_label := if policy == .auto {
		'auto -> ${sync_policy_label(effective_policy)}'
	} else {
		sync_policy_label(effective_policy)
	}
	println(cli_render_sync_result('Sync Pull', 'pull', peer.root_dir, peer.branch, ctx.root_dir,
		ctx.branch, policy_label, execution.exchange.packets.len, sync_packet_bytes(execution.exchange.packets),
		branch.name, branch.commit_cid, 'applied'))
}

fn (mut cli PollyDbCli) run_recommend_sync_policy() ! {
	ctx := cli.resolve_db_context(1, true)!
	peer := cli.resolve_sync_peer_context(ctx.next_idx)!
	simulated_rtt_ms := if cli.args.len > peer.next_idx { cli.args[peer.next_idx].int() } else { 40 }
	mut source_repo := open_cli_persistent_repo(ctx.root_dir)!
	defer {
		source_repo.close() or {}
	}
	mut peer_repo := open_cli_persistent_repo(peer.root_dir)!
	defer {
		peer_repo.close() or {}
	}
	decision, tree_depth, regular_local_ms, manifest1_local_ms, manifest2_local_ms := recommend_sync_policy_for_branches(mut source_repo,
		ctx.branch, mut peer_repo, peer.branch, simulated_rtt_ms)!
	println(cli_render_sync_policy_recommendation(ctx.root_dir, ctx.branch, peer.root_dir,
		peer.branch, simulated_rtt_ms, decision, tree_depth, regular_local_ms, manifest1_local_ms,
		manifest2_local_ms))
}

fn (mut cli PollyDbCli) run_sync_push_sidecar() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx || !cli_looks_like_url(cli.args[ctx.next_idx]) {
		return error('sync-push-sidecar requires [root_dir] [branch] <sidecar_url> [repo_name] [target_branch] [policy]')
	}
	sidecar_url := cli.args[ctx.next_idx]
	mut repo_name := ''
	mut target_branch := ctx.branch
	mut next_idx := ctx.next_idx + 1
	if cli.args.len > next_idx && !looks_like_sync_negotiation_policy(cli.args[next_idx]) {
		if cli.args.len > next_idx + 1
			&& !looks_like_sync_negotiation_policy(cli.args[next_idx + 1]) {
			repo_name = cli.args[next_idx]
			target_branch = cli.args[next_idx + 1]
			next_idx += 2
		} else {
			target_branch = cli.args[next_idx]
			next_idx++
		}
	}
	policy := if cli.args.len > next_idx {
		parse_sidecar_sync_negotiation_policy(cli.args[next_idx])!
	} else {
		resolve_sidecar_default_sync_policy(pollylink.Client{
			base_url:   sidecar_url
			repo_name:  repo_name
			auth_token: cli_sidecar_auth_token()
		})
	}
	mut repo := pollylink.open_local_repo(ctx.root_dir, ctx.branch)!
	defer {
		repo.close() or {}
	}
	client := pollylink.Client{
		base_url:   sidecar_url
		repo_name:  repo_name
		auth_token: cli_sidecar_auth_token()
	}
	result := pollylink.push_branch_to_sidecar(mut repo, ctx.branch, client, target_branch,
		policy)!
	result_label := if result.auto_merged { cli_success('auto_merged') } else { 'applied' }
	sidecar_target := if repo_name.len == 0 { sidecar_url } else { '${sidecar_url} [${repo_name}]' }
	println(cli_render_sync_result('Sync Push (Sidecar)', 'push', ctx.root_dir, ctx.branch,
		sidecar_target, target_branch, sidecar_sync_policy_label(policy), result.packet_count,
		result.packet_bytes, result.branch.name, result.branch.commit_cid, result_label))
}

fn (mut cli PollyDbCli) run_sync_pull_sidecar() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx || !cli_looks_like_url(cli.args[ctx.next_idx]) {
		return error('sync-pull-sidecar requires [root_dir] [branch] <sidecar_url> [repo_name] [source_branch] [policy]')
	}
	sidecar_url := cli.args[ctx.next_idx]
	mut repo_name := ''
	mut source_branch := ctx.branch
	mut next_idx := ctx.next_idx + 1
	if cli.args.len > next_idx && !looks_like_sync_negotiation_policy(cli.args[next_idx]) {
		if cli.args.len > next_idx + 1
			&& !looks_like_sync_negotiation_policy(cli.args[next_idx + 1]) {
			repo_name = cli.args[next_idx]
			source_branch = cli.args[next_idx + 1]
			next_idx += 2
		} else {
			source_branch = cli.args[next_idx]
			next_idx++
		}
	}
	policy := if cli.args.len > next_idx {
		parse_sidecar_sync_negotiation_policy(cli.args[next_idx])!
	} else {
		resolve_sidecar_default_sync_policy(pollylink.Client{
			base_url:   sidecar_url
			repo_name:  repo_name
			auth_token: cli_sidecar_auth_token()
		})
	}
	mut repo := pollylink.open_local_repo(ctx.root_dir, ctx.branch)!
	defer {
		repo.close() or {}
	}
	client := pollylink.Client{
		base_url:   sidecar_url
		repo_name:  repo_name
		auth_token: cli_sidecar_auth_token()
	}
	result := pollylink.pull_branch_from_sidecar(mut repo, ctx.branch, client, source_branch,
		policy)!
	sidecar_source := if repo_name.len == 0 { sidecar_url } else { '${sidecar_url} [${repo_name}]' }
	println(cli_render_sync_result('Sync Pull (Sidecar)', 'pull', sidecar_source, source_branch,
		ctx.root_dir, ctx.branch, sidecar_sync_policy_label(policy), result.packet_count,
		result.packet_bytes, result.branch.name, result.branch.commit_cid, 'applied'))
}

fn (mut cli PollyDbCli) run_sidecar_repos() ! {
	if cli.args.len < 2 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-repos requires <sidecar_url>')
	}
	client := pollylink.Client{
		base_url:   cli.args[1]
		auth_token: cli_sidecar_auth_token()
	}
	repos := client.list_repositories()!
	if repos.len == 0 {
		println(cli_empty('no repositories', 'open one with `pollydb sidecar-open-repo`'))
		return
	}
	mut rows := [][]string{cap: repos.len}
	for repo_name in repos {
		rows << [repo_name]
	}
	println(cli_title('Sidecar Repositories'))
	println(cli_render_table(['repo'], rows))
}

fn (mut cli PollyDbCli) run_sidecar_repo_summaries() ! {
	if cli.args.len < 2 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-repo-summaries requires <sidecar_url> [limit]')
	}
	sidecar_url := cli.args[1]
	limit := if cli.args.len > 2 && cli.args[2].int() > 0 { cli.args[2].int() } else { 20 }
	client := pollylink.Client{
		base_url:   sidecar_url
		auth_token: cli_sidecar_auth_token()
	}
	infos := client.list_repository_summaries(limit)!
	println(cli_render_sidecar_repo_summaries(infos))
}

fn (mut cli PollyDbCli) run_sidecar_global_activity() ! {
	if cli.args.len < 2 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-global-activity requires <sidecar_url> [limit]')
	}
	sidecar_url := cli.args[1]
	limit := if cli.args.len > 2 && cli.args[2].int() > 0 { cli.args[2].int() } else { 20 }
	client := pollylink.Client{
		base_url:   sidecar_url
		auth_token: cli_sidecar_auth_token()
	}
	entries := client.global_activity(limit)!
	println(cli_render_sidecar_global_activity(entries))
}

fn (mut cli PollyDbCli) run_sidecar_open_repo() ! {
	if cli.args.len < 3 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-open-repo requires <sidecar_url> <repo_name> [default_branch]')
	}
	sidecar_url := cli.args[1]
	repo_name := cli.args[2]
	default_branch := if cli.args.len > 3 { cli.args[3] } else { 'main' }
	client := pollylink.Client{
		base_url:   sidecar_url
		repo_name:  repo_name
		auth_token: cli_sidecar_auth_token()
	}
	info := client.open_repository(default_branch)!
	println(cli_render_sidecar_repo_info(info))
}

fn (mut cli PollyDbCli) run_sidecar_governance_status() ! {
	if cli.args.len < 2 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-governance-status requires <sidecar_url>')
	}
	client := pollylink.Client{
		base_url:   cli.args[1]
		auth_token: cli_sidecar_auth_token()
	}
	status := client.governance_status()!
	println(cli_render_sidecar_governance_status(status))
}

fn (mut cli PollyDbCli) run_sidecar_branches() ! {
	if cli.args.len < 2 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-branches requires <sidecar_url> [repo_name]')
	}
	sidecar_url := cli.args[1]
	repo_name := if cli.args.len > 2 { cli.args[2] } else { '' }
	client := pollylink.Client{
		base_url:   sidecar_url
		repo_name:  repo_name
		auth_token: cli_sidecar_auth_token()
	}
	statuses := client.branch_statuses()!
	println(cli_render_sidecar_branch_statuses(repo_name, statuses))
}

fn (mut cli PollyDbCli) run_sidecar_branch_status() ! {
	if cli.args.len < 3 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-branch-status requires <sidecar_url> [repo_name] <branch>')
	}
	sidecar_url := cli.args[1]
	mut repo_name := ''
	mut branch_name := ''
	if cli.args.len == 3 {
		branch_name = cli.args[2]
	} else {
		repo_name = cli.args[2]
		branch_name = cli.args[3]
	}
	client := pollylink.Client{
		base_url:   sidecar_url
		repo_name:  repo_name
		auth_token: cli_sidecar_auth_token()
	}
	status := client.branch_status(branch_name)!
	println(cli_render_sidecar_branch_status(repo_name, status))
}

fn (mut cli PollyDbCli) run_sidecar_repo_activity() ! {
	if cli.args.len < 2 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-repo-activity requires <sidecar_url> [repo_name] [limit]')
	}
	sidecar_url := cli.args[1]
	mut repo_name := ''
	mut limit := 10
	if cli.args.len > 2 {
		if cli.args[2].int() > 0 {
			limit = cli.args[2].int()
		} else {
			repo_name = cli.args[2]
		}
	}
	if cli.args.len > 3 {
		limit = cli.args[3].int()
		if limit <= 0 {
			limit = 10
		}
	}
	client := pollylink.Client{
		base_url:   sidecar_url
		repo_name:  repo_name
		auth_token: cli_sidecar_auth_token()
	}
	entries := client.repo_activity(limit)!
	println(cli_render_sidecar_repo_activity(repo_name, entries))
}

fn (mut cli PollyDbCli) run_sidecar_branch_activity() ! {
	if cli.args.len < 3 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-branch-activity requires <sidecar_url> [repo_name] <branch>')
	}
	sidecar_url := cli.args[1]
	mut repo_name := ''
	mut branch_name := ''
	if cli.args.len == 3 {
		branch_name = cli.args[2]
	} else {
		repo_name = cli.args[2]
		branch_name = cli.args[3]
	}
	client := pollylink.Client{
		base_url:   sidecar_url
		repo_name:  repo_name
		auth_token: cli_sidecar_auth_token()
	}
	activity := client.branch_activity(branch_name)!
	println(cli_render_sidecar_branch_activity(repo_name, activity))
}

fn (mut cli PollyDbCli) run_sidecar_branch_log() ! {
	if cli.args.len < 3 || !cli_looks_like_url(cli.args[1]) {
		return error('sidecar-branch-log requires <sidecar_url> [repo_name] <branch> [limit]')
	}
	sidecar_url := cli.args[1]
	mut repo_name := ''
	mut branch_name := ''
	mut limit := 10
	if cli.args.len == 3 {
		branch_name = cli.args[2]
	} else if cli.args.len == 4 {
		if cli.args[3].int() > 0 {
			branch_name = cli.args[2]
			limit = cli.args[3].int()
		} else {
			repo_name = cli.args[2]
			branch_name = cli.args[3]
		}
	} else {
		repo_name = cli.args[2]
		branch_name = cli.args[3]
		limit = cli.args[4].int()
		if limit <= 0 {
			limit = 10
		}
	}
	client := pollylink.Client{
		base_url:   sidecar_url
		repo_name:  repo_name
		auth_token: cli_sidecar_auth_token()
	}
	entries := client.branch_log(branch_name, limit)!
	println(cli_render_sidecar_branch_log(repo_name, branch_name, entries))
}

fn (mut cli PollyDbCli) run_sidecar_init_governance() ! {
	if cli.args.len < 4 || cli_looks_like_url(cli.args[1]) {
		return error('sidecar-init-governance requires <storage_root> <actor> <token>')
	}
	root_dir := os.real_path(cli.args[1])
	actor := cli.args[2]
	token := cli.args[3]
	pollylink.init_governance(root_dir, actor, token)!
	println(cli_render_field_card('Sidecar Governance', [
		CliField{'root', root_dir},
		CliField{'actor', actor},
		CliField{'status', cli_success('initialized')},
	]))
}

fn (mut cli PollyDbCli) run_sidecar_grant_repo() ! {
	if cli.args.len < 5 || cli_looks_like_url(cli.args[1]) {
		return error('sidecar-grant-repo requires <storage_root> <repo_name> <actor> <role>')
	}
	root_dir := os.real_path(cli.args[1])
	repo_name := cli.args[2]
	actor := cli.args[3]
	role := match cli.args[4] {
		'reader' { pollylink.RepoRole.reader }
		'writer' { pollylink.RepoRole.writer }
		'admin' { pollylink.RepoRole.admin }
		else { return error('invalid repo role: ${cli.args[4]}') }
	}
	pollylink.grant_repo_access(root_dir, repo_name, actor, role)!
	println(cli_render_field_card('Sidecar Repo Grant', [
		CliField{'root', root_dir},
		CliField{'repo', repo_name},
		CliField{'actor', actor},
		CliField{'role', cli.args[4]},
		CliField{'status', cli_success('granted')},
	]))
}

fn cli_parse_bool(raw string) !bool {
	value := raw.trim_space().to_lower()
	return match value {
		'true', '1', 'yes', 'y', 'on' { true }
		'false', '0', 'no', 'n', 'off' { false }
		else { return error('invalid boolean: ${raw}') }
	}
}

fn (mut cli PollyDbCli) run_sidecar_set_repo_policy() ! {
	if cli.args.len < 5 || cli_looks_like_url(cli.args[1]) {
		return error('sidecar-set-repo-policy requires <storage_root> <repo_name> <allow_push_to_default> <require_auto_merge> [default_sync_policy]')
	}
	root_dir := os.real_path(cli.args[1])
	repo_name := cli.args[2]
	allow_push_to_default := cli_parse_bool(cli.args[3])!
	require_auto_merge := cli_parse_bool(cli.args[4])!
	default_sync_policy := if cli.args.len > 5 && cli.args[5].len > 0 { cli.args[5] } else { 'auto' }
	pollylink.set_repo_policy(root_dir, repo_name, allow_push_to_default, require_auto_merge,
		default_sync_policy)!
	println(cli_render_field_card('Sidecar Repo Policy', [
		CliField{'root', root_dir},
		CliField{'repo', repo_name},
		CliField{'allow_push_to_default', if allow_push_to_default {
			cli_success('true')
		} else {
			cli_warn('false')
		}},
		CliField{'require_auto_merge', if require_auto_merge {
			cli_warn('true')
		} else {
			cli_dim('false')
		}},
		CliField{'default_sync_policy', default_sync_policy},
		CliField{'status', cli_success('updated')},
	]))
}

fn (mut cli PollyDbCli) run_sidecar_set_branch_policy() ! {
	if cli.args.len < 6 || cli_looks_like_url(cli.args[1]) {
		return error('sidecar-set-branch-policy requires <storage_root> <repo_name> <branch_name> <allow_push> <require_auto_merge> [default_sync_policy]')
	}
	root_dir := os.real_path(cli.args[1])
	repo_name := cli.args[2]
	branch_name := cli.args[3]
	allow_push := cli_parse_bool(cli.args[4])!
	require_auto_merge := cli_parse_bool(cli.args[5])!
	default_sync_policy := if cli.args.len > 6 && cli.args[6].len > 0 { cli.args[6] } else { 'auto' }
	pollylink.set_branch_policy(root_dir, repo_name, branch_name, allow_push, require_auto_merge,
		default_sync_policy)!
	println(cli_render_field_card('Sidecar Branch Policy', [
		CliField{'root', root_dir},
		CliField{'repo', repo_name},
		CliField{'branch', branch_name},
		CliField{'allow_push', if allow_push { cli_success('true') } else { cli_warn('false') }},
		CliField{'require_auto_merge', if require_auto_merge {
			cli_warn('true')
		} else {
			cli_dim('false')
		}},
		CliField{'default_sync_policy', default_sync_policy},
		CliField{'status', cli_success('updated')},
	]))
}

fn (mut cli PollyDbCli) run_sidecar_set_rate_limit() ! {
	if cli.args.len < 3 || cli_looks_like_url(cli.args[1]) {
		return error('sidecar-set-rate-limit requires <storage_root> <requests_per_minute>')
	}
	root_dir := os.real_path(cli.args[1])
	requests_per_minute := cli.args[2].int()
	pollylink.set_rate_limit_policy(root_dir, requests_per_minute)!
	println(cli_render_field_card('Sidecar Rate Limit', [
		CliField{'root', root_dir},
		CliField{'requests_per_minute', if requests_per_minute > 0 {
			requests_per_minute.str()
		} else {
			cli_dim('unlimited')
		}},
		CliField{'status', cli_success('updated')},
	]))
}

fn (mut cli PollyDbCli) run_sidecar_audit_log() ! {
	if cli.args.len < 2 || cli_looks_like_url(cli.args[1]) {
		return error('sidecar-audit-log requires <storage_root> [limit]')
	}
	root_dir := os.real_path(cli.args[1])
	limit := if cli.args.len > 2 && cli.args[2].int() > 0 { cli.args[2].int() } else { 20 }
	entries := pollylink.read_audit_entries(root_dir, limit)!
	println(cli_render_sidecar_audit(entries))
}

fn (mut cli PollyDbCli) run_branches() ! {
	ctx := cli.resolve_db_context(1, true)!
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	names := db.branch_names()
	if names.len == 0 {
		println(cli_empty('no branches', 'create one with `pollydb create-branch`'))
		return
	}
	mut rows := [][]string{cap: names.len}
	for name in names {
		head := db.branch(name)!
		rows << [head.name, head.commit_cid]
	}
	println(cli_title('Branches'))
	println(cli_render_table(['branch', 'head_commit'], rows))
}

fn (mut cli PollyDbCli) run_create_branch() ! {
	ctx := cli.resolve_root_context(1, true)!
	if cli.args.len <= ctx.next_idx {
		return error('create-branch requires [root_dir] <new_branch> [from_branch]')
	}
	new_branch := cli.args[ctx.next_idx]
	from_branch := if cli.args.len > ctx.next_idx + 1 {
		cli.args[ctx.next_idx + 1]
	} else {
		ctx.default_branch
	}
	mut db := storage.PersistentDatabase.open(ctx.root_dir, from_branch)!
	defer {
		db.close() or {}
	}
	source := db.branch(from_branch)!
	created := db.create_branch(new_branch, source.commit_cid)!
	db.checkpoint()!
	println(cli_render_field_card('Branch Created', [
		CliField{'branch', created.name},
		CliField{'head_commit', created.commit_cid},
	]))
}

fn (mut cli PollyDbCli) run_checkout() ! {
	ctx := cli.resolve_db_context(1, true)!
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	commit := db.checkout(ctx.branch)!
	println(cli_render_field_card('Branch Head', [
		CliField{'branch', ctx.branch},
		CliField{'commit', commit.cid},
		CliField{'root', commit.root_cid},
		CliField{'parents', commit.parent_cids.len.str()},
		CliField{'author', commit.meta.author},
		CliField{'message', commit.meta.message},
	]))
}

fn (mut cli PollyDbCli) run_show_branch() ! {
	ctx := cli.resolve_db_context(1, true)!
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	branch := db.branch(ctx.branch)!
	commit := db.checkout(ctx.branch)!
	println(cli_render_field_card('Branch', [
		CliField{'name', branch.name},
		CliField{'head_commit', branch.commit_cid},
	]))
	println('')
	println(cli_render_field_card('Head Commit', [
		CliField{'commit', commit.cid},
		CliField{'root', commit.root_cid},
		CliField{'parents', commit.parent_cids.len.str()},
		CliField{'author', commit.meta.author},
		CliField{'message', commit.meta.message},
	]))
}

fn (mut cli PollyDbCli) run_log() ! {
	ctx := cli.resolve_db_context(1, true)!
	limit := if cli.args.len > ctx.next_idx { cli.args[ctx.next_idx].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	commits := db.branch_log(ctx.branch, limit)!
	if commits.len == 0 {
		println(cli_empty('no commits', 'this branch has no commit history yet'))
		return
	}
	mut rows := [][]string{cap: commits.len}
	for commit in commits {
		rows << [commit.cid, commit.root_cid, commit.meta.author, commit.meta.message]
	}
	println(cli_title('Commit Log'))
	println(cli_render_table(['commit', 'root', 'author', 'message'], rows))
}

fn (mut cli PollyDbCli) run_merge_base() ! {
	ctx := cli.resolve_root_context(1, true)!
	if cli.args.len <= ctx.next_idx + 1 {
		return error('merge-base requires [root_dir] <left_branch> <right_branch>')
	}
	left_branch := cli.args[ctx.next_idx]
	right_branch := cli.args[ctx.next_idx + 1]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, left_branch)!
	defer {
		db.close() or {}
	}
	base := db.merge_base_branch(left_branch, right_branch)!
	println(cli_render_commit('Merge Base', base))
}

fn (mut cli PollyDbCli) run_merge_preview() ! {
	ctx := cli.resolve_root_context(1, true)!
	if cli.args.len <= ctx.next_idx + 1 {
		return error('merge-preview requires [root_dir] <ours_branch> <theirs_branch>')
	}
	ours_branch := cli.args[ctx.next_idx]
	theirs_branch := cli.args[ctx.next_idx + 1]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ours_branch)!
	defer {
		db.close() or {}
	}
	preview := db.preview_merge(ours_branch, theirs_branch, storage.ChunkConfig.default())!
	println(cli_render_merge_preview(preview))
}

fn (mut cli PollyDbCli) run_merge_report() ! {
	ctx := cli.resolve_root_context(1, true)!
	if cli.args.len <= ctx.next_idx + 1 {
		return error('merge-report requires [root_dir] <ours_branch> <theirs_branch> [conflict_limit]')
	}
	ours_branch := cli.args[ctx.next_idx]
	theirs_branch := cli.args[ctx.next_idx + 1]
	conflict_limit := if cli.args.len > ctx.next_idx + 2 {
		cli.args[ctx.next_idx + 2].int()
	} else {
		8
	}
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ours_branch)!
	defer {
		db.close() or {}
	}
	report := db.merge_report(ours_branch, theirs_branch, storage.ChunkConfig.default(),
		conflict_limit)!
	println(cli_render_merge_report(report))
}

fn (mut cli PollyDbCli) run_merge_branch() ! {
	ctx := cli.resolve_root_context(1, true)!
	if cli.args.len <= ctx.next_idx + 1 {
		return error('merge-branch requires [root_dir] <ours_branch> <theirs_branch> [strategy]')
	}
	ours_branch := cli.args[ctx.next_idx]
	theirs_branch := cli.args[ctx.next_idx + 1]
	strategy := if cli.args.len > ctx.next_idx + 2 { cli.args[ctx.next_idx + 2] } else { '' }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ours_branch)!
	defer {
		db.close() or {}
	}
	cfg := storage.ChunkConfig.default()
	if strategy.len == 0 {
		result := db.merge_branches(ours_branch, theirs_branch, cfg)!
		if result.conflicts.len > 0 {
			return error('merge has ${result.conflicts.len} conflicts; rerun with strategy ours or theirs')
		}
		update := db.commit_to_branch(ours_branch, result.tree, storage.CommitMeta{
			author:    'pollydb-cli'
			message:   'merge ${theirs_branch} into ${ours_branch}'
			timestamp: 0
		})!
		println(cli_render_field_card('Merge Commit', [
			CliField{'branch', update.branch.name},
			CliField{'head_commit', update.branch.commit_cid},
		]))
		return
	}
	resolution_strategy := parse_merge_strategy(strategy)!
	result := db.merge_branches(ours_branch, theirs_branch, cfg)!
	mut resolutions := []storage.ConflictResolution{cap: result.conflicts.len}
	for conflict in result.conflicts {
		resolutions << match resolution_strategy {
			.ours { storage.ConflictResolution.use_ours(conflict.key) }
			.theirs { storage.ConflictResolution.use_theirs(conflict.key) }
			else { storage.ConflictResolution.use_ours(conflict.key) }
		}
	}
	update := db.merge_branch_into(ours_branch, theirs_branch, resolutions, cfg, storage.CommitMeta{
		author:    'pollydb-cli'
		message:   'merge ${theirs_branch} into ${ours_branch} (${strategy})'
		timestamp: 0
	})!
	println(cli_render_field_card('Merge Commit', [
		CliField{'branch', update.branch.name},
		CliField{'head_commit', update.branch.commit_cid},
		CliField{'strategy', strategy},
	]))
}

fn (mut cli PollyDbCli) run_tables() ! {
	ctx := cli.resolve_db_context(1, true)!
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	names := db.table_names()
	if names.len == 0 {
		println(cli_empty('no tables', 'create one with `pollydb create-table`'))
		return
	}
	mut rows := [][]string{cap: names.len}
	for name in names {
		spec := db.table_spec(name)!
		rows << [name, spec.table.primary_key.join(','), spec.table.columns.len.str(),
			spec.indexes.len.str()]
	}
	println(cli_title('Tables'))
	println(cli_render_table(['table', 'primary_key', 'columns', 'indexes'], rows))
}

fn (mut cli PollyDbCli) run_describe_table() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx {
		return error('describe-table requires [root_dir] [branch] <table_name>')
	}
	table_name := cli.args[ctx.next_idx]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	spec := db.table_spec(table_name)!
	println(cli_render_field_card('Table', [
		CliField{'name', spec.name()},
		CliField{'primary_key', spec.table.primary_key.join(',')},
	]))
	mut column_rows := [][]string{cap: spec.table.columns.len}
	for column in spec.table.columns {
		mut modifiers := []string{}
		if column.nullable {
			modifiers << 'nullable'
		}
		if column.aggregate != .none {
			modifiers << column.aggregate.str()
		}
		if column.default_current_timestamp {
			modifiers << 'current_timestamp'
		}
		if column.auto_update_current_timestamp {
			modifiers << 'auto_update'
		}
		column_rows << [column.name, format_column_type(column), if modifiers.len > 0 {
			modifiers.join(',')
		} else {
			'-'
		}]
	}
	println('')
	println(cli_title('Columns'))
	println(cli_render_table(['name', 'type', 'modifiers'], column_rows))
	if spec.indexes.len > 0 {
		mut index_rows := [][]string{cap: spec.indexes.len}
		for index in spec.indexes {
			index_rows << [index.name, index.target_label(), if index.stores_row {
				'covering'
			} else {
				'standard'
			}]
		}
		println('')
		println(cli_title('Indexes'))
		println(cli_render_table(['name', 'target', 'mode'], index_rows))
	}
}

fn (mut cli PollyDbCli) run_export_catalog() ! {
	ctx := cli.resolve_db_context(1, true)!
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	names := db.table_names()
	if names.len == 0 {
		println(cli_empty('no tables', 'create one with `pollydb create-table`'))
		return
	}
	mut rows := [][]string{cap: names.len}
	for name in names {
		spec := db.table_spec(name)!
		rows << [name, spec.table.primary_key.join(','), spec.table.columns.len.str(),
			spec.indexes.len.str()]
	}
	println(cli_title('Catalog'))
	println(cli_render_table(['table', 'primary_key', 'columns', 'indexes'], rows))
}

fn (mut cli PollyDbCli) run_register_table() ! {
	ctx := cli.resolve_db_context(1, false)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('register-table requires [root_dir] [branch] <table_name> <primary_key_csv> <columns_csv> [indexes_csv]')
	}
	table_name := cli.args[ctx.next_idx]
	primary_key_csv := cli.args[ctx.next_idx + 1]
	columns_csv := cli.args[ctx.next_idx + 2]
	indexes_csv := if cli.args.len > ctx.next_idx + 3 { cli.args[ctx.next_idx + 3] } else { '-' }
	spec := parse_register_table_spec(table_name, primary_key_csv, columns_csv, indexes_csv)!
	status := storage.PersistentDatabase.inspect(ctx.root_dir, ctx.branch) or {
		storage.PersistentDatabaseStatusReport{}
	}
	mut db := if status.repository_exists || status.catalog_exists {
		storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	} else {
		storage.PersistentDatabase.init(ctx.root_dir, ctx.branch)!
	}
	defer {
		db.close() or {}
	}
	changed := db.register_or_update_table(spec)!
	if changed && ctx.branch in db.branch_names() {
		_ = db.rebuild_indexes_at_branch(ctx.branch, [spec.name()], storage.ChunkConfig.default())!
	}
	db.checkpoint()!
	report := db.status_report()!
	println(cli_render_status_report(report))
}

fn (mut cli PollyDbCli) run_rebuild_indexes() ! {
	ctx := cli.resolve_db_context(1, true)!
	tables_csv := if cli.args.len > ctx.next_idx { cli.args[ctx.next_idx] } else { '' }
	table_names := if tables_csv.len == 0 || tables_csv == '-' {
		[]string{}
	} else {
		parse_csv_values(tables_csv)
	}
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	update := db.rebuild_indexes_at_branch(ctx.branch, table_names, storage.ChunkConfig.default())!
	db.checkpoint()!
	mut fields := [
		CliField{'branch', ctx.branch},
		CliField{'tables', if table_names.len > 0 { table_names.join(',') } else { cli_dim('(all)') }},
		CliField{'commit', update.branch.commit_cid},
		CliField{'root', update.snapshot.commit.root_cid},
	]
	println(cli_render_field_card('Rebuild Indexes', fields))
}

fn (mut cli PollyDbCli) run_projectors() ! {
	ctx := cli.resolve_db_context(1, true)!
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	states := db.projection_states_at_branch(ctx.branch)!
	if states.len == 0 {
		println(cli_empty('no aggregate projectors', 'register one with `pollydb register-aggregate-projection`'))
		return
	}
	report := db.status_report()!
	println(cli_render_field_card('Projectors', [
		CliField{'recommended_policy', report.recommended_aggregate_projection_refresh_policy},
		CliField{'fresh', report.fresh_projectors.str()},
		CliField{'stale', report.stale_projectors.str()},
	]))
	println('')
	mut rows := [][]string{cap: states.len}
	for state in states {
		rows << [
			state.projection.name,
			state.projection.table_name,
			state.projection.column_name,
			state.projection.priority.str(),
			state.projection.cost_hint.str(),
			if state.fresh { 'fresh' } else { 'stale' },
			if state.stale_reason.len > 0 { state.stale_reason } else { '-' },
		]
	}
	println(cli_render_table(['name', 'table', 'column', 'priority', 'cost', 'state', 'reason'],
		rows))
}

fn (mut cli PollyDbCli) run_register_aggregate_projection() ! {
	ctx := cli.resolve_db_context(1, false)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('register-aggregate-projection requires [root_dir] [branch] <name> <table_name> <column_name> [json_path] [priority] [cost_hint]')
	}
	name := cli.args[ctx.next_idx]
	table_name := cli.args[ctx.next_idx + 1]
	column_name := cli.args[ctx.next_idx + 2]
	json_path := if cli.args.len > ctx.next_idx + 3 { cli.args[ctx.next_idx + 3] } else { '' }
	priority := if cli.args.len > ctx.next_idx + 4 { cli.args[ctx.next_idx + 4].int() } else { 100 }
	cost_hint := if cli.args.len > ctx.next_idx + 5 {
		parse_aggregate_projection_cost_hint(cli.args[ctx.next_idx + 5])!
	} else {
		storage.AggregateProjectionCostHint.medium
	}
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch) or {
		storage.PersistentDatabase.init(ctx.root_dir, ctx.branch)!
	}
	defer {
		db.close() or {}
	}
	def := if json_path.len == 0 {
		storage.AggregateProjectionDef.sum_i64(name, table_name, column_name)!
	} else {
		storage.AggregateProjectionDef.sum_json_i64(name, table_name, column_name, json_path)!
	}.with_priority(priority).with_cost_hint(cost_hint)
	if name !in db.projector_names() {
		db.register_aggregate_projection(def)!
	}
	states := db.projection_states_at_branch(ctx.branch) or { []storage.AggregateProjectorState{} }
	if states.len == 0 {
		println(cli_render_fields('Projector Registered', [
			CliField{'name', name},
			CliField{'state', 'pending'},
		]))
		return
	}
	for state in states {
		if state.projection.name == name {
			println(cli_render_fields('Projector Registered', [
				CliField{'name', state.projection.name},
				CliField{'table', state.projection.table_name},
				CliField{'column', state.projection.column_name},
				CliField{'priority', state.projection.priority.str()},
				CliField{'cost_hint', state.projection.cost_hint.str()},
				CliField{'state', if state.fresh { 'fresh' } else { 'stale' }},
				CliField{'reason', if state.stale_reason.len > 0 { state.stale_reason } else { '-' }},
			]))
			return
		}
	}
	println(cli_render_fields('Projector Registered', [
		CliField{'name', name},
	]))
}

fn (mut cli PollyDbCli) run_refresh_aggregate_projections() ! {
	ctx := cli.resolve_db_context(1, true)!
	policy := if cli.args.len > ctx.next_idx {
		parse_aggregate_projection_refresh_policy(cli.args[ctx.next_idx])!
	} else {
		storage.AggregateProjectionRefreshPolicy.stale_all
	}
	limit := if cli.args.len > ctx.next_idx + 1 { cli.args[ctx.next_idx + 1].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	effective_limit := match policy {
		.none {
			-1
		}
		.stale_one {
			1
		}
		.stale_up_to {
			if limit > 0 { limit } else { return error('stale_up_to requires a positive [limit]') }
		}
		.stale_all {
			0
		}
	}
	if effective_limit < 0 {
		println(cli_render_fields('Projector Refresh', [
			CliField{'policy', 'none'},
			CliField{'status', 'skipped'},
		]))
		println('')
		mut rows := [][]string{}
		for state in db.projection_states_at_branch(ctx.branch)! {
			rows << [
				state.projection.name,
				if state.fresh { 'fresh' } else { 'stale' },
				if state.stale_reason.len > 0 { state.stale_reason } else { '-' },
			]
		}
		if rows.len > 0 {
			println(cli_render_table(['name', 'state', 'reason'], rows))
		}
		return
	}
	commit := db.refresh_aggregate_projections_limited(ctx.branch, storage.ChunkConfig.default(),
		storage.CommitMeta{
		author:    'pollydb-cli'
		message:   'refresh aggregate projections'
		timestamp: 0
	}, effective_limit)!
	println(cli_render_fields('Projector Refresh', [
		CliField{'policy', policy.str()},
		CliField{'commit', commit.cid},
		CliField{'root', commit.root_cid},
	]))
	if commit.virtual_roots.len > 0 {
		println('')
		mut rows := [][]string{cap: commit.virtual_roots.len}
		for virtual_root in commit.virtual_roots {
			rows << [
				virtual_root.name,
				if virtual_root.root_cid.len > 0 { virtual_root.root_cid } else { '(pending)' },
				virtual_root.source_data_root_cid,
				virtual_root.fresh.str(),
			]
		}
		println(cli_render_table(['name', 'virtual_root', 'source_data_root', 'fresh'],
			rows))
	}
}

fn (mut cli PollyDbCli) run_put_row() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('put-row requires [root_dir] [branch] <table_name> <primary_key> <field_values_csv>')
	}
	table_name := cli.args[ctx.next_idx]
	primary_key := cli.args[ctx.next_idx + 1]
	field_values_csv := cli.args[ctx.next_idx + 2]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	input_row := build_typed_row(spec, field_values_csv)!
	row := ingest_external_columns(mut db, spec, apply_insert_defaults(spec, input_row))!
	auto_filled := detect_auto_filled_columns(spec, input_row, row)
	cfg := storage.ChunkConfig.default()
	if !branch_exists(mut db, ctx.branch) {
		codec := storage.TypedRowCodec.new(spec.table)
		table_view := storage.TableView.new(storage.Tree{}, table_name)
		mut tree := storage.Tree.build([
			storage.KVPair{
				key:   table_view.row_key(primary_key.bytes())
				value: codec.encode(row)!
			},
		], cfg)!
		tree = storage.rebuild_typed_indexes_for_specs(tree, [spec], cfg)!
		tree = storage.rebuild_typed_aggregates_for_specs(tree, [spec], cfg)!
		_ = db.commit_to_branch(ctx.branch, tree, storage.CommitMeta{
			author:    'pollydb-cli'
			message:   'init branch ${ctx.branch} with ${table_name}:${primary_key}'
			timestamp: 0
		})!
	} else {
		_ = session.put_row(mut db, table_name, primary_key.bytes(), row, cfg, storage.CommitMeta{
			author:    'pollydb-cli'
			message:   'put row ${table_name}:${primary_key}'
			timestamp: 0
		})!
	}
	session2 := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	loaded := session2.get_row(mut db, table_name, primary_key.bytes())!
	if auto_filled.len > 0 {
		println(cli_render_fields('Auto-filled', [
			CliField{'columns', auto_filled.join(',')},
		]))
		println('')
	}
	println(cli_render_rows('Row', spec, [loaded]))
}

fn (mut cli PollyDbCli) run_set_json_path() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 5 {
		return error('set-json-path requires [root_dir] [branch] <table_name> <primary_key> <json_column> <json_path> <value_type> <value>')
	}
	table_name := cli.args[ctx.next_idx]
	primary_key := cli.args[ctx.next_idx + 1]
	json_column := cli.args[ctx.next_idx + 2]
	json_path := cli.args[ctx.next_idx + 3]
	value_type := cli.args[ctx.next_idx + 4]
	raw_value := cli.args[ctx.next_idx + 5]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	value := parse_json_scalar_value(value_type, raw_value)!
	_ = session.set_json_path(mut db, table_name, primary_key.bytes(), json_column, json_path,
		value, storage.ChunkConfig.default(), storage.CommitMeta{
		author:    'pollydb-cli'
		message:   'set json path ${json_column}.${json_path}'
		timestamp: 0
	})!
	loaded := session.get_row(mut db, table_name, primary_key.bytes())!
	println(cli_render_rows('Row', spec, [loaded]))
}

fn (mut cli PollyDbCli) run_null_json_path() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 3 {
		return error('null-json-path requires [root_dir] [branch] <table_name> <primary_key> <json_column> <json_path>')
	}
	table_name := cli.args[ctx.next_idx]
	primary_key := cli.args[ctx.next_idx + 1]
	json_column := cli.args[ctx.next_idx + 2]
	json_path := cli.args[ctx.next_idx + 3]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	_ = session.set_json_path_null(mut db, table_name, primary_key.bytes(), json_column,
		json_path, storage.ChunkConfig.default(), storage.CommitMeta{
		author:    'pollydb-cli'
		message:   'null json path ${json_column}.${json_path}'
		timestamp: 0
	})!
	loaded := session.get_row(mut db, table_name, primary_key.bytes())!
	println(cli_render_rows('Row', spec, [loaded]))
}

fn (mut cli PollyDbCli) run_delete_json_path() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 3 {
		return error('delete-json-path requires [root_dir] [branch] <table_name> <primary_key> <json_column> <json_path>')
	}
	table_name := cli.args[ctx.next_idx]
	primary_key := cli.args[ctx.next_idx + 1]
	json_column := cli.args[ctx.next_idx + 2]
	json_path := cli.args[ctx.next_idx + 3]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	_ = session.delete_json_path(mut db, table_name, primary_key.bytes(), json_column,
		json_path, storage.ChunkConfig.default(), storage.CommitMeta{
		author:    'pollydb-cli'
		message:   'delete json path ${json_column}.${json_path}'
		timestamp: 0
	})!
	loaded := session.get_row(mut db, table_name, primary_key.bytes())!
	println(cli_render_rows('Row', spec, [loaded]))
}

fn (mut cli PollyDbCli) run_patch_json_paths() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 3 {
		return error('patch-json-paths requires [root_dir] [branch] <table_name> <primary_key> <json_column> <updates_csv>')
	}
	table_name := cli.args[ctx.next_idx]
	primary_key := cli.args[ctx.next_idx + 1]
	json_column := cli.args[ctx.next_idx + 2]
	updates_csv := cli.args[ctx.next_idx + 3]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	updates := parse_json_path_updates(updates_csv)!
	_ = session.patch_json_paths(mut db, table_name, primary_key.bytes(), json_column,
		updates, storage.ChunkConfig.default(), storage.CommitMeta{
		author:    'pollydb-cli'
		message:   'patch json paths ${json_column}'
		timestamp: 0
	})!
	loaded := session.get_row(mut db, table_name, primary_key.bytes())!
	println(cli_render_rows('Row', spec, [loaded]))
}

fn (mut cli PollyDbCli) run_get_row() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 1 {
		return error('get-row requires [root_dir] [branch] <table_name> <primary_key>')
	}
	table_name := cli.args[ctx.next_idx]
	primary_key := cli.args[ctx.next_idx + 1]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	row := session.get_row(mut db, table_name, primary_key.bytes())!
	println(cli_render_rows('Row', spec, [row]))
}

fn (mut cli PollyDbCli) run_delete_row() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 1 {
		return error('delete-row requires [root_dir] [branch] <table_name> <primary_key>')
	}
	table_name := cli.args[ctx.next_idx]
	primary_key := cli.args[ctx.next_idx + 1]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	cfg := storage.ChunkConfig.default()
	_ = session.delete_row(mut db, table_name, primary_key.bytes(), cfg, storage.CommitMeta{
		author:    'pollydb-cli'
		message:   'delete row ${table_name}:${primary_key}'
		timestamp: 0
	}) or {
		if err.msg().contains('empty tree') {
			return error('cannot delete the last row from branch ${ctx.branch} yet')
		}
		return err
	}
	println('deleted ${table_name}:${primary_key}')
}

fn (mut cli PollyDbCli) run_count_rows() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx {
		return error('count-rows requires [root_dir] [branch] <table_name>')
	}
	table_name := cli.args[ctx.next_idx]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	count := session.count_rows(mut db, table_name)!
	println(cli_render_fields('Count', [
		CliField{'table', table_name},
		CliField{'count', count.str()},
	]))
}

fn (mut cli PollyDbCli) run_count_rows_range() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('count-rows-range requires [root_dir] [branch] <table_name> <start_primary_key> <end_primary_key>')
	}
	table_name := cli.args[ctx.next_idx]
	start_primary_key := cli.args[ctx.next_idx + 1].bytes()
	end_primary_key := cli.args[ctx.next_idx + 2].bytes()
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	count := session.count_rows_range(mut db, table_name, start_primary_key, end_primary_key)!
	println(cli_render_fields('Count Range', [
		CliField{'table', table_name},
		CliField{'start', cli.args[ctx.next_idx + 1]},
		CliField{'end', cli.args[ctx.next_idx + 2]},
		CliField{'count', count.str()},
	]))
}

fn (mut cli PollyDbCli) run_sum_column() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 1 {
		return error('sum-column requires [root_dir] [branch] <table_name> <column_name>')
	}
	table_name := cli.args[ctx.next_idx]
	column_name := cli.args[ctx.next_idx + 1]
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	sum := session.sum_i64_column(mut db, table_name, column_name)!
	println(cli_render_fields('Sum', [
		CliField{'table', table_name},
		CliField{'column', column_name},
		CliField{'sum', sum.str()},
	]))
}

fn (mut cli PollyDbCli) run_sum_column_range() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 3 {
		return error('sum-column-range requires [root_dir] [branch] <table_name> <column_name> <start_primary_key> <end_primary_key>')
	}
	table_name := cli.args[ctx.next_idx]
	column_name := cli.args[ctx.next_idx + 1]
	start_primary_key := cli.args[ctx.next_idx + 2].bytes()
	end_primary_key := cli.args[ctx.next_idx + 3].bytes()
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	sum := session.sum_i64_column_range(mut db, table_name, column_name, start_primary_key,
		end_primary_key)!
	println(cli_render_fields('Sum Range', [
		CliField{'table', table_name},
		CliField{'column', column_name},
		CliField{'start', cli.args[ctx.next_idx + 2]},
		CliField{'end', cli.args[ctx.next_idx + 3]},
		CliField{'sum', sum.str()},
	]))
}

fn (mut cli PollyDbCli) run_scan_table() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx {
		return error('scan-table requires [root_dir] [branch] <table_name> [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	limit := if cli.args.len > ctx.next_idx + 1 { cli.args[ctx.next_idx + 1].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	rows := session.scan_table(mut db, table_name, limit)!
	if rows.len == 0 {
		println(cli_empty('no rows', 'this table has no rows yet'))
		return
	}
	println(cli_render_rows('Rows', spec, rows))
}

fn (mut cli PollyDbCli) run_lookup_index() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('lookup-index requires [root_dir] [branch] <table_name> <index_name> <value> [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	index_name := cli.args[ctx.next_idx + 1]
	raw_value := cli.args[ctx.next_idx + 2]
	limit := if cli.args.len > ctx.next_idx + 3 { cli.args[ctx.next_idx + 3].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	index := table_index_def(spec, index_name)!
	column := index_column(spec, index_name)!
	value := parse_typed_value(column, raw_value)!
	rows := session.lookup_index(mut db, table_name, index_name, value, limit)!
	if rows.len == 0 {
		println(cli_empty('no rows', 'no rows matched this index value'))
		return
	}
	println(cli_render_fields('Index Lookup', [
		CliField{'index', index.name},
		CliField{'mode', if index.stores_row { 'covering' } else { 'standard' }},
		CliField{'matches', rows.len.str()},
	]))
	println('')
	println(cli_render_rows('', spec, rows))
}

fn (mut cli PollyDbCli) run_scan_index_between() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 3 {
		return error('scan-index-between requires [root_dir] [branch] <table_name> <index_name> <start_value> <end_value> [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	index_name := cli.args[ctx.next_idx + 1]
	raw_start := cli.args[ctx.next_idx + 2]
	raw_end := cli.args[ctx.next_idx + 3]
	limit := if cli.args.len > ctx.next_idx + 4 { cli.args[ctx.next_idx + 4].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	index := table_index_def(spec, index_name)!
	column := index_column(spec, index_name)!
	start_value := parse_typed_value(column, raw_start)!
	end_value := parse_typed_value(column, raw_end)!
	rows := session.lookup_index_between(mut db, table_name, index_name, start_value,
		end_value, limit)!
	if rows.len == 0 {
		println(cli_empty('no rows', 'no values matched the requested range'))
		return
	}
	println(cli_render_fields('Index Scan', [
		CliField{'index', index.name},
		CliField{'mode', if index.stores_row { 'covering' } else { 'standard' }},
		CliField{'scan', 'between'},
		CliField{'matches', rows.len.str()},
	]))
	println('')
	println(cli_render_rows('', spec, rows))
}

fn (mut cli PollyDbCli) run_scan_index_after() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('scan-index-after requires [root_dir] [branch] <table_name> <index_name> <value> [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	index_name := cli.args[ctx.next_idx + 1]
	raw_value := cli.args[ctx.next_idx + 2]
	limit := if cli.args.len > ctx.next_idx + 3 { cli.args[ctx.next_idx + 3].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	index := table_index_def(spec, index_name)!
	column := index_column(spec, index_name)!
	value := parse_typed_value(column, raw_value)!
	rows := session.lookup_index_after(mut db, table_name, index_name, value, limit)!
	if rows.len == 0 {
		println(cli_empty('no rows', 'no values were found after the requested boundary'))
		return
	}
	println(cli_render_fields('Index Scan', [
		CliField{'index', index.name},
		CliField{'mode', if index.stores_row { 'covering' } else { 'standard' }},
		CliField{'scan', 'after'},
		CliField{'matches', rows.len.str()},
	]))
	println('')
	println(cli_render_rows('', spec, rows))
}

fn (mut cli PollyDbCli) run_scan_index_before() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('scan-index-before requires [root_dir] [branch] <table_name> <index_name> <value> [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	index_name := cli.args[ctx.next_idx + 1]
	raw_value := cli.args[ctx.next_idx + 2]
	limit := if cli.args.len > ctx.next_idx + 3 { cli.args[ctx.next_idx + 3].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	index := table_index_def(spec, index_name)!
	column := index_column(spec, index_name)!
	value := parse_typed_value(column, raw_value)!
	rows := session.lookup_index_before(mut db, table_name, index_name, value, limit)!
	if rows.len == 0 {
		println(cli_empty('no rows', 'no values were found before the requested boundary'))
		return
	}
	println(cli_render_fields('Index Scan', [
		CliField{'index', index.name},
		CliField{'mode', if index.stores_row { 'covering' } else { 'standard' }},
		CliField{'scan', 'before'},
		CliField{'matches', rows.len.str()},
	]))
	println('')
	println(cli_render_rows('', spec, rows))
}

fn (mut cli PollyDbCli) run_scan_index() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('scan-index requires [root_dir] [branch] <table_name> <index_name> <value> [start_primary_key] [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	index_name := cli.args[ctx.next_idx + 1]
	raw_value := cli.args[ctx.next_idx + 2]
	start_primary_key := if cli.args.len > ctx.next_idx + 3 {
		cli.args[ctx.next_idx + 3].bytes()
	} else {
		[]u8{}
	}
	limit := if cli.args.len > ctx.next_idx + 4 { cli.args[ctx.next_idx + 4].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	index := table_index_def(spec, index_name)!
	column := index_column(spec, index_name)!
	value := parse_typed_value(column, raw_value)!
	mut cursor := session.index_cursor(mut db, table_name, index_name, value, start_primary_key,
		limit)!
	rows := cursor.collect(limit)!
	if rows.len == 0 {
		println(cli_empty('no rows', 'no rows matched this index value'))
		return
	}
	println('index=${index.name} mode=${if index.stores_row { 'covering' } else { 'standard' }} matches=${rows.len}')
	for row in rows {
		println(format_typed_row(row.row, spec))
	}
}

fn (mut cli PollyDbCli) run_prefix_index() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 2 {
		return error('prefix-index requires [root_dir] [branch] <table_name> <index_name> <prefix> [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	index_name := cli.args[ctx.next_idx + 1]
	raw_prefix := cli.args[ctx.next_idx + 2]
	limit := if cli.args.len > ctx.next_idx + 3 { cli.args[ctx.next_idx + 3].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	index := table_index_def(spec, index_name)!
	column := index_column(spec, index_name)!
	prefix := parse_typed_value(column, raw_prefix)!
	rows := session.lookup_index_prefix(mut db, table_name, index_name, prefix, limit)!
	if rows.len == 0 {
		println(cli_empty('no rows', 'no rows matched this prefix'))
		return
	}
	println('index=${index.name} mode=${if index.stores_row { 'covering' } else { 'standard' }} scan=prefix matches=${rows.len}')
	for row in rows {
		println(format_typed_row(row, spec))
	}
}

fn (mut cli PollyDbCli) run_prefix_index_projected() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 3 {
		return error('prefix-index-projected requires [root_dir] [branch] <table_name> <index_name> <prefix> <columns_csv> [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	index_name := cli.args[ctx.next_idx + 1]
	raw_prefix := cli.args[ctx.next_idx + 2]
	columns := parse_csv_values(cli.args[ctx.next_idx + 3])
	if columns.len == 0 {
		return error('columns_csv cannot be empty')
	}
	limit := if cli.args.len > ctx.next_idx + 4 { cli.args[ctx.next_idx + 4].int() } else { 0 }
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	index := table_index_def(spec, index_name)!
	column := index_column(spec, index_name)!
	prefix := parse_typed_value(column, raw_prefix)!
	rows := session.lookup_index_prefix_projected(mut db, table_name, index_name, prefix,
		limit, columns)!
	if rows.len == 0 {
		println(cli_empty('no rows', 'no rows matched this prefix'))
		return
	}
	println('index=${index.name} mode=${if index.stores_row { 'covering' } else { 'standard' }} scan=prefix projected=${columns.join(',')} matches=${rows.len}')
	for row in rows {
		println(format_typed_row(row, spec))
	}
}

fn (mut cli PollyDbCli) run_query_fts_preview() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 4 {
		return error('query-fts-preview requires [root_dir] [branch] <table_name> <column_name> <scope> <kind> <terms_csv> [select_columns_csv] [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	column_name := cli.args[ctx.next_idx + 1]
	scope := parse_fts_scope(cli.args[ctx.next_idx + 2])!
	kind := parse_fts_query_kind(cli.args[ctx.next_idx + 3])!
	terms := parse_csv_values(cli.args[ctx.next_idx + 4])
	select_columns, limit := parse_optional_columns_and_limit(cli.args, ctx.next_idx + 5)!
	query := queryapi.FtsRequest{
		table_name:     table_name
		column_name:    column_name
		scope:          scope
		kind:           kind
		terms:          terms
		select_columns: select_columns
		limit:          limit
	}
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	_ = db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	mut query_db := queryapi.open_database(ctx.root_dir, ctx.branch)!
	defer {
		query_db.close() or {}
	}
	query_session := query_db.begin_session(ctx.branch)!
	preview := queryapi.preview_fts_details_in_session(query_session, query)!
	mut lines := []string{}
	lines << cli_render_field_card('FTS Query Preview', [
		CliField{'table', preview.plan.table_name},
		CliField{'column', preview.plan.column_name},
		CliField{'scope', queryapi.fts_scope_name(preview.plan.scope)},
		CliField{'kind', queryapi.fts_kind_name(preview.plan.kind)},
		CliField{'selector', preview.plan.selector},
		CliField{'strategy', preview.plan.strategy},
		CliField{'index', if preview.plan.index_name.len > 0 {
			preview.plan.index_name
		} else {
			cli_dim('(scan)')
		}},
		CliField{'terms', preview.plan.term_count.str()},
		CliField{'limit', preview.plan.limit.str()},
	])
	if preview.warnings.len > 0 {
		lines << ''
		lines << cli_render_field_card('Warnings', preview.warnings.map(CliField{'warning', it}))
	}
	if preview.notes.len > 0 {
		lines << ''
		lines << cli_render_field_card('Notes', preview.notes.map(CliField{'note', it}))
	}
	println(lines.join('\n'))
}

fn (mut cli PollyDbCli) run_query_fts() ! {
	ctx := cli.resolve_db_context(1, true)!
	if cli.args.len <= ctx.next_idx + 4 {
		return error('query-fts requires [root_dir] [branch] <table_name> <column_name> <scope> <kind> <terms_csv> [select_columns_csv] [limit]')
	}
	table_name := cli.args[ctx.next_idx]
	column_name := cli.args[ctx.next_idx + 1]
	scope := parse_fts_scope(cli.args[ctx.next_idx + 2])!
	kind := parse_fts_query_kind(cli.args[ctx.next_idx + 3])!
	terms := parse_csv_values(cli.args[ctx.next_idx + 4])
	select_columns, limit := parse_optional_columns_and_limit(cli.args, ctx.next_idx + 5)!
	query := queryapi.FtsRequest{
		table_name:     table_name
		column_name:    column_name
		scope:          scope
		kind:           kind
		terms:          terms
		select_columns: select_columns
		limit:          limit
	}
	mut db := storage.PersistentDatabase.open(ctx.root_dir, ctx.branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(ctx.branch))!
	spec := session.table_spec(table_name)!
	mut query_db := queryapi.open_database(ctx.root_dir, ctx.branch)!
	defer {
		query_db.close() or {}
	}
	query_session := query_db.begin_session(ctx.branch)!
	result := queryapi.query_fts(query_session, mut query_db, query)!
	if result.rows.len == 0 {
		println(cli_empty('no rows', 'no rows matched this FTS query'))
		return
	}
	mut lines := []string{}
	lines << cli_render_field_card('FTS Query', [
		CliField{'table', result.plan.table_name},
		CliField{'column', result.plan.column_name},
		CliField{'scope', queryapi.fts_scope_name(result.plan.scope)},
		CliField{'kind', queryapi.fts_kind_name(result.plan.kind)},
		CliField{'strategy', result.plan.strategy},
		CliField{'index', if result.plan.index_name.len > 0 {
			result.plan.index_name
		} else {
			cli_dim('(scan)')
		}},
		CliField{'matches', result.rows.len.str()},
	])
	lines << ''
	lines << cli_render_fts_hits(result.hits)
	lines << ''
	lines << cli_render_query_rows('Rows', spec, result.rows)
	println(lines.join('\n'))
}

fn main() {
	mut cli := PollyDbCli.new(os.args[1..])
	cli.run() or {
		eprintln(err.msg())
		if err.msg().starts_with('unknown command:') || err.msg().contains('requires <')
			|| err.msg().contains('requires [') {
			eprintln(cli.usage())
		}
		exit(1)
	}
}
