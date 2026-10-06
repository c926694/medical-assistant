import OpenAI from 'openai';

export class LlmConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LlmConfigError';
  }
}

export interface LlmConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
  timeoutMs: number;
}

// 读取并校验配置，必填项缺失或格式非法时抛出错误
export function loadLlmConfig(env: NodeJS.ProcessEnv = process.env): LlmConfig {
  const baseUrl = requireText(env, 'LLM_BASE_URL');
  const apiKey = requireText(env, 'LLM_API_KEY');
  const model = requireText(env, 'LLM_MODEL');
  const timeoutMs = readPositiveInt(env, 'LLM_TIMEOUT_MS', 60000);
  return { baseUrl, apiKey, model, timeoutMs };
}

export function createLlmClient(config: LlmConfig): OpenAI {
  return new OpenAI({
    baseURL: config.baseUrl,
    apiKey: config.apiKey,
    timeout: config.timeoutMs,
  });
}

let cachedConfig: LlmConfig | null = null;
let cachedClient: OpenAI | null = null;

function config(): LlmConfig {
  cachedConfig ??= loadLlmConfig();
  return cachedConfig;
}

// 首次调用时创建客户端并缓存，之后复用同一个实例
export function getLlmClient(): OpenAI {
  cachedClient ??= createLlmClient(config());
  return cachedClient;
}

export function getLlmModel(): string {
  return config().model;
}

function requireText(env: NodeJS.ProcessEnv, name: string): string {
  const value = env[name]?.trim();
  if (!value) {
    throw new LlmConfigError(`缺少必需配置 ${name}`);
  }
  return value;
}

function readPositiveInt(env: NodeJS.ProcessEnv, name: string, fallback: number): number {
  const raw = env[name];
  if (raw === undefined || raw.trim() === '') {
    return fallback;
  }
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new LlmConfigError(`配置 ${name} 必须为正整数，当前值 ${raw}`);
  }
  return value;
}
