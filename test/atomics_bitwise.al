## e2e — atomic BITWISE fetch ops (spec ch.110 §2): fetch_and / fetch_or / fetch_xor, each returning
## the OLD value via a `lock cmpxchgq` retry loop (x86 has no old-returning locked bitwise RMW).
## x=60: fetch_and(46)->old 60, x=44 ; fetch_or(3)->old 44, x=47 ; fetch_xor(5)->old 47, x=42.
## z (load) = 42; a+b+c = 60+44+47 = 151. Returns z + a + b + c - 151 = 42.
main := fn() -> u64 {
  mut x := 60
  p := ptr(x)
  a := atomic::fetch_and(p, 46, Ordering.seq_cst)
  b := atomic::fetch_or(p, 3, Ordering.relaxed)
  c := atomic::fetch_xor(p, 5, Ordering.acq_rel)
  z := atomic::load(p, Ordering.acquire)
  z + a + b + c - 151
}
