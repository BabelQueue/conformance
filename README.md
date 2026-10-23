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
| `manifest.json` | The case list: each case's fixture file, whether it's `valid`, and the `expect` values a consumer must derive. Drives a generic runner in any language. Since 1.5.0 it also carries a top-level `conformance_version`, the `sections` scope map and the `exceptions` list. |
| `schema/results.schema.json` | JSON Schema (draft 2020-12) of the **results file** an SDK's conformance run emits ([ADR-0032](https://babelqueue.com)). See [Results format](#results-format-adr-0032). |
| `schema/results.example.json` | A valid example results file (checked against the schema in CI). |
| `fetch.sh` | Downloads a released suite, verifies its checksum, and either unpacks it or checks a vendored copy against it. See [Release asset and `fetch.sh`](#release-asset-and-fetchsh). |
| `CONFORMANCE_VERSION` | The suite's SemVer (K-14). Vendored next to `manifest.json` so every SDK records which revision it runs; the canonical repo is tagged `v<version>`. `-pre` = not yet tagged. |

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

**Exact key spelling, last wins.** Envelope keys (`job`, `urn`, `trace_id`, `data`, `meta` and
its members, `attempts`, `dead_letter`) are matched **case-sensitively**: `JOB`, `Data` or
`meta.Queue` is an *unknown key* — never the canonical field — and is preserved and re-emitted
like any other unknown key (`invalid-wrong-case-job`, `wrong-case-keys-roundtrip`). A key that
appears twice follows **last wins** and is never merged (`duplicate-keys-last-wins`: the second
`job` and the second `data` object replace the first).

> Note: `urn-alias.json` uses `urn` instead of `job`. That is a **consumer
> tolerance**, not valid *producer* output — so it intentionally would NOT pass
> the producer JSON Schema (which requires `job`), but a consumer's `accepts()`
> must still accept it.

## Broker-binding conformance (`manifest.json` → `sqs`, `asb`, `pulsar`, `kafka`, `artemis`)

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
`babelqueue-go/azureservicebus`) vendor this manifest via `sync.sh` and run this block from
the vendored copy. SDKs without an ASB transport ignore this block.

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
this manifest via `sync.sh` and run this block from the vendored copy. SDKs without a
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
`sync.sh` and run this block from the vendored copy. SDKs without a Kafka transport ignore
this block.

### `schema_version_gate` — version-gate before decoding (`sqs`, `asb`, `kafka`, `artemis`, `pulsar`)

