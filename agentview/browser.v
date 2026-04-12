module agentview

import term
import term.ui as tui
import vmarkdown
import encoding.utf8.east_asian
import time
import storage

pub struct BrowserOptions {
pub:
	query            string
	cwd_prefix       string
	source           string
	include_archived bool = true
	list_limit       int  = 100
	transcript_limit int  = 40
}

enum BrowserPane {
	sessions
	transcript
}

enum BrowserView {
	transcript
	search
}

enum BrowserInputMode {
	normal
	filter
	cwd
	source
	search
}

enum SearchScope {
	all
	session
	project
}

enum SearchKindFilter {
	all
	message
	tool
	reasoning
}

struct BrowserApp {
	store   PollyDbStore
	options BrowserOptions
mut:
	db                         storage.PersistentDatabase
	db_session                 storage.DatabaseSession
	db_ready                   bool
	has_search_indexes         bool
	tui                        &tui.Context     = unsafe { nil }
	focus                      BrowserPane      = .sessions
	view                       BrowserView      = .transcript
	input_mode                 BrowserInputMode = .normal
	show_help                  bool
	help_scroll                int
	sessions                   []SessionSummary
	sessions_total             int
	list_offset                int
	selected_index             int
	session_query              string
	cwd_prefix                 string
	source_filter              string
	include_archived           bool
	transcript_page            TranscriptPage
	transcript_id              string
	transcript_offset          int
	transcript_selected        int
	transcript_line_scroll     int
	search_query               string
	search_scope               SearchScope      = .all
	search_kind                SearchKindFilter = .all
	search_results             []SearchHit
	search_total               int
	search_offset              int
	search_selected            int
	active_hit_seq             int = -1
	session_page_cache         map[string]SessionListResult
	transcript_page_cache      map[string]TranscriptPage
	transcript_lines_cache     []string
	transcript_lines_cache_key string
	list_density               SessionListDensity = .comfortable
	collapse_tools             bool               = true
	expanded_tools             map[string]bool
	last_layout_width          int
	last_layout_height         int
	layout_ready               bool
	command_input              string
	status                     string
	last_sessions_ms           i64
	last_sessions_strategy     string
	last_transcript_ms         i64
	last_transcript_strategy   string
	last_search_ms             i64
	last_search_strategy       string
}

pub fn browse_store(store PollyDbStore, options BrowserOptions) ! {
	mut app := &BrowserApp{
		store:                 store
		options:               options
		session_query:         options.query
		cwd_prefix:            options.cwd_prefix
		source_filter:         options.source
		include_archived:      options.include_archived
		expanded_tools:        map[string]bool{}
		session_page_cache:    map[string]SessionListResult{}
		transcript_page_cache: map[string]TranscriptPage{}
	}
	app.db = storage.PersistentDatabase.open(store.root_dir, store_branch)!
	app.db_session = app.db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	app.db_ready = true
	entries_spec := app.db_session.table_spec('entries') or { storage.TypedTableSpec{} }
	app.has_search_indexes = table_has_index(entries_spec, 'entries_content_text_fts_idx')
	app.status = if app.has_search_indexes {
		'browser ready'
	} else {
		'search indexes unavailable; run "agentview index-search" to build general FTS indexes'
	}
	defer {
		if app.db_ready {
			app.db.close() or {}
		}
	}
	app.tui = tui.init(
		user_data:      app
		event_fn:       browser_event
		frame_fn:       browser_frame
		hide_cursor:    true
		capture_events: true
		window_title:   'agentview browse'
	)
	app.tui.run()!
}

fn browser_event(e &tui.Event, x voidptr) {
	mut app := unsafe { &BrowserApp(x) }
	if e.typ == .resized {
		app.status = 'resized ${app.tui.window_width}x${app.tui.window_height}'
		app.last_layout_width = 0
		app.last_layout_height = 0
		app.layout_ready = false
		return
	}
	if e.typ != .key_down {
		return
	}
	if app.show_help {
		app.handle_help_input(e)
		return
	}
	if app.input_mode != .normal {
		app.handle_input_mode(e)
		return
	}
	match e.code {
		.q {
			exit(0)
		}
		.escape {
			app.dismiss_secondary_view()
		}
		.tab, .left, .right {
			app.focus = if app.focus == .sessions { .transcript } else { .sessions }
		}
		.r {
			app.refresh_active_view()
		}
		.enter {
			app.handle_enter()
		}
		.j {
			if e.modifiers.has(.shift) {
				app.move_down()
			} else {
				app.scroll_line_down()
			}
		}
		.k {
			if e.modifiers.has(.shift) {
				app.move_up()
			} else {
				app.scroll_line_up()
			}
		}
		.down {
			app.move_cursor_down()
		}
		.up {
			app.move_cursor_up()
		}
		.page_down, .space {
			app.page_down()
		}
		.page_up {
			app.page_up()
		}
		.g {
			if e.modifiers.has(.shift) {
				app.jump_bottom()
			} else {
				app.jump_top()
			}
		}
		.slash {
			app.start_search_input()
		}
		.f {
			app.start_filter_input()
		}
		.c {
			app.start_cwd_input()
		}
		.d {
			if e.modifiers.has(.ctrl) {
				app.half_page_down()
			}
		}
		.u {
			if e.modifiers.has(.ctrl) {
				app.half_page_up()
			}
		}
		.p {
			app.toggle_project_filter()
		}
		.s {
			app.start_source_input()
		}
		.x {
			app.clear_filters()
		}
		.a {
			app.toggle_archived()
		}
		.z {
			app.toggle_list_density()
		}
		.o {
			app.toggle_tool_collapse()
		}
		.t {
			app.view = .transcript
			app.status = 'showing transcript'
		}
		.n {
			if e.modifiers.has(.shift) {
				app.search_previous()
			} else {
				app.search_next()
			}
		}
		.e {
			app.toggle_search_scope()
		}
		.m {
			app.toggle_search_kind()
		}
		.h {
			app.show_help = true
			app.help_scroll = 0
		}
		else {}
	}
}

fn browser_frame(x voidptr) {
	mut app := unsafe { &BrowserApp(x) }
	app.ensure_layout_synced()
	if !app.layout_ready {
		app.draw_bootstrap_frame()
		app.tui.reset()
		app.tui.flush()
		return
	}
	app.tui.clear()
	app.draw_header()
	app.draw_sessions_pane()
	app.draw_right_pane()
	if app.show_help {
		app.draw_help_overlay()
	}
	app.draw_command_bar()
	app.draw_footer()
	app.tui.reset()
	app.tui.flush()
}

fn (mut app BrowserApp) ensure_layout_synced() {
	if app.tui.window_width == app.last_layout_width
		&& app.tui.window_height == app.last_layout_height {
		return
	}
	app.last_layout_width = app.tui.window_width
	app.last_layout_height = app.tui.window_height
	if app.tui.window_width <= 0 || app.tui.window_height <= 0 {
		return
	}
	app.reload_sessions()
	if app.view == .search && app.search_query.len > 0 {
		app.run_search()
	}
	if app.should_reload_transcript_after_layout() {
		app.load_selected_transcript()
	}
	app.layout_ready = true
}

fn (app &BrowserApp) should_reload_transcript_after_layout() bool {
	if app.sessions.len == 0 {
		return false
	}
	selected := app.sessions[app.selected_index]
	if app.transcript_id != selected.id {
		return true
	}
	return app.transcript_page.summary.id != selected.id
}

fn (mut app BrowserApp) draw_bootstrap_frame() {
	app.tui.clear()
	width := max_int(app.tui.window_width, 1)
	height := max_int(app.tui.window_height, 1)
	title := term.bg_rgb(30, 34, 42, pad_right(' AgentView ', width))
	app.tui.draw_text(0, 0, title)
	message := ' Preparing layout... '
	x := max_int((width - term.strip_ansi(message).len) / 2, 0)
	y := max_int(height / 2, 1)
	app.tui.draw_text(0, y - 1, term.bg_rgb(12, 14, 18, ' '.repeat(width)))
	app.tui.draw_text(x, y, term.bg_rgb(20, 23, 28, term.bold(message)))
	app.tui.draw_text(0, y + 1, term.bg_rgb(12, 14, 18, ' '.repeat(width)))
}

