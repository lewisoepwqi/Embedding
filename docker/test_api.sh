#!/usr/bin/env bash
# 验证嵌入服务是否跑通：/v1/models + /v1/embeddings（应返回向量）+ 显存占用。
#
# 用法：
#   bash test_api.sh
#   BASE_URL=http://127.0.0.1:8081/v1 bash test_api.sh
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8081/v1}"

echo "==> /health"
curl -fsS "${BASE_URL%/v1}/health" || { echo "服务未就绪，先看 'docker compose logs -f'"; exit 1; }
echo ""

echo "==> /v1/embeddings（取一句话的向量，看维度）"
curl -fsS "${BASE_URL}/embeddings" \
  -H "Content-Type: application/json" \
  -d '{"input": "中大咨询信息系统运行维护服务合同"}' \
  | (command -v jq >/dev/null 2>&1 \
       && jq '{dim: (.data[0].embedding | length), head: (.data[0].embedding[0:4])}' \
       || head -c 300)
echo ""
echo ""
echo "==> 显存占用（确认嵌入模型在 GPU 上；默认应在 GPU 1）"
nvidia-smi --query-gpu=index,memory.used,utilization.gpu --format=csv
