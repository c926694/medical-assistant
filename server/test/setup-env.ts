import { existsSync, readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';

// jest 的沙箱会复制一份 process.env，Node 的 process.loadEnvFile 只写真实进程的环境变量，
// 这里用 Node 内置的 .env 解析器把配置写进沙箱内的 process.env，测试代码直接读 process.env 即可
if (existsSync('.env')) {
  Object.assign(process.env, parseEnv(readFileSync('.env', 'utf8')));
}
