module agentview

import term

const session_list_chrome_lines = 5

enum SessionListDensity {
	compact
	comfortable
}

struct SessionListViewState {
	width            int
	height           int
	focused          bool
	frame_count      u64
	total            int
	offset           int
	selected_index   int
	sessions         []SessionSummary
	query            string
	cwd_prefix       string
	include_archived bool
	density          SessionListDensity = .comfortable
}

fn browser_visible_session_capacity(total_height int) int {
	return browser_visible_session_capacity_with_density(total_height, .comfortable)
}

fn browser_visible_session_capacity_with_density(total_height int, density SessionListDensity) int {
	return max_int((browser_content_height(total_height) - session_list_chrome_lines) / session_row_height(density),
		1)
}

fn session_row_height(density SessionListDensity) int {
	return match density {
		.compact { 1 }
		.comfortable { 2 }
	}
}

fn render_session_list_lines(state SessionListViewState) []string {
	mut lines := []string{cap: max_int(state.height, 1)}
	row_height := session_row_height(state.density)
	content_height := max_int(state.height - session_list_chrome_lines, 0)
	visible_sessions := max_int(content_height / row_height, 1)
	content_width := if state.total > visible_sessions && state.width > 1 {
		state.width - 1
	} else {
		state.width
	}
	selected := if state.sessions.len > 0 { state.offset + state.selected_index + 1 } else { 0 }
	lines << pane_header(' Sessions ${selected}/${state.total} ', state.focused, content_width)
	lines << style_list_overview_line(session_list_overview_text(state), content_width)
	for row in 0 .. content_height {
		session_index := row / row_height
		if session_index >= state.sessions.len {
			lines << style_list_background(content_width)
			continue
		}
		session := state.sessions[session_index]
		is_selected := session_index == state.selected_index
		rendered := session_row_lines(session, content_width, is_selected, state.density,
			state.frame_count)
		line_index := row % row_height
		lines << rendered[line_index]
	}
	for line in selected_session_summary_lines(state, content_width) {
		lines << line
	}
	return apply_session_scrollbar(lines, state)
}

fn apply_session_scrollbar(lines []string, state SessionListViewState) []string {
	if lines.len == 0 || state.width < 10 {
		return lines
	}
	content_height := max_int(lines.len - session_list_chrome_lines, 0)
	visible_sessions := max_int(content_height / session_row_height(state.density), 1)
	if state.total <= visible_sessions {
		return lines
	}
	track_start := 1
	track_height := max_int(lines.len - session_list_chrome_lines - 1, 1)
	thumb_height := max_int((visible_sessions * track_height) / max_int(state.total, 1),
		1)
	max_offset := max_int(state.total - visible_sessions, 1)
	thumb_start := track_start +
		((state.offset * max_int(track_height - thumb_height, 0)) / max_offset)
	mut out := []string{cap: lines.len}
	for idx, line in lines {
		if idx == 0 || idx >= lines.len - 2 {
			out << line
			continue
		}
		mut base := pad_right(fit_ansi_line(line, max_int(state.width - 1, 1)), max_int(state.width - 1,
			1))
		on_thumb := idx >= thumb_start && idx < thumb_start + thumb_height
		base += if on_thumb { term.bright_white('█') } else { term.bright_black('│') }
		out << base
	}
	return out
}

fn session_row_lines(session SessionSummary, width int, selected bool, density SessionListDensity, frame_count u64) []string {
	title := session_display_title(session)
	left_marker := if selected { '▎' } else { ' ' }
	flags := if session.archived { ' [A]' } else { '' }
	title_prefix := if selected { '◉ ' } else { '● ' }
	title_width := max_int(width - display_width_plain(left_marker) - display_width_plain(title_prefix) - display_width_plain(flags),
		1)
	visible_title := if selected {
		marquee_text(title, title_width, frame_count)
	} else {
		clip_plain(title, title_width)
	}
	if density == .compact {
		line := '${left_marker}${title_prefix}${visible_title}${flags}'
		return [style_session_primary_row(line, width, selected)]
	}
	line1 := '${left_marker}${title_prefix}${visible_title}${flags}'
	meta := compact_session_meta_line(session, width - 4)
	line2 := '  ${meta}'
	return [
		style_session_primary_row(line1, width, selected),
		style_session_secondary_row(line2, width, selected),
	]
}

fn compact_session_meta_line(session SessionSummary, width int) string {
	source := compact_source_label(session)
	cwd := compact_cwd_label(session.cwd, 18)
	mut parts := ['${compact_time(session.updated_at)}']
	if session_has_human_title(session) && cwd.len > 0 {
		parts << cwd
	}
	if !session_has_human_title(session) {
		parts << 'id:${short_session_id(session.id)}'
	}
	parts << source
	parts << 'e:${session.entry_count}'
	parts << 't:${session.tool_calls}'
	if cwd.len > 0 {
		if !session_has_human_title(session) {
			parts << cwd
		}
	}
	return clip_plain(parts.join(' • '), width)
}

fn session_display_title(session SessionSummary) string {
	if session_has_human_title(session) {
		return session.title
	}
	cwd := compact_cwd_label(session.cwd, 18)
	short_id := short_session_id(session.id)
	if cwd.len > 0 && short_id.len > 0 {
		return '${cwd} · ${short_id}'
	}
	if cwd.len > 0 {
		return cwd
	}
	if short_id.len > 0 {
		return 'session ${short_id}'
	}
	source := compact_source_label(session)
	if source.len > 0 {
		return source
	}
	return 'untitled session'
}

