## §8 a @packed struct used as a FIELD of a NON-packed struct (spec Types §6.1, §8): `Pk` has
## alignment 1, so `p` sits at byte 8 of `Big` and `g.p.b` at byte 9, and the program answers 20.
## The legacy x86 emitter laid the outer struct out with the WORD model (each field at `8 * word index`)
## while the nested literal stored the inner value byte-precise, so write and read disagreed (`g.p.b`
## read 0) and it refused the program instead (DEFERRED). aarch64, riscv64 and wasm answer 20 (#1022).
## Since the slice-9 flip (#980) x86_64 emits `main` from the shared IR and answers 20 too;
## `alatyr x86-legacy` still refuses it. The MIRROR direction — a plain struct nested INSIDE a @packed
## struct — is covered by packed_agg_read / packed_nested_struct.
Pk  := @packed struct { a : u8, b : u16, c : u32 }
Big := struct { z : u64, p : Pk }

main := fn() -> u64 {
  g := Big(z = 1, p = Pk(a = 10, b = 20, c = 12))
  if g.z != 1 { return 4 }
  u64(g.p.b)
}
## expect: run 20
