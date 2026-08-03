module memorydb

import memory
import storage

pub fn register_capability(mut db storage.PersistentDatabase, def memory.MemoryCapabilityDef) ! {
	db.register_memory_capability(def)!
}

pub fn replay_query(mut db storage.PersistentDatabase, mut engine memory.EmbeddingEngine, request memory.ReplayQueryRequest) !memory.ReplayQueryResult {
	return db.replay_query(mut engine, request)!
}

pub fn reflect_memory_persistent(mut db storage.PersistentDatabase, branch_name string, pending_writes int, mut embedding_engine memory.EmbeddingEngine, mut generator memory.ReflectionTextGenerator, options memory.ReflectorScheduleOptions, cfg storage.ChunkConfig, meta storage.CommitMeta) ![]memory.PersistedReflection {
	return db.reflect_memory_persistent(branch_name, pending_writes, mut embedding_engine, mut generator, options, cfg, meta)!
}

pub fn reflection_evolution_chain(mut db storage.PersistentDatabase, branch_name string, reflection_id string) !memory.ReflectionEvolutionChain {
	return db.reflection_evolution_chain(branch_name, reflection_id)!
}

pub fn reflection_supersede_graph(mut db storage.PersistentDatabase, branch_name string, reflection_id string) !memory.ReflectionSupersedeGraph {
	return db.reflection_supersede_graph(branch_name, reflection_id)!
}

pub fn scene_block_card_timeline(mut db storage.PersistentDatabase, branch_name string, scene_id string, max_commits int) !memory.SceneBlockCardTimeline {
	return db.scene_block_card_timeline(branch_name, scene_id, max_commits)!
}
