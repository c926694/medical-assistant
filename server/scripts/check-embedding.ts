import { EMBEDDING_DIMENSIONS, getEmbeddingService } from '../src/agent-core/embedding/embedding.service.js';

// 本地向量服务的真实检查：加载 bge-m3，输出维度、模长与相似度
// 用 tsx 直接运行；jest 的 VM 上下文与 onnxruntime-node 的原生浮点数组存在领域不匹配，无法在 jest 内运行
async function main(): Promise<void> {
  process.loadEnvFile('.env');

  const service = getEmbeddingService();
  await service.preload();

  const vectors = await service.embed([
    '高血压需要长期服药吗',
    '血压高要一直吃药吗',
    '脚踝扭伤怎么处理',
  ]);
  const [first, second, third] = vectors;

  if (!first || !second || !third) {
    throw new Error(`向量数量不足: ${vectors.length}`);
  }

  if (first.length !== EMBEDDING_DIMENSIONS) {
    throw new Error(`向量维度错误: ${first.length}`);
  }

  const norm = Math.sqrt(first.reduce((sum, value) => sum + value * value, 0));
  const cosine = (a: number[], b: number[]): number => {
    let sum = 0;
    for (let index = 0; index < a.length; index += 1) {
      const left = a[index];
      const right = b[index];
      if (left === undefined || right === undefined) {
        throw new Error('向量长度不一致');
      }
      sum += left * right;
    }
    return sum;
  };
  const similar = cosine(first, second);
  const unrelated = cosine(first, third);

  console.log(`维度: ${first.length}`);
  console.log(`模长: ${norm.toFixed(6)}`);
  console.log(`相近句子相似度: ${similar.toFixed(4)}`);
  console.log(`无关句子相似度: ${unrelated.toFixed(4)}`);

  if (Math.abs(norm - 1) > 0.001) {
    throw new Error('向量未归一化');
  }
  if (similar <= unrelated) {
    throw new Error('相近句子相似度未高于无关句子');
  }
}

main();
