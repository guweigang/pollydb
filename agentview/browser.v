module agentview

import encoding.utf8.east_asian
import os
import storage
import strings
import term
import term.ui as tui
import time

pub struct BrowserOptions {
pub:
	query            string
	cwd_prefix       string
	source           string
	include_archived bool = true
	list_limit       int  = 100
	transcript_limit int  = 40
}

enum BrowserScreen {
	sessions
	transcript
	search
}

enum BrowserInputMode {
	normal
	search
}

struct BrowserApp {
	store   PollyDbStore
	options BrowserOptions
mut:
	db                 storage.PersistentDatabase
	db_session         storage.DatabaseSession
	db_ready           bool
	tui                &tui.Context = unsafe { nil }
	screen             BrowserScreen
	input_mode         BrowserInputMode
	status             string
	command_input      string
	sessions           []SessionSummary
	sessions_total     int
	session_offset     int
	selected           int
	session_query      string
	cwd_prefix         string
	source_filter      string
	include_archived   bool
	transcript         TranscriptPage
	transcript_id      string
	transcript_offset  int
	transcript_scroll  int
	active_hit_seq     int = -1
	search_query       string
	search_results     []SearchHit
	search_total       int
	search_offset      int
	search_selected    int
	last_sessions_ms   i64
	last_transcript_ms i64
	last_search_ms     i64
	last_window_width  int
	last_window_height int
	sessions_loaded    bool
}

