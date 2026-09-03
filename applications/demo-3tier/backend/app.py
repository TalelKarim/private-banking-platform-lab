import json
import os
import socket
import time
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg

DB_HOST = os.environ.get("DB_HOST", "demo-postgres")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_USER = os.environ["POSTGRESQL_USER"]
DB_PASSWORD = os.environ["POSTGRESQL_PASSWORD"]
DB_NAME = os.environ["POSTGRESQL_DATABASE"]
LISTEN_PORT = int(os.environ.get("PORT", "8080"))

DSN = f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD} connect_timeout=3"

SEED = [
    ("AAPL", 25, Decimal("226.41")),
    ("BNP.PA", 80, Decimal("77.32")),
    ("MSFT", 18, Decimal("512.88")),
    ("SGO.PA", 45, Decimal("96.14")),
]


def connect():
    return psycopg.connect(DSN)


def initialise_database():
    last_error = None
    for attempt in range(1, 61):
        try:
            with connect() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        CREATE TABLE IF NOT EXISTS positions (
                            symbol varchar(16) PRIMARY KEY,
                            quantity integer NOT NULL CHECK (quantity >= 0),
                            price numeric(14,2) NOT NULL CHECK (price >= 0)
                        )
                        """
                    )
                    cur.executemany(
                        """
                        INSERT INTO positions(symbol, quantity, price)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (symbol) DO NOTHING
                        """,
                        SEED,
                    )
                conn.commit()
            print(f"database initialised through {DB_HOST}:{DB_PORT}/{DB_NAME}", flush=True)
            return
        except Exception as exc:  # startup retry is intentionally visible in logs
            last_error = exc
            print(f"database not ready (attempt {attempt}/60): {exc}", flush=True)
            time.sleep(2)
    raise RuntimeError(f"database did not become ready: {last_error}")


def portfolio_payload():
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT symbol, quantity, price FROM positions ORDER BY symbol")
            rows = cur.fetchall()
    items = []
    total = Decimal("0")
    for symbol, quantity, price in rows:
        market_value = Decimal(quantity) * price
        total += market_value
        items.append(
            {
                "symbol": symbol,
                "quantity": quantity,
                "price": float(price),
                "market_value": float(market_value),
            }
        )
    return {
        "application": "private-banking-demo-3tier",
        "served_by": socket.gethostname(),
        "database": f"{DB_HOST}/{DB_NAME}",
        "positions": items,
        "total_market_value": float(total),
    }


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, payload):
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            try:
                with connect() as conn:
                    conn.execute("SELECT 1")
                self.send_json(200, {"status": "ok"})
            except Exception as exc:
                self.send_json(503, {"status": "database-unavailable", "error": str(exc)})
            return
        if self.path == "/api/portfolio":
            try:
                self.send_json(200, portfolio_payload())
            except Exception as exc:
                self.send_json(500, {"error": str(exc)})
            return
        self.send_json(404, {"error": "not-found"})

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    initialise_database()
    print(f"backend listening on 0.0.0.0:{LISTEN_PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()
