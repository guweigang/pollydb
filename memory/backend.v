module memory

pub struct VectorIndexRecord {
pub:
	branch_name string
	int_id      i64
	vector      []f32
}

pub struct VectorIndexQuery {
pub:
	branch_name string
	limit       int = 10
}

pub struct VectorIndexMatch {
pub:
	int_id i64
	score  f64
}

pub interface VectorIndexBackend {
	kind() string
mut:
	ready() !
	upsert(records []VectorIndexRecord) !
	query(vector []f32, query VectorIndexQuery) ![]VectorIndexMatch
}
