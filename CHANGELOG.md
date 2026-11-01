# Changelog

All notable changes to the conformance suite. The version is `CONFORMANCE_VERSION`
(SemVer; MINOR = additive cases or sections, no existing expectation changes, except a
case that contradicted the contract, which a MINOR may correct and must list explicitly). The
per-version prose history lives in `README.md` under "Suite version history".

## 1.9.0

Governing decisions: ADR-0038 (OpenTelemetry semantic-conventions alignment, span shape and the non-UUID
`trace_id` rule) and ADR-0039 (standard metrics and the dead-letter observer), with ADR-0032 (section 2,
the `otel` scope) and ADR-0028 (`traceparent`). R1 OTel plan, phase 02.

### Added

- Section `span-shape` (scope `otel`): 37 cases `{name, mode: span, operation, system?, queue?, urn,
  consumer_group?, trace_id?, message_id?, attempts?, schema_version?, outcome, expect}` (ADR-0038 section 4).
  `expect` is the span name, the span kind (`PRODUCER` | `CONSUMER`), the status and the attribute map (every
  listed key present with that value; a table key not listed must be absent; an extra `babelqueue.*` key is
  forbidden, an extra semconv-defined attribute is allowed, as the ADR permits), including the deprecated transition keys `messaging.operation` and `messaging.babelqueue.attempts` that are
  dual-emitted for one MINOR (ADR-0038 section 5). Covers: the seven broker `system` values, a custom
  `system` (written as given), an absent and an empty `system` (`babelqueue`), Kafka with `consumer_group`
  (and the group on a non-Kafka system, and Kafka without it), an empty, absent and blank `meta.queue` on
  consume (bare `process` name, no `messaging.destination.name`) and an absent or empty queue given to a
  producer (the SDK resolves it, so the expectation is the placeholder `$produced.meta.queue`), an absent `meta.id`, `attempts` 0 and > 0, a
  non-UUID and a whitespace-padded `trace_id` in `messaging.message.conversation_id`, and a failing publish
  and handler (`error.type` presence is asserted, never its language-specific value). A producer cannot fix
  `meta.id` and stamps the active trace's id into `trace_id`, so `send` cases carry no such input and use the
  placeholders `$produced.meta.id`, `$produced.trace_id` and, for an absent or empty queue, `$produced.meta.queue`, which the
  runner replaces with the produced envelope's values. The case where the envelope is never built does not pin the destination
  (`optional_attributes`, `span_name_one_of`), because ADR-0038 only says the producer SHOULD resolve the queue
  before it starts the span.
- Section `trace-id` (scope `otel`): 43 cases (ADR-0038 section 7, `message-envelope.md` sections 5.1 and 7
  rule 2). `map` (22): the OTel TraceID mapping, pinned to the Go reference `otel.TraceIDOf` (a UUID, with or
  without hyphens and in any case, decodes; the all-zero value, a non-UUID and a value with a leading or
  trailing ASCII space or a trailing newline are hashed over the raw bytes, SHA-256 first 16 bytes). `decode` (6), `reemit` (6) and
  `downstream` (4): a non-UUID `trace_id` is preserved byte for byte, never rejected or regenerated. `make`
  (5): a caller-supplied non-UUID `trace_id` is stored with only the ADR-0032 ASCII trim.
- Section `metrics` (scope `otel`): 29 cases (ADR-0039). `instrument` (5): name, kind, unit and attribute key
  set of `messaging.process.duration`, `messaging.client.sent.messages`, `messaging.client.consumed.messages`,
  `babelqueue.retries` and `babelqueue.dlq.messages`, plus the attributes that must never appear. `publish`
  (5) and `consume` (7): scenario cases with the exact recorded data points (one successful consume, a failing
  consume with `attempts` 2, no destination, no meter). `dead_letter` (12): observer-level cases (the five `observer_called: false` cases carry `sdk_test_required: true`: a runner can only report them `pass` trivially, so each SDK's own test must assert the rule) for
  `babelqueue.dlq.messages` (ADR-0039 section 5.1, owner decision 2026-10-31): +1 for a successful BabelQueue
  DLQ write and for a successful SDK-initiated native dead-letter (same attribute set, no native/BabelQueue
  split), 0 for a failed write, a failed native call, a native no-op (SQS), a broker's own dead-letter and a
  disabled DLQ. The cases are defined at the level of the observer event `{queue, dead_letter_queue,
  reason}`, so a runner needs no broker.
- `traceparent`: six cases for the finer W3C validity rules (ADR-0028), all "ignored, behaves like no header" (`source: trace_id`): `version-ff-ignored`, `zero-trace-id-ignored`, `zero-parent-id-ignored`, `uppercase-trace-id-ignored`, `uppercase-parent-id-ignored` and `uppercase-flags-ignored`. The section now has 20 cases.

### Changed

- `CONFORMANCE_VERSION`, `manifest.json` `conformance_version` and `schema/results.example.json` carry
  `1.9.0`. The `sections` map gained `span-shape`, `trace-id` and `metrics` (scope `otel` each).
  `results.example.json` gained one abbreviated block per new section.
- The `traceparent` section `description` no longer says the finer W3C rules and the producer side "are left
  to the R1 OTel plan": it now states the finer validity rules (version `ff`, all-zero trace-id or parent-id,
  upper-case hex) and that the producer side is covered by each SDK's own transport tests. No existing
  `traceparent` case or expectation changed.
