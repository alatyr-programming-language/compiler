#!/usr/bin/env bash
# scripts/fixture_expect.sh — the fixture states its expected result (#1126), and since S3 that is the
# gate's verdict on it.
#
# ## Why
#
# `scripts/corpus.manifest` records what the compiler DOES, per (backend, fixture), and since #1014 the
# cross-backend reference is the observed x86_64 result. So a wrong value that x86_64 produces too is the
# expectation, and the gate is green beside it (#987 sat open next to a green gate that way). What a
# fixture is FOR is written in up to three places — its header prose, its `scripts/e2e.sh` rows and its
# manifest rows — and nothing keeps them together (#1042). This script reads all three and says where
# they part. The directive itself, and its grammar, live in scripts/fixture_oracle.sh (`expect_scan`),
# the one reader of what a fixture declares.
#
# ## The three sources, and which one is a claim
#
#   header        `## expect:` directives; else the two legacy shapes `oracle` reads (`## Expected …
#                 exit N`, `## build_reject`). The spec claim, once written.
#   registration  every row of scripts/e2e.sh, read from the driver's own recording phase
#                 (`ALATYR_E2E_LIST_ROWS=1`, no compiler needed), so loops and wrappers are expanded the
#                 way the gate expands them. A reviewed claim: the gate asserts it on every run.
#   manifest      scripts/corpus.manifest — OBSERVATION only, never a claim.
#
# A registration verb maps to an outcome on a scope (`*` = every backend):
#   run N                                   * run N  (the sweeps assert it on the twins too)
#   run_x86 / run_x86_trap / run_cli_trap / check_export / run_x86_out N, check_arm_rodata_labels _ N,
#   fmt_test / fmt_test_has / fmt_test_has_all N (the reformatted program runs to N; the source must too)
#                                           x86_64 run N
#   run_a64 / run_rv64 / run_wat N, run_{a64,rv64,wat}_out _ N
#                                           that backend, run N
#   check_accept                            * accept
#   check_reject, build_reject              * reject
#   check_reject_has / build_reject_has N, emit_reject_has B _ N
#                                           * reject "N"
#   check_located L, check_parse_located L  * reject "at line L"
#   check_build_located / check_limit_named / check_parse_expected L M
#                                           * reject "M" "at line L"
# A status equal to the backend's checked-trap status (132 x86_64 — so `run N 132` on `*` —, 133
# aarch64/riscv64, 134 wasm) is read as `trap`; any other status is literal (`run variadic_accum 142`
# is a sum, and the `unchecked` division fixtures' x86_64 136 is the hardware fault the spec leaves to
# the backend). Every other verb (CLI, package, emission-shape, formatter-only rows) states nothing a
# corpus row can check and is reported as such, by kind.
#
# A refusal is a SPEC claim only when the checker makes it. `check_*` and `emit_reject_has` (whose emit
# surfaces run the same check) say the program is invalid; `build_reject`/`build_reject_has` alone say
# only that the build refused — by its own documentation, often "a construct the lean lower rejects
# with a panic that sema does not model", i.e. a valid program the backend cannot lower yet. Written as
# `expect: reject`, such a row would turn an implementation limit into the specification (#998 is that
# case), so the generator holds every build-only refusal for review, as it holds every refusal some
# twin builds and runs.
#
# The line goes at the END of the file, because diagnostics print "at line N" (asserted by e2e rows and
# hashed into the manifest's stderr): a line at the top would move every one. The end is not free either.
# A diagnostic quotes the 24 bytes from its token (`near `…``), so a fixture refused in its last 24 bytes
# would quote the new line too. EXCERPT_HOLD below lists the fixtures for which a native x86_64
# `corpus_manifest.sh --check` after `--write` measured exactly that (16, at 55fa477: same phase and
# exit, different stderr hash, on all four backends). The generator holds them until S3 retires that
# hash, and it never touches a file whose last byte is not a newline, so the edit only appends.
#
# The end has a second cost. `alatyr fmt` deletes every comment after the last declaration (#1178,
# against Tooling §4.3.4), and the formatter rows (FMT_TRAILING_HOLD) count the `##` lines before and
# after `fmt`. That count is right — the line is a comment and the formatter must keep it — so the
# generator holds every fixture a formatter row counts (measured: 99 rows went red at 0330b70, gate run
# 41021299879) until #1178 is fixed, rather than exempting the directive from the count.
#
# On one backend, the registration's expectation is the fold of its `*` claims when it has any (the
# four-backend claim), else of that backend's own claims. `accept` is absorbed by a run/trap/reject
# claim (`check_accept` + `build_reject` is the documented "check passes, the build refuses" pair). Two
# different results are a CONFLICT. A backend-scoped claim that differs from the `*` claim is a PIN: it
# freezes today's result on that backend beside a four-backend claim, which is a deviation, not an
# expectation — S2 decides it, the generator never writes it.
#
# ## Output (S1 — the counts are a report; only a self-contradiction is a verdict)
#
#   (a) a fixture whose header and registration disagree on some backend
#   (b) a fixture with no stated expectation in its header
#   (c) an x86_64 manifest row whose observed result is not the registration's — the class every
#       existing check is blind to when x86_64 is the reference
#   plus registration conflicts, pins, malformed directives, and the twins' rows against the claim
#   (the size of S2's known-deviations list), by class.
#
# ## The known deviations (S2)
#
# For every backend a DIRECTIVE speaks for, the committed manifest row either meets it, or the pair is a
# row of scripts/known-deviations.tsv (`backend path observed #issue`) whose `observed` is exactly the
# manifest's. The rows name issues in scripts/known-deviations.issues.tsv (`issue rule difference
# rows|none`), which is also the published list: for each issue, the rule not met and the observable
# difference. Five ways to be wrong, each a --list name:
#   unlisted  a missed directive with no row        changed   a row whose observation moved
#   stale     a row whose backend now meets it      orphan    a row no directive speaks for
#   (a row for a directive fixture that has no manifest row yet is `pending`: counted, never failed
#   here, because the CORPUS MANIFEST stage already fails on a source with no rows)
#   unissued  a row with `#?` or an issue the table lacks, or one the table marks `none`
# and `issues` for the files themselves (an issue marked `rows` that no row names, an issue listed
# twice, a malformed line, or a deviation row out of LC_ALL=C order). A fix deletes its own rows; a change that adds a deviation adds its row, under an issue.
# Every issue in the table is OPEN (#1279). The gate has no network, so it reads an issue-state snapshot
# (`--open-issues FILE`, written by whoever holds `gh`: queue.sh, land.sh, the hosted workflow, or
# full.sh itself on a hand run), and refuses an issue the snapshot does not list as open, or marks
# `closing N` because the object under test closes it on landing. land.sh PHASE 2 asks `gh` the same
# question at the screen; `--issues-open` asks it by hand.
#
# ## The verdict (S3)
#
# --gate reads the OBSERVATION of this tree (--observed: the walk `corpus_manifest.sh --check` leaves at
# target/corpus-manifest/observed.manifest), never the committed manifest, which since S3 holds only the
# sources with no directive yet and the directive sources that print. The exit status is 1 when (a),
# a malformed directive, any deviation count above, a directive pair the walk did not observe
# (`unobserved`, --list pending), or a fixture with neither a directive nor a committed manifest row
# (`unstated`: a new fixture states its expectation) is non-zero (#1128: no gate stage prints a finding
# and passes). (b), (c), the twins and the generator are the S1 review list of the fixtures the manifest
# still holds, printed by --report and --review, never by --gate. Without --gate the status is 0 unless
# the inputs are unusable (2).
#
# ## Usage
#
#   scripts/fixture_expect.sh [--report]            the summary
#   scripts/fixture_expect.sh --gate --observed F   the verdict (see "The verdict (S3)"); exit 1 on a finding
#   scripts/fixture_expect.sh --gate --observed F --open-issues SNAPSHOT
#                                                   the same, and exit 1 when an issue of the table is
#                                                   not open in SNAPSHOT (see snapshot_open below)
#   scripts/fixture_expect.sh --snapshot-open       print a snapshot of the open issues (gh)
#   scripts/fixture_expect.sh --issues-open         exit 1 when an issue of the table is not open (gh)
#   scripts/fixture_expect.sh --list <what>         one line per item: a b c conflict pin malformed
#                                                   unmapped twins stale unlisted changed orphan
#                                                   unissued issues pending unstated
#   scripts/fixture_expect.sh --generate [--write]  the `## expect:` lines the registrations support, for
#                                                   every fixture without a directive. Without --write,
#                                                   print them; with it, APPEND them (rerunnable: a file
#                                                   that has a directive is never touched again).
#   scripts/fixture_expect.sh --review              the fixtures the generator refuses to fill, with the
#                                                   reason, as Markdown for the issue
#   scripts/fixture_expect.sh --self-test           planted inputs for every verdict above
#
#   --rows FILE / --manifest FILE / --test-dir DIR / --deviations FILE / --issues FILE
#                                                   read these instead (the self-test uses them)
#   --observed FILE                                 what each backend did. Required by --gate. Otherwise
#                                                   the default is the walk at target/corpus-manifest/
#                                                   observed.manifest; with no walk, --report and --list
#                                                   stale|unlisted|changed|unissued|pending refuse, and
#                                                   the rest read the --manifest file
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=fixture_oracle.sh
. "$ROOT/scripts/fixture_oracle.sh"
US="$(printf '\037')"
BACKENDS="x86_64 aarch64 riscv64 wasm"
## measured, not predicted: see "The line goes at the END" above
EXCERPT_HOLD="reject_call_call_callee reject_call_index_callee reject_float_exponent
  reject_float_exponent_missing_digit reject_iife reject_int_lit_bad_digit reject_int_lit_lead_sep
  reject_int_lit_line_after_ambient reject_int_lit_upper_prefix reject_trunc_arrow_no_ret_type
  reject_trunc_bind_no_value reject_trunc_fn_params_body string_xhh_invalid
  str_literal_elem_assign_reject value_expr_assign_call_reject value_expr_assign_view_byte_reject"
