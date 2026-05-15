# EDD — Provider OAuth Research: PKCE Across Integrations

| Field | Value |
|---|---|
| Status | Proposed |
| Owner | Solo |
| Last updated | 2026-05-14 |
| Implements ticket | F-14 (Per-provider OAuth integration) |
| Companion docs | EDD — PKCE · EDD — Integration Matrix · EDD — Bootstrap |

---

## Table of contents

1. [Summary](#1-summary)
2. [Common ground](#2-common-ground)
3. [Per-provider breakdown](#3-per-provider-breakdown)
4. [Comparison matrix](#4-comparison-matrix)
5. [Token lifecycle matrix](#5-token-lifecycle-matrix)
6. [Implications for our architecture](#6-implications-for-our-architecture)
7. [Implementation order](#7-implementation-order)
8. [Open questions](#8-open-questions)

---

## 1. Summary

This EDD documents the actual OAuth behavior of each provider From Ink integrates with — researched from primary documentation, not assumed from the RFC spec. The goal is to surface every provider-specific difference that our generic PKCEEngine and OAuthService must handle.

**Key finding:** While the PKCE flow itself is standard across all six providers (authorize → code → exchange → token), the token lifecycle varies dramatically. Access token expiry ranges from 1 hour (Asana, Todoist) to never (GitHub OAuth Apps). Refresh token rotation is required by four of six providers. Two providers (Slack, Todoist) will revoke all tokens if a stale refresh token is replayed. These differences are the engineering risk — the auth flow itself is mechanical.

**Providers covered:** Linear, GitHub, Slack, Asana, Todoist, Canva. Airtable deferred.

---

## 2. Common ground

Every provider shares these behaviors. Our `PKCEEngine` handles all of them correctly as-is.

| Aspect | Common behavior |
|---|---|
| Grant type | `authorization_code` |
| PKCE challenge method | `S256` (SHA-256) — all six support it |
| Code verifier | 32+ bytes, base64url-encoded |
| Redirect capture | Custom URL scheme (`fromink://`) or localhost |
| Token endpoint method | `POST` with `application/x-www-form-urlencoded` body |
| Token response format | JSON with `access_token`, `token_type` fields |
| State parameter | All support it for CSRF; most recommend it |
| Bearer token usage | `Authorization: Bearer {token}` header |

---

## 3. Per-provider breakdown

### 3.1 Linear

| Aspect | Detail |
|---|---|
| **Authorize URL** | `https://linear.app/oauth/authorize` |
| **Token URL** | `https://api.linear.app/oauth/token` |
| **Revoke URL** | `https://api.linear.app/oauth/revoke` |
| **PKCE** | Supported, optional. S256 and plain. |
| **Client secret** | Not required when using PKCE (public client) |
| **Access token expiry** | **24 hours** |
| **Refresh token returned** | Yes, always |
| **Refresh token rotation** | **Yes** — new refresh token on every refresh |
| **Refresh grace period** | **30 minutes** — consumed refresh token remains valid for retries |
| **Scopes** | `read`, `write`, `issues:create`, `comments:create`, `timeSchedule:write`, `admin` |
| **Scope separator** | **Comma** (`,`) — not space |
| **Special** | `actor=app` parameter for resource attribution; `prompt=consent` forces re-consent |

**Risk:** Low. 24h access tokens with rotating refresh + 30min grace is generous. Our 1-hour foreground sweep is sufficient.

### 3.2 GitHub (GitHub Apps)

| Aspect | Detail |
|---|---|
| **Authorize URL** | `https://github.com/login/oauth/authorize` |
| **Token URL** | `https://github.com/login/oauth/access_token` |
| **Revoke URL** | `DELETE /applications/{client_id}/token` (REST API, not a simple POST) |
| **PKCE** | Supported since July 2025, optional. **S256 only.** |
| **Client secret** | Required for token exchange and refresh |
| **Access token expiry** | **8 hours** |
| **Refresh token returned** | Yes (GitHub Apps with token expiration enabled) |
| **Refresh token rotation** | **Yes** — old token invalidated on use |
| **Refresh token expiry** | **6 months** |
| **Scopes** | Permissions-based, not traditional scopes. Limited to intersection of app permissions and user permissions. Scope parameter returns empty string. |
| **Special** | `Accept: application/json` header required on token endpoint to get JSON (otherwise returns form-encoded). Revocation uses `DELETE` not `POST`. |

**Risk:** Medium. Client secret required means we must handle it carefully — the PKCE EDD says no client secrets in the app bundle. For GitHub Apps, the client secret is needed server-side for the token exchange. **This may require a lightweight proxy or a different approach for native apps.** Alternatively, GitHub OAuth Apps (not GitHub Apps) don't expire tokens at all but also don't support PKCE natively. This needs a decision.

**Decision needed:** GitHub App (8h tokens, refresh, needs client secret) vs GitHub OAuth App (non-expiring tokens, no refresh, simpler). See §8.

### 3.3 Slack

| Aspect | Detail |
|---|---|
| **Authorize URL** | `https://slack.com/oauth/v2/authorize` |
| **Token URL** | `https://slack.com/api/oauth.v2.access` |
| **Revoke URL** | `https://slack.com/api/auth.revoke` |
| **PKCE** | **Required** for custom URI schemes. S256 only. |
| **Client secret** | **Not required** for public clients using PKCE + custom URI scheme |
| **Access token expiry** | **12 hours** (with token rotation enabled) |
| **Refresh token returned** | Yes, when token rotation is enabled |
| **Refresh token rotation** | **Mandatory** when using custom URI schemes — Slack forces rotation even if the app setting is off |
| **Refresh token expiry** | **30 days** |
| **Scopes** | User scopes only for desktop redirects (no bot scopes). Examples: `chat:write`, `channels:read`, `users:read` |
| **Scope separator** | Comma (`,`) |
| **Special** | Enabling PKCE marks the app as a public client — **one-way, irreversible**. Desktop redirects (custom URI) cannot request bot scopes. No PKCE parameters needed during refresh (standard refresh flow). |

**Risk:** **High.** 30-day refresh token expiry means background refresh (Layer 2) is mandatory. If the user doesn't open the app for 30 days, the Slack connection dies. Mandatory token rotation means replay of a stale refresh token is a hard failure.

### 3.4 Asana

| Aspect | Detail |
|---|---|
| **Authorize URL** | `https://app.asana.com/-/oauth_authorize` |
| **Token URL** | `https://app.asana.com/-/oauth_token` |
| **Revoke URL** | `https://app.asana.com/-/oauth_revoke` |
| **PKCE** | Supported. S256. |
| **Client secret** | Required for token exchange |
| **Access token expiry** | **1 hour** (3600 seconds) |
| **Refresh token returned** | Yes |
| **Refresh token rotation** | **No** — same refresh token reused |
| **Refresh token expiry** | **Not documented** — appears to be long-lived (possibly indefinite) |
| **Scopes** | Resource-action format: `tasks:read`, `tasks:write`, `projects:read`, `users:read`, etc. Must be pre-registered. |
| **Scope separator** | Space (standard) |
| **Special** | Token response includes a `data` object with user `id`, `gid`, `name`, `email` — can be used for `displayName` without a separate API call. Revocation requires `client_secret` and accepts only refresh tokens (not access tokens). |

**Risk:** Medium. 1-hour access tokens require frequent refresh, but the non-rotating refresh token simplifies things. Client secret required — same concern as GitHub. **However,** Asana's PKCE docs mention `code_verifier` being sent to the token endpoint, which suggests PKCE may be usable without client secret for native apps. Needs verification.

### 3.5 Todoist

| Aspect | Detail |
|---|---|
| **Authorize URL** | `https://app.todoist.com/oauth/authorize` |
| **Token URL** | `https://api.todoist.com/oauth/access_token` |
| **Revoke URL** | `POST https://api.todoist.com/api/v1/revoke` (RFC 7009 compliant) |
| **PKCE** | Required for public clients (using OAuth 2.0 Client ID Metadata Document flow) |
| **Client secret** | **Not required** for public clients using PKCE |
| **Access token expiry** | **1 hour** (3600 seconds) for new apps |
| **Refresh token returned** | Yes (for new apps; legacy apps get 10-year non-expiring access tokens) |
| **Refresh token rotation** | **Yes** — new refresh token on every refresh |
| **Refresh grace period** | **60 seconds** — consumed token remains valid for retry |
| **Refresh token expiry** | Not explicitly documented — but rotation means stale tokens are invalidated |
| **Scopes** | `task:add`, `data:read`, `data:read_write`, `data:delete`, `project:delete`, `backups:read` |
| **Scope separator** | Comma (`,`) |
| **Special** | Supports **Dynamic Client Registration** (RFC 7591) — no pre-registration needed, POST to `https://api.todoist.com/oauth/register`. Also supports zero-registration via Client ID Metadata Document (client_id is an HTTPS URL). **Replay detection:** replaying a consumed refresh token outside the 60s grace window revokes ALL tokens for that user — they must re-authorize. |

**Risk:** Medium-high. Rotating refresh tokens with aggressive replay detection means our `TokenRefreshCoordinator` serialization is critical. The 60-second grace window is shorter than Linear's 30 minutes. Dynamic Client Registration is a nice option for avoiding app store developer console setup.

### 3.6 Canva

| Aspect | Detail |
|---|---|
| **Authorize URL** | `https://www.canva.com/api/oauth/authorize` |
| **Token URL** | `https://www.canva.com/api/oauth/token` (inferred from docs) |
| **Revoke URL** | Exists (URL not specified in public docs) |
| **PKCE** | **Required.** S256 only. |
| **Client secret** | **Required** — "Requests authenticating with client ID and client secret can't be made from web-browser clients" (backend auth required) |
| **Access token expiry** | Short-lived (exact duration not documented — described as "only valid for a short period") |
| **Refresh token returned** | Yes |
| **Refresh token rotation** | **Yes** — "Each refresh token can only be used once" |
| **Refresh token expiry** | Not documented |
| **Scopes** | Resource-action format: `asset:read`, `asset:write`, `design:meta:read`, `folder:read`, `comment:write`. Write does NOT imply read — must request both explicitly. |
| **Scope separator** | Space (standard) |
| **Special** | Backend authentication required — Basic auth with `client_id:client_secret`. This means Canva **cannot be used as a pure public client** without a proxy. |

**Risk:** **High architectural concern.** Canva requires a client secret for token exchange, and their docs explicitly say it can't be done from browser/native clients. This may require a lightweight server proxy for the token exchange step, or Canva may need to be dropped from V1 native integrations. See §8.

---

## 4. Comparison matrix

| | Linear | GitHub | Slack | Asana | Todoist | Canva |
|---|---|---|---|---|---|---|
| **PKCE required** | No | No | Yes (custom URI) | No | Yes (public) | Yes |
| **Client secret needed** | No (PKCE) | Yes | No (PKCE) | Yes | No (PKCE) | Yes |
| **Pure public client** | Yes | No | Yes | No | Yes | No |
| **Scope separator** | Comma | N/A | Comma | Space | Comma | Space |
| **Token response includes user** | No | No | No | Yes (`data` object) | No | No |
| **Revocation** | POST | DELETE | POST | POST (secret required) | POST (RFC 7009) | Exists |

### Public client compatibility (no server needed)

| Provider | Works without client secret? | Notes |
|---|---|---|
| **Linear** | Yes | PKCE replaces client secret |
| **GitHub** | **No** | Client secret required for exchange + refresh |
| **Slack** | Yes | PKCE + custom URI = public client |
| **Asana** | **Unclear** | Docs mention PKCE but also require secret; needs verification |
| **Todoist** | Yes | PKCE + Dynamic Client Registration |
| **Canva** | **No** | Backend auth explicitly required |

---

## 5. Token lifecycle matrix

| | Access token TTL | Refresh token TTL | Refresh rotates? | Grace period | Background refresh needed? |
|---|---|---|---|---|---|
| **Linear** | 24 hours | Indefinite | Yes | 30 min | No (foreground sweep sufficient) |
| **GitHub** | 8 hours | 6 months | Yes | None documented | No (6-month window is long) |
| **Slack** | 12 hours | **30 days** | **Mandatory** | None documented | **Yes — mandatory** |
| **Asana** | 1 hour | Indefinite (long-lived) | No | N/A | No (non-rotating, long-lived) |
| **Todoist** | 1 hour | Rotates (no stated expiry) | Yes | 60 sec | Recommended |
| **Canva** | Short (unspecified) | Rotates (no stated expiry) | Yes | None documented | Recommended |

### Refresh frequency required to stay connected

| Provider | Minimum refresh frequency | What happens if you miss it |
|---|---|---|
| Linear | Every 24h (access token) | Access fails; refresh with grace period |
| GitHub | Every 8h (access token) | Access fails; refresh within 6 months |
| Slack | **Every 30 days** (refresh token) | **Connection permanently lost** — re-auth required |
| Asana | Every 1h (access token) | Access fails; refresh anytime (non-rotating) |
| Todoist | Every 1h (access token) | Access fails; refresh or **all tokens revoked on replay** |
| Canva | Frequently (short access) | Access fails; refresh (rotating) |

---

## 6. Implications for our architecture

### 6.1 Client secret problem

Three providers (GitHub, Asana, Canva) require a client secret for token exchange. Our PKCE EDD principle #2 states "no client secrets in the app bundle." Options:

**Option A — Lightweight token exchange proxy.** A minimal CloudFlare Worker or similar that holds client secrets and proxies the token exchange. The native app sends the authorization code to the proxy; the proxy adds the client secret and forwards to the provider. No user data touches the proxy — only the OAuth exchange.

**Option B — Drop providers that need client secrets from V1.** Ship Linear, Slack, and Todoist first (pure public clients). Add GitHub, Asana, and Canva when the proxy is built.

**Option C — Accept the risk for native apps.** Some providers (GitHub, Asana) accept the reality that native apps ship with embedded client IDs. The client secret for a public-client-style native app is not truly secret — it's a credential for identifying the app, not for authenticating a user. Apple's own guidance for ASWebAuthenticationSession acknowledges this pattern.

**Recommendation:** Option B for V1 (ship pure public clients first), then Option A for V2 (proxy for secret-requiring providers). This keeps V1 simple and server-free.

### 6.2 Scope separator inconsistency

Linear, Slack, and Todoist use **comma** as the scope separator. Asana and Canva use **space** (the RFC standard). Our `OAuthProviderConfig` currently joins scopes with space:

```swift
config.scopes.joined(separator: " ")
```

**Fix:** Add a `scopeSeparator: String` field to `OAuthProviderConfig`. Default to space per RFC, override to comma for Linear/Slack/Todoist.

### 6.3 Refresh token rotation handling

Four of six providers rotate refresh tokens. Our `TokenRefreshCoordinator` already handles this — the new token (with new refresh token) is saved to Keychain atomically. The critical detail: **Todoist revokes ALL tokens on stale replay** outside a 60-second window. Our serialization prevents concurrent refresh, but a crash between "send refresh request" and "save new token" could leave a stale token in Keychain. Mitigation: save the new token **before** returning it to callers.

### 6.4 GitHub revocation uses DELETE, not POST

Our `_revoke` function sends a POST. GitHub uses `DELETE /applications/{client_id}/token`. `OAuthProviderConfig` needs a `revokeMethod: HTTPMethod` field, or revocation should be a provider-specific closure on the config.

### 6.5 Asana returns user data in token response

Asana's token response includes `data.name` and `data.email`. This is the `displayName` for the `IntegrationAccount` — no separate user-info API call needed. Our `parseTokenResponse` should be extensible to capture provider-specific extras.

### 6.6 Todoist Dynamic Client Registration

Todoist supports RFC 7591 — the app can register itself at runtime. This eliminates the need to pre-register at developer.todoist.com. Worth exploring for reduced setup friction, but not required for V1.

---

## 7. Implementation order

Based on complexity, risk, and public-client compatibility:

| Order | Provider | Why |
|---|---|---|
| 1 | **Linear** | Simplest. Pure public client, generous 24h tokens, 30min grace, well-documented. Good first integration to prove the system. |
| 2 | **Todoist** | Pure public client, PKCE required, rotating tokens with 60s grace — tests our serialization. Dynamic Client Registration is a bonus. |
| 3 | **Slack** | Pure public client, mandatory rotation, 30-day refresh expiry — tests our background refresh. Highest risk of silent disconnection. |
| 4 | **Asana** | Needs client secret — blocked until proxy decision. 1h access tokens, non-rotating refresh simplifies lifecycle. |
| 5 | **GitHub** | Needs client secret, 8h tokens, 6-month refresh, DELETE revocation — moderate complexity but blocked. |
| 6 | **Canva** | Needs client secret + backend auth explicitly required — most blocked. Deferred. |

---

## 8. Open questions

| # | Question | Impact |
|---|---|---|
| 1 | GitHub App vs GitHub OAuth App? | OAuth Apps have non-expiring tokens (simpler) but no PKCE. GitHub Apps have PKCE + expiring tokens but require client secret. Which model do we use? |
| 2 | Token exchange proxy for V2? | CloudFlare Worker? AWS Lambda? Apple's own CloudKit? Needs minimal infrastructure — just secret injection on the exchange call. |
| 3 | Can Asana PKCE work without client secret? | Their docs mention PKCE but also require secret. Test with a real request — some providers accept PKCE as a secret replacement even if docs don't say so explicitly. |
| 4 | Todoist Dynamic Client Registration — V1 or V2? | Reduces developer setup friction. Low implementation cost (one POST). Could be V1. |
| 5 | Canva backend auth — is there a mobile/native path? | Canva docs explicitly say no browser clients. Is there an undocumented native app flow? Contact Canva developer relations. |
| 6 | Scope separator — should `OAuthProviderConfig` handle this? | Three providers use comma, two use space. Small fix but important for correctness. |

---

## 9. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-14 | Research all six providers before implementing any. | Token lifecycle differences are the engineering risk, not the auth flow. Must know what we're building for. |
| 2026-05-14 | Ship pure public clients first (Linear, Todoist, Slack). | No server infrastructure needed. Proves the system end-to-end. |
| 2026-05-14 | Defer GitHub, Asana, Canva until proxy decision. | Client secret requirement conflicts with "no secrets in app bundle" principle. |
| 2026-05-14 | Airtable deferred from research. | Will be added when implementation begins. |

---

## Sources

- [Linear OAuth 2.0 Authentication](https://linear.app/developers/oauth-2-0-authentication)
- [GitHub PKCE Support Changelog](https://github.blog/changelog/2025-07-14-pkce-support-for-oauth-and-github-app-authentication/)
- [GitHub Refreshing User Access Tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens)
- [Slack PKCE Authentication](https://docs.slack.dev/authentication/using-pkce/)
- [Asana OAuth](https://developers.asana.com/docs/oauth)
- [Todoist API v1](https://developer.todoist.com/api/v1/)
- [Canva Connect Authentication](https://www.canva.dev/docs/connect/authentication/)
