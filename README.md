# BabelQueue Conformance Suite

The **single, language-neutral set of cases every BabelQueue SDK must satisfy.**
It is the executable form of the wire contract — if two SDKs both pass this suite,
a message one produces is consumable by the other.

> Canonical source. Each SDK **vendors** a copy under `tests/conformance/` (kept in
> sync from here). Published at <https://babelqueue.com> in human form.

## Contents

| Path | What |
| :--- | :--- |
| `schema/message-envelope.schema.json` | The canonical envelope JSON Schema (draft-07). Validates **producer** output (`job` required). |
| `fixtures/*.json` | Canonical envelopes — one per case (pure envelopes, schema-validatable). |
| `manifest.json` | The case list: each case's fixture file, whether it's `valid`, and the `expect` values a consumer must derive. Drives a generic runner in any language. |

## What an SDK must do (per `manifest.json` case)

Decode each fixture with the SDK's core, then:

- **`valid: true`** — the envelope is acceptable:
  - `accepts(envelope)` is **true**;
  - the resolved URN equals `expect.urn` (accepting `urn` as an inbound alias for `job`);
  - `data` equals `expect.data`; `attempts` equals `expect.attempts`;
  - `meta.lang` / `meta.schema_version` equal `expect.lang` / `expect.schema_version`;
  - if `expect.dead_letter` is present, the message carries a matching `dead_letter` block.
- **`valid: false`** — the SDK must **reject** it: `accepts(envelope)` is **false**
  (e.g. unknown `meta.schema_version`, or no `job`/`urn`).

Per-message fields (`meta.id`, `trace_id`, `meta.created_at`) are intrinsically
unique and are asserted for **presence/shape**, not value.

> Note: `urn-alias.json` uses `urn` instead of `job`. That is a **consumer
> tolerance**, not valid *producer* output — so it intentionally would NOT pass
> the producer JSON Schema (which requires `job`), but a consumer's `accepts()`
> must still accept it.

## Broker-binding conformance (`manifest.json` → `sqs`, `asb`, `pulsar`, `kafka`)

