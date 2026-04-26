# Plan: Xomify Social Feed — backend-interactions-and-notifications

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 4 (`backend-interactions-and-notifications`)
**Issue**: #27
**Status**: Ready
**Created**: 2026-04-22
**Last updated**: 2026-04-23
**Scope size**: L
**Repos touched**: `xomify-backend` (code), `xomify-infrastructure` (infra)
**Depends on**: 3 (`backend-shares`) — shares table + handlers already deployed
**Ships as**: 2 PRs in order — **PR-A (infra)** then **PR-B (backend)**. Mirrors the `backend-shares` rollout.

---

## Summary

Layer the signal loop and notification surface on top of `backend-shares`:
1. Finish wiring `xomify-share-interactions` (table already deployed, PK=`shareId`, SK=`email`) with a single-purpose `shares_react` handler + `share_interactions_dynamo` helper. Updates the `shares_feed` enrichment stub to real counts.
2. Add `xomify-device-tokens` table for APNs token storage, `device_tokens_register` + `device_tokens_unregister` handlers, and a new `notifications` service path on API Gateway.
3. Add `notifications_send` internal-invoke lambda that wraps APNs HTTP/2 using the `.p8` key pulled from SSM SecureString (aligned with the existing xomify SSM pattern — see **Secrets Manager vs SSM** below).
4. Add `cron_shares_digest` weekly EventBridge rule (Sunday 18:00 UTC) that scans active device tokens, builds a 7-day feed digest, and invokes `notifications_send`.
5. Threshold push: when `shares_react` takes the total reaction count on a share across 3 distinct friends (toggle-safe, idempotent), invoke `notifications_send` once per `(shareId, threshold)` pair.

Success = any reaction from iOS appears in feed enrichment within one round-trip; three distinct friends reacting fires exactly one push to the author; Sunday 18:00 UTC cron sends one digest push per opted-in user with an accurate 7-day count.

---

## Approach

### Locked context from the epic (do NOT re-litigate)

- **Signal loop**: per-share, per-viewer reaction tracked. Feed card shows `queuedCount` / `ratedCount` / `viewerHasQueued` / `viewerRating`.
- **Queue-threshold push**: APNs fires to `sharedBy` when distinct-reactor count first hits 3. Must be idempotent under simultaneous writes.
- **Ratings canonicalization**: a `rated` action upserts into existing `xomify-track-ratings` so ratings stay canonical.
- **Digest cadence**: **weekly, fixed UTC** for v1 — `digestTime` is NOT in the schema. Per-user time bucketing deferred.
- **APNs cert**: `.p8` at `~/Downloads/AuthKey_A5X4MKX38D.p8`, Key ID `A5X4MKX38D`. Do NOT commit. Must land in an AWS secret store before PR-B merges.

### Deviations from epic to flag to Dom

1. **Interactions table schema**: epic draft said `SK = viewerEmail#action` (composite). Deployed table uses `PK=shareId, SK=email` (one row per viewer per share). The deployed shape is cleaner — one row holds both queue+rate state as attributes. **Going with the deployed schema.**
2. **Handler name**: epic said `shares_interaction`. Both the iOS client (`reactToShare` → `POST /shares/react`) and the terraform stub (`lambdas_shares.tf` entry `react`) use `react`. **Going with `shares_react`** so the folder name maps cleanly to the already-declared function name `xomify-shares-react`.
3. **Secret storage**: epic Locked Answer #1 says "AWS Secrets Manager as `xomify/apns/auth-key`". Existing xomify pattern uses **SSM Parameter Store SecureString** (`/xomify/spotify/CLIENT_SECRET`, `/xomify/api/API_SECRET_KEY`, etc.) — no Secrets Manager usage anywhere in the stack. **Recommendation: use SSM SecureString** at `/xomify/apns/AUTH_KEY` (key content), `/xomify/apns/KEY_ID`, `/xomify/apns/TEAM_ID`, `/xomify/apns/BUNDLE_ID`. The existing `ssm_helpers.py` lazy-load pattern drops in with one new entry. Secrets Manager would require a new IAM statement, new helper module, and new provider wiring for zero functional benefit. **Flagging this as a deviation from the epic** — Dom to confirm before PR-A. If Dom insists on Secrets Manager, swap the four SSM resources for one `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version` JSON blob; all other plan steps unchanged.
4. **Digest scan pattern**: `cron_shares_digest` scans `xomify-device-tokens` filtered by `digestEnabled=true`. For the 5-friend dogfood and 5-digit user count this is fine; a GSI on `digestEnabled` can be added later if Scan becomes expensive.

