# SocietyOS API

Base URL: `http://localhost:8000` (interactive docs at `/docs`).

Authentication: every endpoint except the ones marked Public needs `Authorization: Bearer <Supabase access token>`.

Who may call:
- **Any user**: any signed-in user. Data is scoped to that person's own memberships, bills or flats.
- **Admin**: has an active society admin (secretary) membership.
- **Guard**: has an active guard membership.
- **Resident**: has a current flat membership with `is_resident = true` (owner living in the flat, or tenant).
- **Payer**: the person a bill was snapshotted to (`responsible_user_id`).

Money fields are integer paise. Errors return `{"detail": "<plain-language message>"}`. Authorization is checked against the database on every request.

## Health

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/health` | Public | Service liveness |
| GET | `/health/db` | Public | Database reachability |

## Auth and profile

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/auth/check-invite` | Public | Is this email pre-registered with an unclaimed invite (used before sign-up) |
| GET | `/me` | Any user | Profile, all current roles, status `active` or `pending`; claims pending invites for a verified email |
| PATCH | `/me` | Any user | Edit own name and phone |
| POST | `/me/device-token` | Any user | Register an FCM device token |

## Admin: society, flats, people, invites

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/secretary/society` | Admin | Society details |
| PATCH | `/secretary/society` | Admin | Rename the society |
| GET | `/secretary/flats` | Admin | Flats with type, current members and billing summary |
| POST | `/secretary/flats` | Admin | Add a flat |
| PUT | `/secretary/flats/{flat_id}/type` | Admin | Set flat type (1RK, 1BHK, 2BHK) |
| POST | `/secretary/memberships/{membership_id}/end` | Admin | End an owner or tenant membership (move-out); history is kept |
| GET | `/secretary/invites` | Admin | List invites |
| POST | `/secretary/invites` | Admin | Register a person by email as owner, tenant, secretary or guard |
| DELETE | `/secretary/invites/{invite_id}` | Admin | Withdraw an invite |

## Billing settings

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/secretary/billing` | Admin | Current rates, late fees and due day per flat type |
| PUT | `/secretary/billing/plans/{flat_type}` | Admin | Set monthly rate and fixed late fee for a flat type |
| PUT | `/secretary/billing/due-day` | Admin | Set the due day of the month for new bills |
| POST | `/secretary/billing/run` | Admin | Generate missing monthly bills and late fees now |

## Charges

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/secretary/charges` | Admin | Create a charge for one flat, or omit `flat_id` for a society-wide festival or repair charge billed to every flat |
| GET | `/secretary/charges` | Admin | List charges with paid, balance, status and overdue flag |
| GET | `/secretary/collections` | Admin | Dashboard totals derived from allocations |
| GET | `/charges` | Payer | My bills (only charges snapshotted to me) |
| GET | `/payments/history` | Any user | My payment history |

## Payments

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/payments/intents` | Payer | Create (or return the existing) payment intent and Razorpay order for full or partial amount; needs an idempotency key |
| POST | `/payments/verify` | Payer | Verify checkout signature, confirm with Razorpay, record and allocate the payment |
| GET | `/payments/intents/{intent_id}/status` | Payer | Recovery: reconcile an uncertain attempt with Razorpay and return bill status and balance |

## Guests (GateGuard)

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/guard/guests` | Guard | Log a visitor for a flat and request approval |
| GET | `/guard/guests` | Guard | Latest visitor requests in the society |
| POST | `/guard/guests/{guest_id}/check-in` | Guard | Check in an approved, unexpired visitor (single use) |
| POST | `/guard/guests/{guest_id}/check-out` | Guard | Check out a visitor |
| GET | `/guests/pending` | Resident | Visitors waiting for my answer |
| GET | `/guests/history` | Resident | Past visitors of my flat |
| POST | `/guests/{guest_id}/decision` | Resident | Approve or deny; first valid decision wins, otherwise 409 |

## Complaints

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/complaints` | Any user with a current flat membership | Raise a complaint (plumbing, electrical, lift, security, cleaning, parking, noise, other) |
| GET | `/complaints` | Any user | My complaints and their status |
| GET | `/secretary/complaints` | Admin | All complaints in the society |
| PATCH | `/secretary/complaints/{complaint_id}` | Admin | Change status (open, in progress, resolved) and add a note |

## Bookings

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/amenities` | Any user in a society | Bookable facilities, for example the community hall |
| GET | `/amenities/{amenity_id}/availability` | Any user in a society | Slot availability for the next 1 to 90 days (`days` query) |
| POST | `/bookings` | Resident | Book a morning or evening slot; a taken slot returns a conflict |
| GET | `/bookings/mine` | Any user | My bookings |
| DELETE | `/bookings/{booking_id}` | Booker | Cancel my booking |
| GET | `/secretary/bookings` | Admin | All bookings in the society |
| POST | `/secretary/bookings/{booking_id}/cancel` | Admin | Cancel any booking |

## Contacts

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/contacts` | Any user in a society | Emergency and useful contacts |
| POST | `/secretary/contacts` | Admin | Add a contact |
| PUT | `/secretary/contacts/{contact_id}` | Admin | Edit a contact |
| DELETE | `/secretary/contacts/{contact_id}` | Admin | Delete a contact |

## Notices

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/notices` | Any user in a society | Notices of my societies, pinned first |
| POST | `/secretary/notices` | Admin | Post a notice |
| DELETE | `/secretary/notices/{notice_id}` | Admin | Delete a notice |

## Webhooks

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/webhooks/razorpay` | Razorpay (signature) | Receive `payment.captured`, `order.paid`, `payment.failed`. Rejects a bad signature with 400, stores each event id once and answers `duplicate` on a retry, and records the payment idempotently. Needs a public URL |

## Status codes worth knowing

| Code | Meaning in this API |
|---|---|
| 401 | Missing, invalid or expired token |
| 403 | Signed in but lacking the admin or guard role |
| 404 | Not found, or not yours (deliberately the same) |
| 409 | Already handled: bill already paid, guest already answered, slot taken, duplicate charge |
| 422 | Validation failed, for example amount above the balance |
| 502 | Payment gateway unavailable |
