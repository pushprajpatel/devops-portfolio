import hashlib
import os
import random
import secrets
import sqlite3
import time

import requests

DB_PATH = os.environ.get("DB_PATH", "products.db")
IMAGE_DIR = os.environ.get("IMAGE_DIR", "static/images")


def hash_password(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 100_000).hex()


def init_users():
    """Create the users table if missing, and seed the admin account. Never
    drops existing data — unlike seed(), this is safe to call on every startup."""
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            salt TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            is_admin INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    cur.execute("SELECT id FROM users WHERE username = ?", ("admin",))
    if cur.fetchone() is None:
        salt = secrets.token_hex(16)
        cur.execute(
            "INSERT INTO users (username, salt, password_hash, is_admin) VALUES (?, ?, ?, 1)",
            ("admin", salt, hash_password("admin", salt)),
        )
        print("Seeded default admin user (username: admin, password: admin)")
    conn.commit()
    conn.close()

SIZES = ["S", "M", "L", "XL"]
BRANDS = [
    "Nike", "Adidas", "Puma", "Levis", "H&M", "Zara", "Uniqlo",
    "Allen Solly", "Van Heusen", "Peter England", "Wrangler", "US Polo",
    "Roadster", "Jack & Jones",
]

TOTAL_PRODUCTS = 100

# Realistic price range per category (₹), instead of one flat range for everything.
PRICE_RANGE = {
    "tshirt": (200, 2000),
    "shirt": (500, 4000),
    "pants": (700, 6000),
}

# Real product photos (Platzi Fake Store catalog, hosted on Imgur) — verified
# per category+color so the image actually matches the product's color.
REAL_IMAGES = {
    ("tshirt", "white"): [
        "https://i.imgur.com/Y54Bt8J.jpeg",
        "https://i.imgur.com/SZPDSgy.jpeg",
        "https://i.imgur.com/sJv4Xx0.jpeg",
    ],
    ("tshirt", "black"): [
        "https://i.imgur.com/9DqEOV5.jpeg",
        "https://i.imgur.com/ae0AEYn.jpeg",
        "https://i.imgur.com/mZ4rUjj.jpeg",
    ],
    ("shirt", "grey"): [
        "https://i.imgur.com/R2PN9Wq.jpeg",
        "https://i.imgur.com/IvxMPFr.jpeg",
        "https://i.imgur.com/7eW9nXP.jpeg",
    ],
    ("shirt", "black"): [
        "https://i.imgur.com/cSytoSD.jpeg",
        "https://i.imgur.com/WwKucXb.jpeg",
        "https://i.imgur.com/cE2Dxh9.jpeg",
    ],
    ("pants", "black"): [
        "https://i.imgur.com/ZKGofuB.jpeg",
        "https://i.imgur.com/GJi73H0.jpeg",
        "https://i.imgur.com/633Fqrz.jpeg",
    ],
    ("pants", "grey"): [
        "https://i.imgur.com/mp3rUty.jpeg",
        "https://i.imgur.com/JQRGIc2.jpeg",
    ],
    ("pants", "red"): [
        "https://i.imgur.com/9LFjwpI.jpeg",
        "https://i.imgur.com/vzrTgUR.jpeg",
        "https://i.imgur.com/p5NdI6n.jpeg",
    ],
}

COMBOS = list(REAL_IMAGES.keys())

CATEGORY_DETAIL = {
    "tshirt": "round-neck t-shirt",
    "shirt": "fleece shirt",
    "pants": "pair of joggers",
}
FEATURES = [
    "breathable cotton-blend fabric",
    "fade-resistant fabric",
    "soft-touch, all-day comfort fit",
    "machine-washable, easy-care fabric",
    "stretchable fabric for unrestricted movement",
]
OCCASIONS = ["everyday casual wear", "weekend outings", "gym and lounging", "travel and daily errands"]


def generate_description(brand: str, color: str, category: str) -> str:
    detail = CATEGORY_DETAIL[category]
    feature = random.choice(FEATURES)
    occasion = random.choice(OCCASIONS)
    return (
        f"This {color} {detail} from {brand} is designed for {occasion}. "
        f"Made with {feature}, it pairs easily with the rest of your wardrobe "
        f"and holds its shape wash after wash."
    )


def fetch_url_cache():
    """Download each unique source image once; return {url: bytes}."""
    cache = {}
    for urls in REAL_IMAGES.values():
        for url in urls:
            if url in cache:
                continue
            for attempt in range(5):
                resp = requests.get(
                    url, timeout=15, headers={"User-Agent": "Mozilla/5.0"}
                )
                if resp.status_code == 429:
                    wait = 2 ** attempt
                    print(f"Rate limited on {url}, retrying in {wait}s...")
                    time.sleep(wait)
                    continue
                resp.raise_for_status()
                cache[url] = resp.content
                print(f"Downloaded {url}")
                break
            else:
                raise RuntimeError(f"Failed to download {url} after retries")
            time.sleep(0.5)
    return cache


def seed():
    os.makedirs(IMAGE_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    url_cache = fetch_url_cache()

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS products")
    cur.execute(
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

    rows = []
    for i in range(TOTAL_PRODUCTS):
        category, color = random.choice(COMBOS)
        brand = random.choice(BRANDS)
        size = random.choice(SIZES)
        low, high = PRICE_RANGE[category]
        price = round(random.uniform(low, high), 2)
        name = f"{brand} {category.capitalize()} #{i+1}"
        description = generate_description(brand, color, category)

        discount_pct = random.choice([0, 0, 10, 15, 20, 25, 30, 40])
        mrp = round(price / (1 - discount_pct / 100), 2) if discount_pct else price
        rating = round(random.uniform(3.3, 5.0), 1)
        review_count = random.randint(3, 480)
        stock = random.randint(0, 40)

        image_url = random.choice(REAL_IMAGES[(category, color)])
        image_path = f"{IMAGE_DIR}/product_{i+1}.jpg"
        with open(image_path, "wb") as f:
            f.write(url_cache[image_url])

        rows.append(
            (
                name, brand, category, color, size, price, image_path, "unisex",
                description, mrp, discount_pct, rating, review_count, stock,
            )
        )

    cur.executemany(
        """
        INSERT INTO products (
            name, brand, category, color, size, price, image_path, gender,
            description, mrp, discount_pct, rating, review_count, stock
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    conn.commit()
    conn.close()
    print(f"Seeded {len(rows)} products into {DB_PATH}, images saved to {IMAGE_DIR}/")


def get_connection():
    return sqlite3.connect(DB_PATH)


if __name__ == "__main__":
    seed()
    init_users()