pub fn browse_store(store PollyDbStore, options BrowserOptions) ! {
	mut app := &BrowserApp{
		store:            store
		options:          options
		session_query:    options.query
		cwd_prefix:       options.cwd_prefix
		source_filter:    options.source
		include_archived: options.include_archived
	}
	app.db = storage.PersistentDatabase.open(store.root_dir, store_branch)!
	app.db_session = app.db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	app.db_ready = true
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
	if e.typ != .key_down {
		return
	}
	if app.input_mode != .normal {
		app.handle_input(e)
		return
	}
	match e.code {
		.q {
			exit(0)
		}
		.escape {
			app.go_back()
		}
		.enter {
			app.open_selected()
		}
		.slash {
			app.input_mode = .search
			app.command_input = app.current_search_text()
			app.status = app.search_prompt_status()
		}
		.r {
			app.refresh()
		}
		.n {
			app.next_search_hit()
		}
		.p {
			app.previous_search_hit()
		}
		.j, .down {
			app.move_down()
		}
		.k, .up {
			app.move_up()
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
		else {}
	}
}

fn (mut app BrowserApp) handle_input(e &tui.Event) {
	match e.code {
		.escape {
			app.input_mode = .normal
			app.command_input = ''
			app.status = 'input canceled'
		}
		.enter {
			value := app.command_input.trim_space()
			mode := app.input_mode
			app.input_mode = .normal
			app.command_input = ''
			match mode {
				.search {
					app.apply_context_search(value)
				}
				else {}
			}
		}
		.backspace, .delete {
			app.command_input = trim_last_rune(app.command_input)
		}
		else {
			debug_browser_input_event(e)
			text := browser_input_text(e)
			if text.len > 0 {
				app.command_input += text
			}
		}
	}
}

fn (mut app BrowserApp) reload_sessions() {
	mut sw := time.new_stopwatch()
	mut total_sw := time.new_stopwatch()
	limit := max_int(min_int(app.options.list_limit, max_int(app.visible_rows() - 4, 12)), 1)
	execution := list_sessions_page_in_session(mut app.db, app.db_session, SessionListRequest{
		limit:            limit
		offset:           app.session_offset
		query:            app.session_query
		cwd_prefix:       app.cwd_prefix
		source:           app.source_filter
		include_archived: app.include_archived
	}, storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw) or {
		app.status = 'list error: ${err}'
		return
	}
	app.sessions = execution.result.sessions.clone()
	app.sessions_total = execution.result.total
	if app.selected >= app.sessions.len {
		app.selected = max_int(app.sessions.len - 1, 0)
	}
	app.last_sessions_ms = sw.elapsed().milliseconds()
	app.sessions_loaded = true
	app.status = if app.sessions.len == 0 { 'no sessions' } else { 'sessions ready' }
}

fn (mut app BrowserApp) load_transcript(session_id string, offset int) {
	if session_id.len == 0 {
		return
	}
	mut sw := time.new_stopwatch()
	mut total_sw := time.new_stopwatch()
	limit := max_int(app.options.transcript_limit, 20)
	execution := load_transcript_page_in_session(mut app.db, app.db_session, TranscriptRequest{
		session_id: session_id
		offset:     max_int(offset, 0)
		limit:      limit
	}, storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw) or {
		app.status = 'transcript error: ${err}'
		return
	}
	app.transcript = execution.result
	app.transcript_id = session_id
	app.transcript_offset = max_int(offset, 0)
	app.transcript_scroll = 0
	app.last_transcript_ms = sw.elapsed().milliseconds()
	app.screen = .transcript
	app.status = 'opened ${display_session_title(app.transcript.summary)}'
}

fn (mut app BrowserApp) run_search() {
	if app.search_query.len == 0 {
		app.search_results = []SearchHit{}
		app.search_total = 0
		app.search_selected = 0
		app.active_hit_seq = -1
		app.status = 'search cleared'
		return
	}
	mut sw := time.new_stopwatch()
	mut total_sw := time.new_stopwatch()
	execution := search_entries_in_session(mut app.db, app.db_session, SearchRequest{
		query:      app.search_query
		session_id: app.transcript_id
		limit:      max_int(app.visible_rows() - 4, 10)
		offset:     app.search_offset
		cwd_prefix: app.cwd_prefix
		source:     app.source_filter
	}, app.search_query, normalized_search_terms(app.search_query), storage.PersistentDatabaseOpenTimings{},
		0, mut total_sw) or {
		app.status = 'search error: ${err}'
		return
	}
	app.search_results = execution.result.hits.clone()
	app.search_total = execution.result.total
	if app.search_selected >= app.search_results.len {
		app.search_selected = max_int(app.search_results.len - 1, 0)
	}
	if app.search_selected < 0 {
		app.search_selected = 0
	}
	app.last_search_ms = sw.elapsed().milliseconds()
	app.screen = .search
	app.status = if app.search_total == 0 {
		'no results for "${app.search_query}"'
	} else {
		'search "${app.search_query}"'
	}
}

fn (mut app BrowserApp) next_search_hit() {
	app.navigate_search_hit(1)
}

fn (mut app BrowserApp) previous_search_hit() {
	app.navigate_search_hit(-1)
}

fn (mut app BrowserApp) navigate_search_hit(direction int) {
	if app.search_query.len == 0 {
		app.status = 'no active search'
		return
	}
	if app.screen == .sessions {
		app.status = 'press / to search sessions'
		return
	}
	if app.search_results.len == 0 {
		was_transcript := app.screen == .transcript
		app.run_search()
		if was_transcript && app.search_results.len > 0 {
			app.open_selected_search_hit()
		}
		return
	}
	was_transcript := app.screen == .transcript
	next_index := app.search_selected + direction
	if next_index >= 0 && next_index < app.search_results.len {
		app.search_selected = next_index
		if app.screen == .transcript {
			app.open_selected_search_hit()
		} else {
			app.status = app.search_result_status()
		}
		return
	}
	if direction >= 0 && app.search_offset + app.search_results.len < app.search_total {
		app.search_offset += max_int(app.search_results.len, 1)
		app.search_selected = 0
		app.run_search()
		if was_transcript {
			app.open_selected_search_hit()
		}
		return
	}
	if direction < 0 && app.search_offset > 0 {
		app.search_offset = max_int(app.search_offset - max_int(app.search_results.len, 1), 0)
		app.run_search()
		app.search_selected = max_int(app.search_results.len - 1, 0)
		if was_transcript {
			app.open_selected_search_hit()
		}
		return
	}
	app.status = 'no more matches'
}

fn (mut app BrowserApp) open_selected_search_hit() {
	if app.search_selected < 0 || app.search_selected >= app.search_results.len {
		app.status = 'no selected search hit'
		return
	}
	hit := app.search_results[app.search_selected]
	app.load_transcript(hit.session_id, max_int(hit.entry_seq - 8, 0))
	app.focus_transcript_hit(hit.entry_seq)
}

fn (app &BrowserApp) search_result_status() string {
	if app.search_total == 0 || app.search_selected < 0
		|| app.search_selected >= app.search_results.len {
		return 'no search hit'
	}
	hit := app.search_results[app.search_selected]
	return 'hit ${app.search_offset + app.search_selected + 1}/${app.search_total} #${hit.entry_seq}'
}

fn (mut app BrowserApp) jump_transcript_hit(direction int) {
	if app.search_query.len == 0 || app.transcript.summary.id.len == 0 {
		app.status = 'no active transcript search'
		return
	}
	if app.search_results.len > 0 {
		app.navigate_search_hit(direction)
		return
	}
	current_seq := if app.active_hit_seq >= 0 {
		app.active_hit_seq
	} else {
		app.transcript_offset - 1
	}
	if hit_seq := app.find_hit_seq_in_current_page(current_seq, direction) {
		app.focus_transcript_hit(hit_seq)
	} else {
		app.status = 'no more matches on page'
	}
}

fn (app &BrowserApp) find_hit_seq_in_current_page(current_seq int, direction int) ?int {
	if direction >= 0 {
		for entry in app.transcript.entries {
			if entry.seq <= current_seq {
				continue
			}
			if entry_matches_query(entry, app.search_query) {
				return entry.seq
			}
		}
		return none
	}
	for i := app.transcript.entries.len - 1; i >= 0; i-- {
		entry := app.transcript.entries[i]
		if entry.seq >= current_seq {
			continue
		}
		if entry_matches_query(entry, app.search_query) {
			return entry.seq
		}
	}
	return none
}

fn (mut app BrowserApp) focus_transcript_hit(seq int) {
	app.active_hit_seq = seq
	app.transcript_scroll = max_int(transcript_line_offset_for_seq(app.transcript, seq,
		app.tui.window_width) - 2, 0)
	app.screen = .transcript
	app.status = 'match #${seq}'
}

fn (mut app BrowserApp) apply_context_search(value string) {
	match app.screen {
		.sessions {
			app.session_query = value
			app.session_offset = 0
			app.selected = 0
			app.reload_sessions()
			app.status = if value.len > 0 {
				'search sessions "${value}"'
			} else {
				'session search cleared'
			}
		}
		.transcript, .search {
			app.search_query = value
			app.search_offset = 0
			app.search_selected = 0
			app.run_search()
		}
	}
}

fn (app &BrowserApp) current_search_text() string {
	return match app.screen {
		.sessions { app.session_query }
		.transcript, .search { app.search_query }
	}
}

fn (app &BrowserApp) search_prompt_status() string {
	return match app.screen {
		.sessions { 'search sessions' }
		.transcript, .search { 'search current session' }
	}
}

fn (mut app BrowserApp) open_selected() {
	match app.screen {
		.sessions {
			if app.selected >= 0 && app.selected < app.sessions.len {
				app.load_transcript(app.sessions[app.selected].id, 0)
			}
		}
		.search {
			if app.search_selected >= 0 && app.search_selected < app.search_results.len {
				app.open_selected_search_hit()
			}
		}
		.transcript {}
	}
}

fn (mut app BrowserApp) go_back() {
	match app.screen {
		.sessions {
			if app.session_query.len > 0 {
				app.session_query = ''
				app.session_offset = 0
				app.selected = 0
				app.reload_sessions()
				app.status = 'session search reset'
			} else {
				app.status = 'press q to quit'
			}
		}
		.search {
			app.search_query = ''
			app.search_results = []SearchHit{}
			app.search_total = 0
			app.search_offset = 0
			app.search_selected = 0
			app.active_hit_seq = -1
			app.screen = .transcript
			app.status = 'transcript search reset'
		}
		.transcript {
			if app.search_query.len > 0 {
				app.search_query = ''
				app.search_results = []SearchHit{}
				app.search_total = 0
				app.search_offset = 0
				app.search_selected = 0
				app.active_hit_seq = -1
				app.status = 'transcript search reset'
			} else {
				app.screen = .sessions
				app.status = 'sessions'
			}
		}
	}
}

fn (mut app BrowserApp) refresh() {
	match app.screen {
		.sessions {
			app.reload_sessions()
		}
		.transcript {
			app.load_transcript(app.transcript_id, app.transcript_offset)
		}
		.search {
			app.run_search()
		}
	}
}

fn (mut app BrowserApp) move_down() {
	match app.screen {
		.sessions {
			if app.selected + 1 < app.sessions.len {
				app.selected++
			} else if app.session_offset + app.sessions.len < app.sessions_total {
				app.session_offset += max_int(app.sessions.len, 1)
				app.selected = 0
				app.reload_sessions()
			}
		}
		.search {
			if app.search_selected + 1 < app.search_results.len {
				app.search_selected++
			} else if app.search_offset + app.search_results.len < app.search_total {
				app.search_offset += max_int(app.search_results.len, 1)
				app.search_selected = 0
				app.run_search()
			}
		}
		.transcript {
			app.transcript_scroll++
		}
	}
}

fn (mut app BrowserApp) move_up() {
	match app.screen {
		.sessions {
			if app.selected > 0 {
				app.selected--
			} else if app.session_offset > 0 {
				step := max_int(app.sessions.len, 1)
				app.session_offset = max_int(app.session_offset - step, 0)
				app.reload_sessions()
				app.selected = max_int(app.sessions.len - 1, 0)
			}
		}
		.search {
			if app.search_selected > 0 {
				app.search_selected--
			} else if app.search_offset > 0 {
				step := max_int(app.search_results.len, 1)
				app.search_offset = max_int(app.search_offset - step, 0)
				app.run_search()
				app.search_selected = max_int(app.search_results.len - 1, 0)
			}
		}
		.transcript {
			app.transcript_scroll = max_int(app.transcript_scroll - 1, 0)
		}
	}
}

fn (mut app BrowserApp) page_down() {
	step := max_int(app.visible_rows() - 5, 1)
	match app.screen {
		.sessions {
			app.session_offset += step
			if app.session_offset >= app.sessions_total {
				app.session_offset = max_int(app.sessions_total - 1, 0)
			}
			app.selected = 0
			app.reload_sessions()
		}
		.search {
			app.search_offset += step
			if app.search_offset >= app.search_total {
				app.search_offset = max_int(app.search_total - 1, 0)
			}
			app.search_selected = 0
			app.run_search()
		}
		.transcript {
			next := app.transcript_offset + app.transcript.entries.len
			if next < app.transcript.total_entries {
				app.load_transcript(app.transcript_id, next)
			}
		}
	}
}

fn (mut app BrowserApp) page_up() {
	step := max_int(app.visible_rows() - 5, 1)
	match app.screen {
		.sessions {
			app.session_offset = max_int(app.session_offset - step, 0)
			app.selected = 0
			app.reload_sessions()
		}
		.search {
			app.search_offset = max_int(app.search_offset - step, 0)
			app.search_selected = 0
			app.run_search()
		}
		.transcript {
			prev := max_int(app.transcript_offset - max_int(app.transcript.entries.len, 1), 0)
			app.load_transcript(app.transcript_id, prev)
		}
	}
}

fn (mut app BrowserApp) jump_top() {
	match app.screen {
		.sessions {
			app.session_offset = 0
			app.selected = 0
			app.reload_sessions()
		}
		.search {
			app.search_offset = 0
			app.search_selected = 0
			app.run_search()
		}
		.transcript {
			app.load_transcript(app.transcript_id, 0)
		}
	}
}

fn (mut app BrowserApp) jump_bottom() {
	match app.screen {
		.sessions {
			app.session_offset = max_int(app.sessions_total - max_int(app.sessions.len, 1), 0)
			app.selected = 0
			app.reload_sessions()
		}
		.search {
			app.search_offset = max_int(app.search_total - max_int(app.search_results.len, 1), 0)
			app.search_selected = 0
			app.run_search()
		}
		.transcript {
			app.load_transcript(app.transcript_id, max_int(app.transcript.total_entries - max_int(app.transcript.entries.len,
				1), 0))
		}
	}
}

fn browser_frame(x voidptr) {
	mut app := unsafe { &BrowserApp(x) }
	app.sync_window_layout()
	app.tui.clear()
	app.draw_header()
	match app.screen {
		.sessions { app.draw_sessions() }
		.transcript { app.draw_transcript() }
		.search { app.draw_search() }
	}

	app.draw_footer()
	app.tui.reset()
	app.tui.flush()
}

fn (mut app BrowserApp) sync_window_layout() {
	if app.tui.window_width <= 0 || app.tui.window_height <= 0 {
		return
	}
	changed := app.tui.window_width != app.last_window_width
		|| app.tui.window_height != app.last_window_height
	app.last_window_width = app.tui.window_width
	app.last_window_height = app.tui.window_height
	if !changed && app.sessions_loaded {
		return
	}
	match app.screen {
		.sessions {
			app.reload_sessions()
		}
		.search {
			if app.search_query.len > 0 {
				app.run_search()
			}
		}
		.transcript {}
	}
}

fn (mut app BrowserApp) draw_header() {
	width := app.tui.window_width
	title := match app.screen {
		.sessions { ' AgentView / Sessions ' }
		.transcript { ' AgentView / Transcript ' }
		.search { ' AgentView / Search ' }
	}

	mut right := []string{}
	if app.session_query.len > 0 {
		right << 'search:${clip_plain(app.session_query, 18)}'
	}
	if app.search_query.len > 0 && app.screen == .search {
		right << 'query:${clip_plain(app.search_query, 18)}'
	}
	right << app.debug_status()
	line := title + if right.len > 0 { ' ' + right.join('  ') } else { '' }
	app.tui.draw_text(0, 0, term.bg_rgb(30, 34, 42, pad_right(clip_plain(line, width), width)))
}

fn (mut app BrowserApp) draw_sessions() {
	width := app.tui.window_width
	rows := app.visible_rows()
	y0 := 2
	if app.sessions.len == 0 {
		app.tui.draw_text(2, y0, 'No sessions. Press r to refresh or / to change search.')
		return
	}
	for idx, session in app.sessions {
		if idx >= rows {
			break
		}
		y := y0 + idx
		selected := idx == app.selected
		title := display_session_title(session)
		meta := '${session.updated_at}  ${session.entry_count} entries  ${short_path(session.cwd)}'
		prefix := if selected { '>' } else { ' ' }
		line := '${prefix} ${clip_plain(title, max_int(width - 48, 20))}  ${clip_plain(meta, 44)}'
		app.tui.draw_text(0, y, style_line(line, width, selected))
	}
}

fn (mut app BrowserApp) draw_transcript() {
	width := app.tui.window_width
	rows := app.visible_rows()
	y0 := 2
	if app.transcript.summary.id.len == 0 {
		app.tui.draw_text(2, y0, 'No transcript loaded.')
		return
	}
	end_entry := min_int(app.transcript_offset + app.transcript.entries.len,
		app.transcript.total_entries)
	meta := '${display_session_title(app.transcript.summary)}  ${app.transcript_offset + 1}-${end_entry}/${app.transcript.total_entries}'
	app.tui.draw_text(0, 1,
		term.bg_rgb(18, 22, 28, pad_right(clip_plain(' ' + meta, width), width)))
	lines := transcript_lines(app.transcript, width, app.search_query, app.active_hit_seq)
	start := min_int(app.transcript_scroll, lines.len)
	for i in 0 .. rows {
		idx := start + i
		if idx >= lines.len {
			break
		}
		app.tui.draw_text(0, y0 + i, lines[idx])
	}
}

fn (mut app BrowserApp) draw_search() {
	width := app.tui.window_width
	rows := app.visible_rows()
	y0 := 2
	app.tui.draw_text(0, 1, term.bg_rgb(18, 22, 28, pad_right(clip_plain(' / ${app.search_query}  ${
		app.search_offset + 1}-${app.search_offset + app.search_results.len}/${app.search_total}',
		width), width)))
	if app.search_results.len == 0 {
		app.tui.draw_text(2, y0, 'No search results.')
		return
	}
	mut y := y0
	for idx, hit in app.search_results {
		if y >= y0 + rows {
			break
		}
		selected := idx == app.search_selected
		head := '${if selected { '>' } else { ' ' }} ${hit.session_title} #${hit.entry_seq} ${hit.timestamp}'
		app.tui.draw_text(0, y, style_line(clip_plain(head, width), width, selected))
		y++
		for line in wrap_text(hit.snippet.replace('\n', ' '), max_int(width - 4, 1)) {
			if y >= y0 + rows {
				break
			}
			app.tui.draw_text(2, y, term.rgb(150, 158, 170, highlight_query_in_line(line,
				app.search_query)))
			y++
		}
	}
}

