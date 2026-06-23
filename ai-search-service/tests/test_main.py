import os
import sqlite3
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

# db.py and main.py read DB_PATH/IMAGE_DIR from the environment at import
# time, so these must be set before either module is imported.
_tmp_dir = tempfile.mkdtemp()
os.environ["DB_PATH"] = str(Path(_tmp_dir) / "test_products.db")
os.environ["IMAGE_DIR"] = str(Path(_tmp_dir) / "images")

import db  # noqa: E402

os.makedirs(os.environ["IMAGE_DIR"], exist_ok=True)

# Build a minimal products table directly instead of calling db.seed() —
# seed() downloads real images over the network, which would make this test
# suite slow and dependent on internet access in CI.
_conn = sqlite3.connect(os.environ["DB_PATH"])
_conn.execute(
    """
    CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        brand TEXT NOT NULL,
        category TEXT NOT NULL,
        color TEXT NOT NULL,
        size TEXT NOT NULL,
        price REAL NOT NULL,
        image_path TEXT,
        gender TEXT NOT NULL DEFAULT 'unisex',
        description TEXT,
        mrp REAL,
        discount_pct INTEGER,
        rating REAL,
        review_count INTEGER,
        stock INTEGER
    )
    """
)
TEST_PRODUCTS = [
    ("Nike Tshirt #1", "Nike", "tshirt", "black", "M", 800.0, "img1.jpg", "unisex", "desc", 800.0, 0, 4.5, 10, 5),
    ("Levis Pants #2", "Levis", "pants", "red", "L", 2000.0, "img2.jpg", "unisex", "desc", 2500.0, 20, 4.2, 30, 2),
    ("Zara Shirt #3", "Zara", "shirt", "grey", "S", 1500.0, "img3.jpg", "unisex", "desc", 1500.0, 0, 3.9, 5, 0),
]
_conn.executemany(
    """
    INSERT INTO products (name, brand, category, color, size, price, image_path,
        gender, description, mrp, discount_pct, rating, review_count, stock)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
    TEST_PRODUCTS,
)
_conn.commit()
_conn.close()

db.init_users()  # creates the users table and seeds admin/admin — no network

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402

client = TestClient(main.app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_signup_and_login():
    resp = client.post("/auth/signup", json={"username": "tester1", "password": "pass123"})
    assert resp.status_code == 200

    resp = client.post("/auth/login", json={"username": "tester1", "password": "pass123"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["username"] == "tester1"
    assert data["is_admin"] is False
    assert "token" in data


def test_login_wrong_password():
    client.post("/auth/signup", json={"username": "tester2", "password": "correctpw"})
    resp = client.post("/auth/login", json={"username": "tester2", "password": "wrongpw"})
    assert resp.status_code == 401


def test_signup_duplicate_username():
    client.post("/auth/signup", json={"username": "dupe", "password": "pass123"})
    resp = client.post("/auth/signup", json={"username": "dupe", "password": "pass123"})
    assert resp.status_code == 409


def test_admin_login_seeded():
    resp = client.post("/auth/login", json={"username": "admin", "password": "admin"})
    assert resp.status_code == 200
    assert resp.json()["is_admin"] is True


def test_run_query_filters_by_category_and_color():
    results = main.run_query({"category": "tshirt", "color": "black"})
    assert len(results) == 1
    assert results[0]["brand"] == "Nike"


def test_run_query_no_filters_returns_all():
    results = main.run_query({})
    assert len(results) == len(TEST_PRODUCTS)


def test_run_query_price_range():
    results = main.run_query({"min_price": 1000, "max_price": 2200})
    assert len(results) == 2
    assert {r["brand"] for r in results} == {"Levis", "Zara"}


def test_search_with_mocked_ollama():
    mock_response = MagicMock()
    mock_response.raise_for_status.return_value = None
    mock_response.json.return_value = {
        "message": {
            "tool_calls": [
                {"function": {"arguments": {"category": "pants", "color": "red"}}}
            ]
        }
    }
    with patch("main.requests.post", return_value=mock_response):
        resp = client.post("/search", json={"query": "red pants"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["filters"] == {"category": "pants", "color": "red"}
    assert data["count"] == 1


def test_search_with_no_tool_call_returns_empty_filters():
    mock_response = MagicMock()
    mock_response.raise_for_status.return_value = None
    mock_response.json.return_value = {"message": {"content": "some text, no tool call"}}
    with patch("main.requests.post", return_value=mock_response):
        resp = client.post("/search", json={"query": "tshirt"})
    assert resp.status_code == 200
    assert resp.json()["filters"] == {}


def test_admin_users_requires_auth():
    resp = client.get("/admin/users")
    assert resp.status_code == 401


def test_admin_users_requires_admin_role():
    login = client.post("/auth/login", json={"username": "tester1", "password": "pass123"}).json()
    resp = client.get("/admin/users", headers={"Authorization": f"Bearer {login['token']}"})
    assert resp.status_code == 403


def test_admin_users_success_for_admin():
    login = client.post("/auth/login", json={"username": "admin", "password": "admin"}).json()
    resp = client.get("/admin/users", headers={"Authorization": f"Bearer {login['token']}"})
    assert resp.status_code == 200
    usernames = [u["username"] for u in resp.json()]
    assert "admin" in usernames
