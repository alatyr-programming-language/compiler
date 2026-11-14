## e2e — #1626, #1641's second review (B1): a fixed-array parameter function that a LEGACY caller reaches
## through a call the compiler synthesizes. Types §4.5 / OP-3: `w[i] = v` on a library aggregate is the
## UFCS call of the type's indexed-store function, which the driver writes into the tree; the source
## names that function nowhere at the call site. Functions §2.1/§4.1: the callee reads the caller's array.
## `main` holds an `f64` local, which the shared IR does not build, so every backend emits it with its
## legacy emitter, and the aarch64 and riscv64 legacy emitters pass `s.arr` and `o.inner.arr` by the
## value of the array's FIRST ELEMENT. MEASURED on `f1d31328`, whose plan found callers from the source
## text alone: the callee was IR-built and aarch64 and riscv64 answered 139 (SIGSEGV), where main
## trapped (133). A name the compiler synthesizes is now held to legacy (`ir::ap_synth_name`), so
## x86_64 answers 42 and the twins trap as before (`scripts/known-deviations.tsv`, #1194). The
## callee's name appears in no comment above: one outside every declaration would hold it by itself.
## Each check below answers its own number when it fails; all passing answers 42.
## expect: run 42
W := struct { k : u64 }
S := struct { tag : u64, arr : [u64; 3] }
O := struct { k : u64, inner : S }

mut GOT : u64 = 0

index_set := fn(w : W, i : u64, xs : [u64; 3]) { GOT = w.k + i + xs[0] * 100 + xs[1] * 10 + xs[2] }

main := fn() -> u8 {
  z : f64 = 1.0
  if z > 2.0 { return 9 }
  w := W(k = 0)
  s := S(tag = 1, arr = [0, 4, 2])
  w[0] = s.arr
  if GOT != 42 { return 1 }
  o := O(k = 1, inner = S(tag = 2, arr = [0, 4, 2]))
  GOT = 0
  w[0] = o.inner.arr
  if GOT != 42 { return 2 }
  42
}
