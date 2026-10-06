import { describe, expect, it } from '@jest/globals';
import type { ChatCompletion } from 'openai/resources/chat/completions';
import { LlmResponseError, extractMessageContent } from './llm-extract.js';

function completion(choices: ChatCompletion['choices']): ChatCompletion {
  return {
    id: 'chatcmpl-test',
    object: 'chat.completion',
    created: 0,
    model: 'test-model',
    choices,
  };
}

function choice(overrides: Partial<ChatCompletion.Choice>): ChatCompletion.Choice {
  return {
    index: 0,
    finish_reason: 'stop',
    logprobs: null,
    message: { role: 'assistant', content: null, refusal: null },
    ...overrides,
  };
}

describe('extractMessageContent', () => {
  it('取出回答文本', () => {
    const response = completion([
      choice({ message: { role: 'assistant', content: '正常', refusal: null } }),
    ]);

    expect(extractMessageContent(response)).toBe('正常');
  });

  it('没有 choices 时抛出错误', () => {
    expect(() => extractMessageContent(completion([]))).toThrow(LlmResponseError);
  });

  it('文本为空白且没有工具调用时抛出错误', () => {
    const response = completion([
      choice({ message: { role: 'assistant', content: '   ', refusal: null } }),
    ]);

    expect(() => extractMessageContent(response)).toThrow('既没有文本也没有工具调用');
  });

  it('只有工具调用时返回空字符串', () => {
    const response = completion([
      choice({
        finish_reason: 'tool_calls',
        message: {
          role: 'assistant',
          content: null,
          refusal: null,
          tool_calls: [
            {
              id: 'call_1',
              type: 'function',
              function: { name: 'search_doctors', arguments: '{}' },
            },
          ],
        },
      }),
    ]);

    expect(extractMessageContent(response)).toBe('');
  });
});
