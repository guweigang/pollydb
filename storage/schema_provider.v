module storage

pub struct DatabaseSchema {
pub:
	name                string
	version             string
	tables              []TypedTableSpec
	memory_capabilities []MemoryCapabilityDef
}

pub interface SchemaProvider {
	schema() !DatabaseSchema
}

pub fn (schema DatabaseSchema) table(name string) !TypedTableSpec {
	for table in schema.tables {
		if table.name() == name {
			return table
		}
	}
	return error('schema table not found: ${name}')
}

pub fn (schema DatabaseSchema) table_names() []string {
	return schema.tables.map(it.name())
}