fn (mut app BrowserApp) draw_footer() {
	width := app.tui.window_width
	y := max_int(app.tui.window_height - 1, 0)
	prompt := if app.input_mode == .normal {
		match app.screen {
			.sessions { ' j/k select  Enter open  / search sessions  Esc reset  r refresh  q quit ' }
			.transcript { ' j/k scroll  n/p hits  PgUp/PgDn entries  Esc back/reset  / search  q quit ' }
			.search { ' j/k select  Enter open  n/p hits  Esc reset  / new search  q quit ' }
		}
	} else {
		prefix := match app.input_mode {
			.search { '/' }
			else { '>' }
		}

		' ${prefix} ${app.command_input}'
	}
	line := '${prompt}  ${app.status}'
	app.tui.draw_text(0, y, term.bg_rgb(24, 28, 32, pad_right(clip_plain(line, width), width)))
}

fn (app &BrowserApp) debug_status() string {
	return 'L:${app.last_sessions_ms}ms T:${app.last_transcript_ms}ms S:${app.last_search_ms}ms'
}

fn (app &BrowserApp) visible_rows() int {
	return max_int(app.tui.window_height - 4, 8)
}

fn display_session_title(session SessionSummary) string {
	if session.title.len > 0 {
		return session.title
	}
	return session.id
}

