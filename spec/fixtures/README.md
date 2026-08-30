# Vendored fixtures

## `openapi.json`

The upstream Flodesk API description, used by this suite as a **contract oracle**
rather than as a code-generator input. See `spec/flodesk/contract_spec.rb`.

| | |
| --- | --- |
| Source | <https://developers.flodesk.com/> (Redoc-rendered; the underlying spec asset is not publicly fetchable) |
| Retrieved | 2026-08-30 |
| OpenAPI version | 3.0.3 |
| SHA-256 | `d10b3738782d99e209e06fe5017dfdaf839db8aa038667591e814751b2791458` |
| Contents | 19 paths, 26 operations, 25 schemas, 3 `x-webhooks` inbound events |

### Why it is vendored

The contract spec walks this file and asserts that every documented operation has
a corresponding client method, that declared query parameters are actually sent,
and that every documented status code maps to a known error class. Vendoring
makes the suite hermetic — no network access during tests — and turns "full API
coverage" into an assertion rather than a claim in the README.

### Change history

Updating this file on 2026-08-30 (from `a5ca0a52…`, retrieved 2026-07-29)
surfaced three upstream additions, each caught by a failing contract example
rather than by review:

| Change | Consequence for the client |
| --- | --- |
| `subscriber.status` gained `archived` | `subscribers.list(status: "archived")` raised `ArgumentError` — a documented filter was unreachable |
| `SegmentRes` gained `segment_type` | `"static"`/`"dynamic"` was readable only through `raw` |
| New `publishStudioEmail` (`POST /campaigns/studio`) | 26th operation, unimplemented |

The `archived` gap is the one worth remembering. A missing enum member is not
inert: `validate_enum!` turns it into a client-side rejection of a value the API
accepts, and on the response side `Coercion.enum` passed it through as a String
while every sibling status arrived as a Symbol.

### Updating

Replace this file with a newer copy and run the suite. Coverage gaps fail the
build by design: a newly documented Flodesk operation will surface as a failing
contract example, which is the intended signal to implement it.

Note that the spec defines **no schema for any error response** — every `4xx`
declares only an empty description. The `{"code": ..., "message": ...}` envelope
the client parses was established by probing the live API, not read from this
file, so it is not contract-verifiable and must degrade gracefully.