fn (mut app BrowserApp) reload_sessions() {
	request := SessionListRequest{
		limit:            min_int(app.options.list_limit, browser_visible_session_capacity_with_density(app.tui.window_height,
			app.list_density))
		offset:           app.list_offset
		query:            app.session_query
		cwd_prefix:       app.cwd_prefix
		source:           app.source_filter
		include_archived: app.include_archived
	}
	cache_key := session_list_cache_key(request)
	result := app.session_page_cache[cache_key] or {
		mut sw := time.new_stopwatch()
		mut total_sw := time.new_stopwatch()
		execution := list_sessions_page_in_session(mut app.db, app.db_session, request,
			storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw) or {
			app.status = 'list error: ${err}'
			return
		}
		app.last_sessions_ms = sw.elapsed().milliseconds()
		app.last_sessions_strategy = execution.explain.strategy
		app.session_page_cache[cache_key] = execution.result
		execution.result
	}
	app.sessions_total = result.total
	app.sessions = result.sessions.clone()
	if app.selected_index >= app.sessions.len {
		app.selected_index = max_int(app.sessions.len - 1, 0)
	}
	if app.selected_index < 0 {
		app.selected_index = 0
	}
	if app.sessions.len == 0 {
		app.transcript_page = TranscriptPage{}
		app.transcript_id = ''
		app.status = 'no sessions match current filter'
	}
}

fn (mut app BrowserApp) refresh_active_view() {
	app.clear_data_caches()
	app.reload_sessions()
	if app.view == .search && app.search_query.len > 0 {
		app.run_search()
	}
	app.load_selected_transcript()
}

fn (mut app BrowserApp) load_selected_transcript() {
	if app.sessions.len == 0 {
		app.transcript_page = TranscriptPage{}
		app.transcript_id = ''
		app.status = 'no sessions'
		return
	}
	selected := app.sessions[app.selected_index]
	if app.transcript_id != selected.id {
		app.transcript_offset = 0
		app.transcript_selected = 0
		app.transcript_line_scroll = 0
		if app.view != .search {
			app.active_hit_seq = -1
		}
	}
	app.transcript_id = selected.id
	app.reload_transcript_page()
}

fn (mut app BrowserApp) reload_transcript_page() {
	if app.transcript_id.len == 0 {
		return
	}
	limit := app.effective_transcript_limit()
	request := TranscriptRequest{
		session_id: app.transcript_id
		offset:     app.transcript_offset
		limit:      limit
	}
	cache_key := transcript_page_cache_key(request)
	page := app.transcript_page_cache[cache_key] or {
		mut sw := time.new_stopwatch()
		mut total_sw := time.new_stopwatch()
		fetched := load_transcript_page_in_session(mut app.db, app.db_session, request,
			storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw) or {
			app.status = 'transcript error: ${err}'
			return
		}
		app.last_transcript_ms = sw.elapsed().milliseconds()
		app.last_transcript_strategy = fetched.explain.strategy
		app.transcript_page_cache[cache_key] = fetched.result
		fetched.result
	}
	app.transcript_page = page
	if app.transcript_selected >= page.entries.len {
		app.transcript_selected = max_int(page.entries.len - 1, 0)
	}
	app.transcript_line_scroll = 0
	app.status = 'opened ${session_display_title(page.summary)}'
}

fn (mut app BrowserApp) clear_data_caches() {
	app.session_page_cache.clear()
	app.transcript_page_cache.clear()
	app.transcript_lines_cache = []string{}
	app.transcript_lines_cache_key = ''
}

fn session_list_cache_key(request SessionListRequest) string {
	return [
		'limit:${request.limit}',
		'offset:${request.offset}',
		'query:${request.query}',
		'cwd:${request.cwd_prefix}',
		'source:${request.source}',
		'archived:${request.include_archived}',
	].join('|')
}

fn transcript_page_cache_key(request TranscriptRequest) string {
	return [
		request.session_id,
		'offset:${request.offset}',
		'limit:${request.limit}',
	].join('|')
}

fn (mut app BrowserApp) run_search() {
	if app.search_query.len == 0 {
		app.view = .transcript
		app.search_results = []SearchHit{}
		app.search_total = 0
		app.search_offset = 0
		app.search_selected = 0
		app.active_hit_seq = -1
		app.status = 'search cleared'
		return
	}
	mut sw := time.new_stopwatch()
	mut total_sw := time.new_stopwatch()
	execution := search_entries_in_session(mut app.db, app.db_session, SearchRequest{
		query:      app.search_query
		session_id: app.current_search_session_id()
		preferred_session_id: if app.search_scope == .all { app.transcript_id } else { '' }
		cwd_prefix: app.current_search_cwd_prefix()
		source:     app.source_filter
		kind:       app.current_search_kind_filter()
		limit:      max_int(app.effective_transcript_limit(), 20)
		offset:     app.search_offset
	}, app.search_query, normalized_search_terms(app.search_query),
		storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw) or {
		app.status = 'search error: ${err}'
		return
	}
	result := execution.result
	app.last_search_ms = sw.elapsed().milliseconds()
	app.last_search_strategy = execution.explain.strategy
	app.view = .search
	app.focus = .transcript
	app.search_total = result.total
	app.search_results = result.hits.clone()
	if app.search_selected >= app.search_results.len {
		app.search_selected = max_int(app.search_results.len - 1, 0)
	}
	if app.search_total == 0 {
		app.status = match execution.explain.strategy {
			'fts_no_hits' { 'no indexed hits for "${app.search_query}" (no table scan)' }
			'no_fts_indexes' {
				'search indexes unavailable for "${app.search_query}" (no table scan); run "agentview index-search"'
			}
			else { 'no results for "${app.search_query}"' }
		}
	} else {
		start := app.search_offset + 1
		end := app.search_offset + app.search_results.len
		app.status = 'search "${app.search_query}" ${start}-${end}/${app.search_total} ${app.search_mode_summary()}'
	}
}

fn (mut app BrowserApp) handle_enter() {
	match app.focus {
		.sessions {
			app.view = .transcript
			app.load_selected_transcript()
		}
		.transcript {
			if app.view == .search {
				app.open_selected_search_hit()
			} else {
				app.toggle_selected_tool_entry()
			}
		}
	}
}

fn (mut app BrowserApp) move_down() {
	match app.focus {
		.sessions {
			if app.selected_index + 1 < app.sessions.len {
				app.selected_index++
				app.load_selected_transcript()
				return
			}
			if app.list_offset + app.sessions.len < app.sessions_total {
				app.list_offset += 1
				app.reload_sessions()
				app.load_selected_transcript()
			}
		}
		.transcript {
			if app.view == .search {
				app.move_search_down()
			} else if app.transcript_offset + 1 < app.transcript_page.total_entries {
				app.transcript_offset += 1
				app.transcript_selected = 0
				app.reload_transcript_page()
			}
		}
	}
}

fn (mut app BrowserApp) move_up() {
	match app.focus {
		.sessions {
			if app.selected_index > 0 {
				app.selected_index--
				app.load_selected_transcript()
				return
			}
			if app.list_offset > 0 {
				app.list_offset--
				app.reload_sessions()
				app.load_selected_transcript()
			}
		}
		.transcript {
			if app.view == .search {
				app.move_search_up()
			} else if app.transcript_offset > 0 {
				app.transcript_offset = max_int(app.transcript_offset - 1, 0)
				app.reload_transcript_page()
				app.transcript_selected = 0
			}
		}
	}
}

fn (mut app BrowserApp) move_cursor_down() {
	match app.focus {
		.sessions {
			app.move_down()
		}
		.transcript {
			if app.view == .search {
				app.move_search_down()
			} else if app.transcript_selected + 1 < app.transcript_page.entries.len {
				app.transcript_selected++
				app.status = app.transcript_entry_status()
			}
		}
	}
}

fn (mut app BrowserApp) move_cursor_up() {
	match app.focus {
		.sessions {
			app.move_up()
		}
		.transcript {
			if app.view == .search {
				app.move_search_up()
			} else if app.transcript_selected > 0 {
				app.transcript_selected--
				app.status = app.transcript_entry_status()
			}
		}
	}
}

fn (mut app BrowserApp) scroll_line_down() {
	match app.focus {
		.sessions {
			app.move_down()
		}
		.transcript {
			if app.view == .search {
				app.move_search_down()
				return
			}
			max_scroll := app.transcript_max_line_scroll()
			if app.transcript_line_scroll < max_scroll {
				app.transcript_line_scroll++
				app.status = app.transcript_scroll_status()
				return
			}
			if app.transcript_offset + 1 < app.transcript_page.total_entries {
				app.transcript_offset++
				app.transcript_selected = 0
				app.reload_transcript_page()
			}
		}
	}
}