## the formatter verbs that count `##` lines (scripts/e2e.sh fmt_test, fmt_check): held for #1178
FMT_TRAILING_HOLD="fmt_test fmt_test_has fmt_test_has_all fmt_check"

## ---- registrations ----------------------------------------------------------------------------------
## e2e_rows -> the recorded table, one `printf %q` row per line.
e2e_rows() { ALATYR_E2E_LIST_ROWS=1 bash "$ROOT/scripts/e2e.sh"; }

## claims ROWS TESTDIR -> TSV  name  scope  outcome  needles  kind
## Only fixtures of the corpus (`TESTDIR/<name>.al`) are reported. A row whose verb states nothing a
## corpus row can check is emitted with outcome `-` so the report can name the verb.
## The rows are the repository's own e2e.sh table (trusted, and parsed exactly as e2e.sh's driver parses
## them, with `eval "set -- …"`); never point --rows at untrusted text.
claims() { # rows-file test-dir
  local rows="$1" dir="$2" row kind name scope out nd
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    eval "set -- $row"
    kind="$1"; shift
    name="${1:-}"; scope='*'; out=''; nd=''
    case "$kind" in
      run)                                   out="${2:-}" ;;
      run_x86|run_x86_trap|run_cli_trap|check_export|run_x86_out|fmt_test|fmt_test_has|fmt_test_has_all)
                                             scope=x86_64; out="${2:-}" ;;
      check_arm_rodata_labels)               scope=x86_64; out="${3:-}" ;;
      run_a64)  scope=aarch64; out="${2:-}" ;;   run_a64_out)  scope=aarch64; out="${3:-}" ;;
      run_rv64) scope=riscv64; out="${2:-}" ;;   run_rv64_out) scope=riscv64; out="${3:-}" ;;
      run_wat)  scope=wasm;    out="${2:-}" ;;   run_wat_out)  scope=wasm;    out="${3:-}" ;;
      check_accept)                          out=accept ;;
      check_reject|build_reject)             out=reject ;;
      check_reject_has|build_reject_has)     out=reject; nd="${2:-}" ;;
      emit_reject_has)                       name="${2:-}"; out=reject; nd="${3:-}" ;;
      check_located|check_parse_located)     out=reject; nd="at line ${2:-}" ;;
      check_build_located|check_limit_named|check_parse_expected)
                                             out=reject; nd="${3:-}${US}at line ${2:-}" ;;
      *)                                     out=- ;;
    esac
    [ -n "$name" ] && [ -f "$dir/$name.al" ] || continue
    case "$out" in
      accept|reject|-) ;;
      ''|*[!0-9]*) out=- ;;                 # a non-numeric "status" is not a claim we can read
      *) out="run:$out" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$scope" "$out" "$nd" "$kind"
  done < "$rows"
}

## corpus_files (run inside the test directory) -> every fixture, relative, sorted. The manifest's
## `git ls-files 'test/*.al'` matches below test/ too (test/package/…, test/ffi/…), so this does; and the
## gate's first stage (corpus_enum_check.sh) already holds the index and the worktree to the same set.
corpus_files() { find . -name '*.al' -not -path '*/target/*' | sed 's|^\./||' | LC_ALL=C sort; }

## legacy TESTDIR -> TSV  name  exit:N|reject   for the files whose header holds a legacy declaration
legacy() { # test-dir
  local dir="$1" f o
  ( cd "$dir" && corpus_files | tr '\n' '\0' | xargs -0 awk 'FNR <= 30 && tolower($0) ~ /^##[[:space:]]*(expected|build_reject)/ { print FILENAME; nextfile }' ) |
    while IFS= read -r f; do
      o="$(oracle "$dir/$f")"
      [ "$o" = none ] || printf '%s\t%s\n' "${f%.al}" "$o"
    done
}

## fmt_needles ROWS -> TSV  name  needle   (the formatter rows whose needle a generated line must avoid)
fmt_needles() { # rows-file
  local row kind
  while IFS= read -r row; do
    case "$row" in fmt_test_has\ *|fmt_test_has_all\ *|fmt_refuses_has\ *) ;; *) continue ;; esac
    eval "set -- $row"; kind="$1"; shift
    case "$kind" in
      fmt_test_has_all) local n="$1"; shift 2; for x in "$@"; do printf '%s\t%s\n' "$n" "$x"; done ;;
      fmt_test_has)     printf '%s\t%s\n' "$1" "${3:-}" ;;
      fmt_refuses_has)  printf '%s\t%s\n' "$1" "${2:-}" ;;
    esac
  done < "$rows"
}