### Rationale

- Two-PR split mirrors `backend-shares`: infra (terraform) must apply first so the lambda function names + tables + EventBridge rule + SSM parameters exist before the backend PR ships code into them. `deploy-backend.yml` only calls `update-function-code` — it does NOT create functions.
- Single-purpose handlers keep IAM blast radius narrow and preserve the one-folder-per-function deploy workflow (`tr '_' '-'` mapping).
- Threshold idempotency uses a conditional `UpdateItem` on the parent `xomify-shares` row (`notifiedAtThreshold3` attribute, `attribute_not_exists` condition). Atomic; no second write ever fires.
- Cron helper is async-friendly (APNs is HTTP/2 over TLS — same shape as the Spotify aiohttp client already in the codebase).

---

## Affected Files / Components

### PR-A — `xomify-infrastructure` (infra first)

| File | Change | Why |
|---|---|---|
| `terraform/dynamodb.tf` | **add** `aws_dynamodb_table.device_tokens` block (#12) | New `xomify-device-tokens` table, PK=`email`, SK=`deviceToken`, TTL attr `ttl` |
| `terraform/locals.tf` | **extend** `lambda_variables` with `DEVICE_TOKENS_TABLE_NAME`, `APNS_KEY_ID_PARAM`, `APNS_TEAM_ID_PARAM`, `APNS_BUNDLE_ID_PARAM`, `APNS_AUTH_KEY_PARAM`, `NOTIFICATIONS_SEND_FUNCTION_NAME` | Inject config into all lambdas that need it |
| `terraform/ssm.tf` | **add** four `aws_ssm_parameter` resources (SecureString): `/xomify/apns/AUTH_KEY`, `/xomify/apns/KEY_ID`, `/xomify/apns/TEAM_ID`, `/xomify/apns/BUNDLE_ID` | Holds the `.p8` content + config. Values sourced from new `variables.tf` vars (sensitive) populated via Terraform Cloud workspace vars — never committed |
| `terraform/variables.tf` | **add** `apns_auth_key` (sensitive, string — the `.p8` file contents), `apns_key_id`, `apns_team_id`, `apns_bundle_id` | TF Cloud workspace vars — Dom uploads `.p8` file contents as the `apns_auth_key` value once, then deletes `~/Downloads/AuthKey_A5X4MKX38D.p8` |
| `terraform/lambdas_shares.tf` | **no change** — `react` entry already stubbed | Existing entry already provisions `xomify-shares-react`; PR-B lands the code |
| `terraform/lambdas_notifications.tf` | **new file** — `aws_lambda_function.notifications` `for_each` over `local.notifications_lambdas` (`register`, `unregister`, `send`) plus a distinct `aws_lambda_function.notifications_send` because `send` has different role (no API GW integration, secrets read) | New service pattern |
| `terraform/api_gateway.tf` | **extend** `services` map with `notifications = { path_prefix = "notifications", endpoints = local.notifications_endpoints }` (register + unregister only; `send` is internal) | Add two new HTTP endpoints behind the existing JWT authorizer |
| `terraform/lambdas_cron.tf` | **extend** `local.cron_lambdas` with entry `{ name = "shares-digest", description = "Weekly shares digest", cron_schedule = "cron(0 18 ? * SUN *)", cron_description = "Weekly shares digest Sunday 18:00 UTC" }` | EventBridge rule + target + permission auto-provision via existing loop |
| `terraform/iam_lambda.tf` | **extend** `lambda_role_policy` (API lambdas) with `ssm:GetParameter` on `apns/*` path (already covered by `parameter/xomify/*` wildcard — verify); **extend** `cron_lambda_role_policy` same way. **Add** explicit `lambda:InvokeFunction` on `${app_name}-notifications-send` to both API lambda role (for `shares_react`) and cron role (for `cron_shares_digest`) — already covered by `${app_name}*` wildcard, verify. | Minimal IAM change — existing wildcards already cover new resources |

### PR-B — `xomify-backend` (handlers + helpers, after PR-A merges)

| File | Change | Why |
|---|---|---|
| `lambdas/common/share_interactions_dynamo.py` | **new** | Table helper: `put_reaction(share_id, email, action, rating=None, shared_by=None)`, `remove_reaction(share_id, email, action)`, `list_reactions_for_share(share_id)`, `list_reactions_for_user(email)`, `count_distinct_reactors(share_id)` |
| `lambdas/common/device_tokens_dynamo.py` | **new** | Table helper: `upsert_token(email, device_token, digest_enabled, queue_notifications_enabled)`, `delete_token(email, device_token)`, `list_tokens_for_user(email)`, `scan_tokens_for_digest()` |
| `lambdas/common/apns_client.py` | **new** | Minimal APNs HTTP/2 client. Builds JWT provider token (ES256) from `.p8` pulled from SSM. Caches token for ~50 min (APNs spec: tokens valid ≤1hr, refresh ≥20min). Sends alert payload. Handles `410 Unregistered` → deletes token. |
| `lambdas/common/ssm_helpers.py` | **extend** `__getattr__` param_map with `APNS_AUTH_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` | Lazy-load APNs config with caching |
| `lambdas/common/constants.py` | **extend** with `SHARE_INTERACTIONS_TABLE_NAME`, `DEVICE_TOKENS_TABLE_NAME`, `NOTIFICATIONS_SEND_FUNCTION_NAME` constants (pulled from env vars set by terraform `lambda_variables`) | Match existing table-name pattern |
| `lambdas/common/errors.py` | **extend** with `ApnsError` (inherit from base), `NotificationsError` | Follow existing per-service error class convention |
| `lambdas/shares_react/handler.py` | **new** — `POST /shares/react` | Main interaction write. Body: `{ email, shareId, action: "queued"\|"rated"\|"unqueued"\|"unrated", rating?: int }`. Toggle-safe. On `queued`, run threshold check; on `rated`, upsert `xomify-track-ratings`. |
| `lambdas/shares_feed/handler.py` | **edit** `_enrich` stub → real enrichment via batched `list_reactions_for_share` calls | Return real `queuedCount` / `ratedCount` / `viewerHasQueued` / `viewerRating` |
| `lambdas/shares_user/handler.py` | **edit** same enrichment pattern | Profile view needs same counts |
| `lambdas/common/shares_dynamo.py` | **extend** with `mark_threshold_notified(share_id, threshold)` using `UpdateItem` + `ConditionExpression` `attribute_not_exists(notifiedAtThreshold3)` | Idempotent threshold latch |
| `lambdas/notifications_register/handler.py` | **new** — `POST /notifications/register` | Body: `{ email, deviceToken, digestEnabled?, queueNotificationsEnabled? }`. Upsert into `xomify-device-tokens`. |
| `lambdas/notifications_unregister/handler.py` | **new** — `POST /notifications/unregister` | Body: `{ email, deviceToken }`. Delete single token row. |
| `lambdas/notifications_send/handler.py` | **new** — internal invoke only | Event: `{ kind: "queue_threshold" \| "digest", email, ...payload }`. Looks up tokens, builds APNs payload, sends. Returns `{ sent: n, failed: m, pruned: p }`. |
| `lambdas/cron_shares_digest/handler.py` | **new** | Scans opted-in device tokens, batches by email, computes 7-day count via `shares_feed` helpers, invokes `notifications_send` for each. |
| `tests/test_shares_react.py` | **new** | Happy path + toggle + rating upsert + threshold fires once + threshold idempotency |
| `tests/test_notifications_register.py` | **new** | Upsert + validation |
| `tests/test_notifications_send.py` | **new** | Mock APNs client; payload build; 410 prune |
| `tests/test_cron_shares_digest.py` | **new** | Scan mock + per-user fan-out + time-window filter |
| `tests/test_share_interactions_dynamo.py` | **new** | Helper unit tests (moto) |
| `tests/test_device_tokens_dynamo.py` | **new** | Helper unit tests (moto) |
| `README.md` | **edit** — add `/shares/react` full schema + `/notifications/*` section + new DynamoDB tables + cron `shares-digest` entry | Docs parity |

---

## Implementation Steps

### Phase 0 — Pre-flight (both PRs)

- [ ] **0.1** Move `~/Downloads/AuthKey_A5X4MKX38D.p8` into Terraform Cloud workspace variables: open the workspace, add `apns_auth_key` (sensitive, file contents pasted as string), `apns_key_id` = `A5X4MKX38D`, `apns_team_id` = TBD (from Apple Developer → Membership), `apns_bundle_id` = TBD (from `Xomify-iOS.xcodeproj` Info.plist). After upload, shred the local `.p8`: `rm -P ~/Downloads/AuthKey_A5X4MKX38D.p8`.
- [ ] **0.2** Confirm Team ID + Bundle ID values with Dom before running `terraform apply`.
- [ ] **0.3** Create branch `feature/27-interactions-and-notifications-infra` (PR-A) off `master` in `xomify-infrastructure`.

### Phase 1 — PR-A: Infrastructure

Branch: `feature/27-interactions-and-notifications-infra` in `xomify-infrastructure`.

- [ ] **1.1** Add `variables.tf` entries: `apns_auth_key`, `apns_key_id`, `apns_team_id`, `apns_bundle_id` (all sensitive).
- [ ] **1.2** Add `ssm.tf` entries for the four APNs SecureString params. Follow existing `ignore_changes = [tags, tags_all]` pattern.
- [ ] **1.3** Add `dynamodb.tf` entry `aws_dynamodb_table.device_tokens` — PK=`email` (S), SK=`deviceToken` (S), `ttl` attribute enabled on attr `ttl` (N). Match existing block style (KMS enc, PITR, standard_tags merge). Table number `12`.
- [ ] **1.4** Extend `locals.tf` `lambda_variables`:
  ```hcl
  DEVICE_TOKENS_TABLE_NAME        = aws_dynamodb_table.device_tokens.id
  NOTIFICATIONS_SEND_FUNCTION_NAME = "${var.app_name}-notifications-send"
  APNS_AUTH_KEY_PARAM             = aws_ssm_parameter.apns_auth_key.name
  APNS_KEY_ID_PARAM               = aws_ssm_parameter.apns_key_id.name
  APNS_TEAM_ID_PARAM              = aws_ssm_parameter.apns_team_id.name
  APNS_BUNDLE_ID_PARAM            = aws_ssm_parameter.apns_bundle_id.name
  ```
- [ ] **1.5** Create `terraform/lambdas_notifications.tf` with `local.notifications_lambdas = [{register}, {unregister}]` (HTTP, `lambda_role`) and a separate `aws_lambda_function.notifications_send` (no HTTP, `lambda_role`, same env vars). Use `depends_on` on `aws_iam_role_policy.lambda_role_policy`.
- [ ] **1.6** Extend `api_gateway.tf` with `notifications_endpoints` local + `notifications` entry in `module.api.services` map (`path_prefix = "notifications"`).
- [ ] **1.7** Extend `lambdas_cron.tf` `local.cron_lambdas` with `{ name = "shares-digest", description = "Weekly shares digest", cron_schedule = "cron(0 18 ? * SUN *)", cron_description = "Weekly shares digest Sunday 18:00 UTC" }`.
- [ ] **1.8** Verify IAM: `lambda_role_policy` SSM statement already covers `/xomify/*` wildcard → new `/xomify/apns/*` paths covered. `lambda_role_policy` Lambda invoke already covers `${app_name}*` → new `notifications-send` covered. `cron_lambda_role_policy` covers the same DynamoDB wildcard → new `device_tokens` table covered. **No IAM edits needed** — document verification in PR description.
- [ ] **1.9** `terraform fmt && terraform validate` locally. Run `terraform plan` via TF Cloud. Sanity-check: should create 1 DDB table, 4 SSM params, 3 lambda functions (2 notifications + 1 send + 1 cron = 4 actually), 1 API GW service, 1 EventBridge rule.
- [ ] **1.10** Open PR-A → `Closes #27` (partial — note backend PR-B follows). After merge, TF Cloud applies.
- [ ] **1.11** Post-merge: verify in AWS console that the stub lambda functions exist (they'll return 502 until PR-B lands — expected).

### Phase 2 — PR-B: Backend code

Branch: `feature/27-interactions-and-notifications` in `xomify-backend` (off `master`, after PR-A merges).

**2.A — Common helpers (land first, no handler depends on them yet)**

- [ ] **2.1** Add `SHARE_INTERACTIONS_TABLE_NAME`, `DEVICE_TOKENS_TABLE_NAME`, `NOTIFICATIONS_SEND_FUNCTION_NAME` to `constants.py` (read from env, following the existing `os.environ.get(...)` pattern).
- [ ] **2.2** Write `lambdas/common/share_interactions_dynamo.py`. One row per `(shareId, email)`. Attributes: `shareId`, `email`, `sharedBy` (denormalized for digest fan-out), `queued` (bool), `rated` (bool), `rating` (int 1–5, only when `rated=true`), `queuedAt`, `ratedAt`, `updatedAt`. Functions:
  - `set_reaction(share_id, email, shared_by, action, rating=None)` — idempotent `UpdateItem` toggling the attribute for the given action.
  - `clear_reaction(share_id, email, action)` — flips attr off.
  - `get_reaction(share_id, email) -> Optional[dict]`.
  - `list_reactions_for_share(share_id) -> list[dict]`.
  - `list_reactions_for_user(email) -> list[dict]` (via Scan filter on `email` or add GSI later if needed — **for v1 skip the GSI**, document in helper docstring).
  - `count_distinct_reactors(share_id) -> int` — counts rows where `queued=true OR rated=true`.
- [ ] **2.3** Write `lambdas/common/device_tokens_dynamo.py`. Attributes: `email`, `deviceToken`, `platform` (`ios`), `digestEnabled`, `queueNotificationsEnabled`, `createdAt`, `updatedAt`, `ttl` (epoch seconds, 180 days out — stale tokens auto-prune). Functions:
  - `upsert_token(email, device_token, digest_enabled=True, queue_notifications_enabled=True)`.
  - `delete_token(email, device_token)`.
  - `list_tokens_for_user(email) -> list[dict]`.
  - `scan_tokens_for_digest() -> iter[dict]` — paginated Scan with `FilterExpression: digestEnabled = :true`.
- [ ] **2.4** Write `lambdas/common/apns_client.py`. Dependencies allowed (added to `requirements.txt`): `httpx` (already common, supports HTTP/2) + `pyjwt[crypto]` (ES256 signing). Class `ApnsClient`:
  - Lazy-loads `.p8` via `ssm_helpers.APNS_AUTH_KEY` on first call.
  - Builds ES256 JWT `{ alg: ES256, kid: APNS_KEY_ID }` with claims `{ iss: APNS_TEAM_ID, iat: now }`. Caches JWT for 50 min.
  - `send(device_token, alert_title, alert_body, category=None, custom_data=None) -> dict` → POST to `https://api.push.apple.com/3/device/<token>` with headers `apns-topic: APNS_BUNDLE_ID`, `apns-push-type: alert`, `authorization: bearer <jwt>`.
  - Returns `{ ok, status_code, reason }`. On `410`, caller prunes token.
- [ ] **2.5** Extend `ssm_helpers.py` `param_map` with 4 APNs entries.
- [ ] **2.6** Add `ApnsError`, `NotificationsError` to `errors.py`.

**2.B — Handlers**

- [ ] **2.7** Write `lambdas/shares_react/handler.py` — `POST /shares/react`. Body schema:
  ```json
  { "email": "viewer@...", "shareId": "uuid", "action": "queued|rated|unqueued|unrated", "rating": 1-5 }
  ```
  Flow:
  1. `require_fields(body, 'email', 'shareId', 'action')`.
  2. Fetch parent share via `get_share(share_id)` → 404 if missing, capture `sharedBy`.
  3. If `action == "rated"`, require `1 <= rating <= 5`; upsert `xomify-track-ratings` via existing helper.
  4. If `action` starts with `un`, call `clear_reaction`. Otherwise `set_reaction`.
  5. `count = count_distinct_reactors(share_id)`.
  6. If `action == "queued"` and `count >= 3` and `sharedBy != viewer`, try `mark_threshold_notified(share_id, 3)` — if it succeeds (condition passes), invoke `notifications_send` lambda async with `{ kind: "queue_threshold", email: sharedBy, shareId, reactorCount: count }`. If condition fails (already notified), skip.
  7. Return `success_response({ queuedCount, ratedCount, viewerHasQueued, viewerRating })`.
- [ ] **2.8** Update `lambdas/shares_feed/handler.py` `_enrich` to batch-fetch reaction rows per share (`list_reactions_for_share`) and populate real counts + viewer's state.
- [ ] **2.9** Update `lambdas/shares_user/handler.py` with the same enrichment.
- [ ] **2.10** Extend `lambdas/common/shares_dynamo.py` with `mark_threshold_notified(share_id, threshold)` — conditional `UpdateItem` on `shareId` PK, `SET notifiedAtThreshold<N> = :now`, `ConditionExpression attribute_not_exists(notifiedAtThreshold<N>)`. Returns `True` if newly set, `False` on `ConditionalCheckFailedException`.
- [ ] **2.11** Write `lambdas/notifications_register/handler.py` — parse body, validate, `upsert_token`, success.
- [ ] **2.12** Write `lambdas/notifications_unregister/handler.py` — parse body, validate, `delete_token`, success.
- [ ] **2.13** Write `lambdas/notifications_send/handler.py`. Event shape (internal invoke):
  ```json
  { "kind": "queue_threshold|digest", "email": "recipient@...", "title": "...", "body": "...", "customData": { } }
  ```
  Flow: `list_tokens_for_user(email)` → for each, respect the relevant opt-in flag based on `kind` → call `ApnsClient.send` → on 410, `delete_token`. Return aggregate counts.
- [ ] **2.14** Write `lambdas/cron_shares_digest/handler.py`. Flow:
  1. `scan_tokens_for_digest()` → group by email (dedupe multi-device).
  2. For each email: call a digest helper that queries shares from friends over the last 7 days (reuse `shares_feed` fan-out, cap at 1 per email per week).
  3. Skip users with zero new shares.
  4. Invoke `notifications_send` with `{ kind: "digest", email, title: "Your weekly Xomify digest", body: f"N new shares from your friends this week", customData: { count: N } }`.
  5. Return `{ processed, sent, skipped }`.
- [ ] **2.15** Extend `requirements.txt` with `httpx[http2]`, `pyjwt[crypto]`. Test layer build locally: `pip install --platform manylinux2014_x86_64 --only-binary=:all: -t python/ -r requirements.txt`.
- [ ] **2.16** Update `README.md` — new endpoints, new tables, new cron entry.

**2.C — Tests**

- [ ] **2.17** `tests/test_shares_react.py` — mock dynamo + mock lambda client + mock track-ratings helper. Cover: happy queue, happy rate, toggle (queue then unqueue), double-queue-same-user (idempotent), threshold fires once at exactly 3rd distinct reactor, threshold does NOT fire again at 4th/5th reactor (idempotency latch), self-react does NOT trigger push, `rated` without `rating` → 400, `rated` with rating=6 → 400.
- [ ] **2.18** `tests/test_notifications_register.py` — happy path, missing fields, default opt-in flags.
- [ ] **2.19** `tests/test_notifications_send.py` — mock `ApnsClient`. Cover: multi-device user, token pruned on 410, `kind=digest` respects `digestEnabled`, `kind=queue_threshold` respects `queueNotificationsEnabled`.
- [ ] **2.20** `tests/test_cron_shares_digest.py` — mock scan + mock feed helper + mock `notifications_send`. Cover: zero-activity users skipped, multi-user fan-out, failure of one user doesn't break others.
- [ ] **2.21** `tests/test_share_interactions_dynamo.py` + `tests/test_device_tokens_dynamo.py` — moto-backed table tests for helpers.

**2.D — Deploy**

- [ ] **2.22** Open PR-B → `Closes #27`. Workflow runs pytest per changed lambda folder, then `update-function-code` per folder. `_` → `-` in folder names already handled.
- [ ] **2.23** Post-merge smoke: from iOS TestFlight (sub-feature #9 eventually, but a manual curl works now), register a device token, create a share (one user), have three other test users hit `/shares/react` with `action=queued` — author receives one push. Confirm 4th queue does NOT re-fire.
- [ ] **2.24** Watch first Sunday 18:00 UTC cron run. Check CloudWatch logs for `cron_shares_digest` → confirm scan count, per-user invoke count, and absence of APNs errors.

---

## Out of Scope

- iOS APNs permission flow / token handoff — sub-feature 9 (`ios-notifications`).
- iOS UI for the "queued by N" chip — sub-feature 5 (`ios-feed`).
- Push-open deep links on iOS — sub-feature 9.
- Angular parity for `/shares/react` + `/notifications/*` — sub-feature 10.
- Per-user digest time-of-day bucketing — deferred post-launch per epic Locked Answer #5.
- GSI on `viewerEmail` for `xomify-share-interactions` — not required for v1 feed enrichment; add if profile-view needs "my recent reactions" and scan becomes slow.
- Secrets Manager migration (if we later decide to standardize on it across the stack) — would be a separate infra-only PR.
- Android push / FCM — not in the Xomify roadmap.

---

## Risks / Tradeoffs

- **Secret store deviation**: using SSM SecureString instead of Secrets Manager (epic said Secrets Manager). Rationale in Approach §3. Reversible in one infra PR if Dom insists.
- **APNs cold start**: JWT signing + SSM pull on cold start adds ~300–500ms to `notifications_send`. Accepted — cache the JWT across warm invocations (50min TTL). Cron-triggered path is already async so end-user impact is zero.
- **Threshold idempotency races**: two simultaneous 3rd reactors → both may count as the 3rd distinct. The conditional `UpdateItem` on the share row guarantees only one `notifications_send` invocation. Accepted.
- **Scan-based digest**: works for dogfood. At >10k users the Scan becomes expensive — add a GSI `digestEnabled-email-index` later. Documented as migration path.
- **Self-react push**: excluded from threshold trigger (check `sharedBy != viewer`). No risk of spamming the author with pushes for their own taps.
- **Token staleness**: 410 from APNs prunes the token on send. TTL (180 days) prunes truly dormant devices. Accepted.
- **`action` string design**: using `queued/rated/unqueued/unrated` keeps the iOS `ReactionAction` enum shape (`reactToShare(action:)`) directly compatible — no breaking change to the already-shipped client.
- **Ratings double-write**: `rated` action writes both `xomify-share-interactions` and `xomify-track-ratings`. Not transactional across tables. Accepted — track-ratings is the canonical source; a missed interaction row just means one share card reads `rated=false` until the next write fixes it. Low-stakes, user-retryable.

---

## Open Questions

- [ ] **APNs Team ID + iOS Bundle ID** — Dom to read these off Apple Developer Membership + Xcode project Info.plist before Phase 0.1. These go straight into TF Cloud workspace vars. Blocker for `terraform apply` in PR-A.
- [ ] **Secrets Manager vs SSM** — flagged in Approach §3. Default recommendation: **SSM SecureString** (aligned with existing stack). Dom to confirm before Phase 1.2. 60-second decision — the rest of the plan doesn't change.
- [ ] **Sunday 18:00 UTC vs another slot** — epic suggested Sunday 18:00 UTC. Good default (1pm ET / 10am PT). Confirm or swap in Phase 1.7.

---

## Skills / Agents to Use

- **backend-engineer**: PR-B handlers, helpers, APNs client. Knows the `handle_errors` / `success_response` / `require_fields` conventions.
- **test-writer**: pytest + moto for helper tests; mock `ApnsClient` and `boto3.client('lambda')` for handler tests. Threshold idempotency is the highest-value test.
- **code-reviewer**: run on both PRs before merge. Especially scrutinize IAM scoping (even though we rely on wildcards, the lambdas cross-invoke each other — worth confirming).
- **docs-writer**: `README.md` parity update in Phase 2.16.
