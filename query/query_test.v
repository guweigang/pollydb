module query

import os
import storage

fn query_test_users_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('users', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('name', .string_, false)!,
		storage.ColumnDef.new('email', .string_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.covering('email_idx', 'email')!,
	])
}

fn query_test_docs_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('docs', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('content_text', .string_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.fts_with_options('content_text_fts_idx', 'content_text', storage.FtsIndexOptions{
			prefix_lengths: [2, 3]
		})!,
	])
}

fn query_test_entries_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('entries', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('timestamp', .datetime_, false)!,
		storage.ColumnDef.new('content_text', .string_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('entries_session_idx', 'session_id')!,
		storage.SchemaIndexDef.covering_projected('entries_session_cover_idx', 'session_id', [
			'id',
			'timestamp',
		])!,
	])
}

fn query_test_notes_fts_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('notes', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('title', .string_, false)!,
		storage.ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.markdown_value('body_fts_any_idx', 'body', 'fts')!,
	])
}

fn query_test_seed_user(mut db storage.PersistentDatabase, cfg storage.ChunkConfig) ! {
	mut row := storage.TypedRowData.new()
	row.set('id', 'u1')
	row.set('name', 'Ada')
	row.set('email', 'ada@example.com')
	tree := storage.build_single_row_seed_tree(query_test_users_spec()!, 'u1'.bytes(), row, cfg)!
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'test'
		message:   'seed users'
		timestamp: 1
	})!
}

fn query_test_seed_doc(mut db storage.PersistentDatabase, cfg storage.ChunkConfig) ! {
	mut row := storage.TypedRowData.new()
	row.set('id', 'd1')
	row.set('content_text', 'pollydb roadmap search')
	tree := storage.build_single_row_seed_tree(query_test_docs_spec()!, 'd1'.bytes(), row, cfg)!
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'test'
		message:   'seed docs'
		timestamp: 2
	})!
}