## ---- the decider ------------------------------------------------------------------------------------
## evaluate MODE CLAIMS DIRECTIVES LEGACY MANIFEST NAMES FMTNEEDLES
## MODE is report | list:<what> | generate | review. One awk program holds every rule, so the report,
## the lists, the generator and the review list cannot answer the same question two ways.
evaluate() {
  awk -F'\t' -v OFS='\t' -v MODE="$1" -v US="$US" -v BACKENDS="$BACKENDS" -v EXCERPT="$(printf '%s' "$EXCERPT_HOLD" | tr '\n' ' ')" -v FMTHOLD=" $FMT_TRAILING_HOLD " -v GATE="${GATE:-0}" '
    function trapst(b) { return b == "x86_64" ? 132 : (b == "wasm" ? 134 : 133) }
    ## a registration status on backend b (or on * , read as x86_64: the table is x86_64-native)
    function norm(o, b,   n) {
      if (o !~ /^run:/) return o
      n = substr(o, 5) + 0
      return (n == trapst(b == "*" ? "x86_64" : b)) ? "trap" : o
    }
    function addneedles(key, nd,   k, a, i) {
      if (nd == "") return
      k = split(nd, a, US)
      for (i = 1; i <= k; i++) if (!((key SUBSEP a[i]) in NDSEEN)) {
        NDSEEN[key SUBSEP a[i]] = 1; ND[key] = ND[key] (ND[key] == "" ? "" : US) a[i]
      }
    }
    ## fold an outcome into the accumulator at key; returns nothing, marks CONF[key] on a clash
    function fold(key, o) {
      if (!(key in ACC) || ACC[key] == "accept") { if (!(key in ACC) || o != "accept") ACC[key] = o; return }
      if (o == "accept" || o == ACC[key]) return
      CONF[key] = ACC[key] " vs " o
    }
    function render(o, nd,   s, k, a, i, x) {
      if (o ~ /^run:/) return "run " substr(o, 5)
      if (o != "reject") return o
      s = "reject"; k = (nd == "" ? 0 : split(nd, a, US))
      for (i = 1; i <= k; i++) { x = a[i]; gsub(/\\/, "\\\\", x); gsub(/"/, "\\\"", x); s = s " \"" x "\"" }
      return s
    }
    function sat(o, b, ph, ex) {          # does an observed (phase, exit) meet outcome o on backend b?
      if (o ~ /^run:/)  return ph == "run" && ex == substr(o, 5)
      if (o == "trap")  return ph == "run" && ex == trapst(b)
      if (o == "accept") return ph == "run"
      if (o == "reject") return ph == "compile"
      return 1
    }
    function sameset(x, y,   a, b, i, n, m, h) {
      n = (x == "" ? 0 : split(x, a, US)); m = (y == "" ? 0 : split(y, b, US))
      delete h; for (i = 1; i <= n; i++) h[a[i]] = 1
      for (i = 1; i <= m; i++) { if (!(b[i] in h)) return 0; h[b[i]] = 2 }
      for (i = 1; i <= n; i++) if (h[a[i]] != 2) return 0
      return 1
    }
    FILENAME == ARGV[1] {                 # claims: name scope outcome needles kind
      NAME[$1] = 1
      if (index(FMTHOLD, " " $5 " ")) FMTR[$1] = 1
      if ($3 == "-") { UNMAPPED[$1] = UNMAPPED[$1] (UNMAPPED[$1] == "" ? "" : ",") $5; next }
      REG[$1] = 1; k = $1 SUBSEP $2; o = norm($3, $2)
      fold(k, o); if (o == "reject") addneedles(k, $4)
      if ($2 != "*") SCOPED[$1, $2] = 1; else STAR[$1] = 1
      if ($3 == "reject" && $5 ~ /^(check_|emit_reject_has$)/) CHKREJ[$1] = 1
      next
    }
    FILENAME == ARGV[2] {                 # directives: path scope outcome needles line
      n = $1; sub(/\.al$/, "", n)
      if ($2 == "!") { MAL[n] = MAL[n] (MAL[n] == "" ? "" : "; ") "line " $5 ": " $3; HASDIR[n] = 1; next }
      HASDIR[n] = 1; DIR[n, $2] = $3; DIRND[n, $2] = $4; next
    }
    FILENAME == ARGV[3] {                 # legacy: name exit:N|reject
      LEG[$1] = ($2 == "reject" ? "reject" : norm("run:" substr($2, 6), "x86_64")); next
    }
    FILENAME == ARGV[4] {                 # manifest
      if ($0 ~ /^[a-z0-9_]+\ttest\//) { n = $2; sub(/^test\//, "", n); sub(/\.al$/, "", n); PH[$1, n] = $3; EX[$1, n] = $4 }
      next
    }
    FILENAME == ARGV[5] { ALL[$1] = 1; if ($2 == "noeol") NOEOL[$1] = 1; next }
    FILENAME == ARGV[6] { FMTND[$1] = FMTND[$1] US $2; next }
    FILENAME == ARGV[7] {                 # known deviations: backend path observed issue (#1126 S2)
      if ($0 ~ /^#/ || $0 == "") next
      if (NF != 4 || $2 !~ /^test\/.*\.al$/ || $3 !~ /^[a-z]+\/[0-9]+$/ || $4 !~ /^#([0-9]+|\?)$/) { DVBAD[++n_dvbad] = "line " FNR ": not `backend<TAB>test/<path>.al<TAB>phase/exit<TAB>#<issue>`"; next }
      if (DVPREV != "" && $0 <= DVPREV) DVBAD[++n_dvbad] = "line " FNR ": not in LC_ALL=C sort order, or a duplicate"
      DVPREV = $0
      n = $2; sub(/^test\//, "", n); sub(/\.al$/, "", n)
      if ((($1, n) in DVOBS)) { DVBAD[++n_dvbad] = "line " FNR ": a second row for " $1 " " $2; next }
      DVOBS[$1, n] = $3; DVISS[$1, n] = substr($4, 2); DVLINE[$1, n] = FNR; next
    }
    FILENAME == ARGV[9] {                 # the committed corpus.manifest: which sources it still holds (S3)
      if ($0 ~ /^[a-z0-9_]+\ttest\//) { n = $2; sub(/^test\//, "", n); sub(/\.al$/, "", n); HELD[n] = 1 }
      next
    }
    FILENAME == ARGV[8] {                 # the issue table: issue rule difference rows|none
      if ($0 ~ /^#/ || $0 == "") next
      if (NF != 4 || $1 !~ /^[0-9]+$/ || $2 == "" || $3 == "" || ($4 != "rows" && $4 != "none")) { DVBAD[++n_dvbad] = "issue table line " FNR ": not `<issue><TAB><rule><TAB><difference><TAB>rows|none`"; next }
      if ($1 in ISS) { DVBAD[++n_dvbad] = "issue table line " FNR ": #" $1 " twice"; next }
      ISS[$1] = $4; next
    }
    END {
      nb = split(BACKENDS, B, " ")
      ne = split(EXCERPT, EA, /[ \t\n]+/); for (i = 1; i <= ne; i++) if (EA[i] != "") EXH[EA[i]] = 1
      for (f in ALL) {
        ## the registration, per backend
        for (i = 1; i <= nb; i++) {
          b = B[i]; RB[f, b] = ""; RN[f, b] = ""
          if ((f SUBSEP "*") in CONF) { RCONF[f] = "* " CONF[f, "*"]; continue }
          if (f in STAR) {
            RB[f, b] = ACC[f, "*"]; RN[f, b] = ND[f, "*"]
            if (((f, b) in SCOPED) && ((f SUBSEP b) in CONF)) { RCONF[f] = RCONF[f] b " " CONF[f, b] " "; continue }
            if ((f, b) in SCOPED) {
              s = ACC[f, b]
              if (RB[f, b] == "accept") { RB[f, b] = s; RN[f, b] = ND[f, b] }   # refines a bare accept
              else if (s != "accept" && s != RB[f, b]) PIN[f] = PIN[f] (PIN[f] == "" ? "" : ", ") b ": " render(s, ND[f, b]) " beside * " render(RB[f, b], "")
            }
          } else if ((f, b) in SCOPED) {
            if ((f SUBSEP b) in CONF) { RCONF[f] = RCONF[f] b " " CONF[f, b] " "; RB[f, b] = ""; continue }
            RB[f, b] = ACC[f, b]; RN[f, b] = ND[f, b]
          }
        }
        ## the header, per backend: a scoped directive, else the unscoped one, else the legacy shape
        hdr = 0
        for (i = 1; i <= nb; i++) {
          b = B[i]; HB[f, b] = ""; HN[f, b] = ""; HSRC[f, b] = ""
          if ((f, b) in DIR)        { HB[f, b] = DIR[f, b];   HN[f, b] = DIRND[f, b];   HSRC[f, b] = "directive" }
          else if ((f, "*") in DIR) { HB[f, b] = DIR[f, "*"]; HN[f, b] = DIRND[f, "*"]; HSRC[f, b] = "directive" }
          else if ((f in LEG) && b == "x86_64") { HB[f, b] = LEG[f]; HSRC[f, b] = "legacy" }
          if (HB[f, b] != "") hdr = 1
        }
        if (f in HASDIR) n_dir++
        if (f in LEG) n_leg++
        if (f in REG) n_reg++
        if (f in MAL) { n_mal++; if (MODE == "list:malformed") print f, MAL[f] }
        if (f in RCONF) { n_conf++; if (MODE == "list:conflict") print f, RCONF[f] }
        if (f in PIN) { n_pin++; if (MODE == "list:pin") print f, PIN[f] }
        if ((f in UNMAPPED) && !(f in REG)) { n_unm++; if (MODE == "list:unmapped") print f, UNMAPPED[f] }
        ## (a) header vs registration
        why = ""
        for (i = 1; i <= nb; i++) {
          b = B[i]
          if (HB[f, b] == "" || RB[f, b] == "") continue
          h = HB[f, b]; r = RB[f, b]
          if (HSRC[f, b] == "legacy" && h == "reject" && r == "reject") continue
          if (h != r || (h == "reject" && HSRC[f, b] == "directive" && !sameset(HN[f, b], RN[f, b])))
            why = why (why == "" ? "" : "; ") b ": header " render(h, HN[f, b]) " (" HSRC[f, b] "), registered " render(r, RN[f, b])
        }
        if (why != "") { n_a++; DISA[f] = why; if (MODE == "list:a") print f, why }
        ## (b) no stated expectation
        if (!(f in HASDIR) && !(f in HELD)) { n_unst++; if (MODE == "list:unstated") print f, "no `## expect:` directive, and no row in the committed corpus.manifest" }
        if (!hdr && !(f in MAL)) {
          n_b++
          cls = (f in REG) ? ((RB[f, "x86_64"] == "accept" && !(f in RCONF)) ? "registered-accept-only" : "registered") : ((f in UNMAPPED) ? "unmapped-verbs-only" : "unregistered")
          NB[cls]++
          if (MODE == "list:b") print f, cls, (f in REG) ? render(RB[f, "x86_64"], RN[f, "x86_64"]) : "-", ((("x86_64", f) in PH) ? PH["x86_64", f] "/" EX["x86_64", f] : "no-row")
        }
        ## (c) x86_64 observed vs registered, and the twins against the claim
        for (i = 1; i <= nb; i++) {
          b = B[i]; r = RB[f, b]
          if (r == "" || !((b, f) in PH)) continue
          ph = PH[b, f]; ex = EX[b, f]
          if (sat(r, b, ph, ex)) continue
          if (b == "x86_64") { n_c++; DISC[f] = 1; if (MODE == "list:c") print f, "registered " render(r, RN[f, b]), "observed " ph "/" ex; continue }
          if (r ~ /^run:/ && ph == "run" && ex == trapst(b)) cls = "trap-for-value"
          else if (r ~ /^run:|^trap$|^accept$/ && ph == "run") cls = "WRONG-VALUE"
          else if (r ~ /^run:|^trap$|^accept$/ && ph != "run") cls = "build-fails-" ph
          else if (r == "reject" && ph == "run") { cls = "ACCEPTS-INVALID"; TWRUN[f] = TWRUN[f] (TWRUN[f] == "" ? "" : ",") b }
          else cls = "rejects-in-" ph
          TW[b, cls]++; TWC[cls] = 1
          if (MODE == "list:twins") print b, f, cls, "registered " render(r, RN[f, b]), "observed " ph "/" ex
        }
        ## the known deviations (S2): every backend a DIRECTIVE speaks for, against its manifest row. A
        ## legacy header is not a directive and is not judged here; neither are needles (the manifest
        ## holds a stderr hash, not the text), which (a) already holds against the registration.
        if ((f in HASDIR) && !(f in MAL)) for (i = 1; i <= nb; i++) {
          b = B[i]; o = ((f, b) in DIR) ? DIR[f, b] : (((f, "*") in DIR) ? DIR[f, "*"] : "")
          if (o == "") continue
          ## no observed row: the observation does not cover this pair (S3: the gate passes the fresh
          ## walk, which covers every tracked source, so this is an incomplete input). UNOBSERVED is a
          ## failure under --gate; a listed row for the pair is counted as seen, not as an orphan.
          if (!((b, f) in PH)) { n_pend++; if ((b, f) in DVOBS) { DVSEEN[b, f] = 1; DVUSED[DVISS[b, f]]++ }; if (MODE == "list:pending") print b, "test/" f ".al", ((b, f) in DVOBS) ? DVOBS[b, f] " #" DVISS[b, f] : "no row"; continue }
          DVSEEN[b, f] = 1; obs = PH[b, f] "/" EX[b, f]; listed = ((b, f) in DVOBS)
          if (sat(o, b, PH[b, f], EX[b, f])) {
            if (listed) { n_stale++; if (MODE == "list:stale") print b, "test/" f ".al", "listed " DVOBS[b, f] " #" DVISS[b, f], "but observed " obs " meets " render(o, "") }
            continue
          }
          if (!listed) { n_unl++; if (MODE == "list:unlisted") print b, "test/" f ".al", obs, "#?"; continue }
          n_dev++; DVUSED[DVISS[b, f]]++
          if (DVOBS[b, f] != obs) { n_chg++; if (MODE == "list:changed") print b, "test/" f ".al", "listed " DVOBS[b, f], "observed " obs }
          if (DVISS[b, f] == "?" || !(DVISS[b, f] in ISS)) { n_noiss++; if (MODE == "list:unissued") print b, "test/" f ".al", "#" DVISS[b, f] }
          else if (ISS[DVISS[b, f]] == "none") { n_noiss++; if (MODE == "list:unissued") print b, "test/" f ".al", "#" DVISS[b, f] " is marked none (no fixture row) in the issue table" }
        }
        ## the generator: every fixture with no directive whose registration is clean
        if (MODE != "generate" && MODE != "review" && MODE != "report") continue
        if (f in HASDIR) continue
        reason = ""
        if (!(f in REG))       reason = (f in UNMAPPED) ? "registered only by verbs that state no outcome (" UNMAPPED[f] ")" : "not registered in scripts/e2e.sh"
        else if (f in RCONF)   reason = "the registration contradicts itself: " RCONF[f]
        else if (f in PIN)     reason = "a backend-scoped row pins a result beside the four-backend claim: " PIN[f]
        else if (f in DISA)    reason = "header and registration disagree: " DISA[f]
        else if (f in DISC)    reason = "x86_64 observes something other than the registration (c)"
        else if (f in TWRUN)   reason = "registered as refused, but " TWRUN[f] " build and run it: a spec rejection, or a lowering limit on a valid program?"
        else if (RB[f, "x86_64"] == "reject" && !(f in CHKREJ)) reason = "refused only by the build (no check-level row): a spec rejection, or a lowering limit on a valid program?"
        else if (f in NOEOL)   reason = "the file does not end in a newline, and the migration only appends: placing the line changes its last line"
        else if (f in EXH)     reason = "its diagnostic quotes the last bytes of the file, so an appended line changes its stderr hash (measured): placed when S3 retires that hash"
        else if (f in FMTR)    reason = "a formatter row counts its ## lines, and alatyr fmt deletes a comment after the last declaration (#1178): placed when that is fixed"
        lines = ""
        if (reason == "") {
          ## one unscoped line when every backend agrees; else the * claim, plus a scoped line for each
          ## backend whose claim is not it (a refinement of `accept`, or a backend-only registration)
          same = (RB[f, B[1]] != ""); first = RB[f, B[1]] SUBSEP RN[f, B[1]]
          for (i = 2; i <= nb; i++) if ((RB[f, B[i]] SUBSEP RN[f, B[i]]) != first) same = 0
          base = (f in STAR) ? ACC[f, "*"] SUBSEP ND[f, "*"] : ""
          if (same) lines = "## expect: " render(RB[f, B[1]], RN[f, B[1]])
          else {
            if (f in STAR) lines = "## expect: " render(ACC[f, "*"], ND[f, "*"])
            for (i = 1; i <= nb; i++) if (RB[f, B[i]] != "" && (RB[f, B[i]] SUBSEP RN[f, B[i]]) != base)
              lines = lines (lines == "" ? "" : "\n") "## expect(" B[i] "): " render(RB[f, B[i]], RN[f, B[i]])
          }
          k = split(FMTND[f], fa, US)
          for (j = 2; j <= k; j++) if (index(lines, fa[j])) reason = "a formatter row searches its comments for [" fa[j] "], which the generated line would contain"
        }
        if (reason != "") {
          n_rev++; REVC[reason ~ /^not registered/ ? "unregistered" : (reason ~ /^registered only/ ? "unmapped" : (reason ~ /^the registration/ ? "conflict" : (reason ~ /^a backend/ ? "pin" : (reason ~ /^header/ ? "a" : (reason ~ /^x86_64/ ? "c" : (reason ~ /^registered as refused/ ? "twins-build-a-refusal" : (reason ~ /^refused only/ ? "build-only-refusal" : (reason ~ /^the file does not end/ ? "no-final-newline" : (reason ~ /^its diagnostic quotes/ ? "excerpt-reaches-eof" : (reason ~ /^a formatter row counts/ ? "fmt-drops-trailing-comment" : "fmt-needle"))))))))))]++
          if (MODE == "review") print f, reason
          continue
        }
        n_gen++
        if (MODE == "generate") { k = split(lines, la, "\n"); for (j = 1; j <= k; j++) print f, la[j] }
      }
      for (k in DVOBS) if (!(k in DVSEEN)) {
        split(k, kk, SUBSEP); n_orph++
        if (MODE == "list:orphan") print kk[1], "test/" kk[2] ".al", "line " DVLINE[k] ": no directive speaks for this backend, or no manifest row"
      }
      for (x in ISS) {
        if (ISS[x] == "rows" && !(x in DVUSED)) { n_issbad++; if (MODE == "list:issues") print "#" x, "marked rows, but no deviation row names it" }
        if (MODE == "list:issue-numbers") print x
      }
      for (i = 1; i <= n_dvbad; i++) if (MODE == "list:issues") print "-", DVBAD[i]
      n_issbad += n_dvbad
      if (MODE != "report") exit
      for (f in ALL) n_all++
      if (GATE == 1) {
        n_held = 0; for (f in ALL) if (!(f in HASDIR) && (f in HELD)) n_held++
        n_iss = 0; for (x in ISS) n_iss++
        printf "fixture expect (S3 verdict): fixtures=%d with-directive=%d; held by the committed corpus.manifest with no directive yet: %d (the review list: --review)\n", n_all, n_dir, n_held
        printf "  directives: %d rows missed and listed under %d issues; stale %d, unlisted %d, changed %d, orphan %d, unissued %d, unobserved %d, file/issue-table problems %d\n", n_dev, n_iss, n_stale, n_unl, n_chg, n_orph, n_noiss, n_pend, n_issbad
        printf "  header vs registration %d; malformed directives %d; fixtures with no directive and no manifest row %d\n", n_a, n_mal, n_unst
        bad = n_a + n_mal + n_stale + n_unl + n_chg + n_orph + n_noiss + n_issbad + n_pend + n_unst
        if (bad) { printf "  GATE: FAIL — (a)=%d malformed=%d stale=%d unlisted=%d changed=%d orphan=%d unissued=%d table=%d unobserved=%d unstated=%d; all must be 0 (see --list <name>)\n", n_a, n_mal, n_stale, n_unl, n_chg, n_orph, n_noiss, n_issbad, n_pend, n_unst; exit 3 }
        printf "  GATE: ok — every directive is met on every backend of this walk, or its miss is listed under an issue; every other fixture is held by corpus.manifest\n"
        exit
      }
      printf "fixture expect (S1): fixtures=%d with-directive=%d legacy-header=%d registered=%d\n", n_all, n_dir, n_leg, n_reg
      printf "  (a) header and registration disagree:      %d fixtures\n", n_a
      printf "  (b) no stated expectation in the header:    %d fixtures (registered %d, of which accept-only %d; registered only by outcome-free verbs %d; unregistered %d)\n", n_b, NB["registered"] + NB["registered-accept-only"], NB["registered-accept-only"], NB["unmapped-verbs-only"], NB["unregistered"]
      printf "  (c) x86_64 observed differs from registered: %d rows\n", n_c
      printf "  registration conflicts %d; pins beside a four-backend claim %d; malformed directives %d\n", n_conf, n_pin, n_mal
      printf "  twins against the registered claim (S2 input):"
      for (i = 2; i <= nb; i++) {
        printf "\n    %-8s", B[i]
        for (c in TWC) if (TW[B[i], c]) printf " %s=%d", c, TW[B[i], c]
      }
      printf "\n  generator: %d fixtures fillable now, %d held for review (", n_gen, n_rev
      sep = ""; for (c in REVC) { printf "%s%s=%d", sep, c, REVC[c]; sep = " " }
      printf ")\n"
      n_iss = 0; for (x in ISS) n_iss++
      printf "  known deviations (S2): %d rows listed and reproduced (%d pairs unobserved), under %d issues; stale %d, unlisted %d, changed %d, orphan %d, unissued %d, file/issue-table problems %d\n", n_dev, n_pend, n_iss, n_stale, n_unl, n_chg, n_orph, n_noiss, n_issbad
    }' "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}"
}

## ---- driver -------------------------------------------------------------------------------------------
## Which file says what each backend did (#1225 review). --gate takes only an explicit --observed: the
## verdict is on what this tree DOES, never a walk left over from another tree. Every other mode takes
## --observed, else the walk `corpus_manifest.sh --check` leaves behind, as sites_triage.sh and
## twin_coverage.sh do. With neither, the modes that judge deviations refuse: since S3 the committed
## manifest no longer holds the directive fixtures, so reading it skips every pair as unobserved and
## `--list unlisted` printed nothing with exit 0 (#1128: never a silent "nothing to add"); `unissued`
## too, since it is counted only on an observed pair. With a walk, every mode reads the walk. Only with
## no walk do the S1 review modes fall back to the committed manifest, whose fixtures are their subject.
observation_for() { # mode gate observed walk manifest -> the path on stdout, or a refusal on stderr and 2
  local mode="$1" gate="$2" obs="$3" walk="$4" manifest="$5"
  if [ -n "$obs" ]; then printf '%s\n' "$obs"; return 0; fi
  if [ "$gate" = 1 ]; then
    echo "fixture_expect.sh: --gate needs --observed <walk> (scripts/corpus_manifest.sh --check leaves it at" >&2
    echo "  target/corpus-manifest/observed.manifest); the committed manifest is not an observation of this tree" >&2
    return 2
  fi
  if [ -f "$walk" ]; then
    echo "fixture_expect.sh: reading the observation $walk (written $(date -r "$walk" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?'))" >&2
    printf '%s\n' "$walk"; return 0
  fi
  case "$mode" in
    report|list:stale|list:unlisted|list:changed|list:unissued|list:pending)
      echo "fixture_expect.sh: ${mode#list:} judges deviations and needs an observation of this tree: run" >&2
      echo "  scripts/corpus_manifest.sh --check (it leaves target/corpus-manifest/observed.manifest), or pass" >&2
      echo "  --observed <walk>; the committed manifest no longer holds the directive fixtures (S3)" >&2
      return 2 ;;
  esac
  printf '%s\n' "$manifest"
}

run_mode() { # mode rows manifest test-dir [deviations issues [observed]]
  ## manifest: the committed corpus.manifest (which sources it holds); observed: what each backend did
  ## (the driver's is chosen by observation_for; a self-test call that omits it reads the manifest)
  local mode="$1" rows="$2" manifest="$3" dir="$4" devs="${5:-}" issues="${6:-}" observed="${7:-$3}" w rc=0
  mkdir -p "$ROOT/target" && w="$(mktemp -d "$ROOT/target/fixture-expect.XXXXXX")" || return 2
  claims "$rows" "$dir" > "$w/claims"
  ( cd "$dir" && corpus_files | tr '\n' '\0' | xargs -0 bash -c '. "$1"; shift; expect_scan "$@"' _ "$ROOT/scripts/fixture_oracle.sh" ) > "$w/dirs"
  legacy "$dir" > "$w/legacy"
  ## name, and `noeol` for a file whose last byte is not a newline (the migration only appends, and
  ## `trailing_no_final_newline` exists to test exactly that last byte)
  ( cd "$dir" && corpus_files | while IFS= read -r f; do
      if [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ]; then printf '%s\tnoeol\n' "${f%.al}"; else printf '%s\n' "${f%.al}"; fi
    done ) > "$w/names"
  fmt_needles "$rows" > "$w/fmt"
  ## an absent list is an empty one (the self-test's plants run without one); distinct files, because
  ## awk tells its inputs apart by name
  [ -n "$devs" ] || { : > "$w/devs.empty"; devs="$w/devs.empty"; }
  [ -n "$issues" ] || { : > "$w/issues.empty"; issues="$w/issues.empty"; }
  local erc=0
  [ -f "$manifest" ] && [ -f "$observed" ] || { rm -rf "$w"; return 2; }
  ## awk tells its inputs apart by name: the same file twice is copied
  [ "$observed" != "$manifest" ] || { cp "$manifest" "$w/observed"; observed="$w/observed"; }
  evaluate "$mode" "$w/claims" "$w/dirs" "$w/legacy" "$observed" "$w/names" "$w/fmt" "$devs" "$issues" "$manifest" > "$w/out" || erc=$?
  case "$erc" in 0) ;; 3) rc=1 ;; *) rc=2 ;; esac   # 3: the --gate verdict; anything else: unusable
  case "$mode" in
    generate) sort -s -t "$(printf '\t')" -k1,1 "$w/out" > "$w/gen"   # stable: a fixture keeps its line order
              if [ "${WRITE:-0}" = 1 ]; then
                local f line prev="" skip=0 n=0
                while IFS="$(printf '\t')" read -r f line; do
                  if [ "$f" != "$prev" ]; then
                    prev="$f"; skip=1
                    ## never touch a file that already carries a directive: the generator is rerunnable
                    ## and never one whose last byte is not a newline: the edit only appends
                    if [ -f "$dir/$f.al" ] && ! grep -qiE "$EXPECT_TRIGGER" "$dir/$f.al" \
                       && [ -z "$(tail -c 1 "$dir/$f.al")" ]; then
                      skip=0; n=$((n + 1))
                    fi
                  fi
                  [ "$skip" = 1 ] || printf '%s\n' "$line" >> "$dir/$f.al"
                done < "$w/gen"
                echo "fixture expect: appended directives to $n fixtures"
              else
                cat "$w/gen"
              fi ;;
    review)   sort "$w/out" ;;
    *)        cat "$w/out" ;;
  esac
  ## the closed-issue check (#1279) joins the --gate verdict when a snapshot is given; full.sh always
  ## gives one, or fails the stage itself. Without one, say so: an unchecked fact is never a pass.
  if [ "$mode" = report ] && [ "${GATE:-0}" = 1 ]; then
    if [ -n "${OPEN_ISSUES:-}" ]; then
      local orc=0; issues_open "$issues" "$OPEN_ISSUES" || orc=$?
      case "$orc" in
        0) ;;
        1) echo "  GATE: FAIL — a known-deviation issue is not open (#1279)"; [ "$rc" = 2 ] || rc=1 ;;
        *) echo "  GATE: the issue-state snapshot is unusable (exit 2, not a pass)"; rc=2 ;;
      esac
    else
      echo "  known-deviation issues: NOT CHECKED here (no --open-issues snapshot); full.sh checks them"
    fi
  fi
  rm -rf "$w"
  return "$rc"
}