fn transcript_lines(page TranscriptPage, width int, query string, active_hit_seq int) []string {
	mut out := []string{}
	for entry in page.entries {
		head := '${entry.seq} ${entry.timestamp} ${entry.kind} ${entry.role}'
		head_line := term.bold(clip_plain(head, width))
		out << if entry.seq == active_hit_seq {
			term.bg_rgb(72, 58, 18, head_line)
		} else {
			head_line
		}
		text := if entry.markdown.len > 0 { entry.markdown } else { entry.text }
		for line in wrap_text(text, max_int(width - 2, 1)) {
			rendered := highlight_query_in_line('  ${line}', query)
			out << if entry.seq == active_hit_seq {
				term.bg_rgb(38, 34, 18, rendered)
			} else {
				rendered
			}
		}
		out << ''
	}
	return out
}

fn transcript_line_offset_for_seq(page TranscriptPage, seq int, width int) int {
	mut offset := 0
	for entry in page.entries {
		if entry.seq == seq {
			return offset
		}
		text := if entry.markdown.len > 0 { entry.markdown } else { entry.text }
		offset += 1 + wrap_text(text, max_int(width - 2, 1)).len + 1
	}
	return offset
}

fn entry_matches_query(entry SessionEntry, query string) bool {
	needle := query.to_lower()
	if needle.len == 0 {
		return false
	}
	text := if entry.markdown.len > 0 { entry.markdown } else { entry.text }
	haystack := '${entry.title}\n${entry.tool_name}\n${text}'.to_lower()
	return haystack.contains(needle)
}

