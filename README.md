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

## Broker-binding conformance (`manifest.json` → `sqs`, `asb`)

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
