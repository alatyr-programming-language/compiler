## Modules §3 in a SIGNATURE position: naming `geo`'s non-`pub` type as a parameter type is the same
## violation as constructing it, and is rejected even though no expression mentions the type. The
## parser keeps only the TAIL (`Priv`) of a qualified parameter type, so the module head is recovered
## from source by the shared `gref_split` scan — the reject is on the declaration, not on a call.
take := fn(p : geo::Priv) -> u64 { return 1 }
main := fn() -> u64 {
  return 42
}
