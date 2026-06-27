# Positive Fixture: Issue Decomposition

Pattern: [Issue Decomposition](../issue-decomposition.md)
Kind: positive
Verification: manual review; no automated validator wired
Date: 2026-06-27

## Input

**Issue title:** Add OAuth 2.0 authentication, request throttling, and
client-side caching to the HTTP client library

**Issue body:**

> The HTTP client library currently supports only API-key authentication and
> has no rate-limit handling or response caching. We need to ship three
> capabilities before the v2.0 release:
>
> 1. OAuth 2.0 authorization-code flow with automatic token refresh.
> 2. A token-bucket rate limiter that respects `Retry-After` headers and
>    exposes a configurable burst limit.
> 3. An LRU response cache with TTL support, configurable per-endpoint, and
>    a `cache-bypass` request option.
>
> These features interact: the rate limiter must account for token-refresh
> requests, and cached responses must not be served when the auth token has
> expired. Each capability needs its own tests, documentation, and migration
> guide from v1.x.

**Observed constraints:**

- The library ships as a single package; each feature must not break
  existing API-key users.
- The team has two reviewers familiar with OAuth but none with caching
  internals.
- A marketing deadline requires auth to land two weeks before the other
  two features.

## Decomposition Rationale

Applying the [Issue Decomposition](../issue-decomposition.md) pattern:

1. **Read the full scope.** The request mixes three distinct capabilities
   (auth, throttling, caching) that share a dependency surface (the HTTP
   request pipeline) but have independent risk profiles and reviewer
   availability.

2. **Identify independent concerns.**
   - OAuth 2.0 touches the auth layer and token storage; no dependency on
     rate limiting or caching.
   - Rate limiting touches the request pipeline; needs awareness of
     token-refresh requests but not cache internals.
   - Caching touches the response pipeline; must check token expiry but
     does not need rate-limiter internals.
   - Cross-cutting: integration tests that exercise all three together.

3. **Define sub-task boundaries.** Each capability becomes one sub-task
   scoped to a single PR that leaves the library working for existing users.
   A fourth sub-task covers integration tests and the combined migration
   guide.

4. **Order by dependency.** Auth is foundational (rate limiter and cache
   both reference token state). Rate limiter comes next (cache must respect
   retry-after semantics). Caching last (needs token-expiry awareness from
   auth). Integration tests after all three.

5. **Write scoped acceptance.** Each sub-task has criteria verifiable in
   isolation (see Output below).

6. **Track in a single parent spec.** All sub-tasks link back to this
   fixture issue and to a parent spec tracking v2.0 readiness.

## Output

### Sub-task 1: OAuth 2.0 Authorization-Code Flow

**Scope:**

- Implement `OAuthAuthenticator` class supporting authorization-code flow
  with PKCE.
- Implement automatic token refresh when the access token is within a
  configurable expiry window.
- Store tokens in a pluggable `TokenStore` interface (default:
  file-backed).
- Add configuration options: `client_id`, `client_secret`, `redirect_uri`,
  `scopes`, `token_refresh_margin`.
- Unit tests for token acquisition, refresh, and error paths.
- Documentation: configuration guide, migration guide from API-key auth.

**Non-goals:**

- Client-credentials or device-authorization flows (future work).
- Server-side token management.
- UI components for the authorization redirect.

**Acceptance criteria:**

- A fresh install with valid OAuth credentials can obtain an access token
  and make authenticated requests.
- Expired tokens are refreshed transparently without request failure.
- Existing API-key authentication continues to work unchanged.
- All new public classes and methods have docstrings and appear in the
  generated API reference.

**Dependency / sequencing:**

- No dependency on sub-tasks 2 or 3.
- Must merge before sub-tasks 2 and 3 (they reference `TokenStore`).

**Merge-safe boundary:**

- All existing tests pass without modification.
- New classes are additive; no existing public API signature changes.
- Feature is opt-in via configuration; default behavior is unchanged.

