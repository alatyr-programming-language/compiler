## pilots/json — a JSON parser and printer as a library package (#1125). The consumer is
## `../json-consumer`, which depends on it by path.
json := Package(
  version = "0.1.0",
  ## blocked-by: #1147 — `Kind.source` (sources merged into the consumer) is refused as not
  ## implemented, so the library builds as a static library.
  targets = [Target(kind = Kind.static_lib)],
)
