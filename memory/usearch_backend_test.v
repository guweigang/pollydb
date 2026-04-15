module memory

$if !usearch ? {
	fn test_usearch_backend_skipped_without_flag() {
		assert true
	}
}

$if usearch ? {
	fn test_usearch_backend_upsert_and_query() {
		mut backend := new_usearch_vector_backend(USearchVectorBackendConfig{
			dimensions: 2
			capacity:   8
		}) or { panic(err) }
		defer {
			backend.close() or {}
		}
		backend.upsert([
			VectorIndexRecord{
				branch_name: 'main'
				int_id:      1
				vector:      [f32(1.0), 0.0]
			},
			VectorIndexRecord{
				branch_name: 'main'
				int_id:      2
				vector:      [f32(0.0), 1.0]
			},
		]) or { panic(err) }
		hits := backend.query([f32(0.95), 0.05], VectorIndexQuery{
			branch_name: 'main'
			limit:       2
		}) or { panic(err) }
		assert hits.len == 2
		assert hits[0].int_id == 1
		assert hits[0].score > hits[1].score
	}

	fn test_usearch_backend_filters_branch_metadata() {
		mut backend := new_usearch_vector_backend(USearchVectorBackendConfig{
			dimensions: 2
			capacity:   8
		}) or { panic(err) }
		defer {
			backend.close() or {}
		}
		backend.upsert([
			VectorIndexRecord{
				branch_name: 'main'
				int_id:      1
				vector:      [f32(1.0), 0.0]
			},
			VectorIndexRecord{
				branch_name: 'feature'
				int_id:      2
				vector:      [f32(0.99), 0.01]
			},
		]) or { panic(err) }
		hits := backend.query([f32(1.0), 0.0], VectorIndexQuery{
			branch_name: 'main'
			limit:       2
		}) or { panic(err) }
		assert hits.len == 1
		assert hits[0].int_id == 1
	}
}