---

### Sub-task 2: Token-Bucket Rate Limiter

**Scope:**

- Implement `TokenBucketLimiter` with configurable capacity, refill rate,
  and burst limit.
- Respect `Retry-After` headers: pause and retry on 429 responses.
- Expose `RateLimitExceeded` exception with retry-after metadata.
- Integrate with the request pipeline at the transport layer.
- Unit tests for burst handling, refill, retry-after, and exceeded paths.
- Documentation: configuration guide, behavior under load.

**Non-goals:**

- Distributed rate limiting across multiple client instances.
- Sliding-window or leaky-bucket algorithms.
- Server-side rate-limit enforcement.

**Acceptance criteria:**

- Requests exceeding the configured rate are delayed (not dropped) up to
  the burst limit, then raise `RateLimitExceeded`.
- A 429 response with `Retry-After` causes automatic retry after the
  specified delay.
- Token-refresh requests (from sub-task 1) are counted against the rate
  limit when the limiter is enabled.
- Existing behavior is unchanged when the rate limiter is not configured.

**Dependency / sequencing:**

- Depends on sub-task 1 being merged (needs `OAuthAuthenticator` to
  integrate token-refresh counting).
- Must merge before sub-task 3 (cache respects retry-after semantics).

**Merge-safe boundary:**

- All existing tests and sub-task 1 tests pass.
- Rate limiter is opt-in; default transport behavior unchanged.
- No changes to `OAuthAuthenticator` public API.

---

### Sub-task 3: LRU Response Cache

**Scope:**

- Implement `LRUCache` with per-endpoint TTL configuration and a
  `cache-bypass` request option.
- Check token expiry before serving cached responses; discard stale
  entries when the token has expired.
- Integrate with the response pipeline after the transport layer.
- Unit tests for cache hit, miss, TTL expiry, token-expiry invalidation,
  and bypass.
- Documentation: configuration guide, cache key format.

**Non-goals:**

- Persistent or disk-backed caching.
- Cache sharing across multiple client instances.
- Cache-control header parsing (future work).

**Acceptance criteria:**

- Repeated identical requests within TTL return cached responses without a
  network call.
- Cached responses are invalidated when the OAuth token expires.
- The `cache-bypass` request option forces a fresh network call.
- Existing behavior is unchanged when the cache is not configured.

**Dependency / sequencing:**

- Depends on sub-task 1 being merged (needs `TokenStore` to check token
  expiry).
- Depends on sub-task 2 being merged (cached responses must not bypass
  rate-limit accounting on cache miss).

**Merge-safe boundary:**

- All existing tests and sub-tasks 1-2 tests pass.
- Cache is opt-in; default response behavior unchanged.
- No changes to `OAuthAuthenticator` or `TokenBucketLimiter` public APIs.

---

### Sub-task 4: Integration Tests and Combined Migration Guide

**Scope:**

- Integration tests exercising all three features together: OAuth flow
  under rate limiting with caching enabled.
- Edge-case tests: token refresh during rate-limited queue, cache
  invalidation during token refresh, burst with cache bypass.
- Combined migration guide covering v1.x to v2.0 upgrade path for users
  adopting any combination of the three features.

**Non-goals:**

- Performance benchmarks (separate tracking issue).
- End-to-end tests against live OAuth providers.

**Acceptance criteria:**

- Integration tests cover the three documented interaction points:
  token-refresh rate counting, cache invalidation on token expiry, and
  retry-after behavior with cached responses.
- Migration guide covers: API-key-only users (no change), OAuth-only
  users, OAuth + rate-limit users, and all-three users.
- All CI checks pass with all three features enabled.

**Dependency / sequencing:**

- Depends on sub-tasks 1, 2, and 3 all being merged.
- Does not block any other sub-task.

**Merge-safe boundary:**

- Only adds new test files and documentation; no production code changes.
- All existing tests from sub-tasks 1-3 continue to pass.
