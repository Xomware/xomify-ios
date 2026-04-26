# Plan: Xomify Social Feed — backend-shares

**Epic**: [xomify-social-feed](../xomify-social-feed/PLAN.md)
**Sub-feature ID**: 3 (`backend-shares`)
**Status**: Ready
**Created**: 2026-04-22
**Last updated**: 2026-04-22 (rewrite — infra already 90% deployed)
**Scope size**: M
**Repos touched**: `xomify-infrastructure` (Terraform PR first), `xomify-backend` (handler PR second)
**Infra working dir**: `/Users/dom/Code/xomify-infrastructure/terraform`
**Backend working dir**: `/Users/dom/Code/xomify-backend`
**Depends on**: 1 (`repo-cleanup`, merged)

---

## Summary

Finish the `shares` + `invites` backend: add the two missing lambdas (`delete`, `user`) to Terraform, then land the 6 handler implementations + 2 common helper modules in `xomify-backend`. Tables, GSI, JWT authorizer, API Gateway wiring, and stub lambdas for `create`/`feed`/`react`/`invites_create`/`invites_accept` are already deployed via Terraform. This sub-feature does NOT cover `share_interactions` — that moves to sub-feature #4.

---

## Ground truth (already deployed)

Verified against `/Users/dom/Code/xomify-infrastructure/terraform/` on 2026-04-22. Do not re-derive these — they're live in AWS.

### DynamoDB tables (`dynamodb.tf`)

| Table | PK | SK | GSI | Notes |
|-------|----|----|-----|-------|
| `xomify-shares` | `shareId` (S) | — | `email-createdAt-index` (hash=`email`, range=`createdAt`, PROJECTION_ALL) | Sections #9, lines 261-304. PITR on, KMS on. |
| `xomify-share-interactions` | `shareId` (S) | `email` (S) | — | Section #10, lines 306-337. **Out of scope for this sub-feature** (sub-feature #4). |
| `xomify-invites` | `inviteCode` (S) | — | — | Section #11, lines 339-364. No GSI; "my outstanding invites" handler (if added later) will need one. |

**Schema reality check**: the epic plan's schemas were aspirational. Live tables win. `shares` uses a flat `shareId` PK (no SK); author-ordered feed queries run through the `email-createdAt-index` GSI with `ScanIndexForward=false`. The `invites` table has no sender-indexed GSI — rate-limit logic must work around that (see Risks).

### Lambdas (`lambdas_shares.tf`, `lambdas_invites.tf`)

Each resource loops over a `local.*_lambdas` list and produces `aws_lambda_function` resources named `${var.app_name}-<domain>-<name>`. Runtime + role + layer + tags are uniform. Stubs are deployed with `./templates/lambda_stub.zip`; `lifecycle.ignore_changes` on `filename` / `source_code_hash` / `layers` lets the `deploy-backend.yml` workflow update code out-of-band.

**Deployed stubs today:**
- `xomify-shares-create` (POST /shares/create)
- `xomify-shares-feed` (GET /shares/feed)
- `xomify-shares-react` (POST /shares/react) — **out of scope here**, belongs to #4
- `xomify-invites-create` (POST /invites/create)
- `xomify-invites-accept` (POST /invites/accept)

### API Gateway (`api_gateway.tf` lines 67-110)

Routes wired automatically via `local.shares_endpoints` / `local.invites_endpoints` list comprehensions over the `*_lambdas` locals. Service map at lines 101-110 mounts them at `/shares/*` and `/invites/*`. All routes sit behind the existing JWT `authorizer` lambda. **Adding a new entry to the `local.*_lambdas` list is sufficient — API Gateway picks it up for free.**

### IAM (`iam_lambda.tf`)