## The issue-state SNAPSHOT (#1279): the one input of the closed-issue check, so the gate itself can
## refuse a deviation whose issue is closed while it runs with no network and no credentials. A line is
## an OPEN issue number, `closing <N>` for an issue the object under test closes on landing (its PR's
## `Closes #N`: open on GitHub now, closed the moment the gate's object lands, so its rows must already
## be gone), or a `#` comment. Whoever holds credentials writes it before the gate: scripts/queue.sh for a
## batch, scripts/land.sh for a solo or hand landing, the hosted workflow before `full.sh`, and full.sh
## itself (`--snapshot-open`) on a hand run with `gh` logged in. A snapshot naming no open issue is a
## failed query, never a pass.
snapshot_open() { # -> the snapshot on stdout (gh); 2 when GitHub cannot be read
  local t
  command -v gh > /dev/null || { echo "fixture_expect.sh: gh is not on PATH; the issue states cannot be read (not a pass)" >&2; return 2; }
  mkdir -p "$ROOT/target" && t="$(mktemp "$ROOT/target/fixture-expect-open.XXXXXX")" || return 2
  gh issue list --state open --limit 5000 --json number --jq '.[].number' > "$t" 2> "$t.err" \
    || { echo "fixture_expect.sh: gh issue list failed: $(head -c 300 "$t.err") (not a pass)" >&2; rm -f "$t" "$t.err"; return 2; }
  grep -q '^[0-9][0-9]*$' "$t" || { echo "fixture_expect.sh: gh returned no open issue at all (not a pass)" >&2; rm -f "$t" "$t.err"; return 2; }
  printf '# open issues, read by gh at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; cat "$t"; rm -f "$t" "$t.err"
}

