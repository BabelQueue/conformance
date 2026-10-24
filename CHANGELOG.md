# Changelog

All notable changes to the conformance suite. The version is `CONFORMANCE_VERSION`
(SemVer; MINOR = additive cases or sections, no existing expectation changes, except a
case that contradicted the contract, which a MINOR may correct and must list explicitly). The
per-version prose history lives in `README.md` under "Suite version history".

## 1.6.0

Governing decisions: ADR-0033 (Redis delays and recovery), ADR-0034 (Kafka retry tiers and
poison), ADR-0035 (poison DLQ record shape), ADR-0032 (suite structure).

### Added

- Section `redis_delay` (scope `redis`): delayed-score cases with a pinned clock,
  `floor(now) + ceil(delay)` (broker-bindings §1.6), fractional `now` and `delay` included.
- Section `kafka_poison` (scope `kafka`): 92 cases `{name, body, expect: ok | no_identity | poison}`
  (broker-bindings §6, ADR-0034 §10, ADR-0032 §6). The former 78-row per-SDK table is reclassified
  into it; a repeated top-level key is last-wins. Three old rows change classification: `{"job":5}` and
  `{"job":"urn:x","job":5}` poison to `no_identity`, and "duplicate job number then string"
  (`{"job":5,"job":"urn:x"}`) poison to `ok`.
- Section `poison_dlq` (scope `core`): 43 cases `{name, body | body_base64, expect: {shape, record}}`
  pinning the DLQ record of a poison body (ADR-0035, error-handling §6): an object body is spliced
  (`record` is the body plus `dead_letter`), anything else is wrapped as `{raw, raw_encoding?}` with
  `raw` the plain string for valid UTF-8 (`raw_encoding` omitted, never `utf8`) and the padded standard
  base64 plus `raw_encoding: "base64"` for invalid UTF-8 (U+FFFD substitution is forbidden); an object that
  already carries `dead_letter` is wrapped, not overwritten. Compared as parsed JSON after removing
  `dead_letter`, never as bytes. "Object" is strict RFC 8259: `NaN` / `Infinity` / `-Infinity` literals and
  unpaired surrogate escapes (in a key or a value) are wrapped as plain `raw`. A new case shape
  `splice_or_wrapper` with `splice_literals` covers bodies a re-encoding writer cannot carry losslessly
  (`1e400`, `-1e400`, `1e-400`, an integer beyond int64, a decimal beyond double precision, nesting depth
  600) and bodies with a repeated member name (top-level `{"job":"urn:x","job":5}` and nested), whose
  re-encode keeps only the last value: the record is either the wrapper `{raw: body}` or a byte-level
  splice that contains every `splice_literals` entry verbatim, has no top-level `raw` / `raw_encoding`
  member and whose distinct top-level member names other than `dead_letter`, compared as a set, equal `splice_keys`; a re-encode that
  changes a value or collapses a repeated member fails. The four `encode-fails-*`
  bodies appear here too. No existing case expectation changes for ADR-0035; its cases are additions only.
- `redis_layout.pcall_poison`: four `encode-fails-*` cases (`1e400`, `-1e400`, `NaN`, `Infinity` inside
  `data`) for the second `pcall` of the reserve Lua (the `cjson.encode`, ADR-0033 A1): `cjson.decode` accepts
  these literals and `cjson.encode` refuses them, so the body decodes with a numeric `attempts` and only the
  re-encode fails; the expected result is the same raw `{job, job}` poison as the decode failures. The
  block `description` explains the choice.
- `backoff` blocks `topic_names`, `retry_attempt_tier` and `default_tiers`
  (broker-bindings §6.4-6.5, ADR-0034 §9).
- Section `retry_backoff` (scope `core`): the delay formula table (`jitter = none` exact, `full` bounded
  by `[0, d(n)]`), moved out of the `kafka`-scoped `backoff` because it is core retry policy, not Kafka.
- `redis_layout` behavioural blocks `delayed_score`, `migrate`, `reserve`, `pcall_poison`,
  `release`, `processing_sweep`, `processing_token`, `late_ack`, `identical_copies`,
  `retry_after_null`, `lrem_count`, `malformed_member`, `orphan`, `legacy_release_gate`,
  `legacy_dlq_gate` (broker-bindings §1.1, §1.6, §1.7). `retry_after_null` also pins that `null` is not a
  kill switch (the sweep still runs before every reserve); the gate blocks pin the stale-token and
  valid-token paths of the legacy release and dead-letter scripts. The case DSL gains the op
  `dead_letter` and the count expectations `ready_count` / `dlq_count`.
- `ci.yml` oracles that recompute the expectations of `poison_dlq` (an independent reference of the
  ADR-0035 record shape; every shape covered; strict parsing that rejects `NaN` / `Infinity` literals and
  unpaired surrogates; repeated member names (a plain `splice` case may not contain one; top-level and nested repeats both covered); the `splice_or_wrapper` literals and `splice_keys` (distinct top-level names, compared as a set); a lossy number (overflow, underflow, integer beyond int64 or beyond 2^53 for a double-only writer, decimal beyond double precision) can never sit in a plain `splice` case, and overflow, underflow, int64 and decimal are each covered; wrapper cases required for each non-JSON literal (matched as a bounded token, so `-Infinity` cannot satisfy `Infinity`) and
  surrogate form; every `encode-fails-*` body also present in `poison_dlq`) and check the `encode-fails-*` bodies, and of `redis_delay`, `redis_layout.delayed_score`,
  `backoff` (`topic_names`, `retry_attempt_tier`, `default_tiers`, `retry_republish`),
  `retry_backoff` and the `migrate` notify/ready/delayed counts.
- Runner contract in the `redis_layout` description: behavioural blocks need a live Redis;
  with `BQ_REQUIRE_REDIS` set an unreachable Redis is a failure, not a skip.

### Changed

- `redis_layout` and `backoff` descriptions: the "left to the R1 Redis plan" deferral and the
  "`<n>` undefined" note are removed.
- `backoff.retry_republish` (a v1.5.0 block, key kept) is corrected to the §6.5 attempt-to-tier rule:
  `n = min(attempts_before, N-1) + 1`, `bq-delay` = that tier's ms, `bq-attempts = attempts_before + 1`,
  `bq-original-topic`; the earlier `release_delay_ms` expectation contradicted §6.5. The `backoff`
  description is rewritten to keep the §6.4 requested-delay rule and the §6.5 retry rule apart.
- `redis_layout` `reserve/deadline-is-floor-now-plus-retry-after` and
  `reserve/attempts-0-to-1-raw-to-handler`: `source` now cites broker-bindings §1.1 (the deadline is
  `floor(now) + retry_after`); the fixtures are unchanged. The `delayed_score` and `redis_delay`
  descriptions point at each other.
- `CONFORMANCE_VERSION` and `schema/results.example.json` carry `1.6.0`.

### Compatibility

- No v1.5.0 case expectation changed except the `backoff.retry_republish` correction above; `fetch.sh`
  is untouched. `ci.yml` gained the 1.6.0 oracle steps, and its v1.5 `retry_republish` oracle was
  rewritten to the §6.5 attempt → tier rule to match that correction.
- Until the 1.6.0 release asset is published and its hash pinned, SDK repositories vendor this
  suite from the local checkout with `sync.sh`.

## 1.5.0 and earlier

See "Suite version history" in `README.md`.
