#include "llama_embedding_bridge.h"

#include "ggml-backend.h"
#include "llama.h"

#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct PollyLlamaEmbeddingHandle {
	struct llama_model* model;
	struct llama_context* ctx;
	const struct llama_vocab* vocab;
	int dimensions;
	int n_batch;
};

static char polly_llama_embedding_error[512];

static void polly_set_error(const char* message) {
	snprintf(polly_llama_embedding_error, sizeof(polly_llama_embedding_error), "%s", message);
}

static void polly_set_error_with_code(const char* message, int code) {
	snprintf(polly_llama_embedding_error, sizeof(polly_llama_embedding_error), "%s: %d", message, code);
}

const char* polly_llama_embedding_last_error(void) {
	return polly_llama_embedding_error;
}

static void polly_normalize_embedding(const float* src, float* dst, int n) {
	double sum = 0.0;
	for (int i = 0; i < n; i++) {
		sum += (double) src[i] * (double) src[i];
	}
	if (sum <= 0.0) {
		for (int i = 0; i < n; i++) {
			dst[i] = src[i];
		}
		return;
	}
	const float inv_norm = (float) (1.0 / sqrt(sum));
	for (int i = 0; i < n; i++) {
		dst[i] = src[i] * inv_norm;
	}
}

PollyLlamaEmbeddingHandle* polly_llama_embedding_open(
	const char* model_path,
	int n_ctx,
	int n_batch,
	int n_threads,
	int n_gpu_layers) {
	polly_set_error("");
	ggml_backend_load_all();
	llama_backend_init();

	struct llama_model_params model_params = llama_model_default_params();
	model_params.n_gpu_layers = n_gpu_layers;

	struct llama_model* model = llama_model_load_from_file(model_path, model_params);
	if (model == NULL) {
		polly_set_error("failed to load llama.cpp model");
		return NULL;
	}

	struct llama_context_params ctx_params = llama_context_default_params();
	ctx_params.embeddings = true;
	ctx_params.pooling_type = LLAMA_POOLING_TYPE_MEAN;
	ctx_params.attention_type = LLAMA_ATTENTION_TYPE_NON_CAUSAL;
	ctx_params.n_ctx = n_ctx > 0 ? (uint32_t) n_ctx : 512;
	ctx_params.n_batch = n_batch > 0 ? (uint32_t) n_batch : ctx_params.n_ctx;
	ctx_params.n_ubatch = ctx_params.n_batch;
	ctx_params.n_seq_max = 1;
	if (n_threads > 0) {
		ctx_params.n_threads = n_threads;
		ctx_params.n_threads_batch = n_threads;
	}

	struct llama_context* ctx = llama_init_from_model(model, ctx_params);
	if (ctx == NULL) {
		llama_model_free(model);
		polly_set_error("failed to create llama.cpp context");
		return NULL;
	}

	PollyLlamaEmbeddingHandle* handle = (PollyLlamaEmbeddingHandle*) calloc(1, sizeof(PollyLlamaEmbeddingHandle));
	if (handle == NULL) {
		llama_free(ctx);
		llama_model_free(model);
		polly_set_error("failed to allocate llama.cpp embedding handle");
		return NULL;
	}

	handle->model = model;
	handle->ctx = ctx;
	handle->vocab = llama_model_get_vocab(model);
	handle->dimensions = llama_model_n_embd_out(model);
	handle->n_batch = (int) ctx_params.n_batch;
	return handle;
}

void polly_llama_embedding_close(PollyLlamaEmbeddingHandle* handle) {
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

int polly_llama_embedding_dimensions(PollyLlamaEmbeddingHandle* handle) {
	if (handle == NULL) {
		return 0;
	}
	return handle->dimensions;
}

int polly_llama_embedding_embed(
	PollyLlamaEmbeddingHandle* handle,
	const char* text,
	int text_len,
	float* output,
	int output_len) {
	polly_set_error("");
	if (handle == NULL || handle->ctx == NULL || handle->vocab == NULL) {
		polly_set_error("llama.cpp embedding handle is not open");
		return -1;
	}
	if (output == NULL || output_len < handle->dimensions) {
		polly_set_error("embedding output buffer is too small");
		return -2;
	}

	int token_cap = handle->n_batch;
	llama_token* tokens = (llama_token*) calloc((size_t) token_cap, sizeof(llama_token));
	if (tokens == NULL) {
		polly_set_error("failed to allocate token buffer");
		return -3;
	}

	int n_tokens = llama_tokenize(handle->vocab, text, text_len, tokens, token_cap, true, true);
	if (n_tokens < 0) {
		const int required = -n_tokens;
		free(tokens);
		polly_set_error_with_code("input exceeds llama.cpp embedding batch token capacity", required);
		return -4;
	}
	if (n_tokens == 0) {
		free(tokens);
		polly_set_error("llama.cpp tokenizer returned no tokens");
		return -5;
	}

	struct llama_batch batch = llama_batch_init(n_tokens, 0, 1);
	if (batch.token == NULL || batch.pos == NULL || batch.n_seq_id == NULL || batch.seq_id == NULL || batch.logits == NULL) {
		free(tokens);
		llama_batch_free(batch);
		polly_set_error("failed to allocate llama.cpp batch");
		return -6;
	}

	for (int i = 0; i < n_tokens; i++) {
		batch.token[i] = tokens[i];
		batch.pos[i] = (llama_pos) i;
		batch.n_seq_id[i] = 1;
		batch.seq_id[i][0] = 0;
		batch.logits[i] = 1;
	}
	batch.n_tokens = n_tokens;

	llama_memory_clear(llama_get_memory(handle->ctx), true);
	const int decode_code = llama_decode(handle->ctx, batch);
	free(tokens);
	llama_batch_free(batch);
	if (decode_code < 0) {
		polly_set_error_with_code("llama.cpp failed to decode embedding batch", decode_code);
		return -7;
	}

	const float* embedding = llama_get_embeddings_seq(handle->ctx, 0);
	if (embedding == NULL) {
		polly_set_error("llama.cpp did not return a sequence embedding");
		return -8;
	}

	polly_normalize_embedding(embedding, output, handle->dimensions);
	return handle->dimensions;
}
