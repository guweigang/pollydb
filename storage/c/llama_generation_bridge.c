#include "llama_generation_bridge.h"

#include "ggml-backend.h"
#include "llama.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct PollyLlamaGenerationHandle {
	struct llama_model* model;
	struct llama_context* ctx;
	const struct llama_vocab* vocab;
	int n_ctx;
	int n_batch;
};

static char polly_llama_generation_error[512];

static void polly_generation_set_error(const char* message) {
	snprintf(polly_llama_generation_error, sizeof(polly_llama_generation_error), "%s", message);
}

static void polly_generation_set_error_with_code(const char* message, int code) {
	snprintf(polly_llama_generation_error, sizeof(polly_llama_generation_error), "%s: %d", message, code);
}

static void polly_llama_generation_log_callback(enum ggml_log_level level, const char* text, void* user_data) {
	(void) level;
	(void) text;
	(void) user_data;
}

const char* polly_llama_generation_last_error(void) {
	return polly_llama_generation_error;
}

PollyLlamaGenerationHandle* polly_llama_generation_open(
	const char* model_path,
	int n_ctx,
	int n_batch,
	int n_threads,
	int n_gpu_layers) {
	polly_generation_set_error("");
	llama_log_set(polly_llama_generation_log_callback, NULL);
	ggml_backend_load_all();
	llama_backend_init();

	struct llama_model_params model_params = llama_model_default_params();
	model_params.n_gpu_layers = n_gpu_layers;

	struct llama_model* model = llama_model_load_from_file(model_path, model_params);
	if (model == NULL) {
		polly_generation_set_error("failed to load llama.cpp generation model");
		return NULL;
	}

	struct llama_context_params ctx_params = llama_context_default_params();
	ctx_params.n_ctx = n_ctx > 0 ? (uint32_t) n_ctx : 2048;
	ctx_params.n_batch = n_batch > 0 ? (uint32_t) n_batch : ctx_params.n_ctx;
	ctx_params.n_ubatch = ctx_params.n_batch;
	ctx_params.n_seq_max = 1;
	ctx_params.embeddings = false;
	if (n_threads > 0) {
		ctx_params.n_threads = n_threads;
		ctx_params.n_threads_batch = n_threads;
	}

	struct llama_context* ctx = llama_init_from_model(model, ctx_params);
	if (ctx == NULL) {
		llama_model_free(model);
		polly_generation_set_error("failed to create llama.cpp generation context");
		return NULL;
	}

	PollyLlamaGenerationHandle* handle = (PollyLlamaGenerationHandle*) calloc(1, sizeof(PollyLlamaGenerationHandle));
	if (handle == NULL) {
		llama_free(ctx);
		llama_model_free(model);
		polly_generation_set_error("failed to allocate llama.cpp generation handle");
		return NULL;
	}

	handle->model = model;
	handle->ctx = ctx;
	handle->vocab = llama_model_get_vocab(model);
	handle->n_ctx = (int) ctx_params.n_ctx;
	handle->n_batch = (int) ctx_params.n_batch;
	return handle;
}

void polly_llama_generation_close(PollyLlamaGenerationHandle* handle) {
	if (handle == NULL) {
		return;
	}
	if (handle->ctx != NULL) {
		llama_free(handle->ctx);
	}
	if (handle->model != NULL) {
		llama_model_free(handle->model);
	}
	free(handle);
}

static int polly_decode_tokens(
	PollyLlamaGenerationHandle* handle,
	const llama_token* tokens,
	int n_tokens,
	int pos_start,
	bool logits_last) {
	struct llama_batch batch = llama_batch_init(n_tokens, 0, 1);
	if (batch.token == NULL || batch.pos == NULL || batch.n_seq_id == NULL || batch.seq_id == NULL || batch.logits == NULL) {
		llama_batch_free(batch);
		polly_generation_set_error("failed to allocate llama.cpp generation batch");
		return -1;
	}
	for (int i = 0; i < n_tokens; i++) {
		batch.token[i] = tokens[i];
		batch.pos[i] = (llama_pos) (pos_start + i);
		batch.n_seq_id[i] = 1;
		batch.seq_id[i][0] = 0;
		batch.logits[i] = logits_last && i == n_tokens - 1;
	}
	batch.n_tokens = n_tokens;
	const int code = llama_decode(handle->ctx, batch);
	llama_batch_free(batch);
	if (code < 0) {
		polly_generation_set_error_with_code("llama.cpp failed to decode generation batch", code);
		return -2;
	}
	return 0;
}

