module memory

import json
import os

pub struct OpenAIGeneratorConfig {
pub:
	base_url   string = 'https://dashscope.aliyuncs.com/compatible-mode/v1'
	api_key    string
	model      string = 'qwen3.6-plus'
	max_tokens int    = 600
}

pub struct OpenAIGenerator {
	config OpenAIGeneratorConfig
}

pub fn new_openai_generator(config OpenAIGeneratorConfig) !OpenAIGenerator {
	mut api_key := config.api_key
	mut base_url := config.base_url
	if api_key.len == 0 {
		api_key = os.getenv('BAILIAN_CODING_API_KEY')
	}
	if config.base_url == 'https://dashscope.aliyuncs.com/compatible-mode/v1' {
		// 检查是否配置了自定义 base URL
		custom_url := os.getenv('BAILIAN_CODING_BASE_URL')
		if custom_url.len > 0 {
			base_url = custom_url
		}
	}
	if api_key.len == 0 {
		return error('API key is required (set BAILIAN_CODING_API_KEY)')
	}
	return OpenAIGenerator{
		config: OpenAIGeneratorConfig{
			...config
			api_key:  api_key
			base_url: base_url
		}
	}
}

pub fn (mut gen OpenAIGenerator) generate(prompt string) !string {
	system_msg := '你是 PollyDB 记忆蒸馏引擎。输出精简的技术洞察卡片。只输出最终内容，不要解释。'
	payload := json.encode(ApiRequest{
		model: gen.config.model
		messages: [
			ApiMessage{role: 'system', content: system_msg},
			ApiMessage{role: 'user', content: prompt},
		]
		max_tokens:  gen.config.max_tokens
		temperature: 0.3
	})

	url := '${gen.config.base_url}/chat/completions'
	tmpfile := os.join_path_single(os.temp_dir(), 'polly_api_payload.json')
	os.write_file(tmpfile, payload) or { return error('failed to write payload: ${err}') }
	defer { os.rm(tmpfile) or {} }

	cmd := 'curl -s -w "\\n%{http_code}" -X POST "${url}" -H "Content-Type: application/json" -H "Authorization: Bearer ${gen.config.api_key}" -d @${tmpfile}'
	result := os.execute(cmd)
	if result.exit_code != 0 {
		return error('curl failed: ${result.output}')
	}

	output := result.output.trim_space()
	// 分离 body 和 HTTP status code
	last_newline := output.last_index('\n') or { return error('unexpected curl output') }
	status_code := output[last_newline + 1..].trim_space()
	body := output[..last_newline].trim_space()

	if status_code != '200' {
		return error('API returned ${status_code}: ${body}')
	}

	parsed := json.decode(ApiResponse, body) or { return error('failed to parse response: ${err}') }
	if parsed.choices.len == 0 {
		return error('API returned empty choices')
	}

	return parsed.choices[0].message.content
}

struct ApiMessage {
	role    string
	content string
}

struct ApiRequest {
	model       string       @[json: model]
	messages    []ApiMessage @[json: messages]
	max_tokens  int          @[json: max_tokens]
	temperature f32          @[json: temperature]
}

struct ApiChoice {
	message ApiMessage
}

struct ApiResponse {
	choices []ApiChoice
}