- `ci.yml` step "v1.5 sections agree with their reference oracles": the `traceparent` oracle now matches
  lower-case hex only and treats an all-zero trace-id or parent-id as invalid, so it agrees with the W3C Trace
  Context rules the new cases pin (the old pattern accepted upper-case hex and zero ids). It uses `fullmatch`,
  so a header with a trailing newline is not accepted. Only version `00` is pinned; future versions and reserved
  flag bits are not.

### Compatibility

- No v1.8.0 case or expectation changed; `fetch.sh` and `schema/results.schema.json` are untouched. The PHP
  `Tracing::remoteParentFromHeaders` does not yet pass `uppercase-flags-ignored` (R1 OTel plan, phase 08). A runner
  that enumerates sections from the `sections` map picks the new sections up; an SDK whose `otel` module has
  not implemented ADR-0038 / ADR-0039 fails them until its parity phase lands.
- The new sections have scope `otel`, so a package lists `otel` in `bindings` (and runs them) when it
  carries the optional OpenTelemetry module.
- The release asset is published from the `v1.9.0` tag by the maintainer; until then SDK repositories vendor
  this suite from the local checkout with `sync.sh`.

## 1.8.0

Governing decision: ADR-0037 (poison shape and version-gate parity), with ADR-0035 (poison DLQ record)
and ADR-0036 (post-R1 parity).

### Added

- Sections `version_gate_pulsar`, `version_gate_artemis`, `version_gate_sqs` and `version_gate_asb` (one scope
  each, as `redis_delay`; ADR-0032 §2, ADR-0037 decision 1, broker-bindings sections 5.7, 7.7, 3.7 and 4.7):
  17 cases per section, 68 in all, `{name, on_unknown_urn?, dead_letter, dlq_write?, bq_attempts?, expect}`.
  The version-gate settle rule as a pure function: `expect.outcome` is `ack` | `dlq_raw` | `unsettled` |
  `native`, for the strategies `fail` (absent) / `release` / `delete` / `dead_letter`, dead-lettering `on` /
  `off`, and the DLQ write `ok` / `fails` (absent = `ok`). With dead-lettering off the result is `ack` on
  Pulsar and Artemis and `native` (left to the broker's native mechanism) on SQS and Azure Service Bus. The
  optional `expect.outcome_no_writer` is present exactly on the `dead_letter` strategy with dead-lettering
  off (an SDK without a DLQ writer asserts it instead of `outcome`). `bq_attempts` rows show the outcome
  does not depend on the attempts count (no retry). The four sections hold the same 17 inputs.
- `expect.record: incoming_body` on every `dlq_raw` row, and the section member `incoming_bodies` (3 raw
  bodies, deliberately not in canonical form: pretty-printed with `\u` and `\/` escapes, non-canonical key
  order and number forms, and a non-JSON body): the record written to `<queue>.dlq` must equal the incoming
  body byte for byte and carry no `dead_letter` block, so a writer that decodes and re-encodes fails.
- `ci.yml` step "v1.8 sections agree with their reference oracles": recomputes every `version_gate_<binding>`
  `expect` with an independent reference settle function (once with a DLQ writer for `outcome`, once
  without for `outcome_no_writer`, which must be present exactly where the two differ), requires each
  section's `sections` entry to be exactly its binding scope, `dlq_write` exactly on rows that write (and
  on the `dead_letter`-with-dead-lettering-off rows), `record` exactly on `dlq_raw` rows, full coverage per
  section (strategy x dead-lettering x write result, `bq_attempts` with dead-lettering on and off, every
  outcome of the binding), identical case inputs and `incoming_bodies` across the four sections, and that
  every `incoming_bodies` entry differs from its canonical re-encodings.

### Changed

- `CONFORMANCE_VERSION`, `manifest.json` `conformance_version` and `schema/results.example.json` carry
  `1.8.0`. The `sections` map gained `version_gate_pulsar`, `version_gate_artemis`, `version_gate_sqs` and
  `version_gate_asb` (one binding scope each).
