module storage

pub enum FtsQueryKind {
	term
	prefix
	all
	any
}

pub enum FtsScope {
	any
	heading
	paragraph
	code_block
	list_item
}

pub struct FtsQuery {
pub:
	table_name  string
	column_name string
	scope       FtsScope = .any
	kind        FtsQueryKind
	terms       []string
	limit       int
}

pub fn fts_scope_name(scope FtsScope) string {
	return match scope {
		.any { 'any' }
		.heading { 'heading' }
		.paragraph { 'paragraph' }
		.code_block { 'code_block' }
		.list_item { 'list_item' }
	}
}

pub fn fts_query_kind_name(kind FtsQueryKind) string {
	return match kind {
		.term { 'term' }
		.prefix { 'prefix' }
		.all { 'all' }
		.any { 'any' }
	}
}

pub fn fts_normalize_term(raw string) string {
	return raw.to_lower().trim_space()
}

pub fn fts_normalize_terms(raw_terms []string) []string {
	mut out := []string{}
	for raw in raw_terms {
		normalized := fts_normalize_term(raw)
		if normalized.len == 0 {
			continue
		}
		out << normalized
	}
	return out
}

pub fn validate_fts_query(query FtsQuery) ! {
	if query.table_name.len == 0 {
		return error('fts query requires table_name')
	}
	if query.column_name.len == 0 {
		return error('fts query requires column_name')
	}
	if query.terms.len == 0 {
		return error('fts query requires at least one term')
	}
	normalized := fts_normalize_terms(query.terms)
	if normalized.len == 0 {
		return error('fts query terms cannot all be empty')
	}
	match query.kind {
		.term, .prefix {
			if normalized.len != 1 {
				return error('fts ${fts_query_kind_name(query.kind)} query requires exactly one term')
			}
		}
		.all, .any {}
	}
}