The `cases` above lock the **envelope** (broker-agnostic). The `sqs` block locks the
**Amazon SQS binding** ([broker-bindings.md §3](https://babelqueue.com)) — the native
projection and reconciliation each SQS transport adds on top of the identical body.
Every SDK that ships an SQS transport must satisfy it:

- **`sqs.attribute_projection`** — encode `attribute_projection.envelope_file`, run the
  transport's produce-side projection, and assert the resulting native
  `MessageAttributes` equal `attribute_projection.message_attributes` **exactly** (same
  keys, `DataType` `String` for ids/strings and `Number` for counters, same `StringValue`).
- **`sqs.attempts_reconciliation`** — for each case, the consume-side reconciliation MUST
  yield `expected_attempts` = `max(body_attempts, ApproximateReceiveCount − 1)`: a first
  delivery reads `0`, an absent/garbage count is ignored, and a runtime-incremented count
  is never lowered. A **drop-in driver** that instead surfaces the broker's native count
  (e.g. Laravel's `SqsJob::attempts()` = `ApproximateReceiveCount`) is **exempt** and
  documents that divergence.

Per-message attribute values reuse `fixtures/order-created.json`, so the expected
projection is deterministic. SDKs without an SQS transport ignore this block.

The `asb` block locks the **Azure Service Bus binding**
([broker-bindings.md §4](https://babelqueue.com)) the same way. Every SDK that ships an
ASB transport must satisfy it:

- **`asb.property_projection`** — encode `property_projection.envelope_file`, run the
  transport's produce-side projection, and assert the native message fields equal
  `property_projection.message` (`subject` = the URN, `correlation_id` = `trace_id`,
  `message_id` = `meta.id`, `content_type` = `application/json`) and the
  `ApplicationProperties` equal `property_projection.application_properties` **exactly** —
  as native AMQP-typed values (`bq-schema-version` and `bq-created-at` stay **numbers**,
  `bq-source-lang` a **string**; not the `DataType`-wrapped strings SQS uses).
- **`asb.attempts_reconciliation`** — for each case, the consume-side reconciliation MUST
  yield `expected_attempts` = `max(body_attempts, delivery_count − 1)`: a first delivery
  (`DeliveryCount` 1) reads `0`, `DeliveryCount ≤ 1` leaves the body's own count untouched,
  and a runtime-incremented count is never lowered. The rule is **identical** for the
  native-consumer SDKs (.NET/Java/Node, native `Abandon`) and the Transport+App SDKs
  (Python/Go, republish-retry).

The five ASB SDKs (`babelqueue-dotnet-azureservicebus`, `babelqueue-java-azureservicebus`,
`@babelqueue/azure-service-bus`, `babelqueue` Python `AsbTransport`,
`babelqueue-go/azureservicebus`) vendor this manifest via `sync.sh`; their conformance
runners are wired next. SDKs without an ASB transport ignore this block.

The `pulsar` block locks the **Apache Pulsar binding**
([broker-bindings.md §5](https://babelqueue.com)) the same way. Every SDK that ships a
Pulsar transport must satisfy it:

- **`pulsar.property_projection`** — encode `property_projection.envelope_file`, run the
  transport's produce-side projection, and assert the native message `properties` equal
  `property_projection.properties` **exactly**. Pulsar properties are **string→string**, so
  every value is a string — `bq-job` = the URN, `bq-trace-id` = `trace_id`, `bq-message-id`
  = `meta.id`, and the stringified `bq-schema-version` (`"1"`), `bq-source-lang`, and
  `bq-attempts` (`"0"`). The payload stays the byte-identical envelope; the native publish
  time mirrors `meta.created_at` (broker-set, body authoritative — not asserted).
- **`pulsar.attempts_reconciliation`** — for each case, the consume-side reconciliation MUST
  yield `expected_attempts` = `max(body_attempts, redelivery_count)`. Pulsar's
  `RedeliveryCount` is **0-based** (0 on first delivery) so it maps directly with **no −1**;
  a runtime-incremented count is never lowered, and `redelivery_count` 0 leaves the body's
  own count untouched (the runtime retries by republishing with attempts+1, resetting the
  broker count to 0). The rule is **identical** for the native-consumer SDKs
  (.NET/Java/Node) and the Transport+App SDKs (Python/Go).

The five Pulsar SDKs (`babelqueue-dotnet-pulsar`, `babelqueue-java-pulsar`,
`@babelqueue/pulsar`, `babelqueue` Python `PulsarTransport`, `babelqueue-go/pulsar`) vendor
this manifest via `sync.sh`; their conformance runners are wired next. SDKs without a
Pulsar transport ignore this block.

The `kafka` block locks the **Apache Kafka binding**
([broker-bindings.md §6](https://babelqueue.com)) the same way. Every SDK that ships a Kafka
transport must satisfy it:

- **`kafka.property_projection`** — encode `property_projection.envelope_file`, run the
  transport's produce-side projection, and assert the native record `headers` equal
  `property_projection.headers` **exactly**. Kafka headers are **bytes**, decoded as UTF-8
  strings — `bq-job` = the URN, `bq-trace-id` = `trace_id`, `bq-message-id` = `meta.id`, and
  the stringified `bq-schema-version` (`"1"`), `bq-source-lang`, and `bq-attempts` (`"0"`).
  The record value stays the byte-identical envelope and the record timestamp mirrors
  `meta.created_at` (Unix ms).
- **`kafka.attempts_reconciliation`** — for each case, the consume-side reconciliation MUST
  yield `expected_attempts` = the **`bq-attempts` header when present** (authoritative — Kafka
  has no native delivery count), else the body's own `attempts` (the fallback for a
  non-BabelQueue producer). This is **not a max**: the header overrides the body even when
  lower. A `null` `header_attempts` means the header is absent. The rule is **identical**
  across all five Kafka SDKs.

The five Kafka SDKs (`babelqueue-dotnet-kafka`, `babelqueue-java-kafka`, `@babelqueue/kafka`,
`babelqueue` Python `KafkaTransport`, `babelqueue-go/kafka`) vendor this manifest via
`sync.sh`; their conformance runners are wired next. SDKs without a Kafka transport ignore
this block.

## Idempotency conformance (`manifest.json` → `idempotency`)

The `idempotency` block locks the **consumer-side dedupe contract** (ADR-0022) that every
SDK's optional idempotency helper must honour — `idempotency.Wrap` (Go),
`Idempotent::wrap` (PHP), `idempotency.wrap` (Python), `Wrap` (Node), `Idempotent.wrap`
(Java). It is **broker-free**: the helper never touches the wire envelope (the `cases`
above stay byte-identical), so this block governs only the consume-side **decision** —
*run the handler, or skip-and-ack* — keyed on `meta.id`. Any SDK that ships the helper
must satisfy it; an SDK without it ignores the block.

- **`idempotency.dedup_key`** — the dedupe key is `meta.id` **verbatim** (the canonical
  per-message identity, distinct from `trace_id`). Encode `dedup_key.envelope_file` and
  assert the SDK keys its seen-set on exactly `dedup_key.expected_key` — two deliveries
  with the same `meta.id` are the **same** message and collapse to one effect; messages
  sharing a `trace_id` but with distinct `meta.id` are **distinct** effects.
- **`idempotency.sequences`** — each case drives **one** handler wrapped by the helper,
  backed by **one** seen-set store, through an ordered `deliveries` list. For each
  delivery the SDK derives the effect: **`run`** = the wrapped handler is invoked (the
  side-effect fires) and, on `outcome: "ok"`, the id is remembered; **`skip`** = an
  already-remembered id is recognised, the handler is **not** invoked, and the delivery
  is acked. `outcome` is the handler's result for a `run`: `ok` (remembered) or `throw`
  (raises — the id is left **unmarked**, so a later redelivery runs it again; retry/DLQ
  still apply). `forget_before: true` evicts the id from the store before that delivery.
  After replaying the whole sequence, the total number of side-effects (the `run`+`ok`
  invocations) MUST equal `expected_effects`.

The six sequences pin the whole contract: a duplicate delivery runs **once**; an
at-least-once redelivery storm is a **no-op**; distinct ids each run; a **throw** leaves
the id unmarked (retry survives the guard); a missing `meta.id` **fails open** (runs, never
silently dropped); and `forget` allows a re-run. This is at-least-once delivery collapsed
to an **exactly-once effect** by the consumer — seen-set, post-success dedupe, **not**
exactly-once delivery and **not** an in-flight concurrency lock.

The five core SDKs (`php-sdk`, `babelqueue-python`, `babelqueue-go`, `babelqueue-node`,
`babelqueue-java`) vendor this manifest via `sync.sh`; each runs the block against its
in-memory reference store. The reference `InMemoryStore` is process-local; the same
three-method `Store` interface (`seen` / `remember` / `forget`) backs a shared
Redis/DB store for a fleet — the contract here is **store-agnostic**, it asserts the
decision sequence, not a backend.

## Running it in an SDK

Each SDK ships a conformance test that loads `manifest.json` + `fixtures/` from its
vendored `tests/conformance/` copy and runs the **envelope** checks above:

- PHP: `vendor/bin/phpunit` (the `ConformanceTest`).
- Python: `python -m unittest` / `pytest` (`test_conformance.py`).

The **`sqs`** block is run by each SDK's SQS transport against the same vendored
manifest — **wired + green in all six**:

| SDK | Test | Reads | `attribute_projection` | `attempts_reconciliation` |
| :--- | :--- | :--- | :---: | :---: |
| Go | `babelqueue-go/sqs` `TestSqsConformance` | core's `testdata/conformance/` | ✅ | ✅ |
| Python | `babelqueue-python` `test_sqs_conformance.py` | `tests/conformance/` | ✅ | ✅ |
| Node | `@babelqueue/sqs` `sqs-conformance.test.ts` | `test/conformance/` | ✅ | ✅ |
| Java | `babelqueue-java-sqs` `SqsConformanceTest` | `src/test/resources/conformance/` | ✅ | ✅ |
| .NET | `babelqueue-dotnet-sqs` `SqsConformanceTests` | copied `conformance/` | ✅ | ✅ |
| PHP | `php-sdk` `SqsConformanceTest` | `tests/conformance/` | ✅ | n/a¹ |

¹ `php-sdk`'s `SqsTransport` is produce-only; the consume-side reconciliation lives in
the Laravel `babelqueue-sqs` driver, which surfaces the broker's native count (exempt per
the block's note). The three standalone transport repos (node-adapters, `babelqueue-java-sqs`,
`babelqueue-dotnet-sqs`) vendor their own copy via `sync.sh` (added to its targets).

## Keeping copies in sync

`conformance/` is the source of truth. Run `./sync.sh` to copy `schema/`,
`fixtures/` and `manifest.json` into each sibling SDK's vendored directory (paths
differ per SDK — Go `testdata/`, Java `src/test/resources/`, the rest
`tests/conformance/`).

Drift is guarded automatically:

- **`./sync.sh --check`** — diffs every vendored copy against the canonical suite
  and exits non-zero on drift (the local counterpart to the CI guard). Run it
  before committing fixture changes.
- **Each core SDK's CI** has a `conformance` job that shallow-clones this repo and
  diffs its vendored copy against the canonical `manifest.json`/`fixtures/`/`schema/`
  — so a stale or hand-edited copy turns the SDK's build red.
- **This repo's CI** validates the canonical suite itself (every fixture/schema is
  valid JSON, `manifest.schema_version` is 1, and every case's `file` exists with
  the right `expect`/`reason` block).

So: edit a fixture here → `./sync.sh` → commit each SDK. Forget to re-vendor and CI
catches it.
