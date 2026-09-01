#!/usr/bin/env bash
# Select one same-account issue from GitHub JSON after validating every open PR relation.
#
# Usage:
#   bash .agents/skills/alatyr-lane/select_issue.sh REPOSITORY LOGIN PRS_JSON ISSUES_JSON
#
# The JSON files are data, not shell input. This helper intentionally fails closed: an incomplete,
# ambiguous, fork-owned, or oracle-bearing PR blocks automatic selection instead of being ignored.
set -eu

if [ "$#" -ne 4 ]; then
  echo "usage: $0 REPOSITORY LOGIN PRS_JSON ISSUES_JSON" >&2
  exit 2
fi

REPOSITORY="$1"
LOGIN="$2"
PRS_JSON="$3"
ISSUES_JSON="$4"

if [ -z "$REPOSITORY" ] || [ -z "$LOGIN" ] || [ ! -r "$PRS_JSON" ] || [ ! -r "$ISSUES_JSON" ]; then
  echo "refusing same-account lane fallback: invalid selector input" >&2
  exit 2
fi

exec jq -ner \
  --arg repository "$REPOSITORY" \
  --arg login "$LOGIN" \
  --slurpfile prs "$PRS_JSON" \
  --slurpfile issues "$ISSUES_JSON" '
  def refuse($reason):
    error("refusing same-account lane fallback: " + $reason);

  def one_array($name; $data):
    if ($data | length) != 1 or ($data[0] | type) != "array" then
      refuse($name + " must be one JSON array")
    else
      $data[0]
    end;

  def positive_integer($value; $what):
    if ($value | type) != "number" or ($value <= 0) or ($value != ($value | floor)) then
      refuse($what + " must be a positive integer")
    else
      $value
    end;

  def relation_number($raw):
    if ($raw | test("^[0-9]+[.,;:)]*$")) then
      ($raw | gsub("[.,;:)]"; "") | tonumber) as $number |
      positive_integer($number; "relation issue number")
    else
      refuse("malformed issue relation number")
    end;

  def body_relations($body):
    if ($body | type) == "null" then
      []
    elif ($body | type) != "string" then
      refuse("PR body is not a string")
    else
      # A relation marker is deliberately parsed as data. Nothing from a PR body is re-evaluated.
      [ $body |
        scan("(?i)(?:^|[^[:alnum:]_])(refs|closes|fixes|resolves)[[:space:]]+#([^[:space:]]*)") |
        {kind: (.[0] | ascii_downcase), raw: .[1]}
      ] as $markers |
      # A relation-looking line may not hide a second issue or a malformed target after a valid one.
      [ $body | split("\n")[] |
        select(test("(?i)^[[:space:]]*(?:[-*][[:space:]]*)?(refs|closes|fixes|resolves)(?:[[:space:]]|$)"))
      ] as $declarations |
      [ $declarations[] |
        if (test("(?i)^[[:space:]]*(?:[-*][[:space:]]*)?(refs|closes|fixes|resolves)[[:space:]]+#[0-9]+[[:space:]]*[.,;:)]?[[:space:]]*$")) then
          capture("(?i)^[[:space:]]*(?:[-*][[:space:]]*)?(?<kind>refs|closes|fixes|resolves)[[:space:]]+#(?<number>[0-9]+)(?<tail>.*)$") as $decl |
          if ($decl.tail | test("^[[:space:]]*[.,;:)]?[[:space:]]*$")) then
            true
          else
            refuse("multiple or malformed relations on one PR line")
          end
        else
          refuse("malformed issue relation line")
        end
      ] as $checked_declarations |
      [ $markers[] |
        {kind: .kind, number: relation_number(.raw)}
      ]
    end;

  def closing_numbers($pr):
    if (($pr.closingIssuesReferences | type) != "array") then
      refuse("PR closingIssuesReferences is missing or malformed")
    else
      [ $pr.closingIssuesReferences[] |
        if ((type == "object") and (.number | type) == "number") then
          positive_integer(.number; "closing issue number")
        else
          refuse("PR closingIssuesReferences contains malformed data")
        end
      ]
    end;

  def checked_labels($pr):
    if (($pr.labels | type) != "array") then
      refuse("PR labels are missing or malformed")
    elif any($pr.labels[]; (type != "object") or ((.name | type) != "string")) then
      refuse("PR labels contain malformed data")
    else
      $pr.labels
    end;

  def pr_relation($pr):
    if (($pr | type) != "object") then
      refuse("open PR metadata is not an object")
    elif (($pr.number | type) != "number") then
      refuse("open PR number is missing or malformed")
    elif (($pr.state | type) != "string") or ($pr.state != "OPEN") then
      refuse("PR metadata is not open")
    elif (($pr.isCrossRepository | type) != "boolean") then
      refuse("PR cross-repository state is missing or malformed")
    elif $pr.isCrossRepository then
      refuse("fork-owned PR is present")
    elif (($pr.headRepository | type) != "object") or ($pr.headRepository.nameWithOwner != $repository) then
      refuse("PR head is not in the selected repository")
    elif (($pr.files | type) != "array") then
      refuse("PR files are missing or malformed")
    elif (($pr.changedFiles | type) != "number") or
         ($pr.changedFiles != ($pr.changedFiles | floor)) or
         ($pr.changedFiles < 0) or (($pr.files | length) != $pr.changedFiles) then
      refuse("PR file metadata is incomplete")
    elif any($pr.files[]; (type != "object") or ((.path | type) != "string")) then
      refuse("PR file metadata is malformed")
    elif any($pr.files[]; .path == "scripts/corpus.manifest" or
                       .path == "scripts/idiom.baseline" or
                       .path == "scripts/needle.baseline") then
      refuse("oracle PR is present")
    elif any(checked_labels($pr)[]; .name == "oracle") then
      refuse("oracle-labelled PR is present")
    else
      (body_relations($pr.body // "")) as $body |
      (closing_numbers($pr)) as $closing |
      if ($body | length) > 1 then
        refuse("PR has multiple issue relations")
      elif ($body | length) == 1 then
        if ($body[0].kind == "refs") then
          if ($closing | length) != 0 then
            refuse("PR mixes bounded and closing relations")
          else
            $body[0].number
          end
        elif ($closing | length) == 1 and $closing[0] == $body[0].number then
          $body[0].number
        else
          refuse("PR body relation disagrees with closingIssuesReferences")
        end
      elif ($closing | length) == 1 then
        $closing[0]
      elif ($closing | length) == 0 then
        refuse("open PR has no issue relation")
      else
        refuse("PR has multiple closing issue relations")
      end
    end;

  def checked_issue($issue):
    if (($issue | type) != "object") then
      refuse("issue metadata is not an object")
    elif (($issue.number | type) != "number") then
      refuse("issue number is missing or malformed")
    elif (($issue.state | type) != "string") then
      refuse("issue state is missing or malformed")
    elif (($issue.createdAt | type) != "string") or ($issue.createdAt == "") then
      refuse("issue creation time is missing or malformed")
    elif (($issue.author | type) != "object") or (($issue.author.login | type) != "string") then
      refuse("issue author is missing or malformed")
    elif (($issue.labels | type) != "array") or
         any($issue.labels[]; (type != "object") or ((.name | type) != "string")) then
      refuse("issue labels are missing or malformed")
    else
      $issue
    end;

  (one_array("open PR metadata"; $prs)) as $open_prs |
  (one_array("issue metadata"; $issues)) as $all_issues |
  [ $open_prs[] | pr_relation(.) ] | unique as $open_pr_issues |
  [ $all_issues[] | checked_issue(.) |
    select(.state == "OPEN") |
    select(.author.login == $login) |
    ([.labels[] | .name]) as $label_names |
    select([ $label_names[] |
      select(. == "needs-triage" or . == "needs-info" or . == "in-progress")
    ] | length == 0) |
    ([ $label_names[] | select(test("^priority-[0-9]+$")) ]) as $valid_priorities |
    ([ $label_names[] | select(startswith("priority-")) |
       select(test("^priority-[0-9]+$") | not) ]) as $malformed_priorities |
    if (($valid_priorities | length) > 1 or ($malformed_priorities | length) > 0) then
      refuse("ambiguous or malformed priority label")
    else
      . + {
        priority: (if ($valid_priorities | length) == 1
                   then ($valid_priorities[0] | ltrimstr("priority-") | tonumber)
                   else 1000000
                   end),
        open_pr_relation: (if (.number as $number | any($open_pr_issues[]; . == $number)) then true else false end)
      }
    end |
    select(.open_pr_relation | not)
  ] |
  if length == 0 then
    refuse("no eligible issue authored by " + $login)
  else
    sort_by([.priority, .createdAt, .number]) | .[0].number
  end
' </dev/null
