#ifndef POLLYDB_LLAMA_EMBEDDING_BRIDGE_H
#define POLLYDB_LLAMA_EMBEDDING_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PollyLlamaEmbeddingHandle PollyLlamaEmbeddingHandle;

PollyLlamaEmbeddingHandle* polly_llama_embedding_open(
	const char* model_path,
	int n_ctx,
	int n_batch,
	int n_threads,
	int n_gpu_layers);

void polly_llama_embedding_close(PollyLlamaEmbeddingHandle* handle);
int polly_llama_embedding_dimensions(PollyLlamaEmbeddingHandle* handle);
int polly_llama_embedding_embed(
	PollyLlamaEmbeddingHandle* handle,
	const char* text,
	int text_len,
	float* output,
	int output_len);
const char* polly_llama_embedding_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
