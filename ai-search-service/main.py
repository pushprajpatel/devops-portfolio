import os
import secrets

import requests
from fastapi import FastAPI, Header, HTTPException
from fastapi.staticfiles import StaticFiles
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel

from db import get_connection, hash_password, init_users

IMAGE_DIR = os.environ.get("IMAGE_DIR", "static/images")

app = FastAPI(title="AI Search Service")
Instrumentator().instrument(app).expose(app)
app.mount("/images", StaticFiles(directory=IMAGE_DIR), name="images")

init_users()

# In-memory session store: token -> {username, is_admin}. Demo-grade auth —
# tokens reset on server restart, no HTTPS/rate-limiting/expiry. Don't reuse
# this pattern for anything handling real user data.
SESSIONS = {}

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
OLLAMA_URL = f"{OLLAMA_HOST}/api/chat"
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:7b")

SEARCH_TOOL = {
    "type": "function",
    "function": {
        "name": "search_products",
        "description": "Search the product catalog by filters extracted from a natural-language query",
        "parameters": {
            "type": "object",
            "properties": {
                "category": {
                    "type": "string",
                    "enum": ["tshirt", "shirt", "pants"],
                    "description": "Product category",
                },
                "brand": {"type": "string", "description": "Brand name, e.g. Nike"},
                "color": {
                    "type": "string",
                    "enum": ["white", "black", "grey", "red"],
                    "description": "Product color",
                },
                "size": {
                    "type": "string",
                    "enum": ["S", "M", "L", "XL"],
                    "description": "Product size",
                },
                "min_price": {"type": "number", "description": "Minimum price"},
                "max_price": {"type": "number", "description": "Maximum price"},
            },
            "required": [],
        },
    },
}


class SearchRequest(BaseModel):
    query: str


def run_query(filters: dict):
    clauses = []
    params = []

    if filters.get("category"):
        clauses.append("category = ?")
        params.append(filters["category"].lower())
    if filters.get("brand"):
        clauses.append("brand LIKE ?")
        params.append(f"%{filters['brand']}%")
    if filters.get("color"):
        clauses.append("color = ?")
        params.append(filters["color"].lower())
    if filters.get("size"):
        clauses.append("size = ?")
        params.append(filters["size"].upper())
    if filters.get("min_price") is not None:
        clauses.append("price >= ?")
        params.append(filters["min_price"])
    if filters.get("max_price") is not None:
        clauses.append("price <= ?")
        params.append(filters["max_price"])

    sql = (
        "SELECT id, name, brand, category, color, size, price, image_path, gender, "
        "description, mrp, discount_pct, rating, review_count, stock FROM products"
    )
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)

    conn = get_connection()
    cur = conn.cursor()
    cur.execute(sql, params)
    rows = cur.fetchall()
    conn.close()

    return [
        {
            "id": r[0],
            "name": r[1],
            "brand": r[2],
            "category": r[3],
            "color": r[4],
            "size": r[5],
            "price": r[6],
            "image_path": r[7],
            "gender": r[8],
            "description": r[9],
            "mrp": r[10],
            "discount_pct": r[11],
            "rating": r[12],
            "review_count": r[13],
            "stock": r[14],
        }
        for r in rows
    ]


@app.post("/search")
def search(req: SearchRequest):
    response = requests.post(
        OLLAMA_URL,
        json={
            "model": OLLAMA_MODEL,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You must always call the search_products tool to answer, "
                        "even for vague or single-word queries. Never reply with plain text."
                    ),
                },
                {"role": "user", "content": req.query},
            ],
            "tools": [SEARCH_TOOL],
            "stream": False,
        },
        timeout=60,
    )
    response.raise_for_status()
    tool_calls = response.json()["message"].get("tool_calls")
    filters = tool_calls[0]["function"]["arguments"] if tool_calls else {}
    results = run_query(filters)

    return {
        "query": req.query,
        "filters": filters,
        "count": len(results),
        "results": results,
    }


class AuthRequest(BaseModel):
    username: str
    password: str


def get_current_user(authorization: str | None):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    token = authorization.removeprefix("Bearer ")
    user = SESSIONS.get(token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    return user


@app.post("/auth/signup")
def signup(req: AuthRequest):
    username = req.username.strip()
    if len(username) < 3 or len(req.password) < 4:
        raise HTTPException(status_code=400, detail="Username must be 3+ chars, password 4+ chars")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT id FROM users WHERE username = ?", (username,))
    if cur.fetchone():
        conn.close()
        raise HTTPException(status_code=409, detail="Username already taken")

    salt = secrets.token_hex(16)
    cur.execute(
        "INSERT INTO users (username, salt, password_hash, is_admin) VALUES (?, ?, ?, 0)",
        (username, salt, hash_password(req.password, salt)),
    )
    conn.commit()
    conn.close()
    return {"message": "Account created. You can now log in."}


@app.post("/auth/login")
def login(req: AuthRequest):
    username = req.username.strip()
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT salt, password_hash, is_admin FROM users WHERE username = ?", (username,)
    )
    row = cur.fetchone()
    conn.close()

    if not row or hash_password(req.password, row[0]) != row[1]:
        raise HTTPException(status_code=401, detail="Invalid username or password")

    token = secrets.token_hex(24)
    is_admin = bool(row[2])
    SESSIONS[token] = {"username": username, "is_admin": is_admin}
    return {"token": token, "username": username, "is_admin": is_admin}


@app.get("/auth/me")
def me(authorization: str | None = Header(default=None)):
    return get_current_user(authorization)


@app.get("/admin/users")
def list_users(authorization: str | None = Header(default=None)):
    user = get_current_user(authorization)
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="Admin access required")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT username, is_admin, created_at FROM users ORDER BY created_at DESC")
    rows = cur.fetchall()
    conn.close()
    return [{"username": r[0], "is_admin": bool(r[1]), "created_at": r[2]} for r in rows]


@app.get("/health")
def health():
    return {"status": "ok"}


# Catch-all mount for the frontend — must be added last so it doesn't shadow the API routes above.
app.mount("/", StaticFiles(directory="frontend", html=True), name="frontend")
