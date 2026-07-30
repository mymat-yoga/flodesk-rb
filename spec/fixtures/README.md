# Vendored fixtures

## `openapi.json`

The upstream Flodesk API description, used by this suite as a **contract oracle**
rather than as a code-generator input. See `spec/flodesk/contract_spec.rb`.

| | |
| --- | --- |
| Source | <https://developers.flodesk.com/> (Redoc-rendered; the underlying spec asset is not publicly fetchable) |
| Retrieved | 2026-07-29 |
| OpenAPI version | 3.0.3 |
| SHA-256 | `a5ca0a521050c489c9e9fee4b289a7b2ed8ce9415fd9599c5605ffc604465ff9` |
| Contents | 18 paths, 25 operations, 24 schemas, 3 `x-webhooks` inbound events |

### Why it is vendored

The contract spec walks this file and asserts that every documented operation has
a corresponding client method, that declared query parameters are actually sent,
and that every documented status code maps to a known error class. Vendoring
makes the suite hermetic — no network access during tests — and turns "full API
coverage" into an assertion rather than a claim in the README.

### Updating

Replace this file with a newer copy and run the suite. Coverage gaps fail the
build by design: a newly documented Flodesk operation will surface as a failing
contract example, which is the intended signal to implement it.

Note that the spec defines **no schema for any error response** — every `4xx`
declares only an empty description. The `{"code": ..., "message": ...}` envelope
the client parses was established by probing the live API, not read from this
file, so it is not contract-verifiable and must degrade gracefully.
