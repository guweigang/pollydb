module storage

import time
import x.json2

pub enum AggregateProjectionCostHint {
	low
	medium
	high
}

pub struct AggregateProjectionDef {
pub:
	name              string
	table_name        string
	column_name       string
	source_json_path  string
	aggregate         ColumnAggregate
	priority          int = 100
	cost_hint         AggregateProjectionCostHint = .medium
}

pub struct AggregateProjectorState {
pub:
	projection           AggregateProjectionDef
	current_data_root_cid string
	source_data_root_cid string
	virtual_root_cid     string
	fresh                bool
	stale_reason         string
}

pub fn AggregateProjectionDef.sum_i64(name string, table_name string, column_name string) !AggregateProjectionDef {
	if name.len == 0 {
		return error('aggregate projection name cannot be empty')
	}
	if table_name.len == 0 {
		return error('aggregate projection table name cannot be empty')
	}
	if column_name.len == 0 {
		return error('aggregate projection column name cannot be empty')
	}
	return AggregateProjectionDef{
		name: name
		table_name: table_name
		column_name: column_name
		source_json_path: ''
		aggregate: .sum
		priority: 100
		cost_hint: .medium
	}
}

pub fn AggregateProjectionDef.sum_json_i64(name string, table_name string, column_name string, source_json_path string) !AggregateProjectionDef {
	if source_json_path.len == 0 {
		return error('aggregate projection json path cannot be empty')
	}
	AggregateProjectionDef.sum_i64(name, table_name, column_name)!
	return AggregateProjectionDef{
		name: name
		table_name: table_name
		column_name: column_name
		source_json_path: source_json_path
		aggregate: .sum
		priority: 100
		cost_hint: .medium
	}
}

pub fn (def AggregateProjectionDef) with_priority(priority int) AggregateProjectionDef {
	return AggregateProjectionDef{
		...def
		priority: if priority >= 0 { priority } else { 0 }
	}
}

pub fn (def AggregateProjectionDef) with_cost_hint(cost_hint AggregateProjectionCostHint) AggregateProjectionDef {
	return AggregateProjectionDef{
		...def
		cost_hint: cost_hint
	}
}

pub fn (state AggregateProjectorState) to_virtual_root_ref() VirtualRootRef {
	return VirtualRootRef{
		name: state.projection.name
		root_cid: state.virtual_root_cid
		source_data_root_cid: state.source_data_root_cid
		fresh: state.fresh
		stale_reason: state.stale_reason
	}
}

fn aggregate_projection_value_key(name string) []u8 {
	return 'aggregate:${name}'.bytes()
}

fn build_aggregate_projection_tree(def AggregateProjectionDef, value i64, cfg ChunkConfig) !Tree {
	return Tree.build([
		KVPair{
			key: aggregate_projection_value_key(def.name)
			value: TypedValueEncoder.encode_value(value, .i64_)!
		},
	], cfg)
}

fn compute_sum_json_i64_projection(mut db PersistentDatabase, branch_name string, def AggregateProjectionDef) !i64 {
	session := db.begin_session(SessionOptions.for_branch(branch_name))!
	mut cursor := session.table_cursor(mut db, def.table_name, []u8{}, 0)!
	mut total := i64(0)
	for {
		row := cursor.next() or { break }
		if !row.data.has(def.column_name) {
			continue
		}
		raw := row.data.get(def.column_name)!
		match raw {
			string {
				root := json2.decode[map[string]json2.Any](raw)!
				value := json_lookup_path_value(root, def.source_json_path)!
				match value {
					i64 { total += value }
					NullValue {}
					else {
						return error('aggregate projection ${def.name} requires i64 json scalar at ${def.source_json_path}')
					}
				}
			}
			else {
				return error('aggregate projection ${def.name} requires json string payload in ${def.column_name}')
			}
		}
	}
	return total
}

fn compute_aggregate_projection_value(mut db PersistentDatabase, branch_name string, def AggregateProjectionDef) !i64 {
	session := db.begin_session(SessionOptions.for_branch(branch_name))!
	return if def.source_json_path.len == 0 {
		session.sum_i64_column(mut db, def.table_name, def.column_name)
	} else {
		compute_sum_json_i64_projection(mut db, branch_name, def)
	}
}

pub fn (mut db PersistentDatabase) refresh_aggregate_projections(branch_name string, cfg ChunkConfig, meta CommitMeta) !Commit {
	return db.refresh_aggregate_projections_limited(branch_name, cfg, meta, 0)
}

pub fn (mut db PersistentDatabase) refresh_aggregate_projections_limited(branch_name string, cfg ChunkConfig, meta CommitMeta, limit int) !Commit {
	current := db.engine.checkout(branch_name)!
	mut existing := map[string]VirtualRootRef{}
	for virtual_root in current.virtual_roots {
		existing[virtual_root.name] = virtual_root
	}

	mut next_roots := []VirtualRootRef{}
	for virtual_root in current.virtual_roots {
		if virtual_root.name !in db.projectors {
			next_roots << virtual_root
		}
	}
	mut refreshed := 0
	for name in sorted_projector_names_by_priority(db.projectors) {
		projector := db.projectors[name] or { continue }
		current_ref := existing[name] or {
			VirtualRootRef{
				name: projector.name
				root_cid: ''
				source_data_root_cid: current.root_cid
				fresh: false
				stale_reason: 'registration_backfill'
			}
		}
		if current_ref.fresh && current_ref.source_data_root_cid == current.root_cid && current_ref.root_cid.len > 0 {
			next_roots << current_ref
			continue
		}
		if limit > 0 && refreshed >= limit {
			next_roots << VirtualRootRef{
				name: projector.name
				root_cid: current_ref.root_cid
				source_data_root_cid: current.root_cid
				fresh: false
				stale_reason: 'policy_budget_skipped'
			}
			continue
		}
		value := compute_aggregate_projection_value(mut db, branch_name, projector)!
		tree := build_aggregate_projection_tree(projector, value, cfg)!
		db.engine.repository.node_store.put_tree(tree)!
		refreshed++
		next_roots << VirtualRootRef{
			name: projector.name
			root_cid: tree.root.cid
			source_data_root_cid: current.root_cid
			fresh: true
			stale_reason: ''
		}
	}
	return db.engine.commit_virtual_roots_for_branch(branch_name, next_roots, CommitMeta{
		author: if meta.author.len > 0 { meta.author } else { 'pollydb/projector' }
		message: if meta.message.len > 0 { meta.message } else { 'refresh aggregate projections' }
		timestamp: if meta.timestamp != 0 { meta.timestamp } else { time.now().unix() }
	})
}