fn test_query_facade_page_and_preview() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-facade-page')
	defer {
		os.rmdir_all(dir) or {}
	}
	cfg := storage.ChunkConfig.default()
	mut db := storage.PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(query_test_users_spec() or { panic(err) }) or { panic(err) }
	query_test_seed_user(mut db, cfg) or { panic(err) }
	db.checkpoint() or { panic(err) }

	mut query_db := open_database(dir, 'main') or { panic(err) }
	defer {
		query_db.close() or {}
	}
	query_session := query_db.begin_session('main') or { panic(err) }
	page := query_page(query_session, mut query_db, Request{
		table_name:     'users'
		filters:        [
			Filter.eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id', 'name']
		limit:          1
	}) or { panic(err) }
	assert page.rows.len == 1
	assert page.plan.index_name == 'email_idx'

	preview := preview_plan_details(query_db, Request{
		table_name:     'users'
		filters:        [
			Filter.eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id', 'name']
		limit:          1
	}) or { panic(err) }
	assert preview.plan.index_name == 'email_idx'

	session_preview := preview_plan_details_in_session(query_session, Request{
		table_name:     'users'
		filters:        [
			Filter.eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id', 'name']
		limit:          1
	}) or { panic(err) }
	assert session_preview.plan.index_name == 'email_idx'
	assert session_preview.default_result_shape == 'page'
	assert session_preview.supports_continuation_token

	schema := table_schema(query_db, 'users') or { panic(err) }
	assert schema.table_name == 'users'
	assert schema.columns.len == 3
	assert schema.columns[2].name == 'email'
	assert schema.columns[2].filter_shapes.len > 0
	assert schema.columns[2].filter_shapes[0].sample_explain.strategy.len > 0

	spec := query_test_users_spec() or { panic(err) }
	spec_preview := preview_plan_from_spec(query_spec(spec, map[string]ProjectionDef{}), Request{
		table_name:     'users'
		filters:        [
			Filter.eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id', 'name']
		limit:          1
	}) or { panic(err) }
	assert spec_preview.index_name == 'email_idx'

	spec_preview_details := preview_plan_details_from_spec(query_spec(spec,
		map[string]ProjectionDef{}), Request{
		table_name:     'users'
		filters:        [
			Filter.eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id', 'name']
		limit:          1
	}) or { panic(err) }
	assert spec_preview_details.plan.index_name == 'email_idx'
	assert spec_preview_details.notes.any(it.contains('covering index'))

	spec_schema := table_schema_from_spec(query_spec(spec, map[string]ProjectionDef{}), 'users') or {
		panic(err)
	}
	assert spec_schema.table_name == 'users'
	assert spec_schema.columns.len == 3

	mut tx := query_session.begin_working_set(mut query_db) or { panic(err) }
	tx_preview := preview_plan_details_in_transaction(tx, Request{
		table_name:     'users'
		filters:        [
			Filter.eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id', 'name']
		limit:          1
	}) or { panic(err) }
	assert tx_preview.plan.index_name == 'email_idx'
	assert tx_preview.default_result_shape == 'page'
	assert tx_preview.supports_continuation_token
}

fn test_query_planner_prefers_projected_covering_index_for_selected_columns() {
	spec := query_test_entries_spec() or { panic(err) }
	plan := preview_plan_from_spec(query_spec(spec, map[string]ProjectionDef{}), Request{
		table_name:     'entries'
		filters:        [
			Filter.eq('session_id', QueryValue.string_value('session-001')),
		]
		select_columns: ['id', 'timestamp']
		limit:          10
	}) or { panic(err) }
	assert plan.index_name == 'entries_session_cover_idx'
	assert plan_uses_projection_pushdown(plan)
}

fn test_query_facade_lowering_requests() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-facade-lowering')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut db := storage.PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(query_test_users_spec() or { panic(err) }) or { panic(err) }
	db.checkpoint() or { panic(err) }

	mut query_db := open_database(dir, 'main') or { panic(err) }
	defer {
		query_db.close() or {}
	}
	lowered := lower_request(query_db, LoweringRequest{
		table_name:     'users'
		predicates:     [
			PredicateSpec.column_eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id']
		limit:          1
	}) or { panic(err) }
	assert lowered.table_name == 'users'
	assert lowered.filters.len == 1
	assert lowered.filters[0].column_name == 'email'

	normalized := lower_normalized_request(query_db, NormalizedLoweringRequest{
		table_name:     'users'
		predicates:     [
			NormalizedPredicate.column_eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id']
		limit:          1
	}) or { panic(err) }
	assert normalized.filters.len == 1
	assert normalized.filters[0].column_name == 'email'

	sql_lowered := lower_sql_filter_request(query_db, SqlLoweringRequest{
		table_name:     'users'
		filters:        [
			SqlFilterFragment.column_eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id']
		limit:          1
	}) or { panic(err) }
	assert sql_lowered.filters.len == 1
	assert sql_lowered.filters[0].column_name == 'email'

	spec := query_test_users_spec() or { panic(err) }
	lowered_from_spec := lower_request_from_spec(query_spec(spec, map[string]ProjectionDef{}), LoweringRequest{
		table_name:     'users'
		predicates:     [
			PredicateSpec.column_eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id']
		limit:          1
	}) or { panic(err) }
	assert lowered_from_spec.filters.len == 1
	assert lowered_from_spec.filters[0].column_name == 'email'

	schema := table_schema_from_spec(query_spec(spec, map[string]ProjectionDef{}), 'users') or {
		panic(err)
	}
	lowered_with_schema := lower_request_with_schema(schema, LoweringRequest{
		table_name:     'users'
		predicates:     [
			PredicateSpec.column_eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id']
		limit:          1
	}) or { panic(err) }
	assert lowered_with_schema.filters.len == 1
	assert lowered_with_schema.filters[0].column_name == 'email'

	normalized_from_spec := lower_normalized_request_from_spec(query_spec(spec,
		map[string]ProjectionDef{}), NormalizedLoweringRequest{
		table_name:     'users'
		predicates:     [
			NormalizedPredicate.column_eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id']
		limit:          1
	}) or { panic(err) }
	assert normalized_from_spec.filters.len == 1

	sql_from_spec := lower_sql_filter_request_from_spec(query_spec(spec, map[string]ProjectionDef{}), SqlLoweringRequest{
		table_name:     'users'
		filters:        [
			SqlFilterFragment.column_eq('email', QueryValue.string_value('ada@example.com')),
		]
		select_columns: ['id']
		limit:          1
	}) or { panic(err) }
	assert sql_from_spec.filters.len == 1
}

fn test_query_normalization_conversion_helpers() {
	gt := predicate_spec_from_normalized(NormalizedPredicate.column_gt('created_at',
		QueryValue.string_value('2025-01-01T00:00:00Z'))) or { panic(err) }
	assert gt.target.column_name == 'created_at'
	assert gt.op == .after

	between := predicate_spec_from_normalized(NormalizedPredicate.field_between('body', 'markdown',
		'links', QueryValue.i64_value(i64(1)), QueryValue.i64_value(i64(3)))) or { panic(err) }
	assert between.target.column_name == 'body'
	assert between.target.plugin_name == 'markdown'
	assert between.target.selector == 'links'
	assert between.op == .between
	assert between.has_second_value
}

fn test_query_sql_filter_conversion_helpers() {
	predicate := normalized_predicate_from_sql_filter(SqlFilterFragment.field_like_prefix('body',
		'markdown', 'heading_text:2', 'Road')) or { panic(err) }
	assert predicate.target.column_name == 'body'
	assert predicate.target.plugin_name == 'markdown'
	assert predicate.target.selector == 'heading_text:2'
	assert predicate.op == .prefix
	assert predicate.value.as_string() or { panic(err) } == 'Road'
}

fn test_query_continuation_token_helpers_for_index_plan() {
	plan := Plan{
		table_name:   'users'
		strategy:     'index_eq'
		index_name:   'email_idx'
		index_filter: Filter.eq('email', QueryValue.string_value('ada@example.com'))
		limit:        1
	}
	token := encode_continuation_token_for_plan(plan, 'u1'.bytes(),
		QueryValue.string_value('ada@example.com'))
	assert token.len > 0

	request := request_with_continuation_token(Request{
		table_name:         'users'
		filters:            [
			Filter.eq('email', QueryValue.string_value('ada@example.com')),
		]
		continuation_token: token
		limit:              1
	}, plan) or { panic(err) }
	assert request.start_primary_key.bytestr() == 'u1'
	assert request.has_start_index_value
	assert request.start_index_value.as_string() or { panic(err) } == 'ada@example.com'
}

fn test_query_continuation_token_helpers_for_ordered_plan() {
	plan := Plan{
		table_name: 'users'
		strategy:   'index_order_desc'
		index_name: 'email_idx'
		order_by:   Order{
			column_name: 'email'
			direction:   .desc
		}
		limit:      2
	}
	token := encode_continuation_token_for_plan(plan, 'u2'.bytes(),
		QueryValue.string_value('zoe@example.com'))
	assert token.len > 0

	request := request_with_continuation_token(Request{
		table_name:         'users'
		order_by:           Order{
			column_name: 'email'
			direction:   .desc
		}
		continuation_token: token
		limit:              2
	}, plan) or { panic(err) }
	assert request.start_primary_key.bytestr() == 'u2'
	assert request.has_start_index_value
	assert request.start_index_value.as_string() or { panic(err) } == 'zoe@example.com'
}

fn test_query_build_plan_preview_from_schema() {
	schema := TableSchema{
		table_name:                  'users'
		indexes:                     [
			IndexCapability{
				name:        'email_idx'
				column_name: 'email'
				stores_row:  false
			},
		]
		field_selectors:             [
			FieldSelectorCapability{
				column_name:      'body'
				plugin_name:      'markdown'
				selector:         'heading_text:2'
				projection_names: ['heading_projection']
			},
		]
		projection_metrics:          [
			ProjectionCapability{
				name:        'heading_projection'
				column_name: 'body'
				plugin_name: 'markdown'
				selector:    'heading_text:2'
			},
		]
		default_result_shape:        'page'
		supports_continuation_token: true
	}
	request := Request{
		table_name:     'users'
		filters:        [
			Filter.field_prefix('body', 'markdown', 'heading_text:2',
				QueryValue.string_value('Road')),
		]
		select_columns: ['id']
		limit:          5
	}
	plan := Plan{
		table_name:        'users'
		strategy:          'index_prefix_order_desc_projected'
		index_name:        'email_idx'
		post_filter_count: 1
		order_by:          Order{
			column_name: 'email'
			direction:   .desc
		}
		limit:             5
	}
	preview := build_plan_preview(schema, request, plan) or { panic(err) }
	assert preview.default_result_shape == 'page'
	assert preview.supports_continuation_token
	assert preview.notes.any(it.contains('covering index'))
	assert preview.notes.any(it.contains('post-filters'))
	assert preview.notes.any(it.contains('reverse index scan'))
	assert preview.notes.any(it.contains('Top-N retrieval'))
	assert preview.notes.any(it.contains('Requested ordering'))
	assert preview.warnings.any(it.contains('projection-only'))
	assert plan_uses_projection_pushdown(plan)
	assert plan_supports_reverse_scan(plan)
	assert plan_supports_top_n(plan)
	assert projection_pushdown_eligible(true, false, false, ['id'], 0)
	assert !projection_pushdown_eligible(true, true, false, ['id'], 0)
	assert !projection_pushdown_eligible(true, false, false, ['id'], 1)
	assert fetch_limit(0, 5) == 6
	assert fetch_limit(1, 5) == 0
	assert ordered_index_scan('index_order_asc')
	assert !ordered_index_scan('index_after')
	assert reverse_filtered_order('email', 'email', true, .before)
	assert !reverse_filtered_order('email', 'email', false, .before)
	assert !reverse_filtered_order('email', 'email', true, .eq)
	assert requires_base_row_fetch(true, ['id'], false)
	assert !requires_base_row_fetch(true, ['id'], true)
	assert !requires_base_row_fetch(false, ['id'], false)
	assert preview_notes(1, true, false, true, true, true).len == 5
	assert preview_warnings(true) == [
		'No eligible index matched; planner will fall back to table scan.',
	]
	assert field_selector_planning_warning('body.markdown:heading_text:2', true).contains('projection-only')
	assert field_selector_planning_warning('body.markdown:heading_text:2', false).contains('no matching derived index')
}

fn test_query_schema_helper_builders() {
	string_ops := supported_ops_for_type(.string_)
	assert string_ops == [FilterOp.eq, .prefix, .after, .before, .between]

	markdown_value := sample_value_for_type(.markdown_)
	assert (markdown_value.as_markdown_ref() or { panic(err) }).doc_root_id == ''

	filter := sample_filter('body', 'markdown', 'heading_text:2', .string_, .prefix)
	assert filter.column_name == 'body'
	assert filter.plugin_name == 'markdown'
	assert filter.selector == 'heading_text:2'
	assert filter.op == .prefix

	assert filter_op_supports_reverse_scan(true, '', '', .before)
	assert !filter_op_supports_reverse_scan(true, 'markdown', 'heading_text:2', .before)
	assert filter_op_supports_top_n(true, '', '', .eq)
	assert !filter_op_supports_top_n(false, '', '', .eq)

	assert supported_fts_kinds_for_selector('markdown', 'fts:title') == [FtsKind.term, .prefix,
		.all, .any]
	assert supported_fts_kinds_for_selector('markdown', 'heading_text:2').len == 0
	assert sample_fts_terms(.term) == ['roadmap']
	assert sample_fts_terms(.all) == ['pollydb', 'merge']
	assert supports_order_shapes('', '')
	assert !supports_order_shapes('markdown', 'heading_text:2')
	assert filter_shape_projection_only(false, ['p1'])
	assert !filter_shape_projection_only(true, ['p1'])
	assert filter_shape_continuation_anchor(true)
	assert !filter_shape_continuation_anchor(false)
	flags := filter_shape_flags(false, ['p1'], '', '', .prefix)
	assert flags.projection_only
	assert !flags.continuation_anchor
	assert !flags.supports_reverse
	assert !flags.supports_top_n
	indexed_flags := filter_shape_flags(true, ['p1'], '', '', .prefix)
	assert !indexed_flags.projection_only
	assert indexed_flags.continuation_anchor
	assert indexed_flags.supports_reverse
	assert indexed_flags.supports_top_n
	plan_flags := plan_explain_flags(Plan{
		table_name: 'users'
		strategy:   'index_before_order_desc'
		index_name: 'email_idx'
	}, true)
	assert plan_flags.supports_continuation
	assert plan_flags.supports_reverse
	assert plan_flags.supports_top_n
	assert order_index_eligible(false, false, false, true)
	assert !order_index_eligible(true, false, false, true)
	assert !order_index_eligible(false, true, false, true)
	assert order_index_score(false, []) == 10
	assert order_index_score(true, ['id']) == 15
	assert filter_index_eligible(false, false, false, false, true, false, false, true)
	assert !filter_index_eligible(false, true, false, false, true, false, false, true)
	assert filter_index_eligible(true, true, false, false, true, true, true, false)
	assert !filter_index_eligible(true, true, false, false, true, true, false, false)

	fallback := sample_plan_fallback_explain()
	assert fallback.strategy == 'table_scan'
	assert fallback.warnings == [
		'Unable to build sample plan preview for this filter shape.',
	]
	assert fallback.default_result_shape == 'page'
	assert fallback.supports_continuation_token

	order_by := sample_order_for_filter(true, 'email', '', '', .prefix)
	assert order_by.column_name == 'email'
	assert order_by.direction == .desc
	request :=
		sample_plan_request('users', Filter.prefix('email', QueryValue.string_value('ada')), true)
	assert request.table_name == 'users'
	assert request.filters.len == 1
	assert request.order_by.column_name == 'email'

	no_order := sample_order_for_filter(false, 'email', '', '', .prefix)
	assert no_order.column_name.len == 0

	field_order := sample_order_for_filter(true, 'body', 'markdown', 'heading_text:2', .prefix)
	assert field_order.column_name.len == 0
	filter_capability := filter_shape_capability(Filter.prefix('email',
		QueryValue.string_value('ada')), .string_, .prefix, ['name_projection'], 12, 'email_idx', SamplePlanExplain{
		strategy:             'index_prefix_order_desc'
		index_name:           'email_idx'
		default_result_shape: 'page'
	})
	assert filter_capability.indexed
	assert filter_capability.index_name == 'email_idx'
	assert filter_capability.supports_reverse_scan
	order_cap := order_capability('email', .desc, .prefix, Plan{
		table_name: 'users'
		strategy:   'index_prefix_order_desc'
		index_name: 'email_idx'
	}, PlanPreview{
		plan:                        Plan{
			table_name: 'users'
			strategy:   'index_prefix_order_desc'
			index_name: 'email_idx'
		}
		default_result_shape:        'page'
		supports_continuation_token: true
	})
	assert order_cap.indexed
	assert order_cap.supports_continuation
	assert order_cap.supports_reverse_scan
	assert field_selector_key('body', 'markdown', 'heading_text:2') == 'body\nmarkdown\nheading_text:2'
	field_cap := field_selector_capability('body', 'markdown', 'heading_text:2', .string_, false, [
		.eq,
		.prefix,
	], []PlannerHint{}, [.term], []FtsShapeCapability{})
	assert field_cap.column_name == 'body'
	assert field_cap.filter_ops == [FilterOp.eq, .prefix]
	column_cap := column_capability('email', .string_, false, [.eq, .prefix], [
		'email_idx',
	], []PlannerHint{}, [
		filter_shape_capability(Filter.prefix('email', QueryValue.string_value('ada')), .string_,
			.prefix, []string{}, 12, 'email_idx', SamplePlanExplain{
			strategy:             'index_prefix'
			index_name:           'email_idx'
			default_result_shape: 'page'
		}),
	], [order_cap])
	assert column_cap.name == 'email'
	assert column_cap.index_names == ['email_idx']
	index_cap := index_capability('email_idx', 'email', .string_, true, false, []FtsKind{},
		[]FtsShapeCapability{}, '', FieldSelectorMetaDef{}, [.eq, .prefix])
	assert index_cap.name == 'email_idx'
	assert !index_cap.is_fts
	proj_cap := projection_metric_capability('heading_projection', 'body', '', 'markdown',
		'heading_text:2', .string_, .none, 1, .low)
	assert proj_cap.name == 'heading_projection'
	assert proj_cap.selector == 'heading_text:2'
	table_cap := table_schema_capability('users', ['id'], [column_cap], [index_cap], [
		field_cap,
	], [proj_cap], [.eq, .prefix], 'page', true, true)
	assert table_cap.table_name == 'users'
	assert table_cap.columns.len == 1
	assert table_cap.indexes.len == 1
	assert table_cap.field_selectors.len == 1
}

fn test_query_schema_sample_explain_helpers() {
	preview := PlanPreview{
		plan:                        Plan{
			table_name: 'users'
			strategy:   'index_before_order_desc'
			index_name: 'email_idx'
		}
		warnings:                    ['warn']
		notes:                       ['note']
		default_result_shape:        'page'
		supports_continuation_token: true
	}
	explain := sample_explain_from_preview(preview)
	assert explain.strategy == 'index_before_order_desc'
	assert explain.index_name == 'email_idx'
	assert explain.warnings == ['warn']
	assert explain.notes == ['note']
	assert explain.default_result_shape == 'page'
	assert explain.supports_continuation_token
	assert explain.supports_reverse_scan
	assert explain.supports_top_n

	fts_explain := sample_fts_explain_from_preview(FtsPreview{
		plan:     FtsPlan{
			table_name:  'docs'
			column_name: 'content_text'
			scope:       .any
			kind:        .term
			strategy:    'fts_term'
			index_name:  'content_text_fts_idx'
			limit:       5
		}
		warnings: ['fts warn']
		notes:    ['fts note']
	})
	assert fts_explain.strategy == 'fts_term'
	assert fts_explain.index_name == 'content_text_fts_idx'
	assert fts_explain.default_result_shape == 'rows'
	assert !fts_explain.supports_continuation_token

	general_explain := sample_general_fts_explain(GeneralFtsPlan{
		table_name:  'docs'
		index_name:  'content_text_fts_idx'
		column_name: 'content_text'
		strategy:    'general_fts_term'
		backend:     'sqlite_fts5'
		term_count:  1
		limit:       5
	})
	assert general_explain.strategy == 'general_fts_term'
	assert general_explain.index_name == 'content_text_fts_idx'
	assert general_explain.notes.any(it.contains('SQLite FTS5 sidecar'))
	assert general_explain.default_result_shape == 'rows'
}

fn test_query_facade_general_fts() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-facade-fts')
	defer {
		os.rmdir_all(dir) or {}
	}
	cfg := storage.ChunkConfig.default()
	mut db := storage.PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(query_test_docs_spec() or { panic(err) }) or { panic(err) }
	query_test_seed_doc(mut db, cfg) or { panic(err) }
	db.rebuild_fts_indexes_at_branch('main', ['docs']) or { panic(err) }
	db.checkpoint() or { panic(err) }

	mut query_db := open_database(dir, 'main') or { panic(err) }
	defer {
		query_db.close() or {}
	}
	query_session := query_db.begin_session('main') or { panic(err) }
	preview := preview_general_fts_in_session(query_session, GeneralFtsRequest{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .term
		terms:          ['roadmap']
		select_columns: ['id']
		limit:          5
	}) or { panic(err) }
	assert preview.index_name == 'content_text_fts_idx'

	spec_fts_preview := preview_fts_from_spec(query_spec(query_test_notes_fts_spec() or {
		panic(err)
	}, map[string]ProjectionDef{}), FtsRequest{
		table_name:  'notes'
		column_name: 'body'
		scope:       .any
		kind:        .term
		terms:       ['roadmap']
		limit:       5
	}) or { panic(err) }
	assert spec_fts_preview.index_name == 'body_fts_any_idx'

	spec_fts_details := preview_fts_details_from_spec(query_spec(query_test_notes_fts_spec() or {
		panic(err)
	}, map[string]ProjectionDef{}), FtsRequest{
		table_name:  'notes'
		column_name: 'body'
		scope:       .any
		kind:        .term
		terms:       ['roadmap']
		limit:       5
	}) or { panic(err) }
	assert spec_fts_details.plan.index_name == 'body_fts_any_idx'
	assert spec_fts_details.warnings.len == 0

	fts_preview := fts_plan_preview(FtsPlan{
		table_name:  'notes'
		column_name: 'body'
		scope:       .any
		kind:        .all
		strategy:    'fts_index_all'
		index_name:  'body_fts_any_idx'
		selector:    'fts'
		term_count:  2
		limit:       5
	}, FtsRequest{
		table_name:  'notes'
		column_name: 'body'
		scope:       .any
		kind:        .all
		terms:       ['pollydb', 'merge']
		limit:       5
	})
	assert fts_preview.notes.len == 1
	assert fts_preview.notes[0].contains('intersect exact FTS term matches')
	assert fts_preview.warnings.len == 0

	fts_scan_preview := fts_plan_preview(FtsPlan{
		table_name:  'notes'
		column_name: 'body'
		scope:       .heading
		kind:        .term
		strategy:    'fts_scan_term'
		index_name:  ''
		selector:    'fts:heading'
		term_count:  1
		limit:       5
	}, FtsRequest{
		table_name:  'notes'
		column_name: 'body'
		scope:       .heading
		kind:        .term
		terms:       ['roadmap']
		limit:       5
	})
	assert fts_scan_preview.warnings.len == 1
	assert fts_scan_preview.warnings[0].contains('fall back to table scan')

	spec_general_preview := preview_general_fts_from_spec(query_spec(query_test_docs_spec() or {
		panic(err)
	}, map[string]ProjectionDef{}), GeneralFtsRequest{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .term
		terms:          ['roadmap']
		select_columns: ['id']
		limit:          5
	}) or { panic(err) }
	assert spec_general_preview.index_name == 'content_text_fts_idx'
	spec_general_details := preview_general_fts_details_from_spec(query_spec(query_test_docs_spec() or {
		panic(err)
	}, map[string]ProjectionDef{}), GeneralFtsRequest{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .term
		terms:          ['roadmap']
		select_columns: ['id']
		limit:          5
	}) or { panic(err) }
	assert spec_general_details.plan.index_name == 'content_text_fts_idx'
	assert spec_general_details.notes.any(it.contains('SQLite FTS5 sidecar'))

	general_request_preview := preview_plan_details_from_spec(query_spec(query_test_docs_spec() or {
		panic(err)
	}, map[string]ProjectionDef{}), Request{
		table_name:  'docs'
		general_fts: GeneralFtsClause{
			index_name: 'content_text_fts_idx'
			kind:       .term
			terms:      ['roadmap']
		}
		limit:       5
	}) or { panic(err) }
	assert general_request_preview.plan.index_name == 'content_text_fts_idx'
	assert general_request_preview.default_result_shape == 'rows'
	assert !general_request_preview.supports_continuation_token
	assert general_request_preview.notes.any(it.contains('SQLite FTS5 sidecar'))
	clause_request := general_fts_request_from_clause('docs', GeneralFtsClause{
		index_name: 'content_text_fts_idx'
		kind:       .term
		terms:      ['roadmap']
	}, ['id'], 5)
	assert clause_request.table_name == 'docs'
	assert clause_request.index_name == 'content_text_fts_idx'
	assert clause_request.select_columns == ['id']
	plan_preview := general_fts_plan_preview(GeneralFtsPlan{
		table_name:  'docs'
		index_name:  'content_text_fts_idx'
		column_name: 'content_text'
		strategy:    'sqlite_fts5_match'
		backend:     'sqlite_fts5'
		term_count:  1
		limit:       5
	})
	assert plan_preview.plan.index_name == 'content_text_fts_idx'
	assert plan_preview.default_result_shape == 'rows'
	assert !plan_preview.supports_continuation_token
	assert plan_preview.notes.any(it.contains('SQLite FTS5 sidecar'))

	live_general_request_preview := preview_plan_details(query_db, Request{
		table_name:  'docs'
		general_fts: GeneralFtsClause{
			index_name: 'content_text_fts_idx'
			kind:       .term
			terms:      ['roadmap']
		}
		limit:       5
	}) or { panic(err) }
	assert live_general_request_preview.plan.index_name == 'content_text_fts_idx'
	assert live_general_request_preview.default_result_shape == 'rows'
	assert !live_general_request_preview.supports_continuation_token

	live_general_details := preview_general_fts_details(query_db, GeneralFtsRequest{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .term
		terms:          ['roadmap']
		select_columns: ['id']
		limit:          5
	}) or { panic(err) }
	assert live_general_details.plan.index_name == 'content_text_fts_idx'
	assert live_general_details.notes.any(it.contains('SQLite FTS5 sidecar'))

	session_general_details := preview_general_fts_details_in_session(query_session, GeneralFtsRequest{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .term
		terms:          ['roadmap']
		select_columns: ['id']
		limit:          5
	}) or { panic(err) }
	assert session_general_details.plan.index_name == 'content_text_fts_idx'
	assert session_general_details.default_result_shape == 'rows'

	result := query_general_fts_in_session(query_session, mut query_db, GeneralFtsRequest{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .term
		terms:          ['roadmap']
		select_columns: ['id']
		limit:          5
	}) or { panic(err) }
	assert result.rows.len == 1
	assert result.plan.index_name == 'content_text_fts_idx'
}
