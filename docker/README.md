# 中文嵌入模型服务（Linux + NVIDIA CUDA, Docker）

把中文/多语**嵌入模型**部署成与 Qwen 对话服务（`../../LLM`）平级的**独立、可外部调用**服务：同一官方 llama.cpp CUDA 镜像，换嵌入模型 + `--embeddings` 模式，暴露 OpenAI-compatible `POST /v1/embeddings` 于 `:8081`。合同雷达 `VectorRanker` 与任意 OpenAI 兼容客户端经 HTTP 调它，代码零耦合（只看 `EMBEDDING_BASE_URL`）。

## 为什么单独一个服务

llama.cpp 的 `llama-server` **一个进程只托管一个模型、一种模式**——嵌入要 `--embeddings`，与对话生成互斥，**没法和 Qwen 共用一个进程**。所以嵌入天然是另一个进程、另一个端口，与 Qwen 对称并存。

## 目标环境

```text
Ubuntu 22.04.5 LTS / NVIDIA Driver 535 / CUDA 12.2
2x RTX A4000 16GB
```

策略：**跑在第二张卡 GPU 1**（Qwen 在 GPU 0），两者零争抢。Qwen3-Embedding-0.6B Q8 仅 ~0.8GB，单张 16GB 远远富余。

## 模型选型（二选一，都极小）

| 模型 | 维度 | Q8 显存 | pooling | 说明 |
|---|---|---|---|---|
| **Qwen3-Embedding-0.6B**（默认） | 1024 | ~0.8GB | `last` | 与 Qwen 同族、中文/多语检索 SOTA 级 |
| **bge-m3**（备选） | 1024 | ~0.6–1.2GB | `cls` | 老牌多语强中文、8192 上下文 |

换模型只改 `.env` 的 `EMBED_MODEL_FILE` + `EMBED_POOLING`，调用方不动。要更高召回且显存有富余可上 `Qwen3-Embedding-4B`（2560 维，~4.5GB），代码零改。

## 目录布局（自包含）

```text
~/app/Embedding/
  docker/                       # 本部署套件
    docker-compose.yml
    .env
    test_api.sh
  models/
    Qwen3-Embedding-0.6B/
      Qwen3-Embedding-0.6B-Q8_0.gguf
```

## 步骤

### 1. 宿主机准备（Docker + NVIDIA Container Toolkit）

与 Qwen 套件相同。**同机已为 `../../LLM` 配过则无需重做**；全新机器跑一次 `LLM/docker/setup_docker_gpu.sh` 即可（Docker + nvidia-container-toolkit，两套服务共用）。

### 2. 放模型

```bash
mkdir -p ~/app/Embedding/models/Qwen3-Embedding-0.6B
# 有网：hf download Qwen/Qwen3-Embedding-0.6B-GGUF Qwen3-Embedding-0.6B-Q8_0.gguf \
#         --local-dir ~/app/Embedding/models/Qwen3-Embedding-0.6B
# 无网：有网机下载后 scp 上传到该目录
ls -lh ~/app/Embedding/models/Qwen3-Embedding-0.6B/
```

### 3. 配置并启动

```bash
cd ~/app/Embedding/docker
cp .env.docker.example .env     # 默认 GPU 1 / 端口 8081 / Qwen3-Embedding-0.6B
docker compose up -d
docker compose logs -f          # 出现 "server listening" 即就绪
```

### 4. 验证

```bash
cd ~/app/Embedding/docker && bash test_api.sh
```

应看到 `/health` OK、`/v1/embeddings` 返回 1024 维向量，以及 `nvidia-smi` 里 GPU 1 占用 ~1GB。

## 合同雷达接入

```bash
# 合同雷达后端 / VectorRanker 侧
EMBEDDING_BASE_URL=http://192.168.16.201:8081/v1
```

调用 `POST /v1/embeddings`，`{"input": "<文本或文本数组>"}` → `{"data":[{"embedding":[...]}]}`。检索查询建议给 query 加指令前缀（Qwen3-Embedding 指令感知，document 不加），实现细节在 VectorRanker。

## 常用运维

```bash
docker compose ps
docker compose logs -f
docker compose restart
docker compose down
docker compose pull && docker compose up -d   # 升级镜像
```

`restart: unless-stopped` 已配，崩溃/重启机器自动拉起。

## 调参对照

| 需求 | 改法（`.env`） |
|---|---|
| 换嵌入模型 | `EMBED_MODEL_FILE=...`（bge-m3 同时把 `EMBED_POOLING=cls`） |
| 换端口 | `EMBED_SERVER_PORT=...`（勿撞 Qwen 的 8080） |
| 换 GPU 卡 | `EMBED_GPU_DEVICE_ID=0`（与 Qwen 共卡也行，0.6B 占用小） |
| 走 CPU | `N_GPU_LAYERS=0`（此规模 CPU 单次查询仍 <100ms） |

## 排错

- **`--embeddings` 不识别**：老版 llama.cpp 用 `--embedding`（单数）。本镜像新版用 `--embeddings`；若日志报未知参数，改 compose 里该项。
- **`could not select device driver "nvidia"`**：nvidia-container-toolkit 没装好，见 `LLM/docker/setup_docker_gpu.sh`。
- **端口被占**：8081 若被占改 `EMBED_SERVER_PORT`；确认与 Qwen 8080 不撞。
- **向量维度不对/全 0**：确认 `EMBED_POOLING` 与模型匹配（Qwen3-Embedding=last、bge=cls）。