static int polly_decode_tokens_chunked(
	PollyLlamaGenerationHandle* handle,
	const llama_token* tokens,
	int n_tokens,
	int pos_start,
	bool logits_last) {
	if (handle == NULL || tokens == NULL || n_tokens <= 0) {
		polly_generation_set_error("invalid llama.cpp generation batch input");
		return -1;
	}
	const int chunk_size = handle->n_batch > 0 ? handle->n_batch : handle->n_ctx;
	for (int offset = 0; offset < n_tokens; offset += chunk_size) {
		const int remaining = n_tokens - offset;
		const int take = remaining < chunk_size ? remaining : chunk_size;
		const bool chunk_logits_last = logits_last && (offset + take) == n_tokens;
		if (polly_decode_tokens(handle, tokens + offset, take, pos_start + offset, chunk_logits_last) < 0) {
			return -2;
		}
	}
	return 0;
}

static int polly_append_token_piece(
	PollyLlamaGenerationHandle* handle,
	llama_token token,
	char* output,
	int output_len,
	int* cursor) {
	char piece[512];
	const int n = llama_token_to_piece(handle->vocab, token, piece, (int) sizeof(piece), 0, false);
	if (n < 0) {
		polly_generation_set_error_with_code("llama.cpp token piece buffer too small", -n);
		return -1;
	}
	if (n == 0) {
		return 0;
	}
	if (*cursor + n >= output_len) {
		polly_generation_set_error("llama.cpp generation output buffer is too small");
		return -2;
	}
	memcpy(output + *cursor, piece, (size_t) n);
	*cursor += n;
	output[*cursor] = '\0';
	return 0;
}

int polly_llama_generation_generate(
	PollyLlamaGenerationHandle* handle,
	const char* prompt,
	int prompt_len,
	char* output,
	int output_len,
	int max_tokens,
	float temperature,
	float top_p,
	int top_k,
	unsigned int seed) {
	polly_generation_set_error("");
	if (handle == NULL || handle->ctx == NULL || handle->vocab == NULL) {
		polly_generation_set_error("llama.cpp generation handle is not open");
		return -1;
	}
	if (prompt == NULL || prompt_len <= 0) {
		polly_generation_set_error("llama.cpp generation prompt is empty");
		return -2;
	}
	if (output == NULL || output_len <= 1) {
		polly_generation_set_error("llama.cpp generation output buffer is invalid");
		return -3;
	}
	output[0] = '\0';
	const int limit = max_tokens > 0 ? max_tokens : 512;
	const int token_cap = handle->n_ctx;
	llama_token* tokens = (llama_token*) calloc((size_t) token_cap, sizeof(llama_token));
	if (tokens == NULL) {
		polly_generation_set_error("failed to allocate generation token buffer");
		return -4;
	}

	int n_tokens = llama_tokenize(handle->vocab, prompt, prompt_len, tokens, token_cap, true, true);
	if (n_tokens < 0) {
		const int required = -n_tokens;
		free(tokens);
		polly_generation_set_error_with_code("prompt exceeds llama.cpp generation context", required);
		return -5;
	}
	if (n_tokens == 0) {
		free(tokens);
		polly_generation_set_error("llama.cpp tokenizer returned no generation prompt tokens");
		return -6;
	}
	if (n_tokens + limit >= handle->n_ctx) {
		free(tokens);
		polly_generation_set_error("prompt plus max_tokens exceeds llama.cpp generation context");
		return -7;
	}

	llama_memory_clear(llama_get_memory(handle->ctx), true);
	if (polly_decode_tokens_chunked(handle, tokens, n_tokens, 0, true) < 0) {
		free(tokens);
		return -8;
	}
	free(tokens);

	struct llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
	struct llama_sampler* sampler = llama_sampler_chain_init(sampler_params);
	if (sampler == NULL) {
		polly_generation_set_error("failed to initialize llama.cpp sampler");
		return -9;
	}
	if (top_k > 0) {
		llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
	}
	if (top_p > 0.0f && top_p < 1.0f) {
		llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
	}
	if (temperature > 0.0f) {
		llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
		llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
	} else {
		llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
	}

	int cursor = 0;
	int pos = n_tokens;
	for (int i = 0; i < limit; i++) {
		const llama_token token = llama_sampler_sample(sampler, handle->ctx, -1);
		if (llama_vocab_is_eog(handle->vocab, token)) {
			break;
		}
		llama_sampler_accept(sampler, token);
		if (polly_append_token_piece(handle, token, output, output_len, &cursor) < 0) {
			llama_sampler_free(sampler);
			return -10;
		}
		if (polly_decode_tokens(handle, &token, 1, pos, true) < 0) {
			llama_sampler_free(sampler);
			return -11;
		}
		pos++;
	}

	llama_sampler_free(sampler);
	return cursor;
}