fn session_has_human_title(session SessionSummary) bool {
	title := session.title.trim_space()
	if title.len == 0 {
		return false
	}
	title_lower := title.to_lower()
	id_lower := session.id.to_lower()
	if title_lower == id_lower {
		return false
	}
	return !title_lower.starts_with('rollout-') && !title_lower.starts_with('session-')
}

fn compact_source_label(session SessionSummary) string {
	source := if session.source.len > 0 { session.source } else { 'codex' }
	if session.originator.len > 0 {
		return '${source}/${session.originator}'
	}
	return source
}

fn compact_cwd_label(cwd string, width int) string {
	if cwd.len == 0 || width <= 0 {
		return ''
	}
	segments := cwd.split('/')
	if segments.len == 0 {
		return clip_plain(cwd, width)
	}
	last := segments[segments.len - 1]
	if last.len > 0 {
		return clip_plain(last, width)
	}
	return clip_plain(cwd, width)
}

fn short_session_id(session_id string) string {
	if session_id.len == 0 {
		return ''
	}
	return if session_id.len > 8 { session_id[..8] } else { session_id }
}

fn session_list_overview_text(state SessionListViewState) string {
	mut parts := []string{}
	if state.query.len > 0 {
		parts << 'text:${state.query}'
	}
	if state.cwd_prefix.len > 0 {
		parts << 'cwd:${state.cwd_prefix}'
	}
	if !state.include_archived {
		parts << 'live only'
	}
	if state.density == .compact {
		parts << 'compact'
	}
	if parts.len == 0 {
		parts << 'all sessions'
	}
	return ' ' + clip_plain(parts.join(' • '), max_int(state.width - 2, 1))
}

fn selected_session_summary_lines(state SessionListViewState, width int) []string {
	if state.sessions.len == 0 || state.selected_index >= state.sessions.len {
		return [
			style_summary_line(' Selected', width, true, false),
			style_summary_line(' No session selected', width, false, false),
			style_summary_line('', width, false, true),
		]
	}
	session := state.sessions[state.selected_index]
	title := session_display_title(session)
	title_line := marquee_text(title, max_int(width - 4, 1), state.frame_count)
	meta_line := clip_plain('${compact_time(session.updated_at)} • id:${short_session_id(session.id)} • ${compact_source_label(session)} • ${clip_plain(session.cwd,
		max_int(width - 34, 10))}', max_int(width - 4, 1))
	return [
		style_summary_line(' Selected', width, true, false),
		style_summary_line(' ◆ ' + title_line, width, false, false),
		style_summary_line('   ' + meta_line, width, false, true),
	]
}

fn compact_time(value string) string {
	if value.len >= 19 && value.contains('T') {
		return value.replace('T', ' ')[5..19]
	}
	return value
}

fn style_list_overview_line(text string, width int) string {
	body := pad_right(clip_plain(text, width), width)
	return term.bg_rgb(18, 21, 26, term.rgb(126, 132, 142, body))
}

fn style_summary_line(text string, width int, primary bool, subtle bool) string {
	body := pad_right(clip_plain(text, width), width)
	return if primary {
		term.bg_rgb(20, 23, 28, term.rgb(232, 236, 243, term.bold(body)))
	} else if subtle {
		term.bg_rgb(18, 21, 26, term.rgb(134, 142, 154, body))
	} else {
		term.bg_rgb(18, 21, 26, term.rgb(222, 227, 235, term.bold(body)))
	}
}

fn style_session_primary_row(text string, width int, selected bool) string {
	body := pad_right(clip_ansi_text(text, width), width)
	return if selected {
		term.bg_rgb(96, 124, 188, term.rgb(255, 255, 255, term.bold(body)))
	} else {
		term.bg_rgb(26, 30, 36, term.rgb(236, 239, 244, term.bold(body)))
	}
}

fn style_session_secondary_row(text string, width int, selected bool) string {
	body := pad_right(clip_ansi_text(text, width), width)
	return if selected {
		term.bg_rgb(78, 102, 156, term.rgb(240, 246, 255, body))
	} else {
		term.bg_rgb(22, 25, 30, term.rgb(128, 136, 148, body))
	}
}

fn style_list_background(width int) string {
	return term.bg_rgb(12, 14, 18, ' '.repeat(width))
}

fn marquee_text(text string, width int, frame_count u64) string {
	if width <= 0 {
		return ''
	}
	if display_width_plain(text) <= width {
		return clip_plain(text, width)
	}
	padding := '   '
	loop_text := text + padding + text
	overflow := display_width_plain(text) - width
	hold := 12
	cycle := overflow + hold
	mut offset := int((frame_count / 6) % u64(max_int(cycle, 1)))
	if offset > overflow {
		offset = overflow
	}
	return display_slice(loop_text, offset, width)
}

fn display_slice(text string, offset int, width int) string {
	if width <= 0 {
		return ''
	}
	mut out := []rune{}
	mut skipped := 0
	mut used := 0
	for r in text.runes() {
		rw := display_width_plain(r.str())
		if skipped + rw <= offset {
			skipped += rw
			continue
		}
		if used + rw > width {
			break
		}
		out << r
		used += rw
	}
	return out.string()
}
