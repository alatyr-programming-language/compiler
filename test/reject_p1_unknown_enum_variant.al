## P1 sema conformance: a known enum type must reject an unknown variant name.
E := enum { Known(u64) }

main := fn() -> E {
  return E.Zzz(1)
}
