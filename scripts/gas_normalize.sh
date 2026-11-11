#!/usr/bin/env bash
# scripts/gas_normalize.sh — the x86_64 GAS label normalization. ONE implementation (#980).
#
# Every comparison of two compilers' GAS that must ignore renumbering (the seed promotion's Stage1 ==
# Stage2 == Stage3 check and its seed->Stage1 delta in `scripts/promote.sh`, and any self-host probe)
# asks the same question: which labels does the compiler number for itself, so that a shift in that
# numbering is not a change? Two copies of the answer drift, and a drifted copy turns a pure renumbering
# into a delta nobody can describe in one sentence, or hides a real change behind one. So it lives here.
#
# Source it:  . "$ROOT/scripts/gas_normalize.sh"
#
# ## The label families it folds
#
#   .L<N>              the legacy emitter's per-program counter                  -> .LN
#   .Lra<N>_<k>        the register allocator's per-function labels             -> .LraN_K
#   .Lxir<N>_<k>       the shared-IR selector's region labels (src/lower/isel.al
#                      `sx_lbl`: N is the selected function's number, k the
#                      instruction that opens the region)                        -> .LxirN_K
#   .Lxir<N>_ret       the same selector's one return label per function         -> .LxirN_ret
#
# `.Lra` and `.Lxir` are folded first: `.L[0-9]+` cannot match them (a letter follows `.L`), but the
# order keeps that true by construction rather than by the shape of today's names. Every other number —
# immediates, offsets, and the module-relative `.Lstr<m>_<n>` / `.Lflt<m>_<n>` / `.Lfld<m>_<n>` pool
# labels, which are kept stable on purpose (src/lower.al, MODTAB) — is left as it is: a change there is
# a real change.
#
# The self-test of this function is `scripts/promote.sh --self-test`, a stage of `scripts/full.sh`.

## normalize_gas < GAS -> GAS with the compiler-numbered label families renumbered away
normalize_gas() {
  sed -E \
    -e 's/\.Lxir[0-9]+_[0-9]+/.LxirN_K/g' \
    -e 's/\.Lxir[0-9]+_ret/.LxirN_ret/g' \
    -e 's/\.Lra[0-9]+_[0-9]+/.LraN_K/g' \
    -e 's/\.L[0-9]+/.LN/g'
}
