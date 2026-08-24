## CLAYOUT S2 — Option(bool)'s niche is not implemented until S6. It must
## reject rather than silently report the ordinary one-word fallback.
main := fn() -> u64 {
  s := size(Option(bool))
  if s == 0 { 42 } else { 1 }
}
