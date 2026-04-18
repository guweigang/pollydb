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
