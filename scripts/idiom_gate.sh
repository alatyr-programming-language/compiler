#!/usr/bin/env bash
# scripts/idiom_gate.sh — the IDIOM gate: a duplicate-DECISION detector over `src/` + `lib/`.
# REPORTING ONLY. It never edits a byte of source, and it needs no compiler.
#
# WHY THIS EXISTS, AND WHY IT IS NOT A STYLE CHECKER
# -------------------------------------------------
# `alatyr fmt` settles SPELLING, and `scripts/fmt_corpus.sh` proves it does so without changing
# behaviour. Neither can see "three copies of one table" — and that is the class that actually
# produced defects here. This project's ledger, not a matter of taste:
#
#   * THREE private copies of the `op=` source scan (`sema::assign_is_reassign`,
#     `fmt::fmt_local_is_reassign`, `fmt::fmt_compound_op_str`), each listing a DIFFERENT subset of
#     the eight glyphs -> a valid program REJECTED and a write to an immutable binding ACCEPTED.
#   * THREE-PLUS copies of the `return 0`-after-flush shape -> two real defects: the three non-x86
#     emit surfaces failing OPEN, and an unreportable write failure on two more paths.
#   * FIVE hand-rolled `size(T)`-strided arena containers -> named in ROADMAP as the danger for the
#     layout switch.
#   * caches keyed on the wrong identity (`_sdc_*`/`_edc_*` on a `src` base, `LNI` on a decl COUNT)
#     -> 74 of 630 fixtures died rc 139 the first time a pass exercised them.
#
# THE FIVE RULES, AND WHAT EACH ONE CAN AND CANNOT SEE
# ---------------------------------------------------
#   TABLE   N functions comparing against the SAME short-literal table (>= LK shared literals, each
#           occurring in <= LMAXF functions repo-wide).            general
#   SCAN    N functions with an IDENTICAL parameter signature sharing >= SK literals (<= SMAXF).
#           The signature is "these answer the same question about the same input".  general
#   STRIDE  hand-rolled `<base> + <i> * <stride>` element addressing, per file.       ledger
#   DROPPED a fallible write/flush whose result is never read again.                  ledger
#   CACHE   a module-global memo cache's COLUMN SET, frozen per family.               ledger
#
# What was MEASURED AND REJECTED, so nobody re-derives it: normalized-token-window clone detection
# (the obvious candidate). At a window short enough to see the known cases (13-25 tokens) it reports
# 7 585 function pairs on this tree; at 240 tokens — a verbatim 240-token clone modulo identifier
# spellings — it still reports 216 pairs and misses EVERY case in the ledger, because the ledger's
# shapes are 3 to 15 tokens long. A rare-identifier vocabulary was also measured: 106 to 1 759
# pairs, and it too misses the container family. Neither is gateable. See ROADMAP / the lane report.
#
# HOW IT FAILS
# ------------
# Only on a NEW occurrence. `scripts/idiom.baseline` is a reviewed ALLOW list — one line per
# finding, each carrying a LOCATION, because a bare count cannot tell an accepted duplicate from a
# forgotten one. A baseline line that no longer occurs is reported `stale` and does NOT fail: a lane
# that REMOVES a duplicate must not be punished for it.
#
# Usage (no `nix develop` needed beyond `gawk`):
#   bash scripts/idiom_gate.sh                 check against the baseline (the gate)
#   bash scripts/idiom_gate.sh --show          also print every baselined finding, with locations
#   bash scripts/idiom_gate.sh --write         regenerate the baseline (its OWN reviewed commit)
#   bash scripts/idiom_gate.sh --root DIR      scan DIR/src + DIR/lib instead of this checkout
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_ROOT="$ROOT"
BASELINE="$ROOT/scripts/idiom.baseline"
MODE=check
SHOW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --write) MODE=write; shift ;;
    --show) SHOW=1; shift ;;
    --root) SCAN_ROOT="$2"; shift 2 ;;
    --baseline) BASELINE="$2"; shift 2 ;;
    *) echo "usage: $0 [--write] [--show] [--root DIR] [--baseline FILE]" >&2; exit 2 ;;
  esac