## issues_open TABLE SNAPSHOT -> exit 0 when every issue the table names is OPEN in the snapshot and not
## closed by the object under test, 1 when one is not, 2 when the snapshot is unusable. A row names an
## open issue (#1126 design 4): the fix that closes it deletes its rows in the same PR, so a closed issue
## still in the table is a row that outlived its fix, or a fix that never came.
issues_open() { # table snapshot
  [ -f "$2" ] || { echo "fixture_expect.sh: no issue-state snapshot at $2 (not a pass)" >&2; return 2; }
  grep -q '^[0-9][0-9]*$' "$2" || { echo "fixture_expect.sh: the snapshot $2 names no open issue: a failed query (not a pass)" >&2; return 2; }
  awk -F'\t' 'FILENAME == ARGV[1] {
      if ($0 ~ /^[0-9]+$/) OPEN[$0] = 1; else if ($0 ~ /^closing [0-9]+$/) { split($0, c, " "); CLOSING[c[2]] = 1 }
      else if ($0 !~ /^#/ && $0 != "") { printf "fixture_expect.sh: snapshot line %d is not `N`, `closing N` or a comment\n", FNR > "/dev/stderr"; unusable = 1 }
      next }
    $0 ~ /^#/ || $0 == "" { next }
    { n++
      if ($1 in CLOSING) { bad++; printf "  closed by this landing: #%s (%s): the fix deletes its rows and its table line\n", $1, $3 }
      else if (!($1 in OPEN)) { bad++; printf "  not open: #%s (%s): delete its rows, or reopen it if the deviation stands\n", $1, $3 } }
    END { if (unusable) exit 2
      printf "  known-deviation issues (#1279): %d in the table, %d not open\n", n, bad; exit (bad ? 1 : 0) }' "$2" "$1"
}

