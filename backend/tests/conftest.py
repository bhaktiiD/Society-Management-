"""Test harness.

SAFETY: tests build their OWN engine from TEST_DATABASE_URL and refuse to run
unless it points at localhost and the database name contains "test". They never
touch database.engine / DATABASE_URL (which may be the real Supabase project).
Run, e.g.:

    set TEST_DATABASE_URL=postgresql+psycopg://postgres:<pw>@localhost:5432/societyos_test
    pytest
"""
import os
import uuid
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url
from sqlalchemy.orm import sessionmaker

TEST_URL = os.getenv("TEST_DATABASE_URL")
if not TEST_URL:
    pytest.skip("TEST_DATABASE_URL not set", allow_module_level=True)

_url = make_url(TEST_URL)
if _url.host not in ("localhost", "127.0.0.1") or "test" not in (_url.database or ""):
    raise RuntimeError(
        "Refusing to run: TEST_DATABASE_URL must be localhost and the database "
        "name must contain 'test'"
    )

os.environ.setdefault("DATABASE_URL", TEST_URL)
os.environ["RATE_LIMIT_PER_MIN"] = "0"
os.environ["RAZORPAY_KEY_ID"] = "rzp_test_dummy"
os.environ["RAZORPAY_KEY_SECRET"] = "test_secret"
os.environ["RAZORPAY_WEBHOOK_SECRET"] = "whsec_test"

import auth  # noqa: E402
import deps  # noqa: E402
from database import Base  # noqa: E402
import models  # noqa: E402
from main import app  # noqa: E402

engine = create_engine(TEST_URL)
TestSession = sessionmaker(bind=engine, autocommit=False, autoflush=False)


@pytest.fixture(autouse=True)
def fresh_db():
    import billing_service

    deps._verified_users.clear()
    deps._claim_checked.clear()
    billing_service._last_run.clear()
    Base.metadata.drop_all(engine)
    with engine.begin() as conn:
        conn.exec_driver_sql("CREATE EXTENSION IF NOT EXISTS btree_gist")
    Base.metadata.create_all(engine)
    yield


def _override_db():
    db = TestSession()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[deps.get_db] = _override_db


from fastapi import Header  # noqa: E402


# Tests authenticate by header; real JWT verification is exercised in prod.
def _fake_user(
    x_test_sub: str = Header(),
    x_test_email: str = Header(),
    x_test_unverified: str = Header(default=""),
):
    return {
        "sub": x_test_sub,
        "email": x_test_email,
        "user_metadata": {
            "email_verified": not x_test_unverified,
            "full_name": x_test_email.split("@")[0],
        },
    }


app.dependency_overrides[auth.get_current_user] = _fake_user


@pytest.fixture()
def client():
    return TestClient(app)


@pytest.fixture()
def db():
    s = TestSession()
    yield s
    s.close()


class Actor:
    def __init__(self, email):
        self.id = uuid.uuid4()
        self.email = email
        self.headers = {"x-test-sub": str(self.id), "x-test-email": email}


@pytest.fixture()
def world(client, db):
    """Society S1 with flat A-101 (owner-occupied by `owner`), flat B-202 rented
    (non-resident `landlord`, resident `tenant`), plus a secretary and a guard.
    A second society S2 with its own secretary, for cross-society checks."""
    s1 = models.Society(name="S1")
    s2 = models.Society(name="S2")
    db.add_all([s1, s2])
    db.flush()
    a101 = models.Flat(society_id=s1.id, flat_number="A-101")
    b202 = models.Flat(society_id=s1.id, flat_number="B-202")
    x1 = models.Flat(society_id=s2.id, flat_number="X-1")
    db.add_all([a101, b202, x1])
    db.flush()

    people = {n: Actor(f"{n}@example.com") for n in
              ["secretary", "owner", "landlord", "tenant", "guard", "stranger", "secretary2"]}
    for p in people.values():
        db.add(models.User(id=p.id, email=p.email, full_name=p.email.split("@")[0]))
    db.flush()

    start = date.today() - timedelta(days=30)
    db.add_all([
        models.SocietyAdminMembership(society_id=s1.id, user_id=people["secretary"].id),
        models.SocietyAdminMembership(society_id=s2.id, user_id=people["secretary2"].id),
        models.GuardMembership(society_id=s1.id, user_id=people["guard"].id),
        models.FlatMembership(flat_id=a101.id, user_id=people["owner"].id, kind="owner", is_resident=True, start_date=start),
        models.FlatMembership(flat_id=b202.id, user_id=people["landlord"].id, kind="owner", is_resident=False, start_date=start),
        models.FlatMembership(flat_id=b202.id, user_id=people["tenant"].id, kind="tenant", is_resident=True, start_date=start),
    ])
    db.commit()
    return {"s1": s1.id, "s2": s2.id, "a101": a101.id, "b202": b202.id, "x1": x1.id, **people}