fn (mut app BrowserApp) scroll_line_up() {
	match app.focus {
		.sessions {
			app.move_up()
		}
		.transcript {
			if app.view == .search {
				app.move_search_up()
				return
			}
			if app.transcript_line_scroll > 0 {
				app.transcript_line_scroll--
				app.status = app.transcript_scroll_status()
				return
			}
			if app.transcript_offset > 0 {
				app.transcript_offset = max_int(app.transcript_offset - 1, 0)
				app.transcript_selected = 0
				app.reload_transcript_page()
				app.transcript_line_scroll = app.transcript_max_line_scroll()
			}
		}
	}
}

fn (app &BrowserApp) transcript_render_width() int {
	list_width := browser_list_width(app.tui.window_width)
	x := list_width + 1
	return max_int(app.tui.window_width - x - 1, 1)
}

fn (app &BrowserApp) transcript_viewport_height() int {
	return max_int(browser_content_height(app.tui.window_height) - 1, 1)
}

fn (app &BrowserApp) effective_transcript_limit() int {
	viewport := app.transcript_viewport_height()
	recommended := max_int(viewport / 3, 8)
	return min_int(app.options.transcript_limit, recommended)
}

fn (mut app BrowserApp) current_transcript_lines() []string {
	key := app.transcript_render_cache_key()
	if app.transcript_lines_cache_key == key && app.transcript_lines_cache.len > 0 {
		return app.transcript_lines_cache.clone()
	}
	selected_seq := if app.transcript_selected < app.transcript_page.entries.len
		&& app.transcript_selected >= 0 {
		app.transcript_page.entries[app.transcript_selected].seq
	} else {
		-1
	}
	highlight_query := app.transcript_highlight_query()
	lines := browser_transcript_lines(app.transcript_page, app.transcript_render_width(),
		app.collapse_tools, highlight_query, selected_seq, app.active_hit_seq, app.expanded_tools,
		app.transcript_id)
	app.transcript_lines_cache = lines.clone()
	app.transcript_lines_cache_key = key
	return lines
}

fn (mut app BrowserApp) transcript_max_line_scroll() int {
	lines := app.current_transcript_lines()
	return max_int(lines.len - app.transcript_viewport_height(), 0)
}

fn (mut app BrowserApp) transcript_scroll_status() string {
	return 'transcript lines ${app.transcript_line_scroll + 1}-${min_int(
		app.transcript_line_scroll + app.transcript_viewport_height(), app.current_transcript_lines().len)}'
}

fn (app &BrowserApp) transcript_render_cache_key() string {
	mut expanded := []string{}
	for entry in app.transcript_page.entries {
		key := '${app.transcript_id}:${entry.seq}'
		if app.expanded_tools[key] {
			expanded << key
		}
	}
	mut seqs := []string{}
	for entry in app.transcript_page.entries {
		seqs << '${entry.seq}'
	}
	highlight_query := app.transcript_highlight_query()
	return [
		app.transcript_id,
		'offset:${app.transcript_offset}',
		'selected:${app.transcript_selected}',
		'hit:${app.active_hit_seq}',
		'width:${app.transcript_render_width()}',
		'collapse:${app.collapse_tools}',
		'query:${highlight_query}',
		'seqs:${seqs.join(',')}',
		'expanded:${expanded.join(',')}',
	].join('|')
}

fn (mut app BrowserApp) page_down() {
	match app.focus {
		.sessions {
			step := browser_visible_session_capacity_with_density(app.tui.window_height,
				app.list_density)
			if app.list_offset + app.sessions.len < app.sessions_total {
				app.list_offset += step
				app.reload_sessions()
				app.selected_index = 0
				app.load_selected_transcript()
			}
		}
		.transcript {
			if app.view == .search {
				if app.search_offset + app.search_results.len < app.search_total {
					app.search_offset += max_int(app.search_results.len, 1)
					app.search_selected = 0
					app.run_search()
				}
			} else if app.transcript_offset + app.effective_transcript_limit() < app.transcript_page.total_entries {
				app.transcript_offset += app.effective_transcript_limit()
				app.transcript_selected = 0
				app.reload_transcript_page()
			}
		}
	}
}

fn (mut app BrowserApp) page_up() {
	match app.focus {
		.sessions {
			step := browser_visible_session_capacity_with_density(app.tui.window_height,
				app.list_density)
			if app.list_offset > 0 {
				app.list_offset = max_int(app.list_offset - step, 0)
				app.reload_sessions()
				app.selected_index = 0
				app.load_selected_transcript()
			}
		}
		.transcript {
			if app.view == .search {
				if app.search_offset > 0 {
					app.search_offset = max_int(app.search_offset - max_int(app.search_results.len,
						1), 0)
					app.search_selected = 0
					app.run_search()
				}
			} else if app.transcript_offset > 0 {
				app.transcript_offset = max_int(app.transcript_offset - app.effective_transcript_limit(),
					0)
				app.transcript_selected = 0
				app.reload_transcript_page()
			}
		}
	}
}

fn (mut app BrowserApp) half_page_down() {
	match app.focus {
		.sessions {
			step := max_int(browser_visible_session_capacity_with_density(app.tui.window_height,
				app.list_density) / 2, 1)
			if app.list_offset + app.sessions.len < app.sessions_total {
				app.list_offset += step
				app.reload_sessions()
				app.selected_index = 0
				app.load_selected_transcript()
			}
		}
		.transcript {
			if app.view == .search {
				step := max_int(max_int(app.search_results.len, 1) / 2, 1)
				if app.search_offset + app.search_results.len < app.search_total {
					app.search_offset += step
					app.search_selected = 0
					app.run_search()
				}
			} else {
				step := max_int(app.transcript_viewport_height() / 2, 1)
				max_scroll := app.transcript_max_line_scroll()
				if app.transcript_line_scroll < max_scroll {
					app.transcript_line_scroll = min_int(app.transcript_line_scroll + step,
						max_scroll)
					app.status = app.transcript_scroll_status()
					return
				}
				if app.transcript_offset + 1 < app.transcript_page.total_entries {
					app.transcript_offset += max_int(app.effective_transcript_limit() / 2,
						1)
					app.transcript_selected = 0
					app.reload_transcript_page()
				}
			}
		}
	}
}

fn (mut app BrowserApp) half_page_up() {
	match app.focus {
		.sessions {
			step := max_int(browser_visible_session_capacity_with_density(app.tui.window_height,
				app.list_density) / 2, 1)
			if app.list_offset > 0 {
				app.list_offset = max_int(app.list_offset - step, 0)
				app.reload_sessions()
				app.selected_index = 0
				app.load_selected_transcript()
			}
		}
		.transcript {
			if app.view == .search {
				step := max_int(max_int(app.search_results.len, 1) / 2, 1)
				if app.search_offset > 0 {
					app.search_offset = max_int(app.search_offset - step, 0)
					app.search_selected = 0
					app.run_search()
				}
			} else {
				step := max_int(app.transcript_viewport_height() / 2, 1)
				if app.transcript_line_scroll > 0 {
					app.transcript_line_scroll = max_int(app.transcript_line_scroll - step,
						0)
					app.status = app.transcript_scroll_status()
					return
				}
				if app.transcript_offset > 0 {
					app.transcript_offset = max_int(app.transcript_offset - max_int(app.effective_transcript_limit() / 2,
						1), 0)
					app.transcript_selected = 0
					app.reload_transcript_page()
				}
			}
		}
	}
}

fn (mut app BrowserApp) jump_top() {
	match app.focus {
		.sessions {
			app.list_offset = 0
			app.selected_index = 0
			app.reload_sessions()
			app.load_selected_transcript()
		}
		.transcript {
			if app.view == .search {
				app.search_offset = 0
				app.search_selected = 0
				app.run_search()
			} else {
				app.transcript_offset = 0
				app.transcript_selected = 0
				app.reload_transcript_page()
			}
		}
	}
}

fn (mut app BrowserApp) jump_bottom() {
	match app.focus {
		.sessions {
			visible := browser_visible_session_capacity_with_density(app.tui.window_height,
				app.list_density)
			if app.sessions_total <= visible {
				app.list_offset = 0
			} else {
				app.list_offset = max_int(app.sessions_total - visible, 0)
			}
			app.reload_sessions()
			app.selected_index = max_int(app.sessions.len - 1, 0)
			app.load_selected_transcript()
		}
		.transcript {
			if app.view == .search {
				if app.search_total > max_int(app.search_results.len, 1) {
					app.search_offset = max_int(app.search_total - max_int(app.search_results.len,
						1), 0)
				}
				app.run_search()
				app.search_selected = max_int(app.search_results.len - 1, 0)
			} else {
				if app.transcript_page.total_entries > app.effective_transcript_limit() {
					app.transcript_offset = max_int(app.transcript_page.total_entries - app.effective_transcript_limit(),
						0)
				}
				app.reload_transcript_page()
				app.transcript_selected = max_int(app.transcript_page.entries.len - 1,
					0)
			}
		}
	}
}