done
ulimit -c 0
command -v gawk >/dev/null || { echo "idiom: FAIL gawk is required (every other gate already needs it)" >&2; exit 2; }

# Thresholds. Each was chosen by measurement, and the measurement is recorded so a future change
# can be argued about rather than guessed:
#   LK=4  / LMAXF=20   -> 55 TABLE pairs on this tree, 12 clusters, 0 cluster-level false positives.
#   SK=4  / SMAXF=40   -> 20 SCAN pairs. At SK=3 it is 45; at SMAXF=100 it is 89 and at SK=3/100 it
#                         is 504, which is not a reviewable baseline.
# The `=`-fold in pairs.awk is load-bearing for recall, not a tidy-up: without it the pre-fix
# `sema::assign_is_reassign` scores ZERO against both fmt copies and the detector misses the very
# defect it exists for.
LK=${IDIOM_LK:-4}; LMAXF=${IDIOM_LMAXF:-20}; SK=${IDIOM_SK:-4}; SMAXF=${IDIOM_SMAXF:-40}

AW="$ROOT/scripts/idiom"
W="$ROOT/target/idiom"; rm -rf "$W"; mkdir -p "$W"

# The file list. `git ls-files` when the scan root is a git checkout — deliberately not `find`,
# for the reason `fmt_corpus.sh` gives: a generated, gitignored `.al` would make the gate's
# coverage depend on what ran before it. `find` only for a sandbox (`--root`, the self-test).
filelist() { # -> stdout, one path per line, relative to $SCAN_ROOT
  if [ "$SCAN_ROOT" = "$ROOT" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ROOT" ls-files 'src/*.al' 'lib/*.al'
  else
    ( cd "$SCAN_ROOT" && find src lib -name '*.al' -type f 2>/dev/null | sort )
  fi
}

# ---- the two passes ----------------------------------------------------------------------------
scan() { # $1 = root to scan, $2 = output dir; writes $2/{pairs,text,details,stats}
  local r="$1" o="$2" fl
  mkdir -p "$o"
  ( cd "$r" && filelist_for "$r" ) > "$o/files"
  [ -s "$o/files" ] || { echo "idiom: FAIL no .al files under $r/src, $r/lib" >&2; return 3; }
  ( cd "$r" && xargs -a "$o/files" gawk -f "$AW/tokenize.awk" ) > "$o/stream" 2>"$o/tok.err" || return 3
  [ -s "$o/tok.err" ] && { cat "$o/tok.err" >&2; return 3; }
  gawk -v LK="$LK" -v LMAXF="$LMAXF" -v SK="$SK" -v SMAXF="$SMAXF" \
       -f "$AW/pairs.awk" "$o/stream" > "$o/pairs" 2>"$o/pairs.stats" || return 3
  ( cd "$r" && xargs -a "$o/files" gawk -f "$AW/textual.awk" ) > "$o/textraw" 2>"$o/text.stats" || return 3
  grep    '^\.'  "$o/textraw" | cut -f2- > "$o/details" || true
  grep -v '^\.'  "$o/textraw"           > "$o/text"    || true
  LC_ALL=C sort -o "$o/pairs" "$o/pairs"
  LC_ALL=C sort -o "$o/text"  "$o/text"
  cat "$o/pairs" "$o/text" | LC_ALL=C sort > "$o/observed"
}
filelist_for() { if [ "$1" = "$SCAN_ROOT" ]; then filelist; else ( cd "$1" && find src lib -name '*.al' -type f 2>/dev/null | sort ); fi; }

# ---- the gate-of-the-gate ----------------------------------------------------------------------
# An invariant nobody has seen fail is decoration (AGENTS.md). So before the gate reports anything
# about the real tree, it plants a synthetic corpus that every rule MUST fire on, and a clean twin
# that no rule may fire on. If the detector stops detecting, THIS fails — not the report.
selftest() {
  local s="$W/selftest" ok=1
  rm -rf "$s"; mkdir -p "$s/clean/src" "$s/clean/lib" "$s/plant/src" "$s/plant/lib"
  # The clean twin: one function, no duplicate of anything.
  cat > "$s/clean/src/only.al" <<'ALEOF'
solo := fn(x : usize) -> usize {
  if x == 0 { return 1 }
  return x
}
ALEOF
  cat > "$s/clean/lib/nothing.al" <<'ALEOF'
lone := fn(y : usize) -> usize { return y + 1 }
ALEOF
  cp "$s/clean/src/only.al" "$s/plant/src/only.al"
  cp "$s/clean/lib/nothing.al" "$s/plant/lib/nothing.al"
  # TABLE: two functions, different files, sharing five RARE short literals (posting 2).
  # SCAN:  two functions with an identical signature sharing four literals that are too COMMON for
  #        TABLE (posting 27, above LMAXF) but inside SCAN's looser cutoff — and shared only
  #        through the `=`-fold (`"+="` on one side, `"+"` on the other). That is the exact shape
  #        that made the ledger's worst duplicate invisible, so the fold, the signature test and
  #        the two-cutoff split are all load-bearing here: collapse SMAXF onto LMAXF, or drop the
  #        fold, and this assertion fails.
  #        The posting of 27 is why the planted corpus needs 25 FILLERS. Each filler carries the
  #        four band literals and a UNIQUE signature, so the fillers push the postings into the
  #        (LMAXF, SMAXF] band without pairing with each other under SCAN.
  # STRIDE / DROPPED / CACHE: one planted site each.
  # The four BAND literals, in 25 filler functions each with a signature of its own.
  local i
  for i in $(seq 1 25); do
    cat > "$s/plant/src/zfill$i.al" <<ALEOF
zz_fill$i := fn(v : ZT$i) -> str {
  if v == "+" { return "-" }
  if v == "*" { return "/" }
  return ""
}
ALEOF
  done
  cat > "$s/plant/src/zplantA.al" <<'ALEOF'
zz_glyph_a := fn(c : str) -> str {
  if c == "\v" { return "\v" }
  if c == "\f" { return "\f" }
  if c == "?" { return "?" }
  if c == "!!" { return "!!" }
  if c == ";;" { return ";;" }
  return ""
}
zz_scan_a := fn(src : ptr(u8), zns : usize, znl : usize) -> str {
  mut p := zns + znl
  if str_at((src + p), 2) == "+=" { return "" }
  if str_at((src + p), 2) == "-=" { return "" }
  if str_at((src + p), 2) == "*=" { return "" }
  if str_at((src + p), 2) == "/=" { return "" }
  return ""
}
mut _zpl_key : [usize; 8] = [0; 8]
mut _zpl_val : [usize; 8] = [0; 8]
ALEOF
  cat > "$s/plant/lib/zplantB.al" <<'ALEOF'
zz_glyph_b := fn(c : str) -> str {
  if c == "\v" { return "\v" }
  if c == "\f" { return "\f" }
  if c == "?" { return "?" }
  if c == "!!" { return "!!" }
  if c == ";;" { return ";;" }
  return ""
}
zz_scan_b := fn(src : ptr(u8), zns : usize, znl : usize) -> str {
  mut p := zns + znl
  if str_at((src + p), 1) == "+" { return "" }
  if str_at((src + p), 1) == "-" { return "" }
  if str_at((src + p), 1) == "*" { return "" }
  if str_at((src + p), 1) == "/" { return "" }
  return ""
}
zz_elem := fn(v : ptr(ZVec), i : usize) -> ptr(usize) {
  return unchecked bitcast(ptr(usize), deref(v).base + i * 24)
}
zz_emit := fn(b : rt::StrBuf) -> usize {
  zdrop := rt::sb_flush(b, 1)
  return 0
}
ALEOF
  scan "$s/clean" "$W/st_clean" || { echo "idiom: FAIL self-test could not scan the clean twin"; return 1; }
  scan "$s/plant" "$W/st_plant" || { echo "idiom: FAIL self-test could not scan the planted corpus"; return 1; }
  local n
  n=$(wc -l < "$W/st_clean/observed")
  if [ "$n" != 0 ]; then
    echo "idiom: FAIL gate-of-the-gate — the CLEAN twin produced $n finding(s); the detector fires on nothing"
    sed 's/^/    /' "$W/st_clean/observed"; ok=0
  fi
  local rule
  for rule in TABLE SCAN STRIDE DROPPED CACHE; do
    if ! grep -q "^$rule	" "$W/st_plant/observed"; then
      echo "idiom: FAIL gate-of-the-gate — rule $rule did NOT fire on a planted $rule defect."
      echo "       The detector has stopped detecting. What it saw:"
      sed 's/^/    /' "$W/st_plant/observed"
      ok=0
    fi
  done
  # It must also FAIL, not merely report: an empty baseline plus findings must exit non-zero.
  if verdict "$W/st_plant/observed" /dev/null "$W/st_plant" >/dev/null 2>&1; then
    echo "idiom: FAIL gate-of-the-gate — findings absent from the baseline did not produce a non-zero exit"
    ok=0
  fi
  # The baseline is a reviewed KEY allow-list, not a line-number snapshot.  Exercise both
  # promises here: moving a finding must stay green, and a removed finding is stale-only and
  # must also stay green.  Keep the probe independent of the real baseline so --root self-tests
  # cannot accidentally bless a production change.
  awk 'NR == 1 { $NF = "old:old" } { print }' OFS="\t" "$W/st_plant/observed" > "$W/st_plant/moved.base"
  if ! verdict "$W/st_plant/observed" "$W/st_plant/moved.base" "$W/st_plant/moved" >/dev/null 2>&1; then
    echo "idiom: FAIL gate-of-the-gate — a location-only baseline change produced a NEW finding"
    ok=0
  fi
  {
    cat "$W/st_plant/observed"
    printf 'TABLE\tstale.al\tstale_a\tstale.al\tstale_b\t5\t-\t1:2\n'
  } > "$W/st_plant/stale.base"
  if ! verdict "$W/st_plant/observed" "$W/st_plant/stale.base" "$W/st_plant/stale" >/dev/null 2>&1; then
    echo "idiom: FAIL gate-of-the-gate — a stale baseline line caused a failure"
    ok=0
  fi
  # A global rarity cutoff may make an existing TABLE pair lose shared literals when an unrelated
  # function is added elsewhere.  That must not become NEW; a stronger score for the same pair must
  # still fail, because it records a newly shared decision literal.
  printf 'TABLE\told.al\told_table\tother.al\tother_table\t5\t-\t1:2\n' > "$W/st_plant/stability.base"
  printf 'TABLE\told.al\told_table\tother.al\tother_table\t4\t-\t9:10\n' > "$W/st_plant/stability.observed"
  if ! verdict "$W/st_plant/stability.observed" "$W/st_plant/stability.base" "$W/st_plant/stability-down" >/dev/null 2>&1; then
    echo "idiom: FAIL gate-of-the-gate — an existing pair losing score became NEW"
    ok=0
  fi
  # …and the line that did the suppressing must NOT be advertised as droppable. Reporting a
  # load-bearing ceiling as stale is what makes an honest cleanup turn the gate red.
  if [ -s "$W/st_plant/stability-down/stale" ]; then
    echo "idiom: FAIL gate-of-the-gate — the reviewed CEILING of a still-occurring pair was reported stale;"
    echo "       deleting it as the report instructs would unmask the observation as NEW. What it said:"
    sed 's/^/    /' "$W/st_plant/stability-down/stale"
    ok=0
  fi
  printf 'TABLE\told.al\told_table\tother.al\tother_table\t6\t-\t9:10\n' > "$W/st_plant/stability.observed"
  if verdict "$W/st_plant/stability.observed" "$W/st_plant/stability.base" "$W/st_plant/stability-up" >/dev/null 2>&1; then
    echo "idiom: FAIL gate-of-the-gate — a stronger existing pair did not become NEW"
    ok=0
  fi
  [ "$ok" = 1 ]
}

# Connected components over the pair graph, printed for the human. Union-find in awk; members are
# `file:name`, so a cluster reads as the list of places one decision currently lives.
cluster() {
  gawk -F'\t' '
    function find(x) { while (P[x] != x) { P[x] = P[P[x]]; x = P[x] } return x }
    function uni(a, b,   ra, rb) { ra = find(a); rb = find(b); if (ra != rb) P[ra] = rb }
    { a = $2 ":" $3; b = $4 ":" $5
      if (!(a in P)) P[a] = a
      if (!(b in P)) P[b] = b
      uni(a, b); RULE[a] = RULE[a] $1; RULE[b] = RULE[b] $1; N[a]; N[b] }
    END {
      for (k in N) { r = find(k); M[r] = M[r] " " k; C[r]++ }
      for (r in M) printf("cluster of %d: %s\n", C[r], M[r])
    }' "$1" | sort -t: -k1,1 | sort -rn -k3,3
}

# ---- the verdict -------------------------------------------------------------------------------
# NEW  = observed, not baselined -> FAIL.   stale = baselined, not observed -> report only.
#
# Comparison is on the KEY, which is every field but the LAST: the last field is the location, and
# a line number churns on any edit above it. So a moved function is not a new finding, while a new
# COPY of a decision is. The full line (location included) is recovered for the report by matching
# the key as a prefix.
keyproj() { gawk -F'\t' 'BEGIN { OFS = "\t" } { NF = NF - 1; print }'; }
verdict() { # observed baseline outdir -> 0 iff no NEW findings
  local obs="$1" base="$2" o="$3"
  mkdir -p "$o"
  grep -v '^#' "$base" 2>/dev/null | grep -v '^[[:space:]]*$' | LC_ALL=C sort > "$o/base" || : > "$o/base"
  keyproj < "$obs"     | LC_ALL=C sort -u > "$o/obs.k"
  keyproj < "$o/base"  | LC_ALL=C sort -u > "$o/base.k"
  # TABLE/SCAN scores are lower bounds measured through a global rarity cutoff.  An unrelated
  # function can push one literal over that cutoff and make an existing pair's score fall; compare
  # such a pair monotonically (observed <= reviewed maximum is still the same finding).  A score
  # increase remains NEW, as does any pair absent from the baseline.  The other rules keep their
  # exact key comparison.
  gawk -F '\t' '
    ARGIND == 1 { k = $1 FS $2 FS $3 FS $4 FS $5 FS $7
      if (($1 == "TABLE" || $1 == "SCAN") && $6 + 0 > max[k]) max[k] = $6 + 0
      else exact[$0] = 1
      next
    }
    ARGIND == 2 { k = $1 FS $2 FS $3 FS $4 FS $5 FS $7
      if (($1 == "TABLE" || $1 == "SCAN") && (k in max) && $6 + 0 <= max[k]) next
      if (!(($0) in exact)) print
    }' "$o/base.k" "$o/obs.k" > "$o/new.k"
  # stale must mean SAFE TO DELETE, and for TABLE/SCAN a plain set-difference does not: the NEW rule
  # above is MONOTONIC (a reviewed score of 6 suppresses an observed 4), so the score is part of the
  # key here while the suppression ignores it. A `comm -13` therefore reported the reviewed CEILING of
  # a pair that still occurs at a lower score as stale — and deleting it, exactly as this file and
  # scripts/idiom.baseline instruct, unmasked the observation as NEW. Measured: dropping the two
  # reviewed TABLE lines for aarch64 emit_a64_expr / riscv64 emit_rv_expr (scores 5 and 6) turned the
  # live score-4 finding for that same pair into a NEW one and failed the gate.
  #
  # So a TABLE/SCAN baseline line is reported stale only when it is genuinely droppable: either no
  # observation shares its monotonic key (the pair is gone), or a HIGHER reviewed line covers the same
  # key (this one is redundant — the rule reads max[k], not each line). The line holding the maximum
  # for a key that still occurs is load-bearing and is not reported. Other rules keep the exact
  # comparison, where the set-difference was already correct.
  gawk -F '\t' '
    ARGIND == 1 { oexact[$0] = 1; oseen[$1 FS $2 FS $3 FS $4 FS $5 FS $7] = 1; next }
    ARGIND == 2 { if ($1 == "TABLE" || $1 == "SCAN") {
                    k = $1 FS $2 FS $3 FS $4 FS $5 FS $7
                    if ($6 + 0 > bmax[k]) bmax[k] = $6 + 0
                  }
                  next
    }
    ARGIND == 3 { if ($1 == "TABLE" || $1 == "SCAN") {
                    k = $1 FS $2 FS $3 FS $4 FS $5 FS $7
                    if ((k in oseen) && $6 + 0 == bmax[k]) next   # the reviewed ceiling; load-bearing
                    print; next
                  }
                  if (!(($0) in oexact)) print
    }' "$o/obs.k" "$o/base.k" "$o/base.k" | LC_ALL=C sort -u > "$o/stale.k"
  : > "$o/new"; : > "$o/stale"
  while IFS= read -r k; do grep -m1 -F "$k" "$obs"    >> "$o/new"   || echo "$k" >> "$o/new";   done < "$o/new.k"
  while IFS= read -r k; do grep -m1 -F "$k" "$o/base" >> "$o/stale" || echo "$k" >> "$o/stale"; done < "$o/stale.k"
  [ ! -s "$o/new" ]
}

# ---- run ---------------------------------------------------------------------------------------
echo "### IDIOM GATE (gate-of-the-gate first) ###"
if ! selftest; then
  echo "*** idiom gate: the GATE-OF-THE-GATE failed — no verdict about src/ is trustworthy ***"
  exit 1
fi
echo "idiom: gate-of-the-gate OK — all 5 rules fired on a planted corpus, 0 on its clean twin"

scan "$SCAN_ROOT" "$W/main" || { echo "*** idiom gate: the scan itself failed ***"; exit 1; }

# NON-VACUITY, two independent ways. (1) The tokenizer's function count must be a strict SUPERSET
# of what a plain line regex finds: the tokenizer also sees `@inline name := fn(`, which the regex
# cannot, but a function the REGEX finds and the tokenizer misses means the segmentation silently
# skipped code — the exact failure AGENTS.md records ("a scan whose pattern silently skipped every
# `pub` declaration"), and it caught a real bug in tokenize.awk during development.
nfiles=$(wc -l < "$W/main/files")
nfun=$(grep -c '^F	' "$W/main/stream" || true)
( cd "$SCAN_ROOT" && xargs -a "$W/main/files" grep -hcE '^[[:space:]]*(pub[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:=[[:space:]]*fn[[:space:]]*\(' ) \
  | awk '{s+=$1} END{print s+0}' > "$W/main/regexcount"
nregex=$(cat "$W/main/regexcount")
vac=0
if [ "$nfun" -lt "$nregex" ]; then
  echo "idiom: FAIL the token segmentation found $nfun top-level functions but a plain line regex"
  echo "       found $nregex — the tokenizer is SKIPPING declarations, so every count below is a lie."
  vac=1
fi
# (2) Each textual rule's total must equal an independent grep count of the same shape.
gstride=$( ( cd "$SCAN_ROOT" && xargs -a "$W/main/files" grep -hcE '\.base[[:space:]]*\+[^)]*\*' ) | awk '{s+=$1} END{print s+0}')
astride=$(awk -F'\t' '$1=="STRIDE"{s+=$3} END{print s+0}' "$W/main/text")
if [ "$astride" -gt "$gstride" ]; then
  echo "idiom: FAIL STRIDE counted $astride sites but an independent grep sees at most $gstride"; vac=1
fi
[ "$vac" = 0 ] || { echo "*** idiom gate: a non-vacuity assertion failed ***"; exit 1; }

if [ "$MODE" = write ]; then
  {
    echo "# scripts/idiom.baseline — the reviewed ALLOW list for scripts/idiom_gate.sh."
    echo "#"
    echo "# One line per accepted finding, TAB-separated, each carrying a LOCATION so a reader can"
    echo "# tell an accepted duplicate from a forgotten one. Regenerating this file is an"
    echo "# INTENTIONAL act that belongs in its own reviewed commit — blessing a new duplicate"
    echo "# unreviewed erases the oracle, exactly as with scripts/corpus.manifest."
    echo "#"
    echo "# Columns:"
    echo "#   TABLE|SCAN  fileA  nameA  fileB  nameB  n-shared-literals  signature  lineA:lineB"
    echo "#   STRIDE      file   count                                              -"
    echo "#   DROPPED     file   callee  count                                      -"
    echo "#   CACHE       file   family  columns                                    -"
    echo "#"
    echo "# The LAST field of every row is a LOCATION and is EXCLUDED from the comparison: a line"
    echo "# number churns on any edit above it. Everything before it is the key."
    echo "#"
    echo "# Written by: bash scripts/idiom_gate.sh --write"
    echo "# Thresholds: LK=$LK LMAXF=$LMAXF SK=$SK SMAXF=$SMAXF"
    echo "#"
    echo "# The TABLE/SCAN pairs below, collapsed into CLUSTERS. A pair is the gate's unit (so a new"
    echo "# copy adds lines and FAILS, while a removed copy only goes stale), but a cluster is what a"
    echo "# reader can judge: 21 pairs among 7 functions is ONE duplicated decision, not 21."
    cluster "$W/main/pairs" | sed 's/^/# /'
    cat "$W/main/observed"
  } > "$BASELINE"
  echo "idiom: WROTE $BASELINE ($(wc -l < "$W/main/observed") findings) — review it in its own commit"
fi

verdict "$W/main/observed" "$BASELINE" "$W/main"; rc=$?

# ---- report ------------------------------------------------------------------------------------
if [ "$SHOW" = 1 ]; then
  echo "--- every finding (baselined included) ---"
  awk -F'\t' '{printf "%-8s %s\n", $1, substr($0, index($0,"\t")+1)}' "$W/main/observed" | sed 's/\t/  /g; s/^/  /'
  echo "--- located details for the line-level rules ---"
  sed 's/^/  /' "$W/main/details"
fi
if [ -s "$W/main/new" ]; then
  echo "--- NEW findings (not in $BASELINE) ---"
  sed 's/\t/  /g; s/^/  NEW  /' "$W/main/new"
  echo "  A NEW TABLE/SCAN pair means one decision now has one more copy. Extract the shared"
  echo "  decision, or — if the duplication is deliberate — add the line to the baseline WITH a"
  echo "  reason, in its own commit."
fi
if [ -s "$W/main/stale" ]; then
  echo "--- stale baseline lines (no longer occur; informational, NOT a failure) ---"
  sed 's/\t/  /g; s/^/  stale  /' "$W/main/stale"
fi

# PROOF OF WORK. A green with no counts cannot be told apart from a gate that walked nothing.
# textual.awk reports per INVOCATION, and `xargs` may make more than one; sum them.
nlines=$(sed -n 's/.*lines=\([0-9]*\).*/\1/p' "$W/main/text.stats" | awk '{s+=$1} END{print s+0}')
echo "idiom gate: files=$nfiles lines=${nlines:-?} functions=$nfun (line-regex floor $nregex) $(sed 's/^functions=[0-9]* //' "$W/main/pairs.stats")"
echo "idiom gate: stride-sites=$astride (independent grep ceiling $gstride) findings=$(wc -l < "$W/main/observed") baseline=$(wc -l < "$W/main/base") new=$(wc -l < "$W/main/new") stale=$(wc -l < "$W/main/stale")"
awk -F'\t' '{c[$1]++} END{for (r in c) printf "  %-8s %d\n", r, c[r]}' "$W/main/observed" | sort
if [ "$rc" = 0 ]; then
  echo "*** idiom gate: no NEW duplicate decision (every finding is in the reviewed baseline) ***"
else
  echo "*** idiom gate: $(wc -l < "$W/main/new") NEW duplicate decision(s) — see NEW above ***"
fi
exit "$rc"
