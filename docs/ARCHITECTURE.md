# SocietyOS Architecture

## 1. System overview

```mermaid
flowchart LR
    App["Flutter app (Android)<br/>Riverpod, go_router, Dio"]
    API["FastAPI backend<br/>modular monolith"]
    Auth["Supabase Auth<br/>email + Google"]
    DB[("PostgreSQL<br/>Supabase")]
    RZP["Razorpay<br/>test mode"]
    FCM["Firebase Cloud Messaging<br/>optional"]

    App -- "sign in / refresh token" --> Auth
    App -- "REST + Bearer JWT" --> API
    App -- "checkout SDK" --> RZP
    API -- "verify JWT via JWKS" --> Auth
    API -- "SQLAlchemy" --> DB
    API -- "create order, fetch payment" --> RZP
    RZP -- "signed webhook" --> API
    API -. "push if key configured" .-> FCM
    FCM -. "notification" .-> App
```

The app never talks to the database directly. It authenticates with Supabase, then calls the backend with the Supabase access token. The backend verifies the token, applies authorization, and owns all business rules.

## 2. Data model

Identity is separate from roles. `users.id` equals the Supabase auth user id. Roles are dated or revocable memberships.

```mermaid
erDiagram
    SOCIETIES ||--o{ FLATS : has
    SOCIETIES ||--o{ SOCIETY_ADMIN_MEMBERSHIPS : grants
    SOCIETIES ||--o{ GUARD_MEMBERSHIPS : grants
    SOCIETIES ||--o{ MAINTENANCE_PLANS : sets
    SOCIETIES ||--o{ INVITES : issues
    SOCIETIES ||--o{ NOTICES : posts
    SOCIETIES ||--o{ SOCIETY_CONTACTS : lists
    SOCIETIES ||--o{ AMENITIES : offers
    SOCIETIES ||--o{ CHARGES : bills
    SOCIETIES ||--o{ COMPLAINTS : receives
    SOCIETIES ||--o{ GUEST_REQUESTS : logs
    USERS ||--o{ FLAT_MEMBERSHIPS : holds
    USERS ||--o{ SOCIETY_ADMIN_MEMBERSHIPS : holds
    USERS ||--o{ GUARD_MEMBERSHIPS : holds
    USERS ||--o{ DEVICE_TOKENS : registers
    USERS ||--o{ AUDIT_EVENTS : acts
    FLATS ||--o{ FLAT_MEMBERSHIPS : "occupied by"
    FLATS ||--o{ CHARGES : billed
    FLATS ||--o{ GUEST_REQUESTS : visited
    FLATS ||--o{ BOOKINGS : books
    FLATS ||--o{ INVITES : "invite targets"
    USERS ||--o{ CHARGES : "responsible for"
    CHARGES ||--o| CHARGES : "late fee of"
    CHARGES ||--o{ PAYMENT_INTENTS : "paid via"
    CHARGES ||--o{ PAYMENT_ALLOCATIONS : "receives"
    PAYMENT_INTENTS ||--o{ GATEWAY_PAYMENTS : confirms
    GATEWAY_PAYMENTS ||--o| PAYMENT_ALLOCATIONS : "allocated once"
    AMENITIES ||--o{ BOOKINGS : "booked as"
    USERS ||--o{ COMPLAINTS : raises
    USERS ||--o{ BOOKINGS : "booked by"

    USERS {
        uuid id PK
        string email UK
        string full_name
        string phone
    }
    SOCIETIES {
        int id PK
        string name
        int maintenance_due_day
        date billing_started_on
    }
    FLATS {
        int id PK
        int society_id FK
        string flat_number
        string flat_type
    }
    FLAT_MEMBERSHIPS {
        int id PK
        int flat_id FK
        uuid user_id FK
        string kind
        bool is_resident
        date start_date
        date end_date
    }
    SOCIETY_ADMIN_MEMBERSHIPS {
        int id PK
        int society_id FK
        uuid user_id FK
        datetime revoked_at
    }
    GUARD_MEMBERSHIPS {
        int id PK
        int society_id FK
        uuid user_id FK
        datetime revoked_at
    }
    INVITES {
        int id PK
        int society_id FK
        string email
        string role
        int flat_id FK
        datetime accepted_at
    }
    MAINTENANCE_PLANS {
        int id PK
        int society_id FK
        string flat_type
        bigint amount_paise
        bigint penalty_paise
    }
    CHARGES {
        int id PK
        int society_id FK
        int flat_id FK
        string charge_type
        bigint amount_paise
        bigint late_fee_paise
        date due_date
        date period
        uuid responsible_user_id FK
        int parent_charge_id FK
    }
    PAYMENT_INTENTS {
        int id PK
        int charge_id FK
        uuid user_id FK
        bigint amount_paise
        string idempotency_key
        string razorpay_order_id UK
        string status
    }
    GATEWAY_PAYMENTS {
        int id PK
        int intent_id FK
        string razorpay_payment_id UK
        bigint amount_paise
    }
    PAYMENT_ALLOCATIONS {
        int id PK
        int gateway_payment_id FK
        int charge_id FK
        bigint amount_paise
    }
    WEBHOOK_EVENTS {
        int id PK
        string event_id UK
        string event_type
        jsonb payload
    }
    GUEST_REQUESTS {
        int id PK
        int society_id FK
        int flat_id FK
        string guest_name
        string status
        datetime expires_at
        uuid decided_by FK
    }
    COMPLAINTS {
        int id PK
        int society_id FK
        int flat_id FK
        uuid created_by FK
        string category
        string status
    }
    AMENITIES {
        int id PK
        int society_id FK
        string name
    }
    BOOKINGS {
        int id PK
        int amenity_id FK
        int flat_id FK
        uuid booked_by FK
        date booking_date
        string slot
        string status
    }
    NOTICES {
        int id PK
        int society_id FK
        string title
        bool pinned
    }
    SOCIETY_CONTACTS {
        int id PK
        int society_id FK
        string name
        string phone
        string category
    }
    DEVICE_TOKENS {
        int id PK
        uuid user_id FK
        string token UK
    }
    AUDIT_EVENTS {
        int id PK
        uuid actor_user_id FK
        int society_id FK
        string action
        string resource_type
    }
```

`webhook_events` has no foreign keys; it stores raw deliveries keyed by the gateway event id.

Database constraints that carry business rules:

| Constraint | Rule it enforces |
|---|---|
| `uq_charge_maintenance_period` (partial unique) | One maintenance bill per flat per month |
| `uq_charge_late_fee_parent` (partial unique) | At most one late fee per bill |
| `uq_intents_user_idem` | Same client attempt gives the same payment intent |
| `gateway_payments.razorpay_payment_id` unique | A gateway payment is recorded once |
| `payment_allocations.gateway_payment_id` unique | A payment is allocated once |
| `webhook_events.event_id` unique | A webhook delivery is processed once |
| `uq_booking_slot_confirmed` (partial unique) | No double booking of a hall slot |
| `uq_admin_active`, `uq_guard_active` (partial unique) | One active admin or guard grant per person per society |
| `ck_*_amount_positive`, status and kind checks | No zero or negative money, no invalid states |

## 3. Sign-in and authorization

```mermaid
sequenceDiagram
    participant U as User
    participant A as Flutter app
    participant S as Supabase Auth
    participant B as FastAPI
    participant D as PostgreSQL

    U->>A: Sign in (email or Google)
    A->>S: Authenticate
    S-->>A: Access token (JWT) + refresh token
    A->>B: GET /me with Bearer JWT
    B->>S: Fetch JWKS (cached), verify signature, issuer, audience, expiry
    B->>D: Find or create user by token sub
    B->>D: Is email verified? Any unclaimed invite for it?
    alt verified email with invite
        B->>D: Create membership (owner/tenant/secretary/guard), mark invite accepted
    end
    B->>D: Load current memberships (dates, revoked_at)
    B-->>A: profile, roles, status active or pending
    A->>A: go_router redirect: pending screen, or role home
    Note over A,B: Later request, e.g. POST /secretary/charges
    A->>B: Request with Bearer JWT
    B->>D: require_secretary: live lookup of admin membership
    alt no active membership
        B-->>A: 403 plain-language message
    else allowed
        B-->>A: result
    end
```

Key points:
- A valid token only proves identity. With no membership the user is `pending` and sees a waiting screen.
- An invite is claimed only when the email is verified, so nobody can take an owner's invite by signing up first with that address.
- Membership is read from the database on each request, so revoking access works immediately and does not wait for token expiry.
- When a request returns 401, the Dio interceptor refreshes the Supabase session once and retries.

## 4. Payment flow (PayEngine)

```mermaid
sequenceDiagram
    participant A as Flutter app
    participant B as FastAPI
    participant D as PostgreSQL
    participant R as Razorpay

    A->>B: POST /payments/intents (charge_id, amount, idempotency_key)
    B->>D: Same key already used? return that intent
    B->>D: Check charge is mine and amount <= server balance
    B->>D: Insert intent (status created), commit
    B->>R: Create order
    B->>D: Save order id, status pending
    B-->>A: order_id, key_id, amount
    A->>R: Open checkout, user pays
    R-->>A: payment_id, signature
    A->>B: POST /payments/verify
    B->>B: Check checkout signature
    B->>R: Fetch payment: order, status captured, amount match
    B->>D: record_verified_payment()
    par Webhook, possibly duplicated
        R->>B: POST /webhooks/razorpay (signed)
        B->>B: Check webhook signature
        B->>D: Insert webhook_events row (unique event_id)
        alt event id already stored
            B-->>R: duplicate, no further work
        else new event
            B->>D: record_verified_payment()
        end
    end
    Note over B,D: record_verified_payment locks the charge row (FOR UPDATE),<br/>returns existing gateway_payment if the payment id is known,<br/>else inserts it and allocates min(amount, balance).
    A->>B: GET /payments/intents/id/status (recovery)
    B->>R: List order payments if intent still uncertain
    B->>D: record_verified_payment() if captured
    B-->>A: status, charge status, balance
```

Notes:
- The balance of a bill is never stored. It is the charge amount minus the sum of its allocations.
- Partial payments are normal: a bill is `outstanding`, `partial` or `paid` depending on the allocated total.
- Three paths can confirm a payment (client verify, webhook, status reconciliation). All call the same function and converge on one `gateway_payments` row through a unique constraint.
- The intent is committed before the gateway call, so a crash never leaves an unexplained gateway order.
- If the app is killed after paying, the status endpoint reconciles against Razorpay.

## 5. Monthly billing

```mermaid
flowchart TD
    Start["Request arrives<br/>(or admin taps Generate now)"] --> Gate{"Ran for this society<br/>in the last 2 minutes?<br/>(skipped if forced)"}
    Gate -- yes --> Skip["Skip"]
    Gate -- no --> Setup{"billing_started_on set?"}
    Setup -- no --> Skip
    Setup -- yes --> Lock["Per-society advisory lock"]
    Lock --> Loop["For each month from start to current month"]
    Loop --> Flat["For each flat with a type and a rate"]
    Flat --> Has{"Bill exists<br/>for flat + month?"}
    Has -- yes --> Next["Next flat"]
    Has -- no --> Owner{"Current owner?"}
    Owner -- no --> Count["Count as flat without owner"]
    Owner -- yes --> Create["Create maintenance charge:<br/>snapshot rate and late fee,<br/>responsible = owner,<br/>no late fee if already past due"]
    Create --> Next
    Next --> Late["Overdue, unpaid maintenance bills<br/>with a late fee and no fee yet"]
    Late --> Fee["Create one late_fee charge<br/>linked by parent_charge_id"]
    Fee --> Commit["Commit"]
```

Society-wide festival or repair charges use `POST /secretary/charges` without a flat id. The server creates one charge per flat, billing the owner or the tenant (falling back to the owner when a flat has no tenant), and reports skipped flats that have nobody to bill.

## 6. Key design decisions

