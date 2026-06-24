#!/bin/bash
set -e

# ====== 配置区（按需修改） ======
GITHUB_USER="125337"
GITHUB_REPO="didactic-octo-chainsaw"
ARTIFACT_NAME="xhbb-output"
DEPLOY_PATH="/www/wwwroot/ios公众号关注弹窗"

# 从 .env 加载 GITHUB_TOKEN（不提交到仓库）
if [ -f "$(dirname "$0")/.env" ]; then
  source "$(dirname "$0")/.env"
fi

if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "YOUR_TOKEN_HERE" ]; then
  echo "错误: 请先配置 .env 文件中的 GITHUB_TOKEN"
  exit 1
fi

# ====== 1. 获取最新 Workflow Run ID ======
echo "获取最新构建信息..."
RUN_ID=$(curl -s \
  "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs?per_page=1" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['workflow_runs'][0]['id'])")

echo "Run ID: $RUN_ID"

# ====== 2. 检查构建状态 ======
STATUS=$(curl -s \
  "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs/${RUN_ID}" \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['status'], r.get('conclusion',''))")
echo "Status: $STATUS"

# ====== 3. 构建成功则下载 ======
if echo "$STATUS" | grep -q "completed success"; then
  # 获取 Artifact ID
  ARTIFACT_ID=$(curl -s \
    "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/runs/${RUN_ID}/artifacts" \
    | python3 -c "import sys,json; data=json.load(sys.stdin); print([a['id'] for a in data['artifacts'] if a['name'] == '${ARTIFACT_NAME}'][0])")
  echo "Artifact ID: $ARTIFACT_ID"

  # 下载（返回 zip）
  curl -sL \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -o /tmp/xhbb_output.zip \
    "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/actions/artifacts/${ARTIFACT_ID}/zip"

  # 解压并部署到当前目录
  cd /tmp && rm -rf xhbb_extract && mkdir xhbb_extract && cd xhbb_extract
  unzip -o /tmp/xhbb_output.zip

  echo "===== 部署到 ${DEPLOY_PATH} ====="
  cp -R * "${DEPLOY_PATH}/"
  ls -lh "${DEPLOY_PATH}"/*.dylib "${DEPLOY_PATH}"/*.deb 2>/dev/null || true

  echo "===== 部署成功 ====="
else
  echo "===== 构建失败 ====="
  exit 1
fi