module memory

#flag -I @VMODROOT/storage/c
#flag darwin -I/opt/homebrew/include
#flag darwin -L/opt/homebrew/lib
#flag darwin -lggml
#flag darwin -lllama
#flag linux -lggml
#flag linux -lllama
#flag @VMODROOT/storage/c/llama_generation_bridge.c

#include "llama_generation_bridge.h"

struct C.PollyLlamaGenerationHandle {}

fn C.polly_llama_generation_open(model_path &char, n_ctx int, n_batch int, n_threads int, n_gpu_layers int) &C.PollyLlamaGenerationHandle
fn C.polly_llama_generation_close(handle &C.PollyLlamaGenerationHandle)
fn C.polly_llama_generation_generate(handle &C.PollyLlamaGenerationHandle, prompt &char, prompt_len int, output &char, output_len int, max_tokens int, temperature f32, top_p f32, top_k int, seed u32) int
fn C.polly_llama_generation_last_error() &char

pub struct LlamaGenerationConfig {
pub:
	model_path       string
	n_ctx            int = 2048
	n_batch          int = 512
	n_threads        int
	n_gpu_layers     int = 999
	max_tokens       int = 512
	temperature      f32
	top_p            f32    = 0.8
	top_k            int    = 40
	seed             u32    = 42
	max_output_bytes int    = 16384
	system_prompt    string = '你是一个严谨的本地 Agent 记忆蒸馏器。只基于证据总结，不编造。'
}

pub struct LlamaGenerationEngine {
pub:
	config LlamaGenerationConfig
mut:
	handle &C.PollyLlamaGenerationHandle = unsafe { nil }
}

pub fn new_llama_generation_engine(config LlamaGenerationConfig) !LlamaGenerationEngine {
	if config.model_path.len == 0 {
		return error('llama.cpp generation model path is required')
	}
	handle := C.polly_llama_generation_open(&char(config.model_path.str), config.n_ctx,
		config.n_batch, config.n_threads, config.n_gpu_layers)
	if unsafe { handle == nil } {
		return error(llama_generation_last_error())
	}
	return LlamaGenerationEngine{
		config: config
		handle: handle
	}
}

pub fn (mut engine LlamaGenerationEngine) close() {
	if unsafe { engine.handle != nil } {
		C.polly_llama_generation_close(engine.handle)
		engine.handle = unsafe { nil }
	}
}

pub fn (mut engine LlamaGenerationEngine) generate(prompt string) !string {
	if unsafe { engine.handle == nil } {
		return error('llama.cpp generation engine is closed')
	}
	full_prompt := engine.chat_prompt(prompt)
	output_len := if engine.config.max_output_bytes > 0 {
		engine.config.max_output_bytes
	} else {
		16384
	}
	mut output := []u8{len: output_len}
	code := unsafe {
		C.polly_llama_generation_generate(engine.handle, &char(full_prompt.str), full_prompt.len,
			&char(output.data), output.len, engine.config.max_tokens, engine.config.temperature,
			engine.config.top_p, engine.config.top_k, engine.config.seed)
	}
	if code < 0 {
		return error(llama_generation_last_error())
	}
	return unsafe { (&char(output.data)).vstring_with_len(code).clone() }
}

fn (engine LlamaGenerationEngine) chat_prompt(prompt string) string {
	if engine.config.system_prompt.len == 0 {
		return prompt
	}
	return '<|im_start|>system\n${engine.config.system_prompt}<|im_end|>\n<|im_start|>user\n${prompt}<|im_end|>\n<|im_start|>assistant\n'
}

fn llama_generation_last_error() string {
	msg := C.polly_llama_generation_last_error()
	if unsafe { msg == nil } {
		return 'unknown llama.cpp generation error'
	}
	return unsafe { cstring_to_vstring(msg) }
}