| Decision | Reason |
|---|---|
| Modular monolith: one FastAPI app, one router module per area, shared services for billing and payments | A small team and a single deploy. Module boundaries keep it easy to read and to split later; microservices would add cost with no benefit at this size. |
| Memberships, not a role column | A person can be an owner of one flat, a tenant of another, and the secretary. Dated memberships also preserve history and let moving out end a role without deleting anything. |
| Live membership check on every request | Revocation is immediate. The cost is one query per request, accepted for correctness. |
| Invite-based onboarding with verified email | Google or email sign-in proves identity only. Access comes from the admin registering the email. |
| All money in integer paise | No floating-point rounding. Amounts are `BIGINT` with positive-amount checks. |
| Snapshots on charges (responsible user, rate, late fee) | Later move-outs or rate edits must not rewrite past bills. |
| Derived balances from append-only allocations | No stored balance to drift out of sync. Payments and allocations are never edited. |
| Idempotency plus database constraints | Retries, duplicate webhooks and races are normal in payments. Unique indexes make correctness hold even if application code has a bug or two requests collide. |
| Server is the source of truth for amounts | The client sends an amount, the server checks it against the balance and confirms with Razorpay; client status claims are not trusted. |
| Lazy billing instead of a scheduler | No free always-on job runner. The engine is idempotent (unique indexes, advisory lock), so running it from requests is safe. Throttled to once per 2 minutes per society, except when the admin changes rates or taps Generate. Documented shortcut; replace with a scheduled job. |
| Polling instead of push | FCM needs Firebase files and device setup. The database is the source of truth and the app polls (the guest approval and guard screens refresh every 8 seconds). Push is optional and fails silently, so it never breaks a request. |
| Conditional UPDATE for guest decisions | `UPDATE ... WHERE status='pending' AND not expired` means the first valid answer wins atomically when two residents respond. |
| Partial unique index for hall bookings | The database, not application code, prevents double booking under concurrent requests. |
| 404 instead of 403 for others' records | Does not reveal that a bill or visitor request exists. |
| Audit events | Admin actions, invite claims and payments are recorded in `audit_events`. |

## 7. Flutter structure

```
mobile/lib/
  main.dart            Supabase init, ProviderScope, app widget
  core/
    api_client.dart    Dio provider, token interceptor, errorMessage()
    router.dart        go_router config and auth/role redirects
    theme.dart         Material theme
    design.dart        spacing, colours, shared constants
    widgets.dart       shared widgets (cards, buttons, empty and error states)
    format.dart        money (paise to rupees) and date formatting
  models/models.dart   hand-written model classes with fromJson
  features/
    auth/              login, sign-up, pending and error screens, auth repository
    home/              role-aware shell with bottom navigation, resident home
    bills/             bills list, pay controller (Razorpay checkout)
    guests/            resident approvals, guard screen
    notices/           notice list
    secretary/         dashboard, flats, flat detail, charges, maintenance rates
    complaints/        raise and track (residents), triage (admin)
    bookings/          hall booking and availability
    contacts/          emergency and useful contacts
    services/          entry screen for complaints, bookings, contacts
    profile/           view and edit profile, sign out
```

Each feature follows the same pattern: a repository class wraps the API calls and returns models, Riverpod providers expose the data and actions, and screens watch the providers.

- **State management:** Riverpod. Providers are compile-checked, easy to override in tests, and handle async loading and error states.
- **Routing:** go_router with a redirect that reads auth and profile state: loading, login, pending (no access yet), error, or home. A user holding several roles switches role in the shell.
- **Networking:** one shared Dio client. The interceptor attaches the Supabase access token and, on a 401, refreshes the session once and retries the request.
- **Error handling:** `errorMessage()` converts every error (timeouts, no connection, HTTP status, server `detail`, auth errors) into a plain sentence. Screens never show status codes or stack traces.
- **Design system:** `theme.dart`, `design.dart` and `widgets.dart` keep colours, spacing and components consistent across all features.
- **Models:** written by hand rather than generated, to keep the build simple and the parsing explicit.