- `poison_dlq` (ADR-0035, 1.6.0) becomes **required** for the runners of the Artemis, SQS and Azure
  Service Bus packages of Java, .NET and Node and for `@babelqueue/bullmq` (ADR-0037 decision 2 and 3).
  No `poison_dlq` case changes: each runner drives the cases through the record builder its consumer
  actually uses. Documented in `README.md`.

### Compatibility

- No v1.7.0 case or expectation changed; `fetch.sh` and `schema/results.schema.json` are untouched, so the
  `BQ_FETCH_SH_SHA256` pins stay valid. A runner that enumerates sections from the `sections` map picks the
  new sections up; an SDK that has not implemented ADR-0037 fails it until its parity phase lands.
- Each `version_gate_<binding>` section has exactly one scope, so a package without the binding has no such
  section (ADR-0032 §2; there is no row-level scope). The Laravel `babelqueue-sqs` and Artemis drivers
  report every case of `version_gate_sqs` / `version_gate_artemis` as `skip` with reason
  `ADR-0037 decision 4`; a produce-only transport reports them as `skip` too, citing `ADR-0037` and the
  missing consumer. See `README.md`, "Added in 1.8.0".
- The release asset is published from the `v1.8.0` tag by the maintainer; until then SDK repositories
  vendor this suite from the local checkout with `sync.sh`.

## 1.7.0

Governing decision: ADR-0036 (post-R1 parity), with ADR-0032 (suite structure and the identity rule,
section 6) and ADR-0035 (poison DLQ record).

### Added

- Section `identity_verdict` (scope `core`): 97 cases `{name, body, expect: ok | poison}` (ADR-0036
  decision 4). The first 92 are every `kafka_poison` case (same names, bodies and order) with
  `no_identity` mapped to `poison` and `ok` / `poison` unchanged; 5 extra rows pin the ADR bodies
  `kafka_poison` does not hold (`job` `""`, `" \t"`, `null`, `{}` next to a valid `urn`: `ok`; a tab-only
  `job` without `urn`: `poison`). A runner feeds `body` to the core decoder. Outside Kafka a `poison`
  body takes the poison route, not the unknown-URN strategies.
- Section `pulsar_exhaustion` (scope `pulsar`): 29 cases
  `{name, kind, body_attempts?, bq_attempts?, redelivery_count, max_attempts?, dead_letter, on_unknown_urn?, expect}`
  with `expect.outcome` `retry` | `dlq` | `drop` (and `reason`, `dead_letter_attempts` for `dlq`)
  (ADR-0036 decisions 1 and 2, broker-bindings section 5.5). `counted = reconciled + 1` with
  `reconciled = max(bq_attempts or body_attempts, redelivery_count)`; the default `max_attempts` is 3.
  15 rows of the ADR table, 10 strategy rows (only for an SDK with the `on_unknown_urn` option: Go,
  Python and the PHP `Consume\Dispatcher`; the Java, .NET and Node consumers report them as `skip`). The two
  rows with `on_unknown_urn: dead_letter` and `dead_letter: false` expect `outcome: dlq` (Go and Python: the
  setting is off but the DLQ target is writable) and carry the new optional field `expect.outcome_no_writer: drop`,
  which a runner for an SDK without a DLQ writer (the PHP `Dispatcher` without a `DeadLetterPublisher`) asserts
  instead (owner decision 2026-10-25, ADR-0036 decision 3); the field is present only where the two results differ.
  Plus 4 reconciliation-input rows.
- `ci.yml` step "v1.7 sections agree with their reference oracles": derives the first 92 `identity_verdict`
  cases from `kafka_poison` (names, bodies, order, verdict mapping), requires the 5 extra ADR rows (matched by
  parsed value, so the check cannot pass vacuously) and cross-checks the section one-way with Python's own strict
  parser and the ADR-0036 decision 4 table, and recomputes every `pulsar_exhaustion` `expect` with an
  independent reference settle function (once with a DLQ writer for `outcome`, once without for
  `outcome_no_writer`, which must be present exactly where the two differ), with coverage assertions (every outcome, kind, strategy and
  reason; `max_attempts` 1 and above the default; the reconciliation inputs).

### Changed

- `CONFORMANCE_VERSION`, `manifest.json` `conformance_version` and `schema/results.example.json` carry
  `1.7.0`. The `sections` map gained `identity_verdict` (`core`) and `pulsar_exhaustion` (`pulsar`).

### Compatibility

- No v1.6.0 case or expectation changed; `fetch.sh` and `schema/results.schema.json` are untouched, so the
  `BQ_FETCH_SH_SHA256` pins stay valid. A runner that enumerates sections from the `sections` map picks the
  new sections up; an SDK that has not implemented ADR-0036 fails them until its parity phase lands.
- The release asset is published from the `v1.7.0` tag by the maintainer; until then SDK repositories
  vendor this suite from the local checkout with `sync.sh`.

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
