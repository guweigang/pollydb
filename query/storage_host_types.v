module query

import storage

pub struct Database {
mut:
	db storage.PersistentDatabase
}

pub struct Session {
	session storage.DatabaseSession
}

pub struct Transaction {
	tx storage.TransactionSession
}

pub fn open_database(root_dir string, default_branch string) !Database {
	return Database{
		db: storage.PersistentDatabase.open(root_dir, default_branch)!
	}
}

pub fn init_database(root_dir string, default_branch string) !Database {
	return Database{
		db: storage.PersistentDatabase.init(root_dir, default_branch)!
	}
}

pub fn (mut database Database) close() ! {
	database.db.close()!
}

pub fn (database Database) open_session(branch_name string) !Session {
	return Session{
		session: database.db.open_session(branch_name)!
	}
}

pub fn (database Database) begin_session(branch_name string) !Session {
	return Session{
		session: database.db.begin_session(storage.SessionOptions.for_branch(branch_name))!
	}
}

pub fn (session Session) begin_working_set(mut database Database) !Transaction {
	return Transaction{
		tx: session.session.begin_working_set(mut database.db)!
	}
}

fn query_spec(spec storage.TypedTableSpec, projectors map[string]ProjectionDef) QuerySpec {
	mut copied := map[string]ProjectionDef{}
	for name, def in projectors {
		copied[name] = def
	}
	return QuerySpec{
		schema:      table_schema_def_from_storage(spec)
		projections: copied
	}
}

fn projection_def_from_storage(def storage.AggregateProjectionDef) ProjectionDef {
	return ProjectionDef{
		name:                     def.name
		table_name:               def.table_name
		column_name:              def.column_name
		source_json_path:         def.source_json_path
		source_markdown_selector: def.source_markdown_selector
		aggregate:                query_column_aggregate(def.aggregate)
		priority:                 def.priority
		cost_hint:                query_projection_cost_hint(def.cost_hint)
	}
}

fn projector_defs_from_storage(projectors map[string]storage.AggregateProjectionDef) map[string]ProjectionDef {
	mut out := map[string]ProjectionDef{}
	for name, def in projectors {
		out[name] = projection_def_from_storage(def)
	}
	return out
}

fn field_selector_meta_def(meta storage.FieldSelectorRef) FieldSelectorMetaDef {
	return FieldSelectorMetaDef{
		plugin_name: meta.plugin_name
		selector:    meta.selector
		value_type:  query_column_type(meta.value_type)
		stores_row:  meta.stores_row
	}
}

fn table_schema_def_from_storage(spec storage.TypedTableSpec) TableSchemaDef {
	return TableSchemaDef{
		name:        spec.table.name
		primary_key: spec.table.primary_key.clone()
		columns:     spec.table.columns.map(ColumnSchemaDef{
			name:     it.name
			typ:      query_column_type(it.typ)
			nullable: it.nullable
		})
		indexes:     spec.indexes.map(IndexSchemaDef{
			name:              it.name
			column:            it.column
			json_field:        it.json_field
			markdown_selector: it.markdown_selector
			fts_text_mode:     it.fts_text_mode
			json_field_type:   query_column_type(it.json_field_type)
			stores_row:        it.stores_row
			stored_columns:    it.stored_columns.clone()
		})
	}
}

fn storage_column_schema_query(column ColumnSchemaDef) storage.ColumnDef {
	return storage.ColumnDef{
		name:     column.name
		typ:      storage_column_type(column.typ)
		nullable: column.nullable
	}
}

fn storage_index_schema_query(index IndexSchemaDef) storage.SchemaIndexDef {
	return storage.SchemaIndexDef{
		name:              index.name
		column:            index.column
		json_field:        index.json_field
		markdown_selector: index.markdown_selector
		fts_text_mode:     index.fts_text_mode
		json_field_type:   storage_column_type(index.json_field_type)
		stores_row:        index.stores_row
		stored_columns:    index.stored_columns.clone()
	}
}

fn storage_field_selector_index_query(name string, column_name string, plugin_name string, selector string, value_type ColumnType, stores_row bool) !storage.SchemaIndexDef {
	return storage.SchemaIndexDef.field_selector(name, column_name, plugin_name, selector,
		storage_column_type(value_type), stores_row)!
}

fn storage_table_def_query(schema TableSchemaDef) !storage.TableDef {
	mut columns := []storage.ColumnDef{cap: schema.columns.len}
	for column in schema.columns {
		columns << storage.ColumnDef.new(column.name, storage_column_type(column.typ),
			column.nullable)!
	}
	return storage.TableDef.new(schema.name, columns, schema.primary_key.clone())
}