fn (mut app BrowserApp) move_search_down() {
	if app.search_selected + 1 < app.search_results.len {
		app.search_selected++
		app.status = app.search_result_status()
		return
	}
	if app.search_offset + app.search_results.len < app.search_total {
		app.search_offset += max_int(app.search_results.len, 1)
		app.search_selected = 0
		app.run_search()
	}
}

fn (mut app BrowserApp) move_search_up() {
	if app.search_selected > 0 {
		app.search_selected--
		app.status = app.search_result_status()
		return
	}
	if app.search_offset > 0 {
		app.search_offset = max_int(app.search_offset - max_int(app.search_results.len,
			1), 0)
		app.run_search()
		app.search_selected = max_int(app.search_results.len - 1, 0)
	}
}

fn (mut app BrowserApp) search_next() {
	if app.search_total == 0 {
		app.status = 'no active search'
		return
	}
	app.move_search_down()
	if app.view == .transcript {
		app.open_selected_search_hit()
	}
}

fn (mut app BrowserApp) search_previous() {
	if app.search_total == 0 {
		app.status = 'no active search'
		return
	}
	app.move_search_up()
	if app.view == .transcript {
		app.open_selected_search_hit()
	}
}

fn (mut app BrowserApp) open_selected_search_hit() {
	if app.search_selected < 0 || app.search_selected >= app.search_results.len {
		app.status = 'no selected search result'
		return
	}
	hit := app.search_results[app.search_selected]
	app.transcript_id = hit.session_id
	page_offset := max_int(hit.entry_seq - max_int(app.effective_transcript_limit() / 3,
		1), 0)
	app.transcript_offset = page_offset
	app.active_hit_seq = hit.entry_seq
	app.view = .transcript
	app.sync_selected_session(hit.session_id)
	app.reload_transcript_page()
	if hit.entry_seq >= 0 {
		app.focus_search_hit(hit.entry_seq)
		app.status = 'opened ${hit.session_title} #${hit.entry_seq} ${app.search_mode_summary()}'
	} else {
		app.transcript_selected = 0
		app.transcript_line_scroll = 0
		app.status = 'opened ${hit.session_title} ${app.search_mode_summary()}'
	}
}

fn (mut app BrowserApp) focus_search_hit(entry_seq int) {
	for idx, entry in app.transcript_page.entries {
		if entry.seq == entry_seq {
			app.transcript_selected = idx
			app.transcript_line_scroll = max_int(transcript_line_offset_for_selected(app.transcript_page,
				app.transcript_render_width(), app.collapse_tools, app.search_query, idx,
				app.expanded_tools, app.transcript_id) - 2, 0)
			return
		}
	}
	app.transcript_selected = 0
	app.transcript_line_scroll = 0
}

fn (app &BrowserApp) selected_transcript_entry() ?SessionEntry {
	if app.transcript_selected < 0 || app.transcript_selected >= app.transcript_page.entries.len {
		return none
	}
	return app.transcript_page.entries[app.transcript_selected]
}

fn (app &BrowserApp) selected_tool_entry_key() string {
	entry := app.selected_transcript_entry() or { return '' }
	if entry.kind !in [.tool_call, .tool_result] {
		return ''
	}
	return '${app.transcript_id}:${entry.seq}'
}

fn (mut app BrowserApp) toggle_selected_tool_entry() {
	key := app.selected_tool_entry_key()
	if key.len == 0 {
		app.status = 'selected entry is not a tool block'
		return
	}
	if app.expanded_tools[key] {
		app.expanded_tools.delete(key)
		app.status = 'collapsed tool block'
		return
	}
	app.expanded_tools[key] = true
	app.status = 'expanded tool block'
}

fn (app &BrowserApp) transcript_entry_status() string {
	entry := app.selected_transcript_entry() or { return app.status }
	return 'entry ${entry.seq} ${entry.kind.str()} ${entry.role}'
}

fn (mut app BrowserApp) sync_selected_session(session_id string) {
	for idx, session in app.sessions {
		if session.id == session_id {
			app.selected_index = idx
			return
		}
	}
}

fn (mut app BrowserApp) dismiss_secondary_view() {
	if app.view == .search {
		app.view = .transcript
		app.focus = .sessions
		app.active_hit_seq = -1
		app.status = 'search results hidden'
		return
	}
	app.status = 'press q to quit'
}

fn (mut app BrowserApp) start_filter_input() {
	app.input_mode = .filter
	app.command_input = app.session_query
	app.status = 'filter sessions and press Enter'
}

fn (mut app BrowserApp) start_search_input() {
	app.input_mode = .search
	app.command_input = app.search_query
	app.status = 'search all entries and press Enter'
}

fn (mut app BrowserApp) start_cwd_input() {
	app.input_mode = .cwd
	app.command_input = app.cwd_prefix
	app.status = 'filter cwd prefix and press Enter'
}

fn (mut app BrowserApp) start_source_input() {
	app.input_mode = .source
	app.command_input = app.source_filter
	app.status = 'filter source and press Enter'
}

fn (mut app BrowserApp) toggle_archived() {
	app.include_archived = !app.include_archived
	app.list_offset = 0
	app.selected_index = 0
	app.reload_sessions()
	app.load_selected_transcript()
	state := if app.include_archived { 'including archived' } else { 'hiding archived' }
	app.status = state
}

fn (mut app BrowserApp) toggle_project_filter() {
	project_cwd := if app.transcript_page.summary.cwd.len > 0 {
		app.transcript_page.summary.cwd
	} else {
		app.cwd_prefix
	}
	if project_cwd.len == 0 {
		app.status = 'no project cwd available'
		return
	}
	app.cwd_prefix = if app.cwd_prefix == project_cwd { '' } else { project_cwd }
	app.list_offset = 0
	app.selected_index = 0
	app.search_offset = 0
	app.search_selected = 0
	app.reload_sessions()
	app.load_selected_transcript()
	if app.search_query.len > 0 {
		app.run_search()
	}
	app.status = if app.cwd_prefix.len > 0 {
		'project filter: ${app.cwd_prefix}'
	} else {
		'project filter cleared'
	}
}

fn (mut app BrowserApp) clear_filters() {
	app.session_query = ''
	app.cwd_prefix = ''
	app.source_filter = ''
	app.search_scope = .all
	app.search_kind = .all
	app.list_offset = 0
	app.selected_index = 0
	app.search_offset = 0
	app.search_selected = 0
	app.reload_sessions()
	app.load_selected_transcript()
	if app.search_query.len > 0 {
		app.run_search()
	}
	app.status = 'filters cleared'
}

fn (mut app BrowserApp) toggle_list_density() {
	app.list_density = if app.list_density == .comfortable { .compact } else { .comfortable }
	app.list_offset = 0
	app.selected_index = 0
	app.reload_sessions()
	app.load_selected_transcript()
	app.status = if app.list_density == .compact {
		'list density: compact'
	} else {
		'list density: comfortable'
	}
}

fn (mut app BrowserApp) toggle_search_scope() {
	app.search_scope = match app.search_scope {
		.all { .session }
		.session { .project }
		.project { .all }
	}
	app.search_offset = 0
	app.search_selected = 0
	if app.search_query.len > 0 {
		app.run_search()
		return
	}
	app.status = 'search scope: ${app.search_scope_label()}'
}

fn (mut app BrowserApp) toggle_search_kind() {
	app.search_kind = match app.search_kind {
		.all { .message }
		.message { .tool }
		.tool { .reasoning }
		.reasoning { .all }
	}
	app.search_offset = 0
	app.search_selected = 0
	if app.search_query.len > 0 {
		app.run_search()
		return
	}
	app.status = 'search kind: ${app.search_kind_label()}'
}

fn (mut app BrowserApp) toggle_tool_collapse() {
	if app.focus == .transcript && app.view == .transcript && app.selected_tool_entry_key().len > 0 {
		app.toggle_selected_tool_entry()
		return
	}
	app.collapse_tools = !app.collapse_tools
	app.status = if app.collapse_tools { 'tool blocks: collapsed' } else { 'tool blocks: expanded' }
}

