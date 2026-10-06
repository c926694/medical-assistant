// 集成测试配置：跑 test 目录下的 .e2e-spec.ts，会真实调用模型接口
export default {
  rootDir: ".",
  testEnvironment: "node",
  roots: ["<rootDir>/test"],
  testRegex: ".*\\.e2e-spec\\.ts$",
  transform: {
    "^.+\\.(t|j)s$": "@swc/jest",
  },
  moduleFileExtensions: ["ts", "js", "json"],
  // 源码按 ESM 写法用 .js 后缀引用相对模块，这里映射回 .ts 源文件
  moduleNameMapper: {
    "^(\\.{1,2}/.*)\\.js$": "$1",
  },
  // NestJS 12 与部分依赖按 ESM 发布，排除在忽略列表外，交给 @swc/jest 转成 CommonJS
  transformIgnorePatterns: [
    "/node_modules/\\.pnpm/(?!(@nestjs\\+|zod@|chromadb@|@huggingface\\+transformers@))",
  ],
  setupFiles: ["reflect-metadata", "<rootDir>/test/setup-env.ts"],
  testTimeout: 600000,
};
