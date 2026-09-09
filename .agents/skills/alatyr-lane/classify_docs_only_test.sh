#!/usr/bin/env bash
# Non-vacuous classifier tests: accepted prose and key fail-closed boundaries are exercised.
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CLASSIFIER="$ROOT/.agents/skills/alatyr-lane/classify_docs_only.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

checks=0
fail=0

init_repo() {
  local repo="$1"
  git init -q "$repo"
  git -C "$repo" config user.name "docs classifier test"
  git -C "$repo" config user.email "docs-classifier@example.invalid"
  git -C "$repo" config advice.addEmbeddedRepo false
  mkdir -p "$repo/docs" "$repo/src" "$repo/.agents" "$repo/.github" "$repo/scripts"
  printf 'readme\n' >"$repo/README.md"
  printf 'guide\n' >"$repo/docs/guide.md"
  printf 'policy\n' >"$repo/AGENTS.md"
  printf 'source\n' >"$repo/src/main.al"
  printf 'agent\n' >"$repo/.agents/rule.md"
  printf 'template\n' >"$repo/.github/template.md"
  printf 'script\n' >"$repo/scripts/test.sh"
  git -C "$repo" add .
  git -C "$repo" commit -q -m base
}

run_case() {
  local name="$1" want_rc="$2" setup="$3"
  local repo="$WORK/$name" out="$WORK/$name.out" err="$WORK/$name.err" rc=0
  init_repo "$repo"
  local base
  base="$(git -C "$repo" rev-parse HEAD)"
  if ! "$setup" "$repo"; then
    checks=$((checks + 1))
    fail=1
    echo "FAIL docs-only-classifier: $name setup failed"
    return
  fi
  if ! git -C "$repo" add -A 2>"$WORK/$name.add.err"; then
    checks=$((checks + 1))
    fail=1
    echo "FAIL docs-only-classifier: $name could not stage test case"
    return
  fi
  git -C "$repo" commit -q -m case
  local head
  head="$(git -C "$repo" rev-parse HEAD)"
  (cd "$repo" && bash "$CLASSIFIER" "$base" "$head" >"$out" 2>"$err") || rc=$?
  checks=$((checks + 1))
  if [ "$rc" -ne "$want_rc" ]; then
    fail=1
    echo "FAIL docs-only-classifier: $name returned $rc, expected $want_rc"
  elif [ "$want_rc" -eq 0 ] && ! grep -Fq "docs-only candidate" "$out"; then
    fail=1
    echo "FAIL docs-only-classifier: $name omitted candidate verdict"
  elif [ "$want_rc" -eq 1 ] && ! grep -Fq "full gate required:" "$err"; then
    fail=1
    echo "FAIL docs-only-classifier: $name omitted fail-closed verdict"
  else
    echo "ok   docs-only-classifier: $name"
  fi
}

edit_readme() { printf 'readme clarified\n' >"$1/README.md"; }
add_nested_docs() {
  mkdir -p "$1/docs/design"
  printf 'design note\n' >"$1/docs/design/note.txt"
}
mix_source() {
  printf 'readme clarified\n' >"$1/README.md"
  printf 'changed source\n' >"$1/src/main.al"
}
edit_agents() { printf 'changed policy\n' >"$1/AGENTS.md"; }
edit_dot_agents() { printf 'changed agent rule\n' >"$1/.agents/rule.md"; }
edit_dot_github() { printf 'changed template\n' >"$1/.github/template.md"; }
edit_script() { printf 'changed script\n' >"$1/scripts/test.sh"; }
edit_arbitrary_root_markdown() { printf 'design\n' >"$1/DESIGN.md"; }
make_executable() { chmod +x "$1/README.md"; }
add_symlink() { ln -s guide.md "$1/docs/link.md"; }
replace_with_symlink() {
  git -C "$1" rm -q docs/guide.md
  mkdir -p "$1/docs"
  ln -s target.md "$1/docs/guide.md"
}
add_executable_doc() {
  printf 'tool\n' >"$1/docs/tool.md"
  chmod +x "$1/docs/tool.md"
}
add_unsafe_path() { printf 'unsafe\n' >"$1/docs/"$'\033'"bad.md"; }
add_gitlink() {
  mkdir -p "$1/docs/module.md"
  git -C "$1/docs/module.md" init -q
  git -C "$1/docs/module.md" config user.name "docs classifier test"
  git -C "$1/docs/module.md" config user.email "docs-classifier@example.invalid"
  printf 'nested\n' >"$1/docs/module.md/file"
  git -C "$1/docs/module.md" add file
  git -C "$1/docs/module.md" commit -q -m nested
}
delete_doc() { git -C "$1" rm -q docs/guide.md; }
rename_doc() { git -C "$1" mv docs/guide.md docs/renamed.md; }

run_case root-readme-is-candidate 0 edit_readme
run_case nested-docs-text-is-candidate 0 add_nested_docs
run_case mixed-source-fails-closed 1 mix_source
run_case agents-policy-fails-closed 1 edit_agents
run_case dot-agents-control-fails-closed 1 edit_dot_agents
run_case github-control-fails-closed 1 edit_dot_github
run_case scripts-fail-closed 1 edit_script
run_case arbitrary-root-markdown-fails-closed 1 edit_arbitrary_root_markdown
run_case executable-mode-fails-closed 1 make_executable
run_case symlink-fails-closed 1 add_symlink
run_case existing-file-type-change-fails-closed 1 replace_with_symlink
run_case new-executable-doc-fails-closed 1 add_executable_doc
run_case unsafe-path-fails-closed 1 add_unsafe_path
run_case gitlink-fails-closed 1 add_gitlink
run_case deletion-fails-closed 1 delete_doc
run_case rename-fails-closed 1 rename_doc

repo="$WORK/special"
init_repo "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
rc=0
(cd "$repo" && bash "$CLASSIFIER" "$base" "$base" >"$WORK/empty.out" 2>"$WORK/empty.err") || rc=$?
checks=$((checks + 1))
if [ "$rc" -eq 1 ]; then
  echo "ok   docs-only-classifier: empty range fails closed"
else
  fail=1
  echo "FAIL docs-only-classifier: empty range returned $rc, expected 1"
fi

rc=0
(cd "$repo" && bash "$CLASSIFIER" missing-ref "$base" >"$WORK/ref.out" 2>"$WORK/ref.err") || rc=$?
checks=$((checks + 1))
if [ "$rc" -eq 2 ]; then
  echo "ok   docs-only-classifier: invalid range is refused"
else
  fail=1
  echo "FAIL docs-only-classifier: invalid range returned $rc, expected 2"
fi

tree="$(git -C "$repo" rev-parse "HEAD^{tree}")"
unrelated="$(git -C "$repo" commit-tree "$tree" -m unrelated)"
rc=0
(cd "$repo" && bash "$CLASSIFIER" "$base" "$unrelated" >"$WORK/ancestor.out" 2>"$WORK/ancestor.err") || rc=$?
checks=$((checks + 1))
if [ "$rc" -eq 2 ]; then
  echo "ok   docs-only-classifier: non-ancestor range is refused"
else
  fail=1
  echo "FAIL docs-only-classifier: non-ancestor range returned $rc, expected 2"
fi

if [ "$checks" -ne 19 ]; then
  echo "FAIL docs-only-classifier: expected 19 checks, reached $checks" >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "ok   docs-only-classifier: proof-of-work checks=$checks"
