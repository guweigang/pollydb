module storage

pub struct FtsDerivedKey {
pub:
	scope FtsScope
	term  string
}

pub fn fts_distinct_keys(emissions []FtsTokenEmission) []FtsDerivedKey {
	mut out := []FtsDerivedKey{}
	for emission in emissions {
		fts_append_distinct_key(mut out, FtsDerivedKey{
			scope: emission.scope
			term: emission.term
		})
		fts_append_distinct_key(mut out, FtsDerivedKey{
			scope: .any
			term: emission.term
		})
	}
	return out
}

pub fn fts_markdown_derived_keys(raw string) ![]FtsDerivedKey {
	return fts_distinct_keys(emit_markdown_fts_tokens(raw)!)
}

pub fn fts_matches_query(keys []FtsDerivedKey, query FtsQuery) !bool {
	validate_fts_query(query)!
	normalized_terms := fts_normalize_terms(query.terms)
	match query.kind {
		.term {
			return fts_has_exact_term(keys, query.scope, normalized_terms[0])
		}
		.prefix {
			return fts_has_prefix_term(keys, query.scope, normalized_terms[0])
		}
		.all {
			for term in normalized_terms {
				if !fts_has_exact_term(keys, query.scope, term) {
					return false
				}
			}
			return true
		}
		.any {
			for term in normalized_terms {
				if fts_has_exact_term(keys, query.scope, term) {
					return true
				}
			}
			return false
		}
	}
}

fn fts_append_distinct_key(mut out []FtsDerivedKey, key FtsDerivedKey) {
	for existing in out {
		if existing.scope == key.scope && existing.term == key.term {
			return
		}
	}
	out << key
}

fn fts_has_exact_term(keys []FtsDerivedKey, scope FtsScope, term string) bool {
	for key in keys {
		if key.scope == scope && key.term == term {
			return true
		}
	}
	return false
}

fn fts_has_prefix_term(keys []FtsDerivedKey, scope FtsScope, prefix string) bool {
	for key in keys {
		if key.scope == scope && key.term.starts_with(prefix) {
			return true
		}
	}
	return false
}