fn highlight_query_in_line(line string, query string) string {
	if query.len == 0 {
		return line
	}
	lower := line.to_lower()
	needle := query.to_lower()
	mut start := 0
	mut out := strings.new_builder(line.len + 32)
	for {
		idx := lower.index_after(needle, start) or { break }
		end := idx + query.len
		if idx < start || end > line.len {
			break
		}
		out.write_string(line[start..idx])
		out.write_string(term.bg_rgb(120, 88, 16, term.bold(line[idx..end])))
		start = end
		if start >= line.len {
			break
		}
	}
	if start == 0 {
		return line
	}
	out.write_string(line[start..])
	return out.str()
}

fn wrap_text(text string, width int) []string {
	if width <= 0 {
		return ['']
	}
	mut out := []string{}
	for raw in text.replace('\t', '    ').split_into_lines() {
		if raw.len == 0 {
			out << ''
			continue
		}
		mut current := raw
		for display_width(current) > width {
			part := take_display_prefix(current, width)
			out << part
			current = current[part.len..]
		}
		out << current
	}
	return out
}

fn style_line(text string, width int, selected bool) string {
	line := pad_right(clip_plain(text, width), width)
	return if selected {
		term.bg_rgb(54, 64, 76, term.bold(line))
	} else {
		line
	}
}