fn (mut app BrowserApp) handle_help_input(e &tui.Event) {
	match e.code {
		.h, .escape, .enter, .q {
			app.show_help = false
		}
		.j, .down {
			app.help_scroll_down(1)
		}
		.k, .up {
			app.help_scroll_up(1)
		}
		.d {
			if e.modifiers.has(.ctrl) {
				app.help_scroll_down(app.help_page_step())
			}
		}
		.u {
			if e.modifiers.has(.ctrl) {
				app.help_scroll_up(app.help_page_step())
			}
		}
		.page_down, .space {
			app.help_scroll_down(app.help_page_step())
		}
		.page_up {
			app.help_scroll_up(app.help_page_step())
		}
		.g {
			if e.modifiers.has(.shift) {
				app.help_scroll = max_int(app.help_max_scroll(), 0)
			} else {
				app.help_scroll = 0
			}
		}
		else {}
	}
}

fn (mut app BrowserApp) handle_input_mode(e &tui.Event) {
	match e.code {
		.escape {
			app.input_mode = .normal
			app.command_input = ''
			app.status = 'input canceled'
		}
		.enter {
			app.commit_input_mode()
		}
		.backspace {
			app.command_input = trim_last_rune(app.command_input)
		}
		else {
			if is_browser_input_char(e) {
				app.command_input += if e.code == .space { ' ' } else { e.utf8 }
			}
		}
	}
}

fn (mut app BrowserApp) commit_input_mode() {
	value := app.command_input.trim_space()
	mode := app.input_mode
	app.input_mode = .normal
	app.command_input = ''
	match mode {
		.filter {
			app.session_query = value
			app.list_offset = 0
			app.selected_index = 0
			app.reload_sessions()
			app.load_selected_transcript()
			app.status = if value.len > 0 {
				'filter: ${value}'
			} else {
				'filter cleared'
			}
		}
		.cwd {
			app.cwd_prefix = value
			app.list_offset = 0
			app.selected_index = 0
			app.reload_sessions()
			app.load_selected_transcript()
			app.status = if value.len > 0 {
				'cwd filter: ${value}'
			} else {
				'cwd filter cleared'
			}
		}
		.source {
			app.source_filter = value
			app.list_offset = 0
			app.selected_index = 0
			app.search_offset = 0
			app.search_selected = 0
			app.reload_sessions()
			app.load_selected_transcript()
			if app.search_query.len > 0 {
				app.run_search()
			}
			app.status = if value.len > 0 {
				'source filter: ${value}'
			} else {
				'source filter cleared'
			}
		}
		.search {
			app.search_query = value
			app.search_offset = 0
			app.search_selected = 0
			app.run_search()
		}
		else {}
	}
}

fn (mut app BrowserApp) draw_header() {
	width := app.tui.window_width
	title := ' AgentView '
	focus := if app.focus == .sessions { 'Sessions' } else { 'Transcript' }
	view := if app.view == .search { 'Search' } else { 'Browse' }
	density := if app.list_density == .compact { 'Compact' } else { 'Comfortable' }
	mut chips := [' ${focus} ', ' ${view} ', ' ${app.sessions_total} sessions ', ' ${density} ']
	if app.session_query.len > 0 {
		chips << ' text:${clip_plain(app.session_query, 18)} '
	}
	if app.cwd_prefix.len > 0 {
		chips << ' cwd:${clip_plain(app.cwd_prefix, 18)} '
	}
	if app.source_filter.len > 0 {
		chips << ' source:${clip_plain(app.source_filter, 12)} '
	}
	if app.search_query.len > 0 {
		chips << ' search:${clip_plain(app.search_mode_summary(), 18)} '
	}
	if !app.include_archived {
		chips << ' archived:off '
	}
	mut status := ''
	for chip in chips {
		status += term.bg_rgb(46, 52, 64, chip)
		status += ' '
	}
	line := term.bg_rgb(30, 34, 42, pad_right(clip_ansi_text(title + status, width), width))
	app.tui.draw_text(0, 0, line)
}

fn (mut app BrowserApp) draw_sessions_pane() {
	list_width := browser_list_width(app.tui.window_width)
	height := max_int(app.tui.window_height - 1, 1)
	lines := render_session_list_lines(SessionListViewState{
		width:            list_width
		height:           height
		focused:          app.focus == .sessions
		frame_count:      app.tui.frame_count
		total:            app.sessions_total
		offset:           app.list_offset
		selected_index:   app.selected_index
		sessions:         app.sessions.clone()
		query:            app.session_query
		cwd_prefix:       app.cwd_prefix
		include_archived: app.include_archived
		density:          app.list_density
	})
	for idx, line in lines {
		app.tui.draw_text(0, idx + 1, line)
	}
	for y in 1 .. max_int(app.tui.window_height - 2, 1) {
		app.tui.draw_text(list_width, y, term.bright_black('│'))
	}
}

fn (mut app BrowserApp) draw_right_pane() {
	if app.view == .search {
		app.draw_search_pane()
	} else {
		app.draw_transcript_pane()
	}
}

fn (mut app BrowserApp) draw_transcript_pane() {
	list_width := browser_list_width(app.tui.window_width)
	x := list_width + 1
	width := max_int(app.tui.window_width - x, 1)
	height := browser_content_height(app.tui.window_height)
	start_entry := if app.transcript_page.total_entries == 0 { 0 } else { app.transcript_offset + 1 }
	end_entry := min_int(app.transcript_offset + app.transcript_page.entries.len, app.transcript_page.total_entries)
	header_title := if app.transcript_page.summary.title.len > 0 {
		' Transcript ${clip_plain(app.transcript_page.summary.title, 22)}  ${start_entry}-${end_entry}/${app.transcript_page.total_entries} '
	} else {
		' Transcript ${start_entry}-${end_entry}/${app.transcript_page.total_entries} '
	}
	app.tui.draw_text(x, 1, pane_header(header_title, app.focus == .transcript, width))
	mut lines := app.current_transcript_lines()
	max_scroll := max_int(lines.len - max_int(height - 1, 1), 0)
	if app.transcript_line_scroll > max_scroll {
		app.transcript_line_scroll = max_scroll
	}
	start := min_int(app.transcript_line_scroll, lines.len)
	end := min_int(start + max_int(height - 1, 1), lines.len)
	lines = lines[start..end].clone()
	for i in 0 .. height - 1 {
		y := i + 2
		app.tui.draw_text(x, y, style_right_pane_blank(width))
		if i >= lines.len {
			continue
		}
		app.tui.draw_text(x, y, fit_ansi_line(lines[i], width))
	}
}

fn (mut app BrowserApp) draw_search_pane() {
	list_width := browser_list_width(app.tui.window_width)
	x := list_width + 1
	width := max_int(app.tui.window_width - x, 1)
	height := browser_content_height(app.tui.window_height)
	query := if app.search_query.len > 0 { app.search_query } else { 'empty' }
	current := if app.search_total == 0 { 0 } else { app.search_offset + app.search_selected + 1 }
	header_title := ' Search ${clip_plain(query, 16)}  ${current}/${app.search_total}  ${clip_plain(app.search_scope_label(),
		8)}/${clip_plain(app.search_kind_label(), 9)} '
	app.tui.draw_text(x, 1, pane_header(header_title, app.focus == .transcript, width))
	mut lines := browser_search_lines(app.search_results, app.search_selected, app.search_query,
		width)
	if lines.len > height - 1 {
		lines = lines[..height - 1].clone()
	}
	for i in 0 .. height - 1 {
		y := i + 2
		app.tui.draw_text(x, y, style_right_pane_blank(width))
		if i >= lines.len {
			continue
		}
		app.tui.draw_text(x, y, fit_ansi_line(lines[i], width))
	}
}

fn (mut app BrowserApp) draw_command_bar() {
	y := max_int(app.tui.window_height - 2, 0)
	width := app.tui.window_width
	line := match app.input_mode {
		.filter {
			' filter> ${app.command_input}'
		}
		.cwd {
			' cwd> ${app.command_input}'
		}
		.source {
			' source> ${app.command_input}'
		}
		.search {
			' search[${app.search_scope_label()}/${app.search_kind_label()}]> ${app.command_input}'
		}
		else {
			match app.view {
				.search {
					current := if app.search_total == 0 {
						0
					} else {
						app.search_offset + app.search_selected + 1
					}
					context := 'Search ${clip_plain(app.search_query, 22)}  ${current}/${app.search_total}  ${clip_plain(app.search_mode_summary(),
						24)}'
					if app.status.len > 0 {
						' ${clip_plain(app.status, max_int(width / 3, 18))}  |  ${clip_plain(context,
							max_int(width - max_int(width / 3, 18) - 7, 1))} '
					} else {
						' ${clip_plain(context, max_int(width - 2, 1))} '
					}
				}
				.transcript {
					context := app.transcript_context_summary()
					if app.status.len > 0 {
						' ${clip_plain(app.status, max_int(width / 3, 18))}  |  ${clip_plain(context,
							max_int(width - max_int(width / 3, 18) - 7, 1))} '
					} else {
						' ${clip_plain(context, max_int(width - 2, 1))} '
					}
				}
			}
		}
	}
	app.tui.draw_text(0, y, term.bg_rgb(20, 24, 30, pad_right(clip_plain(line, width),
		width)))
}

