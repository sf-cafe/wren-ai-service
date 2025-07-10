```bash
#!/bin/bash
set -e

INTERVAL=1
TIMEOUT=60

# 預設 port 若沒設就用 8080
WREN_AI_SERVICE_PORT=${WREN_AI_SERVICE_PORT:-8080}

echo "Waiting for qdrant to start..."
current=0
while ! nc -z $QDRANT_HOST 6333; do
    sleep $INTERVAL
    current=$((current + INTERVAL))
    if [ $current -eq $TIMEOUT ]; then
        echo "Timeout: qdrant did not start within $TIMEOUT seconds"
        exit 1
    fi
done
echo "qdrant has started."

if [[ -n "$SHOULD_FORCE_DEPLOY" ]]; then
    # 開子進程跑 uvicorn
    poetry run uvicorn src.__main__:app --host 0.0.0.0 --port $WREN_AI_SERVICE_PORT --loop uvloop --http httptools &
    UVI_PID=$!

    # 等待 uvicorn 起好
    echo "Waiting for wren-ai-service to start..."
    current=0
    while ! nc -z localhost $WREN_AI_SERVICE_PORT; do
        sleep $INTERVAL
        current=$((current + INTERVAL))
        if [ $current -eq $TIMEOUT ]; then
            echo "Timeout: wren-ai-service did not start within $TIMEOUT seconds"
            exit 1
        fi
    done
    echo "wren-ai-service has started."

    echo "Waiting for wren-ui to start..."
    current=0
    while ! nc -z wren-ui $WREN_UI_PORT && ! nc -z host.docker.internal $WREN_UI_PORT; do
        sleep $INTERVAL
        current=$((current + INTERVAL))
        if [ $current -eq $TIMEOUT ]; then
            echo "Timeout: wren-ui did not start within $TIMEOUT seconds"
            exit 1
        fi
    done
    echo "wren-ui has started."

    echo "Forcing deployment..."
    python -m src.force_deploy

    # 切回前景、若 uvicorn 結束 container 跟著結束
    wait $UVI_PID
else
    # 預設直接前景啟動 uvicorn，讓 Zeabur 能探測 8080
    exec poetry run uvicorn src.__main__:app --host 0.0.0.0 --port $WREN_AI_SERVICE_PORT --loop uvloop --http httptools
fi