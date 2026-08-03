module agentview

import os
import memory
import storage

pub struct CodexSessionSchemaOptions {
pub:
	include_search_indexes    bool
	include_memory_indexes    bool
	include_memory_capability bool
}

pub struct CodexSessionSchema {
pub:
	options CodexSessionSchemaOptions
}

pub fn default_codex_session_schema() CodexSessionSchema {
	return CodexSessionSchema{}
}

pub fn codex_session_search_schema() CodexSessionSchema {
	return CodexSessionSchema{
		options: CodexSessionSchemaOptions{
			include_search_indexes: true
		}
	}
}

pub fn codex_session_memory_schema() CodexSessionSchema {
	return CodexSessionSchema{
		options: CodexSessionSchemaOptions{
			include_memory_indexes:    true
			include_memory_capability: true
		}
	}
}

pub fn codex_session_search_memory_schema() CodexSessionSchema {
	return CodexSessionSchema{
		options: CodexSessionSchemaOptions{
			include_search_indexes:    true
			include_memory_indexes:    true
			include_memory_capability: true
		}
	}
}

pub fn (provider CodexSessionSchema) schema() !storage.DatabaseSchema {
	return storage.DatabaseSchema{
		name:                'codex_session'
		version:             'v1'
		tables:              codex_session_table_specs(provider.options)!
		memory_capabilities: codex_session_memory_capabilities(provider.options)!
	}
}

fn codex_session_table_specs(options CodexSessionSchemaOptions) ![]storage.TypedTableSpec {
	mut specs := [
		sessions_spec()!,
		ingest_state_spec()!,
		search_state_spec()!,
		search_meta_state_spec()!,
		sync_resume_state_spec()!,
		entry_ingest_state_spec()!,
		entry_search_state_spec()!,
		episodes_spec()!,
		episode_reports_spec()!,
		episode_reasoning_nodes_spec()!,
		episode_reasoning_links_spec()!,
	]
	specs << codex_session_entries_spec(options)!
	return specs
}

fn codex_session_entries_spec(options CodexSessionSchemaOptions) !storage.TypedTableSpec {
	return if options.include_memory_indexes {
		entries_memory_spec(options.include_search_indexes)!
	} else {
		entries_spec(options.include_search_indexes)!
	}
}

fn codex_session_memory_capabilities(options CodexSessionSchemaOptions) ![]storage.MemoryCapabilityDef {
	if !options.include_memory_capability {
		return []storage.MemoryCapabilityDef{}
	}
	return [
		storage.MemoryCapabilityDef.reflective_field(agentview_memory_capability_table,
			agentview_memory_capability_column, storage.ReflectionOptions{
			embedding_index: agentview_memory_path_index
			reflection_kind: 'summary'
		})!,
	]
}

fn sessions_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('sessions')
}

fn codex_yaml_table_spec(name string) !storage.TypedTableSpec {
	ddl_path := os.join_path(os.dir(@FILE), 'codex_schema.yml')
	ddl := storage.load_yaml_ddl_file(ddl_path)!
	return ddl.table_spec(name)
}

fn ingest_state_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('ingest_state')
}

fn search_state_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('search_state')
}

fn search_meta_state_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('search_meta_state')
}

fn sync_resume_state_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('sync_resume_state')
}

fn entry_ingest_state_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('entry_ingest_state')
}

fn entry_search_state_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('entry_search_state')
}

fn entries_spec(include_search_indexes bool) !storage.TypedTableSpec {
	base := codex_yaml_table_spec('entries')!
	mut indexes := base.indexes.clone()
	if include_search_indexes {
		indexes << storage.SchemaIndexDef.fts_with_options('entries_content_text_fts_idx',
			'content_text', storage.FtsIndexOptions{
			tokenizer:      'unicode61 remove_diacritics 2'
			prefix_lengths: [2, 3, 4]
		})!
	}
	return storage.TypedTableSpec.new(base.table, indexes)!
}

fn entries_memory_spec(include_search_indexes bool) !storage.TypedTableSpec {
	base := entries_spec(include_search_indexes)!
	mut indexes := base.indexes.clone()
	indexes << storage.SchemaIndexDef.embedding_markdown('entries_content_block_vec_idx',
		'content_md', memory.MarkdownEmbeddingScope.block, 'bge-small-zh-v1.5')!
	indexes << storage.SchemaIndexDef.embedding_markdown(agentview_memory_path_index, 'content_md',
		memory.MarkdownEmbeddingScope.path, 'bge-small-zh-v1.5')!
	return storage.TypedTableSpec.new(base.table, indexes)
}

fn episodes_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('episodes')
}

fn episode_reports_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('episode_reports')
}

fn episode_reasoning_nodes_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('episode_reasoning_nodes')
}

fn episode_reasoning_links_spec() !storage.TypedTableSpec {
	return codex_yaml_table_spec('episode_reasoning_links')
}
