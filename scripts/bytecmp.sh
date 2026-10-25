#!/usr/bin/env bash
# bytecmp.sh — prove a refactor moved no emitted byte: emit every corpus program through each backend
# with BOTH compilers and compare. Any difference is a behaviour change wearing a refactor's clothes.
# usage: bytecmp.sh <ref-bin> <base-dir-of-sources> [name-filter-regex]
cd "$(dirname "$0")/.." || exit 1
REF=${1:?ref compiler}; SRC=${2:?source tree}; FILT=${3:-.}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
same=0; diff_=0; fail=0
# the two compilers' own bindirs, resolved physically: trap comments embed them and the two
# worktrees differ there for a reason that is not behaviour.
REFDIR=$(cd "$(dirname "$REF")" && pwd -P)
BASEDIR=$(cd "$(dirname ./target/debug/alatyr)" && pwd -P)
cd "$SRC" || exit 1
for f in $(ls test/*.al | grep -E "$FILT" | sort); do
  for b in x86 x86-ir aarch64 riscv64 wat; do
    case "$b" in
      x86)     a=$(timeout 60 "$REF" "$f" 2>/dev/null); ra=$?
               c=$(timeout 60 ./target/debug/alatyr "$f" 2>/dev/null); rc=$? ;;
      x86-ir)  a=$(timeout 60 "$REF" x86-ir "$f" 2>/dev/null); ra=$?
               c=$(timeout 60 ./target/debug/alatyr x86-ir "$f" 2>/dev/null); rc=$? ;;
      *)       a=$(timeout 60 "$REF" "$b" "$f" 2>/dev/null); ra=$?
               c=$(timeout 60 ./target/debug/alatyr "$b" "$f" 2>/dev/null); rc=$? ;;
    esac
    if [ "$ra" != "$rc" ]; then echo "RC-DIFF  $b $f  ref=$ra base=$rc"; fail=$((fail+1)); continue; fi
    # Trap comments carry the COMPILER's own absolute path (`ud2 # trap div_zero <bindir>/../../lib/…`),
    # so two builds of the same source in two directories differ there for a reason that is not behaviour.
    # Normalise the compiler's own location out of both sides before comparing.
    a=${a//"$REFDIR"/@BIN@}
    c=${c//"$BASEDIR"/@BIN@}
    if [ "$a" = "$c" ]; then same=$((same+1)); else
      d=$(printf '%s' "$a" | diff - <(printf '%s' "$c") | head -4)
      echo "BYTE-DIFF $b $f:"; printf '%s\n' "$d" | sed 's/^/    /'; diff_=$((diff_+1))
    fi
  done
done
echo "bytecmp: same=$same byte-diff=$diff_ rc-diff=$fail"
[ "$diff_" = 0 ] && [ "$fail" = 0 ]
