module storage

pub struct FieldSelectorMeta {
pub:
	plugin_name string
	selector    string
	value_type  ColumnType
	stores_row  bool
}
