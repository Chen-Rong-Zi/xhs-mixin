# 配套 Dockerfile：预烘焙 jobsonlook/xhs-mcp MCP 运行时。
# 目的：把 Python 3.12+、uv 项目依赖和 Playwright Chromium 预装进镜像，避免沙箱运行时访问 PyPI。
# 用法见 README：docker build -t xhs-mcp-runtime:1 .，然后用 sbx template / sbx run 使用该镜像。
# 注意：jobsonlook/xhs-mcp 通过 Playwright 加载 www.xiaohongshu.com 获取签名运行时，必须装浏览器。
# 构建时把内置补丁版 xhs-mcp-src/ 拷贝进镜像，运行时 `uv run --project` 即命中预烘焙的 .venv。
FROM python:3.12-slim

# uv + 系统依赖（Playwright Chromium 需要）
COPY --from=ghcr.io/astral-sh/uv:0.13 /uv /uvx /bin/
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# 项目源码（内置补丁版，含 pyproject.toml）
WORKDIR /app
COPY files/workspace/xhs-mcp-src/ /app/xhs-mcp-src/

# uv sync 装依赖 + 装 Chromium（--with-deps 装系统库）
RUN cd /app/xhs-mcp-src \
    && uv sync --frozen \
    && uv run python -m playwright install --with-deps chromium

# 默认命令（claude 会以 .mcp.json 的 command 启动，这里仅供手动验证）
CMD ["uv", "run", "--project", "/app/xhs-mcp-src", "python", "-m", "xhs_mcp"]