self_test() {
  local d rc=0 got nchk=0
  mkdir -p "$ROOT/target" && d="$(mktemp -d "$ROOT/target/fixture-expect-selftest.XXXXXX")" || return 2
  chk() { nchk=$((nchk + 1)); if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 — got [$2], want [$3]"; rc=1; fi; }
  mkdir -p "$d/t"
  p() { printf '%b' "$2" > "$d/t/$1.al"; }
  m() { printf '%s\ttest/%s.al\t%s\t%s\th\th\n' "$1" "$2" "$3" "$4" >> "$d/m"; }
  : > "$d/m"
  p good      'main := fn() -> u64 { return 42 }\n## expect: run 42\n'
  p hdrdiff   'main := fn() -> u64 { return 42 }\n## expect: run 41\n'
  p legdiff   '## Expected exit: 7.\nmain := fn() -> u64 { return 42 }\n'
  p needles   'main := fn() -> u64 { return x }\n## expect: reject "unbound \\"x\\"" "at line 1"\n'
  p ndldiff   'main := fn() -> u64 { return x }\n## expect: reject "other"\n'
  p bare      'main := fn() -> u64 { return 42 }\n'
  p unreg     'main := fn() -> u64 { return 42 }\n'
  p wrongx86  'main := fn() -> u64 { return 42 }\n'
  p trapper   'main := fn() -> u64 { return 42 }\n'
  p perback   'main := fn() -> u64 { return 42 }\n'
  p pinned    'main := fn() -> u64 { return 42 }\n'
  p clash     'main := fn() -> u64 { return 42 }\n'
  p typo      'main := fn() -> u64 { return 42 }\n##expect: run 42\n'
  p twice     'main := fn() -> u64 { return 42 }\n## expect: run 42\n## expect: run 42\n'
  p nocolon   'main := fn() -> u64 { return 42 }\n## expect run 4\n'
  p capital   'main := fn() -> u64 { return 42 }\n# Expect: run 42\n'
  p range     'main := fn() -> u64 { return 42 }\n## expect: run 256\n'
  p fmtcount  'main := fn() -> u64 { return 42 }\n'
  p fmtd      'main := fn() -> u64 { return 42 }\n'
  p prose     '## Expected: a value, nothing else\nmain := fn() -> u64 { return 42 }\n'
  p refine    'main := fn() -> u64 { return 7 }\n'
  p bonly     'main := fn() -> u64 { return 7 }\n'
  p crej      'main := fn() -> u64 { return x }\n'
  p twrun     'main := fn() -> u64 { return x }\n'
  p noeol     'main := fn() -> u64 { return 42 }'
  cat > "$d/rows" <<'EOF'
run good 42 
run hdrdiff 42 
run legdiff 42 
build_reject_has needles unbound\ \"x\" 
check_located needles 1 
build_reject_has ndldiff unbound 
run bare 42 
run wrongx86 42 
run trapper 132 
run_x86 perback 136 
run_a64 perback 41 
run_rv64 perback 41 
run pinned 42 
run_a64 pinned 133 
run clash 42 
check_reject clash 
run typo 42 
check_accept refine 
build_reject_has bonly lower\ refuses 
check_reject_has crej type\ mismatch 
check_reject twrun 
run_x86 refine 7 
fmt_refuses_has fmtd run 
run fmtd 42 
fmt_test fmtcount 42 
run fmtcount 42 
run noeol 42 
EOF
  for n in good hdrdiff legdiff bare fmtd fmtcount noeol prose typo twice; do m x86_64 "$n" run 42; done
  m x86_64 needles compile 1; m x86_64 ndldiff compile 1; m x86_64 wrongx86 run 41
  m aarch64 wrongx86 run 41; m x86_64 trapper run 132; m aarch64 trapper run 133; m wasm trapper run 0
  m x86_64 perback run 136; m x86_64 refine run 7; m x86_64 bonly compile 1; m x86_64 crej compile 1; m x86_64 twrun compile 1; m aarch64 twrun run 133; m aarch64 perback run 41; m riscv64 perback run 41
  m x86_64 pinned run 42; m aarch64 pinned run 133; m aarch64 good run 133; m riscv64 good run 41
  m wasm good compile 1; m riscv64 needles run 0
  L() { run_mode "list:$1" "$d/rows" "$d/m" "$d/t" | cut -f1 | sort | tr '\n' ' '; }
  got="$(L a)";         chk "(a) a directive, a legacy header and a needle set that disagree" "$got" "hdrdiff legdiff ndldiff "
  got="$(L b)";         chk "(b) no stated expectation: registered, unregistered, prose-only, formatter-only" "$got" "bare bonly clash crej fmtcount fmtd noeol perback pinned prose refine trapper twrun unreg wrongx86 "
  got="$(L c)";         chk "(c) the x86_64 row that differs from its registration"          "$got" "wrongx86 "
  got="$(L conflict)";  chk "a registration that contradicts itself"                         "$got" "clash "
  got="$(L pin)";       chk "a backend row pinning a trap beside a four-backend value"       "$got" "pinned "
  got="$(L malformed)"; chk "a typo, no colon, a capital, a status over 255 and a second directive are malformed, never silent" "$got" "capital nocolon range twice typo "
  got="$(run_mode list:malformed "$d/rows" "$d/m" "$d/t" | awk -F'\t' '$1 == "range" { print $2 }')"
  chk "a status over 255 is refused by the range check itself, not by the shape" "$got" "line 2: a status is 0..255"
  got="$(run_mode list:twins "$d/rows" "$d/m" "$d/t" | awk -F'\t' '{print $1 ":" $2 ":" $3}' | sort | tr '\n' ' ')"
  chk "twins: loud trap, silent wrong value, build failure, accepts-invalid; the trap fixture's own trap is not a deviation" "$got" \
      "aarch64:good:trap-for-value aarch64:pinned:trap-for-value aarch64:twrun:ACCEPTS-INVALID aarch64:wrongx86:WRONG-VALUE riscv64:good:WRONG-VALUE riscv64:needles:ACCEPTS-INVALID wasm:good:build-fails-compile wasm:trapper:WRONG-VALUE "
  got="$(run_mode generate "$d/rows" "$d/m" "$d/t" | tr '\t' '|' | tr '\n' '~')"
  chk "generate: one line from a * claim, a trap, and per-backend lines with no * claim" "$got" \
      'bare|## expect: run 42~crej|## expect: reject "type mismatch"~perback|## expect(x86_64): run 136~perback|## expect(aarch64): run 41~perback|## expect(riscv64): run 41~refine|## expect: accept~refine|## expect(x86_64): run 7~trapper|## expect: trap~'
  got="$(run_mode review "$d/rows" "$d/m" "$d/t" | cut -f1 | tr '\n' ' ')"
  chk "review: every disagreement is held back — a build-only refusal, a refusal a twin runs, a file with no final newline, the unregistered, a fmt-needle collision, a comment-counting formatter row" "$got" "bonly clash fmtcount fmtd legdiff noeol pinned prose twrun unreg wrongx86 "
  got="$(run_mode review "$d/rows" "$d/m" "$d/t" | awk -F'\t' '$1 == "fmtcount" || $1 == "fmtd" { print $1 ":" substr($2, 1, 22) }' | tr '\n' '|')"
  chk "review: the formatter hold names #1178's row, and a needle collision stays its own reason" "$got" "fmtcount:a formatter row counts|fmtd:a formatter row search|"
  cp -R "$d/t" "$d/t2"
  WRITE=1 run_mode generate "$d/rows" "$d/m" "$d/t2" > /dev/null
  got="$(tail -n 3 "$d/t2/perback.al" | tr '\n' '|')"
  chk "--write appends the lines at the end, below the code"  "$got" "## expect(x86_64): run 136|## expect(aarch64): run 41|## expect(riscv64): run 41|"
  got="$(head -n 1 "$d/t2/bare.al")";  chk "--write moves no existing line"  "$got" "main := fn() -> u64 { return 42 }"
  got="$(cmp -s "$d/t/noeol.al" "$d/t2/noeol.al" && echo same)"; chk "--write leaves a file with no final newline byte-identical" "$got" "same"
  cp -R "$d/t2" "$d/t3"; WRITE=1 run_mode generate "$d/rows" "$d/m" "$d/t3" > /dev/null
  got="$(diff -r "$d/t2" "$d/t3" >/dev/null && echo same)"; chk "--write is rerunnable: a second run changes nothing" "$got" "same"
  got="$(run_mode list:a "$d/rows" "$d/m" "$d/t2" | cut -f1 | sort | tr '\n' ' ')"
  chk "after --write, every generated directive agrees with its registration" "$got" "hdrdiff legdiff ndldiff "
  got="$(tail -n 1 "$d/t2/nocolon.al")"; chk "--write never touches a file with a malformed directive" "$got" "## expect run 4"
  ## --gate: (a), malformed and every deviation problem fail; (b) and (c) do not (they are S3's verdict).
  ## `good` meets its directive on x86_64 and misses it on the three twins, so those three rows are
  ## the planted known deviations; `bare` and `wrongx86` carry no directive.
  mkdir -p "$d/g"; cp "$d/t/good.al" "$d/t/bare.al" "$d/t/wrongx86.al" "$d/g/"
  T="$(printf '\t')"
  dv() { printf '# backend\tpath\tobserved\tissue\n' > "$d/dv"; printf '%s\n' "$@" | LC_ALL=C sort | grep -v '^$' >> "$d/dv"; }
  is() { printf '# issue\trule\tdifference\trows|none\n' > "$d/is"; printf '%s\n' "$@" >> "$d/is"; }
  G() { GATE=1 run_mode report "$d/rows" "$d/m" "$d/g" "$d/dv" "$d/is" > /dev/null; echo "$?"; }
  LD() { run_mode "list:$1" "$d/rows" "$d/m" "$d/g" "$d/dv" "$d/is" | cut -f1,2 | tr '\t' ':' | sort | tr '\n' ' '; }
  R1="aarch64${T}test/good.al${T}run/133${T}#11"; R2="riscv64${T}test/good.al${T}run/41${T}#11"; R3="wasm${T}test/good.al${T}compile/1${T}#11"
  I1="11${T}Plant §1${T}a twin answers otherwise${T}rows"
  dv "$R1" "$R2" "$R3"; is "$I1"
  got="$(G)"; chk "--gate passes when every missed directive is a listed deviation, beside (b) and (c)" "$got" "0"
  dv "$R1" "$R2"; got="$(G) $(LD unlisted)"; chk "a missed directive with no row is UNLISTED and fails" "$got" "1 wasm:test/good.al "
  dv "$R1" "$R2" "wasm${T}test/good.al${T}run/134${T}#11"; got="$(G) $(LD changed)"
  chk "a row whose observation moved is CHANGED and fails" "$got" "1 wasm:test/good.al "
  dv "$R1" "$R2" "$R3" "x86_64${T}test/good.al${T}run/41${T}#11"; got="$(G) $(LD stale)"
  chk "a row for a backend that now meets its directive is STALE and fails: the fix deletes its own row" "$got" "1 x86_64:test/good.al "
  dv "$R1" "$R2" "$R3" "aarch64${T}test/bare.al${T}run/133${T}#11"; got="$(G) $(LD orphan)"
  chk "a row no directive speaks for is ORPHAN and fails" "$got" "1 aarch64:test/bare.al "
  cp "$d/t/good.al" "$d/g/fresh.al"; dv "$R1" "$R2" "$R3" "aarch64${T}test/fresh.al${T}run/133${T}#11"; got="$(G) $(LD pending)"
  chk "a directive fixture the observation does not cover is UNOBSERVED and fails (S3: the gate reads the whole walk)" "$got" "1 aarch64:test/fresh.al riscv64:test/fresh.al wasm:test/fresh.al x86_64:test/fresh.al "
  rm "$d/g/fresh.al"; got="$(G) $(LD orphan)"; chk "the same row once its fixture is gone is ORPHAN" "$got" "1 aarch64:test/fresh.al "
  ## S3: the observation and the committed scope are two inputs. The committed manifest (m2) no longer
  ## holds the directive fixture `good`; the walk (m) does, and the verdict reads the walk.
  dv "$R1" "$R2" "$R3"; grep -v 'test/good\.al' "$d/m" > "$d/m2"
  OB() { GATE=1 run_mode report "$d/rows" "$d/m2" "$d/g" "$d/dv" "$d/is" "$1" > /dev/null; echo "$?"; }
  got="$(OB "$d/m")"; chk "--gate judges a directive fixture from the observation when the committed manifest no longer holds it" "$got" "0"
  got="$(OB "$d/m2")"; chk "...and the committed scope alone, which lacks its rows, is not an observation of it (UNOBSERVED)" "$got" "1"
  cp "$d/t/bare.al" "$d/g/newbare.al"; got="$(OB "$d/m") $(run_mode list:unstated "$d/rows" "$d/m2" "$d/g" "$d/dv" "$d/is" "$d/m" | cut -f1 | tr '\n' ' ')"
  chk "a fixture with no directive and no committed manifest row is UNSTATED and fails (a new fixture states its expectation)" "$got" "1 newbare "
  rm "$d/g/newbare.al"; got="$(OB "$d/m")"; chk "a fixture with no directive that the committed manifest holds passes (the review list)" "$got" "0"
  ## The CLI's choice of observation (#1225 review): with no --observed, `--list unlisted` once read the
  ## committed scope (m2), skipped `good` as unobserved and printed nothing with exit 0.
  OF() { local o rc; o="$(observation_for "$1" "$2" "$3" "$4" "$d/m2" 2>/dev/null)"; rc=$?; echo "${o#"$d/"}:$rc"; }
  dv "$R1" "$R2"; got="$(run_mode list:unlisted "$d/rows" "$d/m2" "$d/g" "$d/dv" "$d/is" "$(observation_for list:unlisted 0 "" "$d/m" "$d/m2" 2>/dev/null)" | cut -f1,2 | tr '\t' ':')"
  chk "--list unlisted with no --observed reads the walk and lists the missed row" "$got" "wasm:test/good.al"
  got=""; for md in report list:stale list:unlisted list:changed list:unissued list:pending; do got="$got $(OF "$md" 0 "" "$d/nowalk")"; done
  chk "...and with no walk, every mode that judges deviations refuses (2), never the committed scope" "$got" " :2 :2 :2 :2 :2 :2"
  got="$(OF list:b 0 "" "$d/nowalk") $(OF list:unstated 0 "" "$d/nowalk")"
  chk "the S1 review modes with no walk keep the committed manifest" "$got" "m2:0 m2:0"
  got="$(OF report 1 "" "$d/m") $(OF report 1 "$d/m2" "$d/m") $(OF list:unlisted 0 "$d/m2" "$d/m")"
  chk "--gate never takes a leftover walk; an explicit --observed wins over the walk" "$got" ":2 m2:0 m2:0"
  ## The same through the command line, from a copy of this script whose ROOT has no walk, then one:
  ## the driver, not only the helper, must refuse (the old fallback printed nothing with exit 0).
  mkdir -p "$d/root/scripts"; cp "$ROOT/scripts/fixture_expect.sh" "$ROOT/scripts/fixture_oracle.sh" "$d/root/scripts/"
  dv "$R1" "$R2" "wasm${T}test/good.al${T}compile/1${T}#?"
  CL() { local o rc; o="$(bash "$d/root/scripts/fixture_expect.sh" --list "$1" --rows "$d/rows" --manifest "$d/m2" --test-dir "$d/g" --deviations "$d/dv" --issues "$d/is" 2>/dev/null)"; rc=$?; echo "$rc:$(printf '%s' "$o" | cut -f1,2 | tr '\t\n' ': ')"; }
  got="$(CL unissued) $(CL unlisted)"; chk "CLI: --list unissued and --list unlisted with no walk exit 2 and print nothing" "$got" "2: 2:"
  mkdir -p "$d/root/target/corpus-manifest"; cp "$d/m" "$d/root/target/corpus-manifest/observed.manifest"
  dv "$R1" "$R2" "wasm${T}test/good.al${T}compile/1${T}#?"; got="$(CL unissued)"
  chk "CLI: with the walk in place, --list unissued reads it and lists the #? row" "$got" "0:wasm:test/good.al "
  dv "$R1" "$R2" "$R3"
  dv "$R1" "$R2" "wasm${T}test/good.al${T}compile/1${T}#12"; got="$(G) $(LD unissued)"
  chk "a row naming an issue the table lacks fails" "$got" "1 wasm:test/good.al "
  dv "$R1" "$R2" "wasm${T}test/good.al${T}compile/1${T}#?"; got="$(G) $(LD unissued)"
  chk "a row still marked #? fails" "$got" "1 wasm:test/good.al "
  dv "$R1" "$R2" "$R3"; is "$I1" "13${T}Plant §2${T}never seen${T}rows"; got="$(G) $(LD issues)"
  chk "an issue marked rows that no row names fails" "$got" "1 #13:marked rows, but no deviation row names it "
  is "11${T}Plant §1${T}a twin answers otherwise${T}none"; got="$(G) $(LD unissued | wc -w | tr -d ' ')"
  chk "an issue marked none that rows name fails" "$got" "1 3"
  is "$I1" "14${T}Plant §3${T}a spelling, no value differs${T}none"; got="$(G)"
  chk "an issue marked none, with no row, is a published deviation without a fixture" "$got" "0"
  is "$I1"; printf '%s\n%s\n' "$R2" "$R1" > "$d/dv"; printf '%s\n' "$R3" >> "$d/dv"; got="$(G)"
  chk "an unsorted list fails (one sorted row per deviation keeps merge=union safe)" "$got" "1"
  cp "$d/t/nocolon.al" "$d/g/"; dv "$R1" "$R2" "$R3"; got="$(G)"; chk "--gate fails on a malformed directive" "$got" "1"
  rm "$d/g/nocolon.al"; cp "$d/t/hdrdiff.al" "$d/g/"; got="$(G)"; chk "--gate fails on (a)" "$got" "1"
  got="$(GATE=1 run_mode report "$d/rows" "$d/nomanifest" "$d/g" "$d/dv" "$d/is" > /dev/null 2>&1; echo "$?")"
  chk "--gate: unusable input is 2, never a pass" "$got" "2"
  is "$I1" "14${T}Plant §3${T}a spelling${T}none"
  ## the closed-issue check (#1279), on the same planted table (#11 rows, #14 none)
  printf '# snap\n11\n14\n99\n' > "$d/st"; issues_open "$d/is" "$d/st" > /dev/null; got="$?"
  printf '11\n99\n' > "$d/st"; issues_open "$d/is" "$d/st" > /dev/null; got="$got $?"
  printf '11\n14\nclosing 14\n' > "$d/st"; issues_open "$d/is" "$d/st" > /dev/null; got="$got $?"
  printf '# no numbers\n' > "$d/st"; issues_open "$d/is" "$d/st" > /dev/null 2>&1; got="$got $?"
  printf '11\n14\nCLOSED 3\n' > "$d/st"; issues_open "$d/is" "$d/st" > /dev/null 2>&1; got="$got $?"
  chk "issue states: open passes; closed, or closed by this landing, fails; an empty or malformed snapshot is 2" "$got" "0 1 1 2 2"
  ## and through --gate: a planted CLOSED issue (#11, named by three rows) turns the gate red
  rm -f "$d/g/hdrdiff.al"; is "$I1"; dv "$R1" "$R2" "$R3"
  GO() { GATE=1 OPEN_ISSUES="$d/st" run_mode report "$d/rows" "$d/m" "$d/g" "$d/dv" "$d/is" > "$d/go" 2>&1; echo "$?"; }
  printf '11\n' > "$d/st"; got="$(GO)"
  printf '12\n' > "$d/st"; got="$got $(GO) $(grep -c 'not open: #11' "$d/go")"
  printf '11\nclosing 11\n' > "$d/st"; got="$got $(GO)"
  printf '# none\n' > "$d/st"; got="$got $(GO)"
  chk "--gate with a snapshot: a row under a closed issue fails, an unusable snapshot is 2" "$got" "0 1 1 1 2"
  rm -rf "$d"
  [ "$rc" = 0 ] && echo "fixture expect self-test: $nchk checks, 0 failed" || echo "fixture expect self-test: FAILED"
  return "$rc"
}

OPEN_ISSUES="" MODE=report ROWS="" MANIFEST="$ROOT/scripts/corpus.manifest" OBSERVED="" TESTDIR="$ROOT/test" WRITE=0 GATE=0
DEVIATIONS="$ROOT/scripts/known-deviations.tsv" ISSUES="$ROOT/scripts/known-deviations.issues.tsv"
while [ $# -gt 0 ]; do
  case "$1" in
    --report)    MODE=report; shift ;;
    --gate)      MODE=report; GATE=1; shift ;;
    --list)      case "${2:-}" in a|b|c|conflict|pin|malformed|unmapped|twins|stale|unlisted|changed|orphan|unissued|issues|pending|unstated) MODE="list:$2" ;;
                   *) echo "fixture_expect.sh: --list needs one of a b c conflict pin malformed unmapped twins stale unlisted changed orphan unissued issues pending unstated" >&2; exit 2 ;; esac
                 shift 2 ;;
    --generate)  MODE=generate; shift ;;
    --write)     WRITE=1; shift ;;
    --review)    MODE=review; shift ;;
    --rows)      ROWS="${2:-}"; shift 2 ;;
    --manifest)  MANIFEST="${2:-}"; shift 2 ;;
    --observed)  OBSERVED="${2:-}"; shift 2 ;;
    --test-dir)  TESTDIR="${2:-}"; shift 2 ;;
    --deviations) DEVIATIONS="${2:-}"; shift 2 ;;
    --issues)    ISSUES="${2:-}"; shift 2 ;;
    --issues-open) MODE=issues-open; shift ;;
    --open-issues) OPEN_ISSUES="${2:-}"; [ -n "$OPEN_ISSUES" ] || { echo "fixture_expect.sh: --open-issues needs a snapshot file" >&2; exit 2; }; shift 2 ;;
    --snapshot-open) snapshot_open; exit $? ;;
    --self-test) self_test; exit $? ;;
    -h|--help)   sed -n '2,/^set -u/p' "$ROOT/scripts/fixture_expect.sh" | sed '$d'; exit 0 ;;
    *) echo "fixture_expect.sh: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
