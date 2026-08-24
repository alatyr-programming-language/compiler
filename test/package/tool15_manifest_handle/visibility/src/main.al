## Positive TOOL-15 seam: package source may pass the manifest handle's field value.
strlen := fn(s : str) -> u64 { return s.len() }
main := fn() -> u64 {
  v := app.version
  return strlen(v)
}