`aws_iam_role.lambda_role` (used by every API lambda including the new shares/invites set) already grants DynamoDB `BatchGetItem`, `GetItem`, `Query`, `Scan`, `BatchWriteItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `DescribeTable` on both `arn:aws:dynamodb:<region>:<acct>:table/xomify*` AND `.../xomify*/index/*`. **GSI `Query` is already permitted** — no IAM delta needed for this sub-feature.

### Deploy workflow (`xomify-backend/.github/workflows/deploy-backend.yml`)

Confirms the folder→function-name mapping: `FUNCTION_NAME=$(echo "xomify-${matrix.lambda}" | tr '_' '-')`. A folder `lambdas/shares_create/` deploys to `xomify-shares-create`. Workflow runs `aws lambda update-function-code` against pre-existing functions — **if the Terraform lambda resource doesn't exist yet, the deploy step fails**. Hence the infra PR must merge before the backend PR.

---

## Approach

Two coordinated PRs, merged in order:

1. **`xomify-infrastructure` PR** (`feat/backend-shares-tf`): extend `local.shares_lambdas` with `delete` + `user` entries. Run `terraform plan` (expect: 2 new `aws_lambda_function` resources, 2 new API Gateway routes created automatically by the `api` module, 0 changes to tables/IAM/authorizer). Review diff, `apply`.
2. **`xomify-backend` PR** (`feat/backend-shares-handlers`): add 6 handler folders + 2 common helper modules + tests. On merge to `master`, `deploy-backend.yml` packages each changed lambda dir and calls `update-function-code` against the live functions (which now all exist thanks to PR #1).

No changes to `dynamodb.tf`, `iam_lambda.tf`, `api_gateway.tf`, or `lambdas_invites.tf`. Invites lambdas are already fully declared — we're just filling in the handlers.

---

## Terraform delta (PR #1)

Single file edited: `xomify-infrastructure/terraform/lambdas_shares.tf`. Append two entries to `local.shares_lambdas`:

```hcl
locals {
  shares_lambdas = [
    {
      name        = "create"
      description = "Create a new share"
      path_part   = "create"
      http_method = "POST"
    },
    {
      name        = "feed"
      description = "Get the merged feed of shares from user and accepted friends"
      path_part   = "feed"
      http_method = "GET"
    },
    {
      name        = "react"
      description = "React to a share (like/love/fire/etc or toggle off)"
      path_part   = "react"
      http_method = "POST"
    },
    # NEW — sub-feature backend-shares
    {
      name        = "delete"
      description = "Delete a share by id (owner only)"
      path_part   = "delete"
      http_method = "DELETE"
    },
    {
      name        = "user"
      description = "List shares authored by a specific user"
      path_part   = "user"
      http_method = "GET"
    },
  ]
}
```

Do NOT touch the `aws_lambda_function.shares` resource block — the `for_each` auto-expands. Tags follow the existing `merge(local.standard_tags, tomap({ "name" = "...", "lambda_type" = "shares" }))` pattern, propagated by the same `for_each`.

Expected `terraform plan`:
- `+ aws_lambda_function.shares["delete"]`
- `+ aws_lambda_function.shares["user"]`
- `+` API Gateway method/integration/permission resources under `module.api` for the two new endpoints (counts depend on module internals — eyeball the plan).
- Zero changes to `aws_dynamodb_table.*`, `aws_iam_role.*`, `aws_iam_role_policy.*`, authorizer.

Invites lambdas (`lambdas_invites.tf`) are unchanged — both `create` and `accept` are already declared.

---

## Backend handler delta (PR #2)

All handlers follow the single-purpose pattern from `lambdas/friends_list/handler.py`:

```python
from lambdas.common.logger import get_logger
from lambdas.common.errors import handle_errors
from lambdas.common.utility_helpers import success_response, parse_body, get_query_params, require_fields
from lambdas.common.<helper> import <fn>

log = get_logger(__file__)
HANDLER = '<name>'

@handle_errors(HANDLER)
def handler(event, context):
    ...
```

`@handle_errors` maps `ValidationError→400`, `AuthorizationError→403`, `NotFoundError→404`, `DynamoDBError→500`. Handlers are thin; business logic sits in `lambdas/common/*_dynamo.py`.

### 1. `lambdas/shares_create/` — `POST /shares/create` → `xomify-shares-create`

- **Body**: `{ email, trackId, trackUri, trackName, artistName, albumName, albumArtUrl, caption?, moodTag?, genreTags? }`
- **Required**: `email, trackId, trackUri, trackName, artistName, albumName, albumArtUrl`
- **Validation** (all 400 via `ValidationError`):
  - `caption` present and `len(caption) > 140`
  - `moodTag` present and not in `{hype, chill, sad, party, focus, discovery}`
  - `genreTags` present and `len(genreTags) > 3`
- **DDB**: `shares_dynamo.create_share(...)` — generate `shareId = uuid4()`, `createdAt = iso8601 now`, `PutItem` on `xomify-shares` with PK `shareId` and `email` attribute populated for GSI indexing.
- **Response 200**: `{ shareId, createdAt }`
- **Errors**: 400 (missing/invalid field), 500 (DDB)

### 2. `lambdas/shares_feed/` — `GET /shares/feed` → `xomify-shares-feed`

- **Query**: `email` (required, requester), `groupId` (optional), `limit` (optional, default 50, max 100), `before` (optional, ISO8601 cursor)
- **Flow**:
  1. `friendships_dynamo.list_all_friends_for_user(email)` → filter `status == 'accepted'`.
  2. Include requester's own email in the fan-out set so their shares appear in their feed.
  3. If `groupId`: `group_members_dynamo.list_members_of_group(groupId)` → intersect with fan-out set.
  4. Per email in the resulting set, `Query` the `email-createdAt-index` GSI with `KeyConditionExpression=Key('email').eq(e)`, `ScanIndexForward=False`, `Limit=limit`, optional `ExclusiveStartKey` derived from `before`. Parallelize via `concurrent.futures.ThreadPoolExecutor(max_workers=10)`.
  5. Merge-sort by `createdAt` desc, take top `limit`.
  6. Enrichment stubs (set to zero/false/null until sub-feature #4 lands): `queuedCount`, `ratedCount`, `viewerHasQueued`, `viewerRating`, `sharerRating`.
- **Response 200**: `{ shares: [...], nextBefore: "iso8601|null" }`
- **Errors**: 400 (missing `email`, `limit > 100`), 500 (DDB)
- **Edge case**: user with no accepted friends → return `{ shares: [<own shares, if any>], nextBefore: null }`.

### 3. `lambdas/shares_delete/` — `DELETE /shares/delete` → `xomify-shares-delete`

- **Query**: `email` (requester), `shareId`
- **Flow**:
  1. `shares_dynamo.get_share(shareId)` → `GetItem` on PK. `NotFoundError` (404) if missing.
  2. Compare `share['email'] == requester email`. `AuthorizationError` (403) if mismatch.
  3. `shares_dynamo.delete_share(shareId)` → `DeleteItem`.
- **Response 204** via `success_response({}, status_code=204)`.
- **Errors**: 400 (missing fields), 403 (not owner), 404 (not found), 500 (DDB)

### 4. `lambdas/shares_user/` — `GET /shares/user` → `xomify-shares-user`

- **Query**: `email` (requester — kept for future gating), `targetEmail` (required), `limit` (default 50, max 100), `before` (optional)
- **Flow**: `Query` `email-createdAt-index` GSI with `Key('email').eq(targetEmail)`, `ScanIndexForward=False`. **No friendship gate in v1** — consistent with `ratings_track` posture (flagged in Risks).
- **Response 200**: `{ shares: [...], nextBefore: "iso8601|null" }`
- **Errors**: 400 (missing `targetEmail`, `limit > 100`), 500 (DDB)

### 5. `lambdas/invites_create/` — `POST /invites/create` → `xomify-invites-create`

- **Body**: `{ email }` (sender)
- **Flow**:
  1. **Rate limit**: sender may hold ≤ 10 outstanding (non-consumed, non-expired) invites at once. Because the `xomify-invites` table has no sender GSI, v1 uses a `Scan` with `FilterExpression="senderEmail = :s AND attribute_not_exists(consumedAt) AND expiresAt > :now"` — acceptable at 5-user dogfood scale. Flagged in Risks; add a `sender-invites-index` GSI in a follow-up TF PR once traffic justifies it.
  2. Generate 8-char base32 code (`base64.b32encode(os.urandom(5))[:8]`, uppercase).
  3. `PutItem` on `xomify-invites`: `{ inviteCode, senderEmail, createdAt, consumedAt: null, consumedBy: null, expiresAt: now + 30d }`. `ConditionExpression="attribute_not_exists(inviteCode)"` to handle collision; on `ConditionalCheckFailedException`, regenerate once.
- **Response 200**: `{ inviteCode, inviteUrl }` where `inviteUrl = INVITE_URL_TEMPLATE.format(code=inviteCode)`. Template env var defaults to `https://xomify.app/invite/{code}` — deep-link scheme is still TBD (blocks iOS #7, not this sub-feature).
- **Errors**: 400 (missing `email`), 429 (rate limit exceeded, message `"Max 10 outstanding invites"`), 500 (DDB, after two code-collision retries)

### 6. `lambdas/invites_accept/` — `POST /invites/accept` → `xomify-invites-accept`

- **Body**: `{ email, inviteCode }` (email = consumer)
- **Flow**:
  1. `invites_dynamo.get_invite(inviteCode)` → `NotFoundError` (404) if missing.
  2. If `expiresAt < now` OR `consumedAt is not None` → return **410 Gone** (`ValidationError` with status override). Keep "expired" and "already consumed" distinguishable in the response body's `error_code` field.
  3. If `invite.senderEmail == email` → 400 (can't accept your own invite).
  4. If sender and consumer already friends with `status=accepted` (check via `friendships_dynamo.list_all_friends_for_user(email)`) → 409 Conflict. **Open question**: idempotent 200 no-op may be friendlier UX — flagged below.
  5. Transactional: `UpdateItem` on `xomify-invites` setting `consumedAt = now`, `consumedBy = email`, with `ConditionExpression="attribute_not_exists(consumedAt) AND expiresAt > :now"` (race guard). Plus create accepted friendship — extend `friendships_dynamo.py` with a new `create_accepted_friendship(sender, recipient)` that writes both directional rows in a single `transact_write_items` with `status=accepted, acceptedAt=now`.
- **Response 200**: `{ ok: true, senderEmail }`
- **Errors**: 400 (missing fields, self-invite), 404 (code not found), 409 (already friends), 410 (expired or already consumed), 500 (DDB)

---

## Common helpers (PR #2)

### `lambdas/common/shares_dynamo.py` (new)

Mirror the `friendships_dynamo.py` style exactly: module-level `boto3.resource`, `_get_timestamp()` helper, per-function try/except raising `DynamoDBError(message, function, table)`.

```python
# Reads from lambdas/common/constants.py
SHARES_TABLE_NAME = os.environ.get('SHARES_TABLE_NAME', 'xomify-shares')
SHARES_EMAIL_INDEX = 'email-createdAt-index'
```

Functions:

- `create_share(email, track_id, track_uri, track_name, artist_name, album_name, album_art_url, caption=None, mood_tag=None, genre_tags=None) -> dict` — returns `{shareId, createdAt}`.
- `get_share(share_id) -> dict | None` — `GetItem` on PK; returns `None` on miss.
- `delete_share(share_id) -> bool` — `DeleteItem`; returns `False` on conditional-check-failed.
- `list_shares_for_user(email, limit=50, before=None) -> (list, next_before)` — `Query` on `email-createdAt-index`, `ScanIndexForward=False`, handles pagination.
- `query_feed_for_emails(emails: list[str], limit=50, before=None) -> list` — fan-out helper: `ThreadPoolExecutor(max_workers=10)` over `list_shares_for_user`, merge-sort desc by `createdAt`, take top `limit`.

### `lambdas/common/invites_dynamo.py` (new)

```python
INVITES_TABLE_NAME = os.environ.get('INVITES_TABLE_NAME', 'xomify-invites')
INVITE_URL_TEMPLATE = os.environ.get('INVITE_URL_TEMPLATE', 'https://xomify.app/invite/{code}')
INVITE_TTL_DAYS = 30
```

Functions:

- `create_invite(sender_email, invite_code, ttl_days=INVITE_TTL_DAYS) -> dict` — `PutItem` with `ConditionExpression="attribute_not_exists(inviteCode)"`.
- `get_invite(invite_code) -> dict | None` — `GetItem` on PK.
- `consume_invite(invite_code, recipient_email) -> dict` — `UpdateItem` with `ConditionExpression="attribute_not_exists(consumedAt) AND expiresAt > :now"`; raises on conditional fail so handler maps to 410.
- `list_invites_by_sender(sender_email, active_only=True) -> list` — v1 uses `Scan` + `FilterExpression` (no GSI on sender). Returns list of invite rows filtered on `active_only=True` (not expired, not consumed). Used by `invites_create` for rate limit; comment flags GSI follow-up.

### `lambdas/common/friendships_dynamo.py` (extend)

Add:

- `create_accepted_friendship(sender_email, recipient_email) -> bool` — puts both directional rows (`direction='outgoing'` / `'incoming'`) with `status='accepted'`, `createdAt` + `acceptedAt` both = now, via `transact_write_items`. Used by `invites_accept` only. `ConditionExpression="attribute_not_exists(email) AND attribute_not_exists(friendEmail)"` on both puts so a retry after partial failure doesn't stomp existing rows.

### `lambdas/common/constants.py` (extend)

Add three constants (env-var-backed, matching existing `FRIENDSHIPS_TABLE_NAME` pattern):

- `SHARES_TABLE_NAME`
- `INVITES_TABLE_NAME`
- `INVITE_URL_TEMPLATE`

Use `Edit`, not `Write` — file is large.

---

## Affected files

### `xomify-infrastructure` PR (`feat/backend-shares-tf`)

| File | Change | Why |
|------|--------|-----|
| `terraform/lambdas_shares.tf` | edit — add 2 entries to `local.shares_lambdas` | Create `xomify-shares-delete` + `xomify-shares-user` lambda stubs + API GW routes |

### `xomify-backend` PR (`feat/backend-shares-handlers`)

| File | Change | Why |
|------|--------|-----|
| `lambdas/common/constants.py` | edit — add 3 consts | `SHARES_TABLE_NAME`, `INVITES_TABLE_NAME`, `INVITE_URL_TEMPLATE` |
| `lambdas/common/shares_dynamo.py` | create | Table helpers (mirror `friendships_dynamo.py`) |
| `lambdas/common/invites_dynamo.py` | create | Invites table helpers |
| `lambdas/common/friendships_dynamo.py` | edit — add `create_accepted_friendship` | Single-transaction accepted-friend write for invite flow |
| `lambdas/shares_create/handler.py` | create | POST /shares/create |
| `lambdas/shares_feed/handler.py` | create | GET /shares/feed — fan-out-on-read via GSI |
| `lambdas/shares_delete/handler.py` | create | DELETE /shares/delete — owner-only |
| `lambdas/shares_user/handler.py` | create | GET /shares/user — one user's shares |
| `lambdas/invites_create/handler.py` | create | POST /invites/create |
| `lambdas/invites_accept/handler.py` | create | POST /invites/accept — auto-friend |
| `tests/conftest.py` | edit | Add `SHARES_TABLE_NAME`, `INVITES_TABLE_NAME` to `_TEST_ENV_VARS` |
| `tests/test_shares_create.py` | create | 1 happy + 3+ error paths |
| `tests/test_shares_feed.py` | create | Fan-out merge, group filter, pagination, empty friends |
| `tests/test_shares_delete.py` | create | 204 owner, 403 non-owner, 404 not found |
| `tests/test_shares_user.py` | create | Happy + pagination + missing fields |
| `tests/test_invites_create.py` | create | Happy + code-collision retry + rate limit (429) |
| `tests/test_invites_accept.py` | create | Happy / already-consumed (410) / expired (410) / self-invite (400) / not-found (404) / already-friends (409) |
| `README.md` | edit | Document 6 new endpoints + schemas pointer |

---

## Implementation steps (ordered)

### Phase A — Terraform PR (`xomify-infrastructure`)

- [ ] **A1.** Branch `feat/backend-shares-tf` off `main`.
- [ ] **A2.** Edit `terraform/lambdas_shares.tf` — append `delete` and `user` entries to `local.shares_lambdas`.
- [ ] **A3.** `cd terraform && terraform init && terraform plan -out=tfplan.out`. Verify plan shows: 2 new lambda functions, N new API GW method/integration/permission resources under `module.api`, 0 changes to tables/IAM/authorizer.
- [ ] **A4.** Open PR. Description: paste trimmed `terraform plan`, link this plan, link epic. Self-review.
- [ ] **A5.** Merge PR. `terraform apply` via whatever the infra apply flow is (CI, manual). Verify in AWS console: `xomify-shares-delete` and `xomify-shares-user` exist with stub code and the existing `lambda_role` attached. Verify API GW routes `DELETE /shares/delete` and `GET /shares/user` are wired to the JWT authorizer.

### Phase B — Backend PR (`xomify-backend`)

- [ ] **B1.** Branch `feat/backend-shares-handlers` off `master` (only after Phase A is applied).
- [ ] **B2.** Edit `lambdas/common/constants.py` — add 3 constants. Use `Edit` tool, not `Write`.
- [ ] **B3.** Edit `tests/conftest.py` — add `SHARES_TABLE_NAME=xomify-shares-test`, `INVITES_TABLE_NAME=xomify-invites-test`, `INVITE_URL_TEMPLATE=https://xomify.test/invite/{code}` to `_TEST_ENV_VARS`.
- [ ] **B4.** Create `lambdas/common/shares_dynamo.py`. Mirror `friendships_dynamo.py` style.
- [ ] **B5.** Create `lambdas/common/invites_dynamo.py`.
- [ ] **B6.** Edit `lambdas/common/friendships_dynamo.py` — add `create_accepted_friendship`.
- [ ] **B7.** Create 6 handler folders (`shares_create`, `shares_feed`, `shares_delete`, `shares_user`, `invites_create`, `invites_accept`), each with `handler.py`. Keep each 20-50 lines; all logic delegates to helpers.
- [ ] **B8.** Create 6 test files (`tests/test_<folder>.py`). Follow `tests/test_friends_list.py` pattern: patch the dynamo-layer helpers, assert `response['statusCode']` + decoded body. Cover every error case listed per-handler above. Target ≥1 happy + ≥2 error paths per handler.
- [ ] **B9.** Run `pytest tests/ -v` locally. All new tests green; no regressions elsewhere.
- [ ] **B10.** Edit `README.md` — add endpoints section.
- [ ] **B11.** Dom spot-checks Spotify ToS on denormalized track metadata (epic Locked Answer #3). Record outcome in the PR description. Abort merge if ToS has tightened.
- [ ] **B12.** Open PR. Description includes: link to Phase A PR (merged), endpoint list, ToS spot-check outcome, known gaps (deep-link scheme TBD, invite sender GSI follow-up).
- [ ] **B13.** On merge to `master`, `deploy-backend.yml` auto-packages changed lambda dirs and runs `update-function-code` for each. Verify in AWS console: each of the 6 functions shows a new code SHA and the updated description. Smoke-test via curl (see Testing below).

---

## Testing

Match the existing pattern: pytest + helper-layer mocks (moto NOT currently used; don't introduce it in this PR).

```python
@patch('lambdas.shares_create.handler.create_share')
def test_shares_create_happy_path(mock_create, mock_context, api_gateway_event):
    mock_create.return_value = {"shareId": "uuid", "createdAt": "2026-04-22 12:00:00"}
    event = {**api_gateway_event, "httpMethod": "POST", "path": "/shares/create",
             "body": json.dumps({"email": "a@b", "trackId": "x", ...})}
    resp = handler(event, mock_context)
    assert resp['statusCode'] == 200
```

Coverage matrix (minimum):

| Handler | Required tests |
|---------|----------------|
| `shares_create` | happy, missing required → 400, caption >140 → 400, bad moodTag → 400, >3 genreTags → 400, DDB error → 500 |
| `shares_feed` | happy (3 friends merged), empty friends → `{shares:[]}`, group filter intersects members, pagination via `before`, limit>100 → 400 |
| `shares_delete` | owner → 204, non-owner → 403, not found → 404, missing fields → 400 |
| `shares_user` | happy, pagination, missing `targetEmail` → 400 |
| `invites_create` | happy, code collision → regenerate once, rate limit (>10 active) → 429 |
| `invites_accept` | happy (friendship created), already consumed → 410, expired → 410, self-invite → 400, not found → 404, already friends → 409 |

**Post-deploy smoke** (manual): curl each endpoint against the live API with a valid JWT. Script template in the PR description.

---

## Deploy flow

Ordering is load-bearing — `deploy-backend.yml` uses `update-function-code` which **fails if the function doesn't exist**.

1. **PR #1 (infra)** merges → `terraform apply` creates `xomify-shares-delete` + `xomify-shares-user` as stubs.
2. **PR #2 (backend)** merges → workflow packages all 6 handler dirs and calls `update-function-code` against the now-existing functions. Stubs get replaced with real code in the same run.
3. If PR #2 merges **before** PR #1 is applied, `update-function-code` fails for `shares-delete` and `shares-user` (other 4 succeed). Mitigation: branch protection + explicit PR #1 link in PR #2 description; reviewer checks Phase A is applied before approving B.

No feature flags. Scope is 5-user dogfood.

---

## Spotify ToS note

Denormalized track metadata (`trackName` / `artistName` / `albumName` / `albumArtUrl`) in the `xomify-shares` row is accepted per epic Locked Answer #3. No action here other than Dom's pre-merge spot-check of current Spotify Developer ToS (Implementation step B11). Refreshable cache pattern — no user-visible staleness risk in v1.

---

## Out of Scope

- `xomify-share-interactions` table usage + `shares_react` handler — sub-feature #4 (`backend-interactions-and-notifications`).
- `device_tokens` table, `device_token_register`, `notifications_send`, `cron_shares_digest` — sub-feature #4.
- Feed enrichment counts (`queuedCount`, `ratedCount`, `viewerHasQueued`, `viewerRating`, `sharerRating`) — stubs return zero/false/null until #4 ships.
- iOS client wiring — sub-features #5, #7.
- Angular parity — sub-feature #10.
- `sender-invites-index` GSI on `xomify-invites` — follow-up TF PR if rate-limit `Scan` becomes a hotspot.
- Any IAM or DynamoDB table changes — all already live.

---

## Risks / Tradeoffs

- **Deploy ordering**: `deploy-backend.yml` will fail on `update-function-code` if the TF PR hasn't applied yet. Mitigation: Phase A must merge + apply before Phase B opens.
- **Invite deep-link URL scheme TBD**: blocks `ios-friends-management` (#7) invite UI, not this sub-feature. Backend returns a code string with a placeholder URL template swappable via env var.
- **No sender GSI on `invites`**: v1 rate-limit uses `Scan` + filter. Fine at 5-user scale. If launch traffic grows, follow-up TF PR adds `sender-invites-index` and `invites_dynamo.list_invites_by_sender` switches to `Query`.
- **Fan-out-on-read scaling ceiling**: accepted per epic. `ThreadPoolExecutor(max_workers=10)` handles the 5-200-friend range; revisit at 1k DAU.
- **`shares_user` has no friendship gate in v1**: consistent with `ratings_track`. Accept; revisit if profile views ever become follower-gated.
- **`invites_accept` already-friends conflict response** (409 vs idempotent 200): flagged as open question below.
- **Feed enrichment returns zeros**: iOS (#5) ships after #4 per epic dep graph, so this is never user-visible.
- **Schema in live TF differs from epic plan**: epic specced `shares` PK=`sharedBy`, SK=`sharedAt#shareId`; live table is PK=`shareId` + GSI for author queries. Live wins; this plan works with the deployed shape.

---

## Open Questions

- [ ] **`invites_accept` when already friends**: return 409 (strict) or 200 no-op (friendlier)? Default in this plan: 409. Dom's call before Phase B merge.
- [ ] **Deep-link URL scheme**: `https://xomify.app/invite/{code}` (universal link, needs `apple-app-site-association`) vs `xomify://invite/{code}` (custom). Backend ships with placeholder env var either way; must resolve before sub-feature #7.
- [ ] **`shares_user` friendship gate**: stay open (match `ratings_track`) or gate to accepted friends? Default: stay open for v1.

---

## PR shape

- **Infra PR** (`xomify-infrastructure`): branch `feat/backend-shares-tf`, base `main`. Commit: `feat(shares): add delete and user lambdas for backend-shares sub-feature`. Paste `terraform plan` in description.
- **Backend PR** (`xomify-backend`): branch `feat/backend-shares-handlers`, base `master`. Commit: `feat(shares): implement 6 shares+invites handlers + common helpers`. Link infra PR in description. Include ToS spot-check outcome.
- Squash-merge both.

---

## Skills / Agents to Use

- **backend-engineer**: authoring the 6 handlers + 2 common helpers. Knows the `common/` pattern and `handle_errors` / `success_response` / `require_fields` conventions.
- **test-writer**: pytest coverage per the matrix above. Mirror `tests/test_friends_list.py`.
- **code-reviewer**: run on both PRs before merge. Focus on Phase A → ownership check in `shares_delete` handler, rate-limit logic in `invites_create`, transactional write in `invites_accept`.
