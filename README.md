# SocietyOS

SocietyOS is a residential-society management app. A Flutter Android client talks to a FastAPI backend backed by PostgreSQL on Supabase. Residents pay maintenance and approve guests, guards log visitors, and the society admin runs billing, people, notices, complaints and hall bookings.

Authentication uses Supabase Auth (email and Google). Payments use Razorpay in test mode.

## Features

**Admin (secretary)**
- Dashboard with collection totals (billed, collected, outstanding) derived from payment allocations.
- Register people by email (invite) as owner, tenant, secretary or guard; end a membership on move-out with history kept.
- Manage flats and flat types (1RK, 1BHK, 2BHK).
- Monthly maintenance: a rate and a fixed late fee per flat type, a due day, automatic monthly bills, one late fee per overdue unpaid bill.
- One-off charges for one flat, or society-wide festival and repair charges that bill every flat.
- Post and delete notices (pinned or normal).
- Triage complaints (open, in progress, resolved, with a note); view and cancel hall bookings.
- Manage emergency and useful contacts.

**Owner and tenant**
- See own bills, pay in full or in part with Razorpay checkout, view payment history.
- Approve or deny visitors at the gate (first valid answer wins); see visitor history.
- Raise complaints and track their status.
- Book the community hall (morning or evening slot, residents only); cancel own bookings.
- Read notices, call society contacts, edit own profile.

**Guard**
- Log a visitor for a flat, see the latest 100 visitor requests, check visitors in and out once approved.

## Tech stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (Dart 3.10), Riverpod, go_router, Dio, supabase_flutter, razorpay_flutter |
| Backend | Python, FastAPI, SQLAlchemy 2, Alembic, PyJWT, psycopg |
| Database | PostgreSQL on Supabase |
| Auth | Supabase Auth (email + Google), JWT verified in the backend against the Supabase JWKS |
| Payments | Razorpay (test mode), signed webhooks |
| Push (optional) | Firebase Cloud Messaging via firebase-admin |
| Tests | pytest + httpx (backend), flutter_test (mobile) |

## Repository layout

```
societyos/
  backend/
    main.py              app wiring and /health endpoints
    models.py            SQLAlchemy tables and DB constraints
    deps.py              auth dependencies, live membership checks
    billing_service.py   monthly maintenance and late-fee engine
    payments_service.py  idempotent payment recording and allocation
    gateway.py           Razorpay wrapper and signature checks
    push.py              optional FCM notifications
    routers/             one module per area (secretary, billing, payments, guest, ...)
    migrations/          Alembic migrations
    seed_data.py         society, flats, first admin invite
    seed_demo.py         demo residents, bills, payments, notices
    tests/               pytest suite
  mobile/
    lib/core/            api_client, router, theme, design, widgets, format
    lib/models/          hand-written models
    lib/features/        auth, home, bills, guests, notices, secretary,
                         complaints, bookings, contacts, services, profile
    test/                Flutter tests
  docs/                  ARCHITECTURE.md, API.md, DEMO.md
```

## Prerequisites

- Python 3.11+ and a Supabase project (free tier is enough)
- Flutter SDK (Dart ^3.10.7) and Android toolchain, an Android phone or emulator
- A Razorpay account in test mode (key id, key secret, webhook secret)
- Optional: Firebase project for push; a tunnel such as ngrok or cloudflared for webhooks

## Backend setup

```bash
cd backend
python -m venv venv
# Windows: venv\Scripts\activate    macOS/Linux: source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # then fill in the values below
alembic upgrade head
python seed_data.py
python seed_demo.py
uvicorn main:app --host 0.0.0.0 --port 8000
```

`.env` variables (placeholders only, never commit real values):

```
DATABASE_URL=<supabase postgres connection string>
RAZORPAY_KEY_ID=<rzp_test_...>
RAZORPAY_KEY_SECRET=<test secret>
RAZORPAY_WEBHOOK_SECRET=<webhook secret>
FIREBASE_CREDENTIALS=<path to service-account json, optional>
GUEST_APPROVAL_TTL_MINUTES=<minutes a guest request stays valid>
```

`seed_data.py` creates the society, flats and the first admin invite; edit the admin email in that file to your own first. `seed_demo.py` adds fake residents (`@demo.societyos` emails that cannot sign in), flats with types, rates, bills in every state, payments, notices and contacts. `python seed_demo.py --reset` removes the demo data.

Check it is up: `GET http://localhost:8000/health` and `/health/db`.

### Supabase setup

1. Authentication, Providers, Email: enable, and keep **Confirm email ON**. The backend only claims an invite for a verified email.
2. Authentication, Providers, Google: enable with your OAuth client id and secret.
3. Authentication, URL Configuration: add the redirect URL `io.supabase.societyos://login-callback/`.
4. If you use your own Supabase project, set its URL and public anon key in `mobile/lib/main.dart` and its URL in `backend/auth.py` (used to fetch the JWKS that verifies tokens).
5. Sign in with the admin email from `seed_data.py` so the invite is claimed and the admin role is granted.

## Mobile setup

```bash
cd mobile
flutter pub get
adb reverse tcp:8000 tcp:8000     # USB phone: lets the app reach the PC backend
flutter run
```

Over Wi-Fi, or if you cannot use `adb reverse`, point the app at your PC:

```bash
flutter run --dart-define=API_BASE_URL=http://<pc-lan-ip>:8000
```

The default API address is `http://localhost:8000`.

### Razorpay webhook (optional for demo)

Checkout verification works without a webhook. To demonstrate webhooks, expose the backend with a tunnel and register `https://<tunnel-host>/webhooks/razorpay` in the Razorpay test dashboard with events `payment.captured`, `order.paid` and `payment.failed`, using the same secret as `RAZORPAY_WEBHOOK_SECRET`.

## Tests

Backend (99 tests: access and guests, billing, bookings, society-wide charges, complaints, contacts, payments):

```bash
cd backend
export TEST_DATABASE_URL=postgresql+psycopg://<user>:<password>@localhost:5432/societyos_test
pytest
```

`TEST_DATABASE_URL` must point to a localhost database whose name contains `test`; the suite refuses to run otherwise, so it can never touch the real Supabase project. Without the variable the tests are skipped.

Mobile:

```bash
cd mobile
flutter analyze
flutter test
```

## Security

- Never commit `.env`, Firebase service-account files or any key. Only `.env.example` with placeholders is tracked.
- All secrets (Razorpay secret, webhook secret, database URL, Firebase credentials) live on the server only. The app receives only the public Razorpay key id.
- Razorpay keys are test-mode keys. Do not use live keys with this project.
- Authorization is checked against the database on every request, so removing a membership takes effect at once.
- Payment amounts are validated against the server-side balance and confirmed with the gateway; webhooks are signature-checked.
- Residents get 404 (not 403) for bills, visitors and payments that are not theirs.

## Limitations and next steps

- Supabase region is Europe, so every database query adds about 0.3 s from India. The backend batches work and skips unnecessary commits to limit round trips; moving the project to an Asia region would remove most of the delay.
- Payments are test-mode only.
- Android only; no iOS build.
- The Razorpay webhook needs a public URL, so a tunnel is required for a local demo.
- Push is optional: it is a silent no-op without a Firebase key, and the app polls instead.
- Billing runs lazily on requests rather than on a scheduler (documented shortcut). Next step: a scheduled job.
- Next: refund handling, receipts, full multi-society support (most endpoints use the first society a person administers), and CI for tests.
