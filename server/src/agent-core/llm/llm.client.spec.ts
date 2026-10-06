import { describe, expect, it } from '@jest/globals';
import { LlmConfigError, createLlmClient, loadLlmConfig } from './llm.client.js';

const requiredEnv = {
  LLM_BASE_URL: 'https://api.example.com',
  LLM_API_KEY: 'test-key',
  LLM_MODEL: 'test-model',
};

describe('loadLlmConfig', () => {
  it('缺少必需配置时抛出 LlmConfigError', () => {
    const env = { LLM_BASE_URL: 'https://api.example.com', LLM_MODEL: 'test-model' };
    expect(() => loadLlmConfig(env)).toThrow(LlmConfigError);
    expect(() => loadLlmConfig(env)).toThrow('缺少必需配置 LLM_API_KEY');
  });

  it('未配置超时时使用 60000 毫秒', () => {
    expect(loadLlmConfig(requiredEnv).timeoutMs).toBe(60000);
  });

  it('超时配置非法时抛出 LlmConfigError', () => {
    const env = { ...requiredEnv, LLM_TIMEOUT_MS: 'abc' };
    expect(() => loadLlmConfig(env)).toThrow('配置 LLM_TIMEOUT_MS 必须为正整数');
  });
});

describe('createLlmClient', () => {
  it('产出的客户端与配置一致', () => {
    const client = createLlmClient({
      baseUrl: 'https://api.example.com',
      apiKey: 'test-key',
      model: 'test-model',
      timeoutMs: 1234,
    });

    expect(client.baseURL).toBe('https://api.example.com');
    expect(client.timeout).toBe(1234);
  });
});