[ "$WRITE" = 0 ] || [ "$MODE" = generate ] || { echo "fixture_expect.sh: --write goes with --generate" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "fixture_expect.sh: no manifest at $MANIFEST" >&2; exit 2; }
OBSERVED="$(observation_for "$MODE" "$GATE" "$OBSERVED" "$ROOT/target/corpus-manifest/observed.manifest" "$MANIFEST")" || exit 2
[ -f "$OBSERVED" ] || { echo "fixture_expect.sh: no observation at $OBSERVED" >&2; exit 2; }
[ -d "$TESTDIR" ] || { echo "fixture_expect.sh: no test directory at $TESTDIR" >&2; exit 2; }
[ -f "$DEVIATIONS" ] || { echo "fixture_expect.sh: no known-deviations list at $DEVIATIONS" >&2; exit 2; }
[ -f "$ISSUES" ] || { echo "fixture_expect.sh: no issue table at $ISSUES" >&2; exit 2; }
if [ "$MODE" = issues-open ]; then
  mkdir -p "$ROOT/target" && SNAP="$(mktemp "$ROOT/target/fixture-expect-snap.XXXXXX")" || exit 2
  snapshot_open > "$SNAP" || { rm -f "$SNAP"; exit 2; }
  rc=0; issues_open "$ISSUES" "$SNAP" || rc=$?; rm -f "$SNAP"; exit "$rc"
fi
mkdir -p "$ROOT/target" && TMPROWS="$(mktemp "$ROOT/target/fixture-expect-rows.XXXXXX")" || exit 2
trap 'rm -f "$TMPROWS"' EXIT
if [ -z "$ROWS" ]; then
  e2e_rows > "$TMPROWS" || { echo "fixture_expect.sh: ALATYR_E2E_LIST_ROWS=1 scripts/e2e.sh failed" >&2; exit 2; }
  ROWS="$TMPROWS"
fi
[ -s "$ROWS" ] || { echo "fixture_expect.sh: the registration table is empty — refusing to report on nothing" >&2; exit 2; }
WRITE="$WRITE" GATE="$GATE" OPEN_ISSUES="$OPEN_ISSUES" run_mode "$MODE" "$ROWS" "$MANIFEST" "$TESTDIR" "$DEVIATIONS" "$ISSUES" "$OBSERVED"