fn (app &BrowserApp) session_list_debug_strategy() string {
	if app.session_query.len > 0 || app.cwd_prefix.len > 0 || app.source_filter.len > 0 || !app.include_archived {
		return 'idx:updated_at_cover+filter'
	}
	return 'idx:updated_at_cover'
}

fn (app &BrowserApp) browser_debug_summary() string {
	mut parts := []string{}
	if app.last_sessions_strategy.len > 0 {
		parts << 'L:${app.short_debug_strategy(app.last_sessions_strategy)} ${app.last_sessions_ms}ms'
	}
	if app.last_transcript_strategy.len > 0 {
		parts << 'T:${app.short_debug_strategy(app.last_transcript_strategy)} ${app.last_transcript_ms}ms'
	}
	if app.view == .search && app.last_search_strategy.len > 0 {
		parts << 'S:${app.short_debug_strategy(app.last_search_strategy)} ${app.last_search_ms}ms'
	}
	return parts.join(' | ')
}

fn (app &BrowserApp) short_debug_strategy(strategy string) string {
	return match strategy {
		'idx:updated_at_cover' { 'list' }
		'idx:updated_at_cover+filter' { 'list+f' }
		'idx:entries_session_idx' { 'txn' }
		'fts_index_prefix' { 'fts' }
		'fts_no_hits' { 'none' }
		'no_fts_indexes' { 'nofts' }
		'table_scan_fallback' { 'scan*' }
		'table_scan' { 'scan' }
		else { clip_plain(strategy, 8) }
	}
}

fn (mut app BrowserApp) draw_footer() {
	y := max_int(app.tui.window_height - 1, 0)
	width := app.tui.window_width
	hints := if app.input_mode == .normal {
		match app.focus {
			.sessions {
				' j/k move | ^d/^u half page | J/K page | Enter open | / search | p project | x clear | f text | c cwd | s source | a archived | z density | Tab switch | h help '
			}
			.transcript {
				if app.view == .search {
					' j/k move | ^d/^u half page | Enter open | e scope | m kind | p project | x clear | s source | n/N next prev | Esc close | Tab switch | h help '
				} else {
					' j/k line | ^d/^u half page | J/K entry | ↑/↓ select | Enter toggle | o tools | / search | e scope | m kind | p project | x clear | s source | n/N hits | Tab switch | h help '
				}
			}
		}
	} else {
		' enter apply | esc cancel | backspace delete '
	}
	debug := app.browser_debug_summary()
	search_hint := if app.has_search_indexes { '' } else { '  |  search:unindexed' }
	line_text := if debug.len > 0 {
		base_width := max_int(width - min_int(debug.len + 5, width / 2), 1)
		'${clip_plain(hints, base_width)}  |  ${clip_plain(debug + search_hint, max_int(width - base_width - 5, 1))}'
	} else {
		hints + search_hint
	}
	line := term.bg_rgb(24, 28, 32, pad_right(clip_plain(line_text, width), width))
	app.tui.draw_text(0, y, line)
}

fn (mut app BrowserApp) draw_help_overlay() {
	width := min_int(max_int(app.tui.window_width - 10, 48), 96)
	height := min_int(max_int(app.tui.window_height - 6, 14), 24)
	x := max_int((app.tui.window_width - width) / 2, 0)
	y := max_int((app.tui.window_height - height) / 2, 0)
	inner_pad_x := 2
	inner_pad_y := 1
	scrollbar_width := 1
	content_width := max_int(width - inner_pad_x * 2 - scrollbar_width - 1, 1)
	lines := help_overlay_lines()
	content_height := max_int(height - inner_pad_y * 2, 1)
	max_scroll := max_int(lines.len - content_height, 0)
	if app.help_scroll > max_scroll {
		app.help_scroll = max_scroll
	}
	for row in 0 .. height {
		app.tui.draw_text(x, y + row, term.bg_rgb(18, 22, 28, pad_right('', width)))
		viewport_row := row - inner_pad_y
		if viewport_row < 0 || viewport_row >= content_height {
			continue
		}
		content_row := app.help_scroll + viewport_row
		if content_row < 0 || content_row >= lines.len {
			continue
		}
		mut line := lines[content_row]
		if content_row == 0 {
			line = term.bold(line)
		}
		mut content := clip_plain(line, content_width)
		content = pad_right(content, content_width)
		app.tui.draw_text(x + inner_pad_x, y + row, term.bg_rgb(18, 22, 28, content))
	}
	app.draw_help_scrollbar(x + width - inner_pad_x - 1, y + inner_pad_y, content_height, lines.len)
}

fn help_overlay_lines() []string {
	return [
		' AgentView Help ',
		'',
		'Tab / Left / Right : switch focus',
		'j / k              : line scroll or list move',
		'Ctrl-d / Ctrl-u    : half page down / up',
		'J / K              : jump by entry or list page',
		'Up / Down          : select transcript entry',
		'PageUp / PageDown  : page',
		'g / G              : top / bottom',
		'Enter              : open or toggle selected item',
		'/                  : search all entries',
		'                     note: requires "agentview index-search" for indexed results',
		'e                  : cycle search scope all/session/project',
		'm                  : cycle search kind all/message/tool/reasoning',
		'n / N              : next / previous search hit',
		'p                  : toggle current project cwd filter',
		'x                  : clear text/cwd/source/scope/kind filters',
		'f                  : filter sessions by text',
		'c                  : filter sessions by cwd prefix',
		's                  : filter sessions and search by source',
		'a                  : toggle archived sessions',
		'z                  : toggle list density',
		'o                  : collapse or expand tool blocks',
		't                  : return to transcript view',
		'r                  : refresh sessions and active view',
		'Esc                : close search view or cancel input',
		'q                  : quit',
		'',
		'Scroll: j/k, Ctrl-d/u, PageUp/PageDown, g/G',
		'Press h, Enter, Esc, or q to close this help.',
	]
}

fn (app &BrowserApp) help_page_step() int {
	height := min_int(max_int(app.tui.window_height - 6, 14), 24)
	inner_pad_y := 1
	content_height := max_int(height - inner_pad_y * 2, 1)
	return max_int(content_height / 2, 1)
}

fn (app &BrowserApp) help_max_scroll() int {
	height := min_int(max_int(app.tui.window_height - 6, 14), 24)
	inner_pad_y := 1
	content_height := max_int(height - inner_pad_y * 2, 1)
	return max_int(help_overlay_lines().len - content_height, 0)
}

fn (mut app BrowserApp) help_scroll_down(step int) {
	app.help_scroll = min_int(app.help_scroll + max_int(step, 1), app.help_max_scroll())
}

fn (mut app BrowserApp) help_scroll_up(step int) {
	app.help_scroll = max_int(app.help_scroll - max_int(step, 1), 0)
}

fn (mut app BrowserApp) draw_help_scrollbar(x int, y int, height int, total_lines int) {
	if height <= 0 {
		return
	}
	track := term.bg_rgb(18, 22, 28, term.rgb(54, 62, 74, '│'))
	for row in 0 .. height {
		app.tui.draw_text(x, y + row, track)
	}
	if total_lines <= height {
		app.tui.draw_text(x, y, term.bg_rgb(18, 22, 28, term.rgb(120, 132, 150, '█')))
		return
	}
	thumb_height := max_int((height * height) / total_lines, 1)
	max_scroll := max_int(total_lines - height, 1)
	thumb_y := y + ((height - thumb_height) * app.help_scroll) / max_scroll
	for row in 0 .. thumb_height {
		app.tui.draw_text(x, thumb_y + row, term.bg_rgb(18, 22, 28, term.rgb(120, 132, 150,
			'█')))
	}
}

fn (app &BrowserApp) current_search_session_id() string {
	return match app.search_scope {
		.session { app.transcript_id }
		else { '' }
	}
}