Each of the five broker blocks also carries a **`schema_version_gate`** table that locks the
consumer-side version gate ([broker-bindings.md](https://babelqueue.com) §3.7 / §4.7 / §5.7 /
§6.7 / §7.7) across SDKs. The table names the native `property` the gate reads
(`bq-schema-version` for SQS, ASB, Kafka and Pulsar; `bq_schema_version` — underscores, ADR-0017 —
for Artemis), the `fixture` that is always the (valid) message body, and a list of `cases`, each
with either a `value` or `"absent": true`, and the `expect`ed verdict:

- **`decode`** — the gate lets the message through to the normal decode path: value `"1"`, or an
  **absent** or **blank** property. Blank means the empty string or only ASCII whitespace
  (space, `\t`, `\n`, `\v`, `\f`, `\r`) — the same set in every SDK. (The body's
  `meta.schema_version` check still runs afterwards.)
- **`reject`** — the gate rejects/quarantines the message **without decoding the body**
  (poison/DLQ path): any other present value. The value is compared as-is and is **never
  trimmed**: `"2"`, `"01"`, `"x"`, `" 1"`, `"1 "` and `"\t1\n"` all reject, and so do values made
  of **non-ASCII** whitespace (NBSP U+00A0, U+0085, U+3000) or a BOM (U+FEFF) — those are *not*
  blank. A gate that trims before comparing, or that uses a unicode-aware blank check
  (`str.isspace()`, `char.IsWhiteSpace`, `Character.isWhitespace`), fails these cases.

The `asb` table additionally has JSON-**number** cases, because ASB `ApplicationProperties` are
AMQP-typed and `bq-schema-version` is a native number there: **any AMQP integral type**
(byte/short/int/long, signed or unsigned) with value `1` decodes; any other numeric value (`2`,
`0`, non-integral `1.5`) and any other type rejects. A JSON number carries no width, so a runner
MUST exercise integral `1` and `2` at both **int32 and int64** width. A floating-point `1.0`
is a native AMQP float/double, **not** integral `1`, and rejects. JSON parsers in several
languages (Go, Node) cannot tell `1.0` from `1`, so that case carries an explicit
`"value_type": "float"` marker and a runner MUST hand the SDK a real floating-point value
(`float32` and `float64` where the language has both), never an integer. A language with a
single number type (JavaScript: an AMQP float `1.0` arrives as the number `1`) cannot represent
the case and its runner skips it explicitly; this is the documented JavaScript exception in
[broker-bindings.md §4.7](https://babelqueue.com), where such a runtime MAY accept float `1.0`
as `1`. A reader that ignores the marker sees `1` and fails the case loudly rather than passing
silently. Since the body is always valid, a `reject` verdict can only come from the property
gate. SDKs that have not yet wired a runner for this key ignore it.

The `asb`, `kafka` and `artemis` tables also have a `{"value": null, "expect": "decode"}` case: a
property (header) that is present with a null value is treated exactly like an absent one, so the
runner MUST put the key into the message with a null value (not omit it), and an SDK must not
stringify the null (Kafka headers: never the text `"null"`). A reader whose message API cannot carry
a null application property (e.g. a JMS client that cannot set one) skips the case explicitly and
asserts that it skips. SQS and Pulsar cannot carry a null value and have no such case.

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

## Behaviour conformance (`manifest.json` → `roundtrip`, `data_shape`, `forbidden_keys`, `payload_schema_unicode`, `extension_write`, `encode_reject`)

These six blocks lock **behaviour** every SDK core must share on top of the envelope
`cases` — what happens when a message is decoded and written back. A runner that does
not know a block skips it (all existing runners look sections up by name), so adding a
block never turns an old runner red. JSON pointers are **RFC 6901** (`/meta/vendor_flag`).
"Same value" means JSON deep-equality **with type distinction**: `true` ≠ `1`, `{}` ≠ `[]`.

**Unknown case fields are ignored.** A runner reads only the case fields it knows; an extra
field (for example a field added by a later suite version) never fails the case and never
makes the runner skip it. This is the field-level counterpart of the block-level rule above
(a runner skips a block it does not know). A runner evaluates an optional field only when the
case carries it; a case without the field behaves exactly as it did before the field existed.

### `roundtrip` — unknown keys survive re-emit

Contract basis: consumers MUST ignore unknown keys ([message-envelope.md](https://babelqueue.com) §4, §8).
Ignoring must not mean **deleting**: retry, DLQ, redrive and outbox relay all decode and
re-encode, so an SDK that drops unknown keys silently breaks forward compatibility (GR-5).

Case shape: `{ "name", "file", "description", "expect_attempts", "expect_preserved": { "<pointer>": <value> }, "producer_schema_valid"?, "expect_absent_after_reencode"?, "apply_dead_letter"?, "expect_dead_letter"? }`.

Runner: decode `file` (MUST be accepted) → `attempts + 1` → encode → parse the output and
assert `attempts == expect_attempts` and every `expect_preserved` pointer holds the given
value. Key order and whitespace are **not** asserted. Decoding a `roundtrip` fixture MUST
NOT emit any warning (none of these fixtures carries a forbidden key; when `job` is missing
or blank, `urn` is the source of the identity, not a dropped key) — the runner asserts the
SDK's warning hook stayed silent. If the case has `expect_absent_after_reencode` (1.4.0),
none of its pointers may exist in that same re-encoded output.

**`apply_dead_letter` / `expect_dead_letter` (1.4.0, optional).** A dead-letter move is a
re-emit too (message-envelope.md §8 rule 7), so it must keep unknown keys. When a case carries
`apply_dead_letter: { "reason", "original_queue" }`, the runner, after the `attempts + 1` step,
moves the decoded message to the dead-letter queue with **the SDK's own DLQ helper** (the code
path its worker uses on retry exhaustion — in Java this includes each of the four adapters'
DLQ paths), with `reason` one of `failed` / `unknown_urn` / `poison`, and parses the
**dead-letter copy** instead of the plain re-encode. Every assertion of the case
(`expect_attempts`, `expect_preserved`, `expect_absent_after_reencode`) is then evaluated on that
copy. `expect_dead_letter` is a map `{ "<dead_letter sub-field>": <value> }`: the copy MUST carry
a `dead_letter` object (message-envelope.md §10b) and each listed sub-field MUST deep-equal the
value. Anything else the helper needs or writes (`error`, `exception`, `failed_at`, `attempts`,
`lang`) is runner-chosen or SDK-determined and is **not** asserted. A runner that does not know
these fields ignores them and runs the case as a plain roundtrip, which the case also passes —
so an old runner stays green but does not cover the DLQ path until it is wired.

| Case | Expected behaviour |
| :--- | :--- |
| `unknown-meta-roundtrip` | `meta.vendor_flag` (`true`) and nested `meta.vendor_ctx` come back unchanged; `attempts` 0 → 1. |
| `unknown-toplevel-roundtrip` | Top-level `extra_top` (`1`) comes back unchanged; `attempts` 1 → 2. |
| `unknown-lang` | `meta.lang: "cobol"` decodes without error and is re-emitted as `"cobol"`. |
| `empty-data-roundtrip` | `data: {}` comes back as an **object** `{}`, never `[]`. |
| `wrong-case-keys-roundtrip` | A valid envelope that also carries `JOB`, `Data` and `meta.Queue`: the canonical `job` / `data` / `meta.queue` are unchanged and the three wrongly cased keys come back with their own values; `attempts` 0 → 1. |
| `meta-ext-vendor-roundtrip` | (1.4.0) Vendor blocks under `meta.ext.<vendor>` (`acme`, `globex`) with nested objects and arrays come back unchanged (ADR-0031); `attempts` 0 → 1. |
| `dead-letter-roundtrip` | (1.4.0) Moved to the DLQ with `apply_dead_letter` (`reason: failed`, `original_queue: orders`): `meta.id` / `queue` / `lang` / `created_at` / `schema_version`, `meta.vendor_flag`, `meta.ext.acme`, top-level `extra_top`, `trace_id` and `data` come back unchanged, and `dead_letter.reason` / `dead_letter.original_queue` carry the requested values; `attempts` 2 → 3. |
| `urn-only-roundtrip` | (1.4.0) Only `urn`, no `job`: accepted, the URN is read from `urn`, the re-emit has `/job` = the URN and no `/urn`. No warning (the alias is the identity source). |
| `blank-ascii-job-urn-fallback` | (1.4.0) `job` is two spaces, `urn` present: the blank `job` counts as absent, so the URN falls back to `urn`; re-emit has `/job` = the URN and no `/urn`. Blank means empty or only ASCII whitespace (space, `\t`, `\n`, `\v`, `\f`, `\r`). |

`producer_schema_valid: false` (on `unknown-lang` and `urn-only-roundtrip`) marks a
**consumer-tolerance** fixture: like `urn-alias`, it intentionally fails the producer JSON
Schema (`meta.lang` is an enum there; `job` is required) but a consumer MUST still accept and
faithfully re-emit it.

### `data_shape` — `data` is always an object

Case shape: `{ "name", "mode": "encode" | "decode", ... }`.

- **`mode: "encode"`** — `{ "urn", "queue", "data", "expect_encoded_data_json" }`. Build a new
  envelope with the SDK's producer API and assert the raw JSON text of the emitted `data`
  value, insignificant whitespace removed, equals `expect_encoded_data_json`.
- **`mode: "decode"`** — `{ "file", "valid", "reason" }`. Decode `file`; the verdict must equal
  `valid` (`false` = rejected, as for the invalid envelope `cases`).

| Case | Expected behaviour |
| :--- | :--- |
| `empty-data` | Encoding an empty map emits `"data":{}` — never `"data":[]` (the PHP pitfall). |
| `data-array-rejected` | A fixture whose `data` is `[1, 2]` is **rejected** on decode. |

### `forbidden_keys` — warn on decode, never emit

Policy **K-15** (R0 reading): decoding a message that carries a non-canonical key
([message-envelope.md](https://babelqueue.com) §10) **succeeds with a warning**, so old
producers keep working; encoding **never** emits the key. The forbidden key is therefore
**not** captured into the unknown-key extras — otherwise "preserve unknown keys" and
"never emit forbidden keys" would contradict each other.

Case shape: `{ "name", "file", "forbidden_key": "<pointer>", "expect": "warn", "expect_absent_after_reencode": ["<pointer>", ...], "expect_preserved"? }`.

Runner: decode `file` → MUST succeed **and** the SDK MUST surface at least one warning
(its logger / warning hook) naming the key → re-encode the decoded message unchanged →
none of `expect_absent_after_reencode` may exist in the output, and (1.4.0, optional) every
`expect_preserved` pointer (`{ "<pointer>": <value> }`) holds the given value in that same
re-encoded output.

ADR-0031 (c)
makes the decode warning a MUST and makes **encode reject** a forbidden key (see
`encode_reject` below); decode itself stays lenient.

| Case | Expected behaviour |
| :--- | :--- |
| `forbidden-key-timestamp` | Top-level `timestamp` → decode warns; re-encoded envelope has no `/timestamp`. |
| `forbidden-key-meta-max-retries` | `meta.max_retries` → decode warns; re-encoded envelope has no `/meta/max_retries`. |
| `forbidden-key-meta-attempts` | `meta.attempts` (draft shadow of top-level `attempts`) → decode warns; re-encoded envelope has no `/meta/attempts`; top-level `/attempts` is unaffected. |
| `forbidden-key-meta-source` | `meta.source` → decode warns; re-encoded envelope has no `/meta/source`. |
| `forbidden-key-meta-ts` | `meta.ts` → decode warns; re-encoded envelope has no `/meta/ts`. |
| `forbidden-key-job-and-urn` | (1.4.0) Both `job` and top-level `urn` present: `job` wins, `urn` is dropped with a warning naming `/urn`; re-encoded envelope keeps `/job` and has no `/urn`. |
| `forbidden-key-job-nonascii-space-and-urn` | (1.4.0) `job` is only U+2003 (not ASCII whitespace, so **not** blank): `job` wins, `urn` is dropped with a warning, **no** fallback to `urn`; re-encoded envelope keeps `/job` = U+2003 and has no `/urn`. |

### `extension_write` — the producer `meta` write API (1.4.0)

ADR-0031 (b):
Go `WithMeta(key, value)`, Python `make(meta=)`, Node `MakeOptions.meta`, PHP `make(meta:)`,
Java `make(urn, data, queue, traceId, Map meta)`, .NET `Make(meta:)`. There is no top-level
write API.

Case shape: `{ "name", "description", "urn", "queue", "data", "meta": { "<key>": <value> }, "expect_envelope": { "<pointer>": <value> } }`.

Runner: build the message with the SDK's producer API from `urn`, `queue`, `data` and the
`meta` entries (a vendor block is supplied as the whole `ext` value) → encode → parse the
output → every `expect_envelope` pointer holds the given value → then decode that output,
`attempts + 1`, encode and parse again and assert the same pointers plus `/attempts == 1`
(extension keys survive a retry hop). Per-message fields (`meta.id`, `trace_id`,
`meta.created_at`) are not asserted by value; key order and whitespace are not asserted.

| Case | Expected behaviour |
| :--- | :--- |
| `flat-scalar-key` | A flat key (`vendor_flag: true`) sits in `meta` next to the core keys. |
| `vendor-block-under-ext` | `meta.ext.acme` with nested object and array survives. |
| `two-vendors-in-one-ext` | `meta.ext.acme` and `meta.ext.globex` both survive. |
| `several-flat-keys-mixed-types` | String, integer, array and `{}` values keep name, value and type. |
| `non-ascii-value` | A non-ASCII value is value-equal after parse (the runner compares parsed values, so `\uXXXX` escaping in the output is accepted). |

### `encode_reject` — encode refuses forbidden and colliding keys (1.4.0)

ADR-0031 (b), (c):
encode **rejects** (an `error` in Go, an exception elsewhere; never a silent drop) a forbidden
key (also when it arrives through preserved extras), a collision with a core `meta` key (`id`,
`queue`, `lang`, `schema_version`, `created_at`) and a repeated extension key.

Case shape: `{ "name", "description", "urn", "queue", "data", "expect": "reject", "offending_key", <one input field> }` where the input is one of:

- `meta` — entries passed through the producer `meta` write API;
- `meta_entries` — the same as an ordered `[key, value]` list, for a **repeated** key a JSON
  object cannot express (SDKs whose write API takes one map per call skip these cases);
- `extras_top` / `extras_meta` — entries the runner places into the message's preserved
  unknown-key container at top level / under `meta`, by whatever test access the SDK has,
  standing for extras carried over from an inbound message (the write API has no top-level keys).

Runner: build → encode MUST fail and produce no envelope JSON. `offending_key` is
informational; a runner MAY assert the error mentions it.

| Case | Rejected input |
| :--- | :--- |
| `reject-top-level-timestamp`, `reject-top-level-urn` | forbidden top-level key via `extras_top` |
| `reject-meta-max-retries`, `-attempts`, `-source`, `-ts` | forbidden `meta` key via the write API |
| `reject-forbidden-meta-key-in-extras` | forbidden `meta` key via `extras_meta` |
| `reject-core-meta-id`, `-queue`, `-lang`, `-schema-version`, `-created-at` | core `meta` key collision |
| `reject-repeated-key` | `ext` supplied twice (`meta_entries`) |

### `payload_schema_unicode` — string length is code points

Same shape and runner as `payload_schema`: `{ "schema", "cases": [{ "name", "data", "valid" }] }`.
`minLength` counts **Unicode code points** — not UTF-8 bytes (Go `len`), not UTF-16 code
units (Java/.NET/JS `length`), not grapheme clusters (.NET `StringInfo`).

| Case | Value | `minLength` | Code points | Expected |
| :--- | :--- | :---: | :---: | :--- |
| `ascii-3cp-min3` | `"abc"` | 3 | 3 | valid |
| `turkish-2cp-min3` | `"ğü"` | 3 | 2 (4 UTF-8 bytes) | invalid |
| `turkish-3cp-min3-boundary` | `"ğüş"` | 3 | 3 | valid |
| `emoji-1cp-min2` | `"😀"` | 2 | 1 (2 UTF-16 units) | invalid |
| `emoji-plus-ascii-2cp-min3` | `"😀a"` | 3 | 2 (3 UTF-16 units) | invalid |
| `combining-2cp-min2` | `"é"` (é, decomposed) | 2 | 2 (1 grapheme) | valid |

`maxLength` is deliberately **not** covered: no SDK supports it yet. It arrives with the
Draft-07 keyword subset in R1 (**K-17**), together with its own cases.

## Sections, scopes and exceptions (1.5.0, ADR-0032)

Every block of `manifest.json` is a **section**. The top-level `sections` map assigns each
section exactly one **scope** — `core`, a binding it exercises (`redis`, `amqp`, `sqs`,
`asb`, `pulsar`, `kafka`, `artemis`; the `rabbitmq` section's scope is `amqp`), or `otel`.
`otel` is not a broker: it is the optional W3C `traceparent` extract/inject code of ADR-0028
(in the core of Node and .NET; a separate module for Go, Python, Java and PHP), so only a
package that carries it runs the `otel` sections. A runner enumerates sections from this map
rather than from a hard-coded list, runs the sections whose scope the package carries, and
**tolerates a section newer than the suite version it implements** (it does not crash on it).
That tolerance is not a pass: for the version it pins, every in-scope section MUST be run and
reported, and an unimplemented in-scope section means the package is not Compatible (`skip`
is never a way to leave a section out — see below). A section whose scope the package does not
carry is simply absent from its results; the required sections are all `core` sections plus
the sections of every binding in `bindings`.

The top-level `exceptions` list records deliberate, ADR-backed, family-level non-support, e.g.
`{"family": "php", "binding": "asb", "adr": "ADR-0021"}` (PHP has no conformant Azure Service
Bus path). A binding under an exception is **not** listed in `bindings` and its sections are
**absent** from `results.json`; it is not a `skip`. A `skip` is only for an individual case of
an in-scope section and always cites an ADR.

A deviation from the wire contract is never a reason to skip: for example a Redis transport
that does not use the §1.1 key layout fails `redis_layout` and the SDK is fixed. Details the
contract leaves open are not pinned by any section. Since 1.6.0 the Redis available-at formula,
the delayed/reserved migration, the reserve/release behaviour and the legacy `:processing` sweep
are pinned (see "Added in 1.6.0" below); the Kafka tier numbering is pinned by the `backoff`
blocks and the retry delay formula by `retry_backoff`, and the DLQ handling after a poison pop is still left open.

Six sections were added in 1.5.0. Each is kept to what the wire contract actually pins; where
the contract is silent the section says so in its `description` and tests nothing.

| Section | Scope | Pins |
| :--- | :--- | :--- |
| `trim` | `core` | ADR-0032 §5: the ASCII whitespace set (space, `\t`, `\n`, `\r`, `\f`, `\v`) is trimmed from the `make` input (URN, `trace_id`); U+00A0, U+2003 and U+3000 are *not* whitespace and stay in the value; blank `job` / `urn` / `trace_id` on decode and `accepts`; re-emit never trims (a non-blank `job` and `trace_id` survive byte-for-byte, GR-4). |
| `job_type` | `core` | ADR-0032 §6: a non-string `job` (null, number, boolean, object, array) is ignored and decode MUST warn; a blank-string `job` falls back to `urn` without a warning; a non-string `urn` is ignored; with no valid identity decode raises. |
| `delay` | `sqs` | broker-bindings §3.4–3.5: `DelaySeconds` on standard queues, the 900 s cap and FIFO per-message delay raising `BabelQueueException`, and the `ChangeMessageVisibility` timeout of a release. |
| `backoff` | `kafka` | broker-bindings §6.3–6.5, two separate rules: the requested-delay rule (§6.4: smallest tier ≥ the requested delay, `bq-delay` = the requested delay, `bq-original-topic`; reject above the largest tier) and the retry/release rule (§6.5: tier `n = min(attempts_before, N−1) + 1`, `bq-delay` = that tier's ms, `bq-attempts = attempts_before + 1`, `bq-original-topic`, body `attempts` in sync; no tiers configured is rejected). The two rules are not merged. |
| `traceparent` | `otel` | ADR-0028 / ADR-0025: consumer-side extraction of the W3C `traceparent` header (valid header wins, malformed or absent header falls back to the `trace_id`-derived hex, never raises). Only the `00-<32hex>-<16hex>-<2hex>` structure is pinned; the finer W3C rules and the out-of-band carriage on a real transport are left to the R1 OTel plan. |
| `redis_layout` | `redis` | broker-bindings §1.1: the key names of the Laravel-compatible layout (`queues:<q>`, `:delayed`, `:reserved`, `:notify`). In 1.5.0 names only; 1.6.0 adds behavioural blocks (below). |

### Added in 1.6.0 (ADR-0033, ADR-0034)

Version 1.6.0 locks the Redis delay/recovery behaviour, the Kafka retry-tier arithmetic and the
Kafka poison trigger set. It is a MINOR: the only v1.5.0 case expectation that changed is the `backoff.retry_republish`
correction, which contradicted broker-bindings §6.5 (see below); every other change is additive.

| Section / block | Scope | Pins |
| :--- | :--- | :--- |
| `redis_delay` (new section) | `redis` | broker-bindings §1.6: the delayed score `floor(now) + ceil(delay)` (integer epoch seconds) with the clock pinned by the case (`now`), fractional `now` and `delay` included (`now = 1000.7`, `delay = 1.5` gives `1002`). It is a separate section because `delay` is scoped `sqs` and a section has exactly one scope. The 1.0–3.5 s live-timing window is not a fixture. |
| `backoff.topic_names`, `retry_attempt_tier`, `default_tiers`; `backoff.retry_republish` (rewritten, see below) | `kafka` | broker-bindings §6.4–6.5 and ADR-0034 §9: the retry topic name `<topic>.retry.<n>` (`n` starts at 1), the tier of a retry `min(attempts_before, N−1) + 1` (the last tier is kept when the tiers run out) and the RECOMMENDED tier constant `[5000, 30000, 300000, 1800000]`. The "`<n>` undefined" note is gone. Kafka does not apply `retry_backoff`: a retry republish uses the tier, not the formula. |
| `retry_backoff` (new section) | `core` | broker-bindings §6.5 / ADR-0034 §9: the delay formula table `d(n) = min(max, retry_backoff × multiplier^(n−1))` (`max = 0` is uncapped): `jitter = none` exact values including the defaults `multiplier = 1`, `max = 0`; `full` only the bound `[0, d(n)]`. It is a `core` section of its own (moved out of `backoff`, which is scoped `kafka`) because the formula belongs to the SDK core retry policy of every transport, not to Kafka. |
| `redis_layout.delayed_score`, `migrate`, `reserve`, `pcall_poison`, `release` | `redis` | broker-bindings §1.1, §1.6, §1.7 (zset layout): due delayed items move to the ready list (`score <= floor(now)`), expired reservations return to ready after the delayed pass, in chunks of 100, one notify token per moved item; a reserve hands the handler the raw member byte for byte and stores it in `:reserved` with `attempts + 1`; a body that cannot be decoded or whose `attempts` is not a number is stored raw and reported as poison (the A1 `pcall` guard); a release deletes the reservation and writes the SDK-encoded body to `:delayed` with only `attempts` changed (unknown keys, their types and `{}` versus `[]` survive, ADR-0031). |
| `redis_layout.processing_sweep`, `processing_token`, `late_ack`, `identical_copies`, `retry_after_null`, `lrem_count`, `malformed_member`, `orphan` | `redis` | broker-bindings §1.7 (legacy `:processing` layout, A11/A13/K1): the sweep moves only the expired item to the end of the ready list byte for byte with `attempts` unchanged; a deadline member is `<32 lowercase hex token>:<raw>`; an ack with the token of an already swept reservation changes nothing; byte-identical copies carry separate members and one ack touches only its own; a member that does not match the format is only `ZREM`'d; an `LREM` that returns 0 only `ZREM`s the member (orphan cleanup); `retry_after: null` writes a `+inf` score so the item itself is never swept, but it is not a kill switch: a consumer with `null` still runs the sweep before every reserve and recovers a foreign expired member (case `retry_after_null/null-consumer-still-sweeps-foreign-expired-member`); `LREM` count is 1. Blocks `legacy_release_gate` and `legacy_dlq_gate` pin the §1.7 gate: `ZREM` of `<token>:<raw>` first, a result of 1 runs `LREM` and the rest in the same script, a result of 0 (stale token) touches nothing; both a stale and a valid token are covered. The reserve deadline is `floor(now) + retry_after` (§1.1). |
| `kafka_poison` (new section) | `kafka` | broker-bindings §6 and ADR-0034 §10 / ADR-0032 §6: case `{name, body, expect}` with `expect` one of `ok` (decodes), `no_identity` (valid JSON object but no usable `job` / `urn`) or `poison` (the consumer routes the record to the DLQ). A repeated top-level key is last-wins, so "duplicate job number then string" (`{"job":5,"job":"urn:x"}`) is `ok`; three rows of the old table change classification in total: `{"job":5}` and `{"job":"urn:x","job":5}` poison → `no_identity`, and "duplicate job number then string" poison → `ok`.  It replaces the five per-SDK copies of `poison-trigger-set.json`. |

Runner contract for `redis_layout`: the cases in its `cases` array need no Redis; the behavioural
blocks need a live Redis (`redis:7`). When `BQ_REQUIRE_REDIS` is set, an unreachable Redis is a
**failure**, never a skip; when it is unset the runner skips the behavioural blocks and logs it.
Each SDK's Redis transport CI sets `BQ_REQUIRE_REDIS` together with a `redis:7` service
container. The block-level case DSL (`layout`, `state`, ordered `steps` with `now`, ops
`push_delayed` / `migrate` / `reserve` / `release` / `ack` / `sweep` / `dead_letter`, count expectations `ready_count` / `dlq_count`) is documented in the
`redis_layout` section `description` of `manifest.json`; a runner therefore needs hooks that run
the SDK's migrate and sweep steps on their own and that inject the clock. The migrate and sweep
chunk size is 100, so the cases that exercise it only check completeness (everything moved), not
the intermediate state of a partial chunk.

The `trim` cases pin the ASCII-trim rule of `make` only. Some of them feed `make` a Unicode-space
or space-padded URN; that fixes what the blank check does with it, not that such strings are
well-formed URNs. The contract defines no rejection of them today, so the expectation stands:
`make` must accept them and not fail the blank check. Should URN grammar validation
(urn-naming §2, lowercase ASCII) ever be added to `make`, these cases would be updated in a new
suite version together with an ADR; until then an SDK that rejects them fails the case.

Case ids used by a runner (and by the results file) follow one rule: a section's `cases`
array yields the case's `name`, or `<section>#<0-based index>` when it has none; a sub-key that
has its own `cases` array yields `<sub-key>/<name>` (`<sub-key>/<0-based index>` when
unnamed); any other object sub-key is a single case keyed by the sub-key; `description` and
`schema` are not cases; the top-level `cases` array is the section named `cases`.

## Results format (ADR-0032)

A conformance run emits one `results.json`, validated by `schema/results.schema.json` (see
`schema/results.example.json`): `sdk`, `version`, `conformance_version`, `generated_at`
(RFC 3339; UTC recommended), `bindings` and `sections` — section → case id → `{"status": "pass" | "fail" | "skip",
"reason"?}`. `bindings` is **every transport/binding the package carries**, derived from its
modules (`otel` when it carries the traceparent code), and it **MUST be complete**: leaving a
carried binding out is not a way to narrow the scope. A real file lists every case of every
in-scope section; `schema/results.example.json` is abbreviated. A `skip` is only for an
individual case of an in-scope section and MUST carry a `reason` that cites the ADR which makes
the case not applicable (`ADR-NNNN`). The schema only checks the *shape*; that the ids match
the manifest is checked by the consumer of the results.

## Release asset and `fetch.sh`

A `v<version>` tag publishes a GitHub release with two assets: the deterministic
`babelqueue-conformance-<version>.tar.gz` (root directory `babelqueue-conformance-<version>/`
holding `CONFORMANCE_VERSION`, `manifest.json`, `schema/`, `fixtures/` and `LICENSE`) and its
`SHA256SUMS`. The tarball is reproducible (sorted entries, fixed mtime, owner 0, `gzip -n`), so
two builds of the same tree have the same sha256.

```bash
./fetch.sh 1.5.0 /tmp/conformance            # download, verify, unpack (dest must be empty)
./fetch.sh --check 1.5.0 tests/conformance   # exit 1 if the vendored copy differs
```

`fetch.sh` needs only `curl`, `tar` and `sha256sum` (or `shasum -a 256`). It refuses an asset
whose checksum does not match, or whose entries escape the single root directory; `--check`
compares with `diff -r`, ignoring `LICENSE` (which is not vendored). It also rejects an asset
that contains a symlink, hardlink or special file. The checksum gives **integrity, not
authenticity**: `SHA256SUMS` is published beside the asset, so it detects corruption, not a
release whose asset and `SHA256SUMS` were both replaced; a consumer that needs authenticity
pins the expected hash (or the exact tag) itself. Set
`BQ_CONFORMANCE_BASE_URL` to read the assets from another location (a `file://` URL or a local
mirror) instead of the GitHub release; the default is
`https://github.com/BabelQueue/conformance/releases/download/v<version>`.

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

## Suite version history

- **1.6.0** — ADR-0033, ADR-0034.
  Adds the sections `redis_delay` (`redis`), `kafka_poison` (`kafka`) and `retry_backoff` (`core`); the `backoff` blocks
  `topic_names`, `retry_attempt_tier` and `default_tiers`; and the `redis_layout`
  behavioural blocks `delayed_score`, `migrate`, `reserve`, `pcall_poison`, `release`,
  `processing_sweep`, `processing_token`, `late_ack`, `identical_copies`, `retry_after_null`,
  `lrem_count`, `malformed_member`, `orphan`, `legacy_release_gate` and `legacy_dlq_gate`, with the runner contract (`BQ_REQUIRE_REDIS`).
  Corrects `backoff.retry_republish` to the §6.5 attempt-to-tier rule (the key stays; the earlier
  `release_delay_ms` expectation contradicted §6.5). Otherwise additive: no other v1.5.0 case expectation changed. Vendored copies may be red on the new cases
  until each SDK implements ADR-0033 / ADR-0034. See `CHANGELOG.md`.

- **1.5.0** — ADR-0032.
  Adds the sections `trim`, `job_type` (scope `core`), `traceparent` (`otel`), `delay` (`sqs`),
  `backoff` (`kafka`) and `redis_layout` (`redis`); the top-level `conformance_version`,
  `sections` (section → scope) and `exceptions` keys of `manifest.json`; the results format
  (`schema/results.schema.json`, `schema/results.example.json`); and the release asset
  (`babelqueue-conformance-<version>.tar.gz` + `SHA256SUMS`) with `fetch.sh`. Additive: no
  existing case, fixture or schema changed, and a runner may ignore a section newer than the version it pins.
  Vendored copies may be red on the new cases until each SDK implements ADR-0032.

- **1.4.0** — ADR-0031.
  Adds the blocks `extension_write` and `encode_reject`; the `forbidden_keys` cases
  `forbidden-key-job-and-urn` and `forbidden-key-job-nonascii-space-and-urn`; the `roundtrip`
  cases `meta-ext-vendor-roundtrip`, `urn-only-roundtrip` and `blank-ascii-job-urn-fallback`;
  the `roundtrip` case `dead-letter-roundtrip` (a DLQ move keeps unknown keys); and the
  optional case fields `expect_preserved` (on `forbidden_keys`),
  `expect_absent_after_reencode`, `apply_dead_letter` and `expect_dead_letter` (on `roundtrip`). Additive: no existing case, fixture or
  schema changed, and a case without the new fields behaves as before. Vendored copies may
  be red on the new cases until each SDK implements ADR-0031.
- **1.3.0** — adds the `cases` entries `invalid-wrong-case-job` (a `JOB` key is not `job`: the
  message has no identity) and `duplicate-keys-last-wins` (repeated `job` / `data` keys: last
  wins, never merged), and the `roundtrip` case `wrong-case-keys-roundtrip` (wrongly cased
  keys are unknown keys and survive re-emit). Additive: no existing case, block, fixture or
  schema changed; the Go core was the only one that needed a decode change.
- **1.2.0** — adds the `asb` `schema_version_gate` case `{"value": 1.0, "value_type": "float",
  "expect": "reject"}` (a floating-point `1.0` is not integral `1`) and the optional `value_type`
  case key; adds `{"value": null, "expect": "decode"}` to the `asb`, `kafka` and `artemis` gates (a
  present-but-null property / header is treated as absent); removes the "unspecified and not tested" note. Additive: no existing case, block,
  fixture or schema changed.
- **1.1.0** — adds `schema_version_gate` to the `sqs`, `asb`, `kafka`, `artemis` and `pulsar`
  blocks (additive; no existing block, fixture or schema changed).
- **1.0.0** — initial tagged suite.

## Keeping copies in sync

`conformance/` is the source of truth. Run `./sync.sh` to copy `schema/`,
`fixtures/`, `manifest.json` and `CONFORMANCE_VERSION` into each sibling SDK's vendored directory (paths
differ per SDK — Go `testdata/`, Java `src/test/resources/`, the rest
`tests/conformance/`).

Drift is guarded automatically:

- **`./sync.sh --check`** — diffs every vendored copy against the canonical suite
  and exits non-zero on drift (the local counterpart to the CI guard). Run it
  before committing fixture changes.
- **Each SDK's CI** has a `conformance` job that shallow-clones this repo **at the release
  tag it pins** (`git clone --depth 1 --branch vX.Y.Z …`) and diffs its vendored copy against that
  tag's `CONFORMANCE_VERSION`/`manifest.json`/`fixtures/`/`schema/` — so a stale or hand-edited
  copy turns the SDK's build red, and unreleased changes on `main` never break an SDK's CI.
- **This repo's CI** validates the canonical suite itself (every fixture/schema is
  valid JSON, `manifest.schema_version` is 1, and every case's `file` exists with
  the right `expect`/`reason` block). It also checks `CONFORMANCE_VERSION` is SemVer and
  cross-checks the behaviour blocks against a reference Draft-07 validator (Python
  `jsonschema`): roundtrip/forbidden-key fixtures pass the envelope schema (except
  `producer_schema_valid: false`), `data-array-rejected` fails it, every pointer exists
  in its fixture, and the `payload_schema_unicode` verdicts match.

So, to release a suite change: edit fixtures here → bump `CONFORMANCE_VERSION` → commit, push
and tag `vX.Y.Z` → `./sync.sh` → in each SDK, commit the vendored copy together with the
`--branch vX.Y.Z` bump in its `ci.yml`. CI catches a copy that disagrees with its pinned tag (re-vendored
without the pin bump, or the reverse); an SDK left behind on both the old copy and the old pin
stays green, so run `./sync.sh --check` here to find it.
