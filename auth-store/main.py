"""
TMLink Auth Store
-----------------
Lightweight microservice that persists the TMLink session cookie
and login state so n8n agents can share it across executions.

All configuration is loaded from environment variables.
"""

import json
import logging
import os
import threading
from datetime import datetime, timezone, timedelta

from fastapi import FastAPI
from pydantic import BaseModel

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("auth-store")

DATA_PATH = os.getenv("DATA_PATH", "/data/auth.json")
TMLINK_EMAIL = os.getenv("TMLINK_EMAIL", "")
LOGIN_COOLDOWN_MINUTES = int(os.getenv("LOGIN_COOLDOWN_MINUTES", "5"))

_lock = threading.Lock()

_DEFAULT_STATE: dict = {
    "cookie": "",
    "email": TMLINK_EMAIL,
    "status": "idle",
    "last_login_attempt": None,
    "login_attempt_count": 0,
    "login_blocked": "no",
    "approvalToken": "",
}


def _read() -> dict:
    try:
        with open(DATA_PATH) as f:
            data = json.load(f)
        # Back-fill any keys added after initial write
        for k, v in _DEFAULT_STATE.items():
            data.setdefault(k, v)
        # Use env email only when nothing is stored yet
        if not data.get("email"):
            data["email"] = TMLINK_EMAIL
        return data
    except Exception as exc:
        log.warning("Could not read auth state (%s), using defaults", exc)
        return dict(_DEFAULT_STATE)


def _write(data: dict) -> None:
    os.makedirs(os.path.dirname(DATA_PATH) or ".", exist_ok=True)
    with open(DATA_PATH, "w") as f:
        json.dump(data, f, indent=2)


app = FastAPI(title="TMLink Auth Store", version="0.2.0")


class AuthUpdate(BaseModel):
    cookie: str | None = None
    email:  str | None = None
    status: str | None = None
    linkage_message: str | None = None
    trigger_login: bool = False
    approvalToken: str | None = None


@app.get("/auth")
def get_auth() -> dict:
    with _lock:
        return _read()


@app.post("/auth")
def set_auth(update: AuthUpdate) -> dict:
    with _lock:
        data = _read()

        if update.cookie is not None:
            data["cookie"] = update.cookie
        if update.email is not None:
            data["email"] = update.email
        if update.status is not None:
            data["status"] = update.status
        if update.linkage_message is not None:
            data["linkage_message"] = update.linkage_message
        if update.approvalToken is not None:
            data["approvalToken"] = update.approvalToken

        if update.trigger_login:
            now = datetime.now(timezone.utc)
            last_str = data.get("last_login_attempt")
            if last_str:
                last_dt = datetime.fromisoformat(last_str)
                if last_dt.tzinfo is None:
                    last_dt = last_dt.replace(tzinfo=timezone.utc)
                if now - last_dt < timedelta(minutes=LOGIN_COOLDOWN_MINUTES):
                    data["login_blocked"] = "yes"
                    log.info("Login blocked (cooldown active, next allowed in %ds)",
                             int((timedelta(minutes=LOGIN_COOLDOWN_MINUTES) - (now - last_dt)).total_seconds()))
                else:
                    data["last_login_attempt"] = now.isoformat()
                    data["login_attempt_count"] = data.get("login_attempt_count", 0) + 1
                    data["login_blocked"] = "no"
                    log.info("Login triggered (attempt #%d)", data["login_attempt_count"])
            else:
                data["last_login_attempt"] = now.isoformat()
                data["login_attempt_count"] = 1
                data["login_blocked"] = "no"
                log.info("First login attempt")

        _write(data)
        return data


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