fn (app &BrowserApp) current_search_cwd_prefix() string {
	return match app.search_scope {
		.project {
			if app.cwd_prefix.len > 0 {
				app.cwd_prefix
			} else if app.transcript_page.summary.cwd.len > 0 {
				app.transcript_page.summary.cwd
			} else {
				''
			}
		}
		else {
			''
		}
	}
}

fn (app &BrowserApp) current_search_kind_filter() string {
	return match app.search_kind {
		.all { '' }
		.message { 'message' }
		.tool { 'tool' }
		.reasoning { 'reasoning' }
	}
}

fn (app &BrowserApp) search_scope_label() string {
	return match app.search_scope {
		.all { 'all' }
		.session { 'session' }
		.project { 'project' }
	}
}

fn (app &BrowserApp) search_kind_label() string {
	return match app.search_kind {
		.all { 'all' }
		.message { 'message' }
		.tool { 'tool' }
		.reasoning { 'reasoning' }
	}
}

fn (app &BrowserApp) search_mode_summary() string {
	mut parts := ['scope:${app.search_scope_label()}', 'kind:${app.search_kind_label()}']
	project_cwd := app.current_search_cwd_prefix()
	if app.search_scope == .project && project_cwd.len > 0 {
		parts << 'cwd:${clip_plain(project_cwd, 18)}'
	}
	if app.source_filter.len > 0 {
		parts << 'source:${clip_plain(app.source_filter, 12)}'
	}
	return parts.join(' • ')
}

fn (app &BrowserApp) transcript_context_summary() string {
	title := if app.transcript_page.summary.id.len > 0 {
		session_display_title(app.transcript_page.summary)
	} else {
		'No session selected'
	}
	mut parts := [title]
	if app.active_hit_seq >= 0 && app.search_query.len > 0 {
		parts << 'hit:#${app.active_hit_seq}'
		parts << clip_plain(app.search_mode_summary(), 28)
	} else if app.transcript_page.total_entries > 0 {
		start_entry := app.transcript_offset + 1
		end_entry := min_int(app.transcript_offset + app.transcript_page.entries.len,
			app.transcript_page.total_entries)
		parts << 'entries ${start_entry}-${end_entry}/${app.transcript_page.total_entries}'
	}
	return parts.join('  •  ')
}

fn (app &BrowserApp) transcript_highlight_query() string {
	return if app.search_query.len > 0 && (app.view == .search || app.active_hit_seq >= 0) {
		app.search_query
	} else {
		''
	}
}

fn browser_list_width(total_width int) int {
	return max_int(min_int((total_width * 38) / 100, 52), 32)
}

fn browser_content_height(total_height int) int {
	return max_int(total_height - 4, 1)
}

fn pane_header(title string, focused bool, width int) string {
	body := pad_right(clip_plain(title, width), width)
	return if focused {
		term.bg_rgb(58, 66, 82, term.rgb(244, 247, 252, term.bold(body)))
	} else {
		term.bg_rgb(34, 38, 46, term.rgb(176, 184, 196, body))
	}
}

fn style_right_pane_blank(width int) string {
	return term.bg_rgb(12, 14, 18, ' '.repeat(width))
}

fn style_pane_line(text string, width int, selected bool) string {
	body := pad_right(clip_plain(text, width), width)
	return if selected {
		term.bg_rgb(58, 74, 110, body)
	} else {
		body
	}
}

fn style_meta_line(text string, width int, selected bool) string {
	body := pad_right(clip_plain(text, width), width)
	return if selected {
		term.bg_rgb(48, 62, 92, body)
	} else {
		term.bright_black(body)
	}
}

fn browser_transcript_lines(page TranscriptPage, width int, collapse_tools bool, search_query string, selected_seq int, active_hit_seq int, expanded_tools map[string]bool, session_id string) []string {
	mut out := []string{}
	if page.summary.id.len == 0 {
		return ['No transcript loaded.']
	}
	title := if page.summary.title.len > 0 { page.summary.title } else { page.summary.id }
	out << term.bold(clip_plain(title, width))
	meta := 'cwd=${page.summary.cwd} • updated=${page.summary.updated_at} • entries=${page.total_entries} • tools=${page.summary.tool_calls}'
	for line in wrap_browser_text(meta, width) {
		out << term.bright_black(line)
	}
	out << term.bright_black('─'.repeat(min_int(width, 40)))
	for entry in page.entries {
		is_selected := entry.seq == selected_seq
		is_active_hit := entry.seq == active_hit_seq && active_hit_seq >= 0
		out << style_entry_header(entry, width, is_selected, is_active_hit)
		for line in render_entry_lines(entry, max_int(width - 2, 1), collapse_tools, search_query,
			expanded_tools['${session_id}:${entry.seq}']) {
			out << style_transcript_body_line(line, is_selected, is_active_hit)
		}
		divider := term.rgb(92, 98, 110, '  ' + '─'.repeat(min_int(max_int(width - 2, 1), 20)))
		out << if is_selected || is_active_hit {
			style_selected_entry_prefix(divider, is_active_hit)
		} else {
			divider
		}
		out << ''
	}
	return out
}

fn transcript_line_offset_for_selected(page TranscriptPage, width int, collapse_tools bool, search_query string, selected_index int, expanded_tools map[string]bool, session_id string) int {
	if selected_index <= 0 {
		return 0
	}
	mut line_offset := 0
	for idx, entry in page.entries {
		if idx >= selected_index {
			break
		}
		line_offset += 1
		line_offset += render_entry_lines(entry, max_int(width - 2, 1), collapse_tools,
			search_query, expanded_tools['${session_id}:${entry.seq}']).len
		line_offset += 2
	}
	return line_offset
}

fn render_entry_lines(entry SessionEntry, width int, collapse_tools bool, search_query string, expanded bool) []string {
	markdown := if entry.markdown.len > 0 {
		entry.markdown
	} else if entry.title.len > 0 && entry.text.len > 0 {
		'${entry.title}\n\n${entry.text}'
	} else if entry.title.len > 0 {
		entry.title
	} else {
		entry.text
	}
	rendered := vmarkdown.preview_lines(markdown, .terminal, max_int(width, 20)) or {
		return wrap_browser_text(markdown, width)
	}
	mut out := []string{}
	for line in rendered {
		out << highlight_rendered_line(fit_ansi_line(line, width), search_query, width)
	}
	if collapse_tools && !expanded && entry.kind in [.tool_call, .tool_result] {
		return collapse_rendered_tool_lines(out, width)
	}
	return out
}

fn collapse_rendered_tool_lines(lines []string, width int) []string {
	if lines.len <= 8 {
		return lines
	}
	mut out := []string{}
	out << lines[..6]
	out << term.bright_black(clip_plain('… tool output collapsed (${lines.len - 6} more lines). Press o to expand.',
		width))
	return out
}

fn highlight_rendered_line(line string, query string, width int) string {
	if query.len == 0 {
		return line
	}
	plain := term.strip_ansi(line)
	if !plain.to_lower().contains(query.to_lower()) {
		return line
	}
	return highlight_plain_text(plain, query, width)
}

fn highlight_plain_text(text string, query string, width int) string {
	if query.len == 0 {
		return clip_plain(text, width)
	}
	lower_text := text.to_lower()
	lower_query := query.to_lower()
	if !lower_text.contains(lower_query) {
		return clip_plain(text, width)
	}
	text_runes := text.runes()
	lower_runes := lower_text.runes()
	query_runes := lower_query.runes()
	mut out := ''
	mut i := 0
	for i < text_runes.len {
		if i + query_runes.len <= lower_runes.len
			&& lower_runes[i..i + query_runes.len].string() == lower_query {
			chunk := text_runes[i..i + query_runes.len].string()
			out += term.bg_rgb(120, 92, 24, term.rgb(255, 244, 184, chunk))
			i += query_runes.len
			continue
		}
		out += text_runes[i].str()
		i++
	}
	return clip_ansi_text(out, width)
}

