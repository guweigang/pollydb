module storage

#flag -I @VMODROOT/storage/c
#flag darwin -I/opt/homebrew/include
#flag darwin -L/opt/homebrew/lib
#flag darwin -lggml
#flag darwin -lllama
#flag linux -lggml
#flag linux -lllama
#flag @VMODROOT/storage/c/llama_embedding_bridge.c

#include "llama_embedding_bridge.h"

struct C.PollyLlamaEmbeddingHandle {}

fn C.polly_llama_embedding_open(model_path &char, n_ctx int, n_batch int, n_threads int, n_gpu_layers int) &C.PollyLlamaEmbeddingHandle
fn C.polly_llama_embedding_close(handle &C.PollyLlamaEmbeddingHandle)
fn C.polly_llama_embedding_dimensions(handle &C.PollyLlamaEmbeddingHandle) int
fn C.polly_llama_embedding_embed(handle &C.PollyLlamaEmbeddingHandle, text &char, text_len int, output &f32, output_len int) int
fn C.polly_llama_embedding_last_error() &char

pub struct LlamaEmbeddingConfig {
pub:
	model_path   string
	n_ctx        int = 512
	n_batch      int = 512
	n_threads    int
	n_gpu_layers int = 999
}

pub struct LlamaEmbeddingEngine {
pub:
	config LlamaEmbeddingConfig
mut:
	handle &C.PollyLlamaEmbeddingHandle = unsafe { nil }
	dims   int
}

pub fn new_llama_embedding_engine(config LlamaEmbeddingConfig) !LlamaEmbeddingEngine {
	if config.model_path.len == 0 {
		return error('llama.cpp embedding model path is required')
	}
	handle := C.polly_llama_embedding_open(&char(config.model_path.str), config.n_ctx,
		config.n_batch, config.n_threads, config.n_gpu_layers)
	if unsafe { handle == nil } {
		return error(llama_embedding_last_error())
	}
	dims := C.polly_llama_embedding_dimensions(handle)
	if dims <= 0 {
		C.polly_llama_embedding_close(handle)
		return error('llama.cpp embedding model returned invalid dimensions')
	}
	return LlamaEmbeddingEngine{
		config: config
		handle: handle
		dims:   dims
	}
}

pub fn (engine LlamaEmbeddingEngine) model_name() string {
	return engine.config.model_path
}

pub fn (engine LlamaEmbeddingEngine) dimensions() int {
	return engine.dims
}

pub fn (mut engine LlamaEmbeddingEngine) close() {
	if unsafe { engine.handle != nil } {
		C.polly_llama_embedding_close(engine.handle)
		engine.handle = unsafe { nil }
	}
}

pub fn (mut engine LlamaEmbeddingEngine) embed(text string) ![]f32 {
	if unsafe { engine.handle == nil } {
		return error('llama.cpp embedding engine is closed')
	}
	mut vector := []f32{len: engine.dims}
	code := unsafe {
		C.polly_llama_embedding_embed(engine.handle, &char(text.str), text.len, &vector[0],
			vector.len)
	}
	if code < 0 {
		return error(llama_embedding_last_error())
	}
	if code != engine.dims {
		return error('llama.cpp embedding returned ${code} dimensions, expected ${engine.dims}')
	}
	return vector
}

pub fn (mut engine LlamaEmbeddingEngine) embed_batch(texts []string) ![][]f32 {
	mut vectors := [][]f32{cap: texts.len}
	for text in texts {
		vectors << engine.embed(text)!
	}
	return vectors
}

fn llama_embedding_last_error() string {
	msg := C.polly_llama_embedding_last_error()
	if unsafe { msg == nil } {
		return 'unknown llama.cpp embedding error'
	}
	return unsafe { cstring_to_vstring(msg) }
}
