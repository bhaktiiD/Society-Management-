import logging
import os
import time
from collections import defaultdict, deque

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from deps import get_db  # noqa: F401
from routers import (
    billing,
    bookings,
    complaints,
    contacts,
    emergencies,
    gate_passes,
    guest,
    me,
    meetings,
    payments,
    polls,
    resident,
    secretary,
)

log = logging.getLogger("societyos")

# API docs/schema reveal every route; expose only when explicitly enabled (dev).
_DOCS = os.getenv("ENABLE_DOCS") == "1"
app = FastAPI(
    title="SocietyOS API",
    docs_url="/docs" if _DOCS else None,
    redoc_url=None,
    openapi_url="/openapi.json" if _DOCS else None,
)

# shortcut: in-memory per-process limiter, swap for Redis/gateway limits when running >1 worker.
_RATE = int(os.getenv("RATE_LIMIT_PER_MIN", "120"))  # 0 disables (tests)
_STRICT = {"/auth/check-invite": 10}  # unauthenticated, enumeration-prone
_hits: dict[tuple[str, str], deque] = defaultdict(deque)


@app.middleware("http")
async def guard(request: Request, call_next):
    if _RATE:
        ip = request.client.host if request.client else "?"
        path = request.url.path
        limit = _STRICT.get(path, _RATE)
        q = _hits[(ip, path if path in _STRICT else "*")]
        now = time.monotonic()
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= limit:
            return JSONResponse({"detail": "Too many requests. Please slow down."}, status_code=429)
        q.append(now)
    if int(request.headers.get("content-length") or 0) > 1_000_000:  # avatar cap is 400KB
        return JSONResponse({"detail": "Request too large."}, status_code=413)
    try:
        resp = await call_next(request)
    except Exception:
        log.exception("Unhandled error")  # never leak stack traces/SQL to the client
        resp = JSONResponse({"detail": "Something went wrong. Please try again."}, status_code=500)
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Cache-Control"] = resp.headers.get("Cache-Control", "no-store")
    resp.headers["Strict-Transport-Security"] = "max-age=31536000"
    return resp


app.include_router(me.router)
app.include_router(secretary.router)
app.include_router(billing.router)
app.include_router(complaints.router)
app.include_router(bookings.router)
app.include_router(contacts.router)
app.include_router(polls.router)
app.include_router(meetings.router)
app.include_router(resident.router)
app.include_router(payments.router)
app.include_router(guest.router)
app.include_router(emergencies.router)
app.include_router(gate_passes.router)


@app.get("/health")
def health():
    return {"status": "ok", "service": "SocietyOS"}
