## e2e (#422) — a BYTE element read through a RANGE SLICE used DIRECTLY as the index base,
## `xs[lo..hi][i]` with `xs : [u8; N]`, plus the other two packed byte kinds `[i8; N]` and
## `[bits8; N]`. Grammar §3.4 (pin `v1.6.0`) writes `postfix-expr ::= primary { postfix }` with
## both `"[" expr "]"` and the range form among the postfix ops, so this is ONE primary plus TWO
## postfix steps and needs no intermediate binding; `v := xs[lo..hi]; v[i]` is the SAME access one
## binding later. Types §6.4 fixes the read: "the **stride** is `T`'s size rounded up to its
## alignment; element access is `base + i × stride`", and appendix 160 §3.5 makes `[T]` a
## `{ptr, len}` pair "over a contiguous run of `T`" — so a `[u8]` view steps ONE BYTE per element
## and its element is a one-byte load, never a word at `ptr + i*8`.
##
## Measured on `main` `c00eae90` with the published seed 0.2.21 on native x86_64 (`omen`), each
## program built with `alatyr -o <bin> <src>` and the produced binary's own `$?` read outside any
## pipeline: the BOUND spelling answered 42 and 93, while every DIRECT row was REFUSED at compile
## time by the located `index BASE is not a named array/slice place` refusal. Two spellings of one
## access disagreeing IS #422; the bound spelling is the reference the direct one must meet.
##
## x86_64 is the ONLY backend this fixture moves, and that is a layout fact read off the emitted
## GAS, not an assumption: x86_64 lays `[u8; N]` as PACKED BYTES (`movb %al, 0(%r13)` …
## `3(%r13)`), while aarch64, riscv64 and WAT store one WORD per element (measured on the parent:
## aarch64 `str x0, [x29, #16]`, `#24`, `#32`, `#40`) and already answer the direct spelling —
## 42 / 93 on all three, with `v := xs[1..3]; v[i]` answering the same. Their rows in
## `scripts/e2e.sh` are therefore CONTROLS that this change does not move them, not the regression
## evidence; the x86_64 `run` row is the regression.
##
## Every code below names the WRONG ANSWER it rules out rather than only the failing line (#386),
## because on this shape a plausible word is exactly what a partial fix produces: a zero, `lo`
## ignored (element 0 of the BASE array), one element either side of the intended one, and the
## view's own LENGTH in place of its element. The neighbours 71, 42, 93, 55 are non-zero and
## pairwise distinct, and `xs[3..4]` is a LENGTH-1 view whose length (1) and element (55) differ,
## so neither a zero nor a returned length can pass by coincidence. Index 1 of the two-byte view
## `{42, 93}` is the row that catches a stride still taken as a WORD: at `ptr + 8` the read leaves
## the four-byte run entirely and cannot answer 93.
##
## The `i8` rows decide SIGNEDNESS with a COMPARISON, not a returned value: `-42` zero-extended is
## 214, and `0 - 214` is 42 mod 256 — the same exit code `-42` sign-extended gives — so at this
## width an arithmetic result cannot tell `movzbq` from `movsbq` and only `< 0` can.
##
## NOT here: `[f32; N]` / `[f64; N]` and struct/enum elements. Those keep their existing located
## reject on x86_64 and their fail-loud trap on aarch64 / riscv64 / WAT, and stay with #422/#494;
## asserting them here would freeze a shape this change does not deliver. No index WRITE appears
## either: `xs[lo..hi][i] = v` is a parser gap tracked in #494, and a fixture that walked into it
## would pin a different defect.
main := fn() -> u64 {
  xs : [u8; 4] = [71, 42, 93, 55]
  ## the plain neighbours first: if these move, nothing below is attributable
  if xs[1] != 42 { return 1 }
  v := xs[1..3]
  if v[0] != 42 { return 2 }
  if v[1] != 93 { return 3 }
  ## #422 — element 0 of the byte view {42, 93}
  if xs[1..3][0] == 0 { return 4 }                    ## a zero word
  if xs[1..3][0] == 71 { return 5 }                   ## `lo` ignored: element 0 of the BASE array
  if xs[1..3][0] == 93 { return 6 }                   ## one element PAST the view's start
  if xs[1..3][0] == 2 { return 7 }                    ## the view's LENGTH instead of its element
  if xs[1..3][0] != 42 { return 8 }                   ## any other wrong word (a WORD load)
  if xs[1..3][1] == 0 { return 9 }
  if xs[1..3][1] == 42 { return 10 }                  ## one element BEFORE (the view's element 0)
  if xs[1..3][1] == 55 { return 11 }                  ## one element PAST the view's end
  if xs[1..3][1] != 93 { return 12 }                  ## a stride of 8 leaves this run: 93 impossible
  ## a LENGTH-1 view: its length (1) and its element (55) differ, so answering the length fails here
  if xs[3..4][0] == 1 { return 13 }
  if xs[3..4][0] != 55 { return 14 }
  ## the zero-start control pins the other half — adding a zero offset must not shift the element
  if xs[0..4][1] != 42 { return 15 }
  ## the bounds need not be literals
  lo := 1
  hi := 3
  if xs[lo..hi][0] != 42 { return 16 }
  if xs[lo..hi][1] != 93 { return 17 }
  ## the two spellings of ONE access must agree — the disagreement IS #422
  if v[0] != xs[1..3][0] { return 18 }
  if v[1] != xs[1..3][1] { return 19 }
  ## the direct read composes with arithmetic, and two base arrays must not share a view
  ys : [u8; 4] = [11, 22, 33, 44]
  if xs[1..3][0] + ys[0..2][1] != 64 { return 20 }
  if ys[1..3][0] != 22 { return 21 }
  if xs[1..3][0] != 42 { return 22 }
  ## an `unchecked` scope drops the bounds check and keeps the SAME address math (CG-7): index 2 of
  ## a two-element view names `xs[3]` = 55, which also proves `lo` is folded into the pointer.
  if unchecked xs[1..3][2] != 55 { return 23 }
  ## SIGNEDNESS: `-42` reaches the consumer sign-extended, so `< 0` holds; a `movzbq` answers 214
  ## and falls to the else. Decided by comparison because 0 - 214 == 42 (mod 256).
  bs : [i8; 4] = [-1, -42, 3, 4]
  if bs[1..3][0] < 0 { } else { return 24 }
  if bs[1..3][1] > 0 { } else { return 25 }
  ## `[bits8; N]` is the third packed byte kind and reads unsigned
  bt : [bits8; 4] = [71, 42, 93, 55]
  if bt[1..3][1] != 93 { return 26 }
  42
}
## expect: run 42