fn clip_plain(text string, width int) string {
	if width <= 0 {
		return ''
	}
	if display_width(text) <= width {
		return text
	}
	mut out := strings.new_builder(text.len)
	mut used := 0
	for r in text.runes() {
		ch := r.str()
		w := display_width(ch)
		if used + w > max_int(width - 1, 0) {
			break
		}
		out.write_string(ch)
		used += w
	}
	return out.str() + '…'
}

fn take_display_prefix(text string, width int) string {
	mut out := strings.new_builder(text.len)
	mut used := 0
	for r in text.runes() {
		ch := r.str()
		w := display_width(ch)
		if used + w > width {
			break
		}
		out.write_string(ch)
		used += w
	}
	return out.str()
}

fn pad_right(text string, width int) string {
	visible := display_width(text)
	if visible >= width {
		return text
	}
	return text + ' '.repeat(width - visible)
}

fn display_width(text string) int {
	mut width := 0
	for r in text.runes() {
		width += east_asian.display_width(r.str(), 0)
	}
	return width
}

fn short_path(path string) string {
	if path.len <= 42 {
		return path
	}
	parts := path.split('/')
	if parts.len <= 2 {
		return clip_plain(path, 42)
	}
	return '…/' + parts[parts.len - 2..].join('/')
}

fn trim_last_rune(text string) string {
	runes := text.runes()
	if runes.len == 0 {
		return ''
	}
	mut out := strings.new_builder(text.len)
	for r in runes[..runes.len - 1] {
		out.write_string(r.str())
	}
	return out.str()
}

