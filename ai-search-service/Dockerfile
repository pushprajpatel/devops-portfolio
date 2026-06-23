FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --upgrade pip setuptools wheel

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY db.py main.py entrypoint.sh ./
COPY frontend ./frontend
RUN chmod +x entrypoint.sh

ENV DB_PATH=/app/data/products.db
ENV IMAGE_DIR=/app/data/images
ENV OLLAMA_HOST=http://ollama:11434
ENV OLLAMA_MODEL=qwen2.5:7b

EXPOSE 8000

ENTRYPOINT ["./entrypoint.sh"]