fn browser_search_lines(hits []SearchHit, selected int, query string, width int) []string {
	if hits.len == 0 {
		return ['No search results.']
	}
	mut out := []string{}
	for idx, hit in hits {
		title := if hit.session_title.len > 0 { hit.session_title } else { hit.session_id }
		head := clip_plain('${if idx == selected { '▸ ' } else { '' }}${idx + 1}. ${title}',
			width)
		out << style_search_head(head, width, idx == selected)
		mut meta_parts := ['${hit.timestamp}']
		if hit.entry_seq >= 0 {
			meta_parts << '${hit.session_id}#${hit.entry_seq}'
		} else {
			meta_parts << hit.session_id
		}
		if hit.session_source.len > 0 {
			meta_parts << hit.session_source
		}
		if hit.session_cwd.len > 0 {
			meta_parts << clip_plain(hit.session_cwd, 24)
		}
		meta := clip_plain(meta_parts.join(' • '), width)
		out << style_search_meta(meta, width, idx == selected)
		for line in wrap_browser_text(hit.snippet, width) {
			rendered := highlight_plain_text(line, query, max_int(width - 2, 1))
			out << style_search_snippet('  ' + rendered, width, idx == selected)
		}
		out << style_search_divider(width, idx == selected)
	}
	return out
}

fn style_entry_header(entry SessionEntry, width int, selected bool, active_hit bool) string {
	mut prefix := ''
	if active_hit {
		prefix = '◆ '
	} else if selected {
		prefix = '▸ '
	}
	mut head := '${prefix}[${entry.seq}] ${entry.kind.str()}'
	if entry.role.len > 0 {
		head += ' ${entry.role}'
	}
	if entry.tool_name.len > 0 {
		head += ' ${entry.tool_name}'
	}
	if entry.status.len > 0 {
		head += ' (${entry.status})'
	}
	body := pad_right(clip_plain(head, width), width)
	if active_hit {
		return match entry.kind {
			.message { term.bg_rgb(82, 60, 18, term.rgb(255, 238, 168, term.bold(body))) }
			.reasoning { term.bg_rgb(82, 60, 18, term.rgb(255, 238, 168, term.bold(body))) }
			.tool_call { term.bg_rgb(82, 60, 18, term.rgb(255, 238, 168, term.bold(body))) }
			.tool_result { term.bg_rgb(82, 60, 18, term.rgb(255, 238, 168, term.bold(body))) }
			.meta { term.bg_rgb(82, 60, 18, term.rgb(255, 238, 168, term.bold(body))) }
		}
	}
	return match entry.kind {
		.message {
			if selected {
				term.bg_rgb(22, 66, 76, term.rgb(160, 245, 255, term.bold(body)))
			} else {
				term.bg_rgb(16, 48, 56, term.rgb(110, 235, 255, body))
			}
		}
		.reasoning {
			if selected {
				term.bg_rgb(60, 50, 24, term.rgb(255, 228, 140, term.bold(body)))
			} else {
				term.bg_rgb(44, 38, 18, term.rgb(255, 214, 102, body))
			}
		}
		.tool_call {
			if selected {
				term.bg_rgb(48, 28, 72, term.rgb(230, 196, 255, term.bold(body)))
			} else {
				term.bg_rgb(34, 20, 52, term.rgb(215, 176, 255, body))
			}
		}
		.tool_result {
			if selected {
				term.bg_rgb(28, 56, 38, term.rgb(182, 255, 206, term.bold(body)))
			} else {
				term.bg_rgb(20, 42, 28, term.rgb(146, 255, 182, body))
			}
		}
		.meta {
			if selected {
				term.bg_rgb(42, 48, 58, term.rgb(240, 240, 240, term.bold(body)))
			} else {
				term.bg_rgb(30, 34, 42, term.rgb(220, 220, 220, body))
			}
		}
	}
}

fn style_selected_entry_prefix(text string, active_hit bool) string {
	if active_hit {
		return term.rgb(255, 214, 102, '▌') + ' ' + text
	}
	return term.rgb(120, 168, 255, '▏') + ' ' + text
}

fn style_transcript_body_line(text string, selected bool, active_hit bool) string {
	if !selected && !active_hit {
		return '  ' + text
	}
	return style_selected_entry_prefix(text, active_hit)
}

fn style_search_head(text string, width int, selected bool) string {
	body := pad_right(clip_plain(text, width), width)
	return if selected {
		term.bg_rgb(46, 64, 102, term.rgb(234, 240, 255, term.bold(body)))
	} else {
		term.bg_rgb(28, 32, 38, term.rgb(224, 228, 236, body))
	}
}

fn style_search_meta(text string, width int, selected bool) string {
	body := if selected {
		term.rgb(120, 168, 255, '▏') + ' ' +
			pad_right(clip_plain(text, max_int(width - 2, 1)), max_int(width - 2, 1))
	} else {
		pad_right(clip_plain(text, width), width)
	}
	return if selected {
		term.bg_rgb(22, 26, 34, term.rgb(148, 156, 170, body))
	} else {
		term.bg_rgb(18, 21, 26, term.rgb(122, 128, 138, body))
	}
}

fn style_search_snippet(text string, width int, selected bool) string {
	body := if selected {
		term.rgb(120, 168, 255, '▏') + ' ' +
			pad_right(fit_ansi_line(text, max_int(width - 2, 1)), max_int(width - 2, 1))
	} else {
		pad_right(fit_ansi_line(text, width), width)
	}
	return if selected {
		term.bg_rgb(12, 14, 18, body)
	} else {
		term.bg_rgb(12, 14, 18, body)
	}
}

fn style_search_divider(width int, selected bool) string {
	body := '─'.repeat(min_int(width, 24))
	return if selected {
		term.bg_rgb(12, 14, 18, term.rgb(92, 98, 110, term.rgb(120, 168, 255, '▏') + ' ' +
			pad_right(body, max_int(width - 2, 1))))
	} else {
		term.bg_rgb(12, 14, 18, term.rgb(92, 98, 110, pad_right(body, width)))
	}
}

fn (app &BrowserApp) search_result_status() string {
	if app.search_total == 0 || app.search_selected < 0
		|| app.search_selected >= app.search_results.len {
		return 'no selected search result'
	}
	hit := app.search_results[app.search_selected]
	return if hit.entry_seq >= 0 {
		'search hit ${app.search_offset + app.search_selected + 1}/${app.search_total} ${hit.session_title} #${hit.entry_seq}'
	} else {
		'search hit ${app.search_offset + app.search_selected + 1}/${app.search_total} ${hit.session_title}'
	}
}

fn wrap_browser_text(text string, width int) []string {
	if width <= 0 {
		return ['']
	}
	if text.len == 0 {
		return ['']
	}
	mut out := []string{}
	for raw_line in text.split_into_lines() {
		if raw_line.len == 0 {
			out << ''
			continue
		}
		mut rest := raw_line
		for display_width_plain(rest) > width {
			chunk := truncate_display_width_plain(rest, width)
			out << chunk
			rest = rest[chunk.len..]
		}
		out << rest
	}
	return out
}

fn clip_plain(text string, width int) string {
	if width <= 0 {
		return ''
	}
	plain := term.strip_ansi(text)
	if display_width_plain(plain) <= width {
		return text
	}
	if width <= 1 {
		return truncate_display_width_plain(plain, width)
	}
	return truncate_display_width_plain(plain, width - 1) + '…'
}

fn clip_ansi_text(text string, width int) string {
	if width <= 0 {
		return ''
	}
	plain := term.strip_ansi(text)
	if display_width_plain(plain) <= width {
		return text
	}
	if width <= 1 {
		return truncate_display_width_plain(plain, width)
	}
	return truncate_display_width_plain(plain, width - 1) + '…'
}

fn fit_ansi_line(text string, width int) string {
	if width <= 0 {
		return ''
	}
	plain := term.strip_ansi(text)
	if display_width_plain(plain) <= width {
		return text
	}
	if width <= 1 {
		return truncate_display_width_plain(plain, width)
	}
	return truncate_display_width_plain(plain, width - 1) + '…'
}

fn pad_right(text string, width int) string {
	plain_len := display_width_plain(term.strip_ansi(text))
	if plain_len >= width {
		return text
	}
	return text + ' '.repeat(width - plain_len)
}

fn display_width_plain(text string) int {
	return east_asian.display_width(text, 1)
}

fn truncate_display_width_plain(text string, width int) string {
	if width <= 0 {
		return ''
	}
	mut out := []rune{}
	mut used := 0
	for r in text.runes() {
		rw := display_width_plain(r.str())
		if used + rw > width {
			break
		}
		out << r
		used += rw
	}
	return out.string()
}

fn trim_last_rune(text string) string {
	runes := text.runes()
	if runes.len == 0 {
		return ''
	}
	return runes[..runes.len - 1].string()
}

fn is_browser_input_char(e &tui.Event) bool {
	if e.code == .space {
		return true
	}
	if e.ascii >= 33 && e.ascii <= 126 {
		return true
	}
	return e.utf8.runes().len == 1 && e.utf8 != '\x00'
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}
