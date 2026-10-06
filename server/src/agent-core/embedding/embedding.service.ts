import path from 'node:path';
import { env, pipeline, type FeatureExtractionPipeline } from '@huggingface/transformers';

// bge-m3 的输出维度
export const EMBEDDING_DIMENSIONS = 1024;

export class EmbeddingConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EmbeddingConfigError';
  }
}

export interface EmbeddingConfig {
  model: string;
  modelDir: string;
  batchSize: number;
}

// 读取向量配置，批大小非法时抛出错误
export function loadEmbeddingConfig(envVars: NodeJS.ProcessEnv = process.env): EmbeddingConfig {
  const model = envVars['EMBEDDING_MODEL']?.trim() || 'BAAI/bge-m3';
  const modelDir = envVars['EMBEDDING_MODEL_DIR']?.trim() || './models';
  const raw = envVars['EMBEDDING_BATCH_SIZE'];
  const batchSize = raw === undefined || raw.trim() === '' ? 8 : Number(raw);
  if (!Number.isInteger(batchSize) || batchSize <= 0) {
    throw new EmbeddingConfigError(`配置 EMBEDDING_BATCH_SIZE 必须为正整数，当前值 ${raw}`);
  }
  return { model, modelDir: path.resolve(modelDir), batchSize };
}

export class EmbeddingService {
  private extractor: FeatureExtractionPipeline | null = null;
  private loading: Promise<FeatureExtractionPipeline> | null = null;
  // 把并发调用串行化，避免重复加载模型
  private queue: Promise<unknown> = Promise.resolve();

  constructor(private readonly config: EmbeddingConfig) {}

  // 加载模型，权重下载或加载失败时直接抛出错误；服务启动阶段调用一次即可
  async preload(): Promise<void> {
    await this.getExtractor();
  }

  embed(texts: string[]): Promise<number[][]> {
    return this.enqueue(() => this.runEmbed(texts));
  }

  async embedOne(text: string): Promise<number[]> {
    const vectors = await this.embed([text]);
    const [vector] = vectors;
    if (!vector) {
      throw new Error('向量计算返回空结果');
    }
    return vector;
  }

  private async runEmbed(texts: string[]): Promise<number[][]> {
    if (texts.length === 0) {
      return [];
    }
    const extractor = await this.getExtractor();
    const vectors: number[][] = [];
    for (let start = 0; start < texts.length; start += this.config.batchSize) {
      const batch = texts.slice(start, start + this.config.batchSize);
      const output = await extractor(batch, { pooling: 'cls', normalize: true });
      vectors.push(...(output.tolist() as number[][]));
    }
    return vectors;
  }

  private async getExtractor(): Promise<FeatureExtractionPipeline> {
    if (this.extractor) {
      return this.extractor;
    }
    if (!this.loading) {
      this.loading = this.createExtractor();
    }
    this.extractor = await this.loading;
    return this.extractor;
  }

  private async createExtractor(): Promise<FeatureExtractionPipeline> {
    // 权重下载到配置目录；BAAI/bge-m3 的 fp32 权重以外置数据文件存放，需要显式开启加载
    env.cacheDir = this.config.modelDir;
    return pipeline('feature-extraction', this.config.model, {
      dtype: 'fp32',
      use_external_data_format: true,
    });
  }

  private enqueue<T>(task: () => Promise<T>): Promise<T> {
    const result = this.queue.then(task, task);
    this.queue = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }
}

let cachedService: EmbeddingService | null = null;

// 进程内单例：向量计算只加载一份模型
export function getEmbeddingService(): EmbeddingService {
  cachedService ??= new EmbeddingService(loadEmbeddingConfig());
  return cachedService;
}
