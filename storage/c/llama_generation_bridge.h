#ifndef POLLYDB_LLAMA_GENERATION_BRIDGE_H
#define POLLYDB_LLAMA_GENERATION_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PollyLlamaGenerationHandle PollyLlamaGenerationHandle;

PollyLlamaGenerationHandle* polly_llama_generation_open(
	const char* model_path,
	int n_ctx,
	int n_batch,
	int n_threads,
	int n_gpu_layers);

void polly_llama_generation_close(PollyLlamaGenerationHandle* handle);
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
	unsigned int seed);
const char* polly_llama_generation_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