fn browser_input_text(e &tui.Event) string {
	if e.modifiers.has(.ctrl) || e.modifiers.has(.alt) {
		return ''
	}
	if e.code == .space {
		return ' '
	}
	if e.utf8.len == 0 {
		return ''
	}
	first := e.utf8[0]
	if first == 0x1b {
		return browser_text_from_escape_sequence(e.utf8)
	}
	if first < 32 || first == 127 {
		return ''
	}
	return e.utf8
}

fn debug_browser_input_event(e &tui.Event) {
	if os.getenv('AGENTVIEW_INPUT_DEBUG') == '' {
		return
	}
	mut bytes := []string{cap: e.utf8.len}
	for b in e.utf8.bytes() {
		bytes << int(b).str()
	}
	mut file := os.open_append('/tmp/agentview-input.log') or { return }
	file.writeln('code=${int(e.code)} ascii=${int(e.ascii)} mods=${int(e.modifiers)} utf8="${e.utf8}" bytes=${bytes.join(',')}') or {
		return
	}
	file.close()
}

fn browser_text_from_escape_sequence(text string) string {
	csi_u := browser_text_from_csi_u(text)
	if csi_u.len > 0 {
		return csi_u
	}
	return browser_text_from_modify_other_keys(text)
}

fn browser_text_from_csi_u(text string) string {
	if text.len < 4 || text[0] != 0x1b || text[1] != `[` || text[text.len - 1] != `u` {
		return ''
	}
	parts := text[2..text.len - 1].split(';')
	if parts.len == 0 || parts.len > 3 {
		return ''
	}
	if parts.len > 2 {
		return browser_text_from_reported_codepoints(parts[2])
	}
	codepoint := parts[0].split(':')[0].int()
	if codepoint < 32 || codepoint == 127 || codepoint > 0x10ffff {
		return ''
	}
	return rune(codepoint).str()
}

fn browser_text_from_modify_other_keys(text string) string {
	if text.len < 7 || text[0] != 0x1b || text[1] != `[` || text[text.len - 1] != `~` {
		return ''
	}
	parts := text[2..text.len - 1].split(';')
	if parts.len != 3 || parts[0] != '27' {
		return ''
	}
	codepoint := parts[2].int()
	if codepoint < 32 || codepoint == 127 || codepoint > 0x10ffff {
		return ''
	}
	return rune(codepoint).str()
}

fn browser_text_from_reported_codepoints(param string) string {
	if param.len == 0 {
		return ''
	}
	mut builder := strings.new_builder(param.len)
	for part in param.split(':') {
		codepoint := part.int()
		if codepoint < 32 || codepoint == 127 || codepoint > 0x10ffff {
			continue
		}
		builder.write_string(rune(codepoint).str())
	}
	return builder.str()
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}
