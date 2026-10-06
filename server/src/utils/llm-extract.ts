import type { ChatCompletion } from 'openai/resources/chat/completions';

export class LlmResponseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LlmResponseError';
  }
}

// 从对话模型的返回中取出回答文本
// 返回里没有 choices 时抛出错误；既没有文本也没有工具调用时同样抛出错误
export function extractMessageContent(completion: ChatCompletion): string {
  const choice = completion.choices[0];
  if (!choice) {
    throw new LlmResponseError(`模型返回里没有 choices，id=${completion.id}`);
  }

  const content = choice.message.content ?? '';
  const hasToolCalls = (choice.message.tool_calls?.length ?? 0) > 0;
  if (content.trim() === '' && !hasToolCalls) {
    throw new LlmResponseError(
      `模型返回既没有文本也没有工具调用，finish_reason=${choice.finish_reason}`,
    );
  }
  return content;
}
