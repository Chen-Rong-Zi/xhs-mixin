# 配套 Dockerfile：预烘焙 xhs-mcp MCP 运行时。
# 目的：把 xhs-mcp 和它需要的 Chromium 预装进镜像，避免沙箱运行时访问 npm。
# 用法见 README：docker build -t xhs-mcp-runtime:1 .，然后用 sbx template / sbx run 使用该镜像。
# 注意：xhs-mcp 通过无头 Chromium (puppeteer) 抓取小红书，必须装浏览器。
# 基础镜像：优先固定到具体 patch 版本（如 node:22.11.0-slim）以保证可复现构建；
# 但本环境 `docker manifest inspect node:22.11.0-slim` 无法解析（离线/无 daemon），
# 暂保留浮动 tag；在能联网校验后可改回固定版本。
FROM node:22-slim

# 合并安装层：全局装 xhs-mcp，并用它自带的 browser 子命令安装与其 puppeteer 版本匹配的
# Chromium（xhs-mcp browser 是 algovate/xhs-mcp CLI 的子命令，--with-deps 会装系统依赖）。
RUN npm install -g xhs-mcp@0.8.13 --no-audit --no-fund \
    && xhs-mcp browser --with-deps

# XHS_ENABLE_LOGGING 是 xhs-mcp 的真实环境变量（npm 文档：XHS_ENABLE_LOGGING=true npx xhs-mcp mcp）
ENV XHS_ENABLE_LOGGING=false
CMD ["xhs-mcp", "mcp"]
