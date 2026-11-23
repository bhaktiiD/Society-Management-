# SocietyOS Demo Script (6 minutes)

Goal: show a real, end-to-end product and the engineering decisions behind it. Sign in as the admin first. Keep a second device or account (resident, guard) ready for the guest and payment steps.

## Timeline

| Time | Screen | Do | Say |
|---|---|---|---|
| 0:00 | Admin home | Open the dashboard: billed, collected, outstanding. | "Three roles, one app: admin, resident, guard. These totals are derived from payment allocations, never stored, so they cannot drift." |
| 0:45 | People / flat detail | Register a person by email as tenant of a flat. | "Signing in with Google gives no access by itself. The admin pre-registers the email, and the invite is claimed on first login only if the email is verified. Roles are dated memberships, not a role column." |
| 1:30 | Charges | Create a society-wide festival charge with a due date. | "One action bills every flat: the owner or the tenant, falling back to the owner. Flats with nobody registered are reported back, and a double-tap is rejected as a duplicate." |
| 2:15 | Maintenance | Show rates per flat type, due day, late fee. Change a rate, tap Generate now. | "Rates are per flat type. Each bill snapshots the rate and late fee, so editing a rate never rewrites old bills. Late fee is a fixed amount, once per overdue unpaid bill." |
| 3:00 | Resident Bills | Switch to a resident. Pay part of a bill with Razorpay test card, then pay the rest. | "Amounts are integer paise. The server checks the amount against the real balance and confirms the payment with Razorpay, it does not trust the app. Partial payments are allocations on the bill." |
| 3:45 | Talking point | No screen needed. | "Razorpay can deliver a webhook twice, or alongside the app's verify call. The event id is unique in the database and so is the payment id and its allocation, so the second delivery changes nothing. If the app dies mid-payment, a status endpoint reconciles with Razorpay." |
| 4:15 | Guard and resident Guests | Guard logs a visitor; resident approves on the other device. Try answering twice. | "First valid decision wins through one conditional UPDATE, so two family members tapping at once cannot both succeed. Screens refresh every 8 seconds; push is optional." |
| 5:00 | Services | Resident raises a complaint; admin moves it to in progress. Book the hall, then try the same slot again. | "Double booking is blocked by a partial unique index in the database, not just by app code." |
| 5:40 | Profile | Edit name and phone, then sign out. | "Roles are live: end a membership and access is gone on the next request, no waiting for token expiry." |
| 6:00 | Wrap up | | "Tested backend suite of 99 tests plus 49 Flutter tests, clean error messages, honest shortcuts listed in the README." |

## Trade-offs to mention

- **Lazy billing:** monthly bills are created on requests, throttled to once per 2 minutes per society, because there is no free always-on scheduler. It is idempotent, so safe. A cron job is the next step.
- **Polling over push:** FCM needs Firebase files; the database is the source of truth and push never breaks a request.
- **Latency:** the Supabase project is in Europe, about 0.3 s per query from India. I reduced round trips (fewer commits, claim-invite check once a minute, throttled billing). Moving the region is the real fix.
- **Test-mode payments only,** Android only, and the webhook needs a tunnel locally.
- **Hand-written models** instead of code generation: simpler build, explicit parsing, more typing.

## Likely interview questions

**Why Riverpod?** Providers are compile-checked, independent of the widget tree, easy to override in tests, and give async loading and error states without boilerplate. I did not need a heavier pattern such as Bloc for this size.

**Why go_router?** Declarative routes and a single `redirect` that reads auth and profile state: loading, login, pending (signed in but no access), home. Auth-driven navigation lives in one place instead of scattered pushes.

**What does the Dio interceptor do?** It attaches the Supabase access token to every request. On a 401 it refreshes the session once and retries the request; a flag prevents retry loops. If refresh fails, the original error surfaces and the user is asked to sign in again.

**How do you handle errors?** One function, `errorMessage()`, turns any error (timeouts, offline, HTTP status, server message, auth errors) into a plain sentence. The backend also returns plain-language `detail` messages. Users never see a status code or a stack trace. It has unit tests.

**How is it tested?** Backend: 92 pytest tests against a local PostgreSQL database (the suite refuses to run against anything not on localhost with "test" in the name). They cover access control, guest races, billing and late fees, society-wide charges, payments including duplicate webhooks, bookings, complaints and contacts. Mobile: `flutter analyze`, an error-message unit test and a widget test.

**Performance and latency?** Each query pays about 0.3 s because the database is far away, so I cut round trips: skip commits when nothing changed, check invites once a minute per user, throttle billing, and aggregate totals in the database. A closer region would help most.

**Security?** Supabase JWT is verified in the backend against the JWKS (signature, issuer, audience, expiry). Authorization is a live database check on every request. Invites need a verified email. Secrets stay on the server; the app has only the public Razorpay key id. Webhooks are signature-checked, amounts are validated against the server balance, and other people's records return 404.

**Why memberships instead of roles?** One person can own one flat, rent another and be the secretary. Dates keep history and let a move-out end access cleanly.

**Why not store the balance?** It would drift. The balance is the amount minus allocations, and allocations are append-only.

**What would you do next?** A scheduled billing job, push notifications end to end, refunds and receipts, a closer database region, CI running the tests.

## Pre-demo checklist

- [ ] Backend running: `uvicorn main:app --host 0.0.0.0 --port 8000`; `/health` and `/health/db` return ok.
- [ ] API URL reachable from the phone: USB with `adb reverse tcp:8000 tcp:8000`, or Wi-Fi with `--dart-define=API_BASE_URL=http://<pc-lan-ip>:8000` (same network, firewall allows port 8000).
- [ ] Supabase project awake (free projects pause when idle); sign in once beforehand.
- [ ] Razorpay test keys set in `.env`; do one test payment before the demo.
- [ ] Webhook demo only: tunnel running and its `/webhooks/razorpay` URL saved in the Razorpay test dashboard.
- [ ] Demo data loaded (`seed_data.py`, `seed_demo.py`). Seeded residents cannot sign in, so register real resident and guard emails from the admin screen beforehand and confirm they can sign in.
- [ ] Second device or emulator ready for the guard and resident steps.
- [ ] Phone charged, screen timeout raised, notifications silenced, charger and cable in the bag.
- [ ] Backend tests green (`pytest` with `TEST_DATABASE_URL`) and `flutter analyze` clean.
- [ ] Open the README and ARCHITECTURE diagrams in a browser tab as a fallback.
