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

## Running it in an SDK

Each SDK ships a conformance test that loads `manifest.json` + `fixtures/` from its
vendored `tests/conformance/` copy and runs the checks above:

- PHP: `vendor/bin/phpunit` (the `ConformanceTest`).
- Python: `python -m unittest` / `pytest` (`test_conformance.py`).

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
