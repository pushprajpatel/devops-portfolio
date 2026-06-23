#!/bin/sh
set -e

echo "Waiting for Ollama at $OLLAMA_HOST..."
until curl -s "$OLLAMA_HOST" > /dev/null 2>&1; do
  sleep 2
done
echo "Ollama is up."

echo "Ensuring model $OLLAMA_MODEL is pulled (this can take a while on first run)..."
curl -s -X POST "$OLLAMA_HOST/api/pull" -d "{\"name\": \"$OLLAMA_MODEL\"}" > /dev/null

if [ ! -f "$DB_PATH" ]; then
  echo "No database found at $DB_PATH — seeding..."
  python db.py
else
  echo "Database already exists at $DB_PATH — skipping seed."
fi

exec uvicorn main:app --host 0.0.0.0 --port 8000
