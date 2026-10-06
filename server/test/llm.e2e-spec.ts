import { describe, expect, it } from '@jest/globals';
import { getLlmClient, getLlmModel } from '../src/agent-core/llm/llm.client.js';
import { extractMessageContent } from '../src/utils/llm-extract.js';

// 真实调用对话模型接口，不使用任何假数据（.env 由 jest 的 setup 文件载入）
describe('对话模型真实调用', () => {
  it('用导出的客户端与模型名完成一次补全，并取出回答文本', async () => {
    const client = getLlmClient();
    const model = getLlmModel();

    const response = await client.chat.completions.create({
      model,
      max_tokens: 16,
      temperature: 0,
      messages: [{ role: 'user', content: '只回复两个字：正常' }],
    });

    const content = extractMessageContent(response);
    expect(content.trim().length).toBeGreaterThan(0);
    expect(response.usage?.total_tokens ?? 0).toBeGreaterThan(0);
  });
});
