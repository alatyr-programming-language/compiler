## #1579 — a `match` whose scrutinee is no variant of its enum reaches no arm. Only an explicit
## reinterpretation can make such a value: `bitcast` checks no validity invariant, and a later use of
## the out-of-range pattern has a hardware-defined meaning, never undefined behaviour the compiler
## exploits (Types §4.4, I11). So the spec fixes no single outcome here and each backend's is stated
## on its own line below. Every backend stops the program: the shared IR emits a `match_no_arm` trap.
## The legacy x86 emitter instead fell out of the `match` with -1 as its value, so `pick` returned a
## value no arm computes and the program ran on (exit 255) — the fall-through that hid #1108 inside
## the compiler. Since the slice-9 flip (#980) x86_64 emits `pick` from the shared IR.
Col := enum { R, G, B }
## A payload-free enum of the same width whose last variant's discriminant (7) is no `Col` variant.
Wide := enum { V0, V1, V2, V3, V4, V5, V6, V7 }

pick := fn(c : Col) -> u64 {
  match c {
    Col.R => { 1 }
    Col.G => { 2 }
    Col.B => { 3 }
  }
}

main := fn() -> u64 {
  w : Wide = Wide.V7
  c : Col = unchecked bitcast(Col, w)
  pick(c)
}
## expect(x86_64): trap
## expect(aarch64): trap
## expect(riscv64): trap
## expect(wasm): trap
