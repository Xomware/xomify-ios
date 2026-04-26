# Reference: Auth Identity Hardening + Live `/user/top-items`

This repo (`xomify-ios`) is part of a **5-repo epic**. The canonical plan lives at:

**`/Users/dom/Code/xomify-backend/docs/features/auth-identity-and-live-top-items/PLAN.md`**

Read that doc for full context. This file is a pointer + a list of sub-features that touch THIS repo.

## Sub-features in this repo

- **(0d) `ios-per-user-jwt`** — After Spotify OAuth (existing `AuthService.saveRefreshTokenToXomify` flow), call `POST /auth/login` to mint a per-user JWT. Store in keychain (same access group as the Spotify refresh token). Replace every `XOMIFY_API_TOKEN` reference (`AuthService.swift:265`, `NetworkService.swift:202`, others — sweep with `grep -r`). Add a 401-retry interceptor in `NetworkService` that refreshes Spotify token, re-mints, and retries once.

- **(1k) `ios-drop-caller-email`** — Sweep iOS networking layer. Remove caller `email` from request construction. Keep target emails (`friendEmail`, etc.).

- **(2c) `ios-current-page-wire-up`** — Point the "Top 25 — Last 4 Weeks (Current)" page at `GET /user/top-items` instead of `GET /wrapped/all`. Wrapped page (historical snapshot view) stays on `/wrapped/all`.

## Affected repos (full epic)

1. `xomify-backend` (Python lambdas) — canonical plan owner
2. `xomify-frontend` (Angular)
3. `xomify-ios` (Swift) — **this repo**
4. `xomify-infrastructure` (Terraform)
5. `api-gateway-service` (external Terraform module) — published from a separate GitHub repo, not locally cloned

## Status

Per-sub-feature status is tracked on **XomBoard (GitHub Project #2)** via per-repo issues. The canonical plan doc is the source of truth for design and dependencies.
