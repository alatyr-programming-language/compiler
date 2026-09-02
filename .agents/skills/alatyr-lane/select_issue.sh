#!/usr/bin/env bash
# Select one same-account issue from GitHub JSON after reading every open PR's issue relation.
#
# Usage:
#   bash .agents/skills/alatyr-lane/select_issue.sh REPOSITORY LOGIN PRS_JSON ISSUES_JSON
#
# The JSON files are data, not shell input. Exit status is the answer, not the printed text:
#
#   0  one issue number on stdout; every diagnostic note is on stderr
#   3  the queue is empty: the inputs were trustworthy and no issue is eligible
#   2  refusal: the selector's own input is unreliable, and the message names the PR or issue
#
# Contributor-controlled content never stops the run. A PR whose relation is missing, multiple,
# mixed, malformed, or disagreeing is reported by number and excludes only the issues it legibly
# names, so one careless PR body anywhere in the repository cannot disable the fallback for every
# issue. Metadata integrity — a requested field that is absent or of the wrong JSON type — is a
# refusal instead, because that means the query, not a contributor, has to be fixed.
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

SELECTOR_JQ='
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

  # Every message names its subject. An entry too malformed to carry a number is named by position.
  def pr_label($index; $pr):
    if (($pr | type) == "object") and (($pr.number | type) == "number") then
      "PR #" + ($pr.number | tostring)
    else
      "open PR entry " + ($index | tostring)
    end;

  def issue_label($index; $issue):
    if (($issue | type) == "object") and (($issue.number | type) == "number") then
      "issue #" + ($issue.number | tostring)
    else
      "issue entry " + ($index | tostring)
    end;

  def numbers_phrase($numbers):
    if ($numbers | length) == 0 then
      "no issue"
    else
      "issue " + ([$numbers[] | "#" + tostring] | join(", "))
    end;

  # A relation number is data: it is parsed, range-checked, and never re-evaluated.
  def relation_number($raw):
    if ($raw | test("^[0-9]+[.,;:)]*$")) then
      (($raw | gsub("[.,;:)]"; "")) | tonumber) as $number |
      (if ($number > 0) and ($number == ($number | floor)) then $number else null end)
    else
      null
    end;

  # Returns {numbers, kinds, defect}. A defect is a description of contributor-written text; it
  # never quotes that text, so an untrusted body cannot inject escapes into an operator terminal.
  def body_relations($who; $body):
    if ($body | type) == "null" then
      {numbers: [], kinds: [], defect: null}
    elif ($body | type) != "string" then
      refuse($who + " body is not a string")
    else
      [ $body |
        scan("(?i)(?:^|[^[:alnum:]_])(refs|closes|fixes|resolves)[[:space:]]+#([^[:space:]]*)") |
        {kind: (.[0] | ascii_downcase), raw: .[1], number: relation_number(.[1])}
      ] as $markers |
      # A relation-looking line may not hide a second issue or a malformed target after a valid one.
      # Every issue such a line mentions is kept as an exclusion, so flagging it never loses one.
      [ $body | split("\n") | to_entries[] |
        select(.value | test("(?i)^[[:space:]]*(?:[-*][[:space:]]*)?(refs|closes|fixes|resolves)(?:[[:space:]]|$)")) |
        select((.value | test("(?i)^[[:space:]]*(?:[-*][[:space:]]*)?(refs|closes|fixes|resolves)[[:space:]]+#[0-9]+[[:space:]]*[.,;:)]?[[:space:]]*$")) | not) |
        {line: (.key + 1), numbers: [ .value | scan("#([0-9]+)") | .[0] | tonumber | select(. > 0) ]}
      ] as $bad_lines |
      [ $markers[] | select(.number != null) | .number ] as $good |
      {
        numbers: (($good + [ $bad_lines[].numbers[] ]) | unique),
        kinds: [ $markers[] | select(.number != null) | .kind ],
        defect: (
          if ($bad_lines | length) > 0 then
            "malformed issue relation on body line " + ($bad_lines[0].line | tostring)
          elif any($markers[]; .number == null) then
            "malformed issue relation number"
          elif ($markers | length) > 1 then
            "multiple issue relations (" + numbers_phrase($good) + ")"
          else
            null
          end
        )
      }
    end;

  def closing_numbers($who; $pr):
    if (($pr.closingIssuesReferences | type) != "array") then
      refuse($who + " closingIssuesReferences is missing or malformed")
    else
      [ $pr.closingIssuesReferences[] |
        if ((type == "object") and ((.number | type) == "number")) then
          positive_integer(.number; $who + " closing issue number")
        else
          refuse($who + " closingIssuesReferences contains malformed data")
        end
      ] | unique
    end;

  def checked_labels($who; $pr):
    if (($pr.labels | type) != "array") then
      refuse($who + " labels are missing or malformed")
    elif any($pr.labels[]; (type != "object") or ((.name | type) != "string")) then
      refuse($who + " labels contain malformed data")
    else
      [ $pr.labels[] | .name ]
    end;

  # Returns {veto: [issue numbers this PR removes from candidacy], notes: [operator diagnostics]}.
  def pr_result($index; $pr):
    pr_label($index; $pr) as $who |
    if ($pr | type) != "object" then
      refuse($who + " metadata is not an object")
    elif (($pr.number | type) != "number") then
      refuse($who + " has a missing or malformed number")
    else
      positive_integer($pr.number; $who + " number") as $ignored |
      if (($pr.state | type) != "string") then
        refuse($who + " state is missing or malformed")
      elif ($pr.state != "OPEN") then
        refuse($who + " metadata is not open")
      elif (($pr.isCrossRepository | type) != "boolean") then
        refuse($who + " cross-repository state is missing or malformed")
      elif (($pr.headRepository | type) != "object") or (($pr.headRepository.nameWithOwner | type) != "string") then
        refuse($who + " head repository metadata is missing or malformed")
      elif (($pr.files | type) != "array") then
        refuse($who + " files are missing or malformed")
      elif (($pr.changedFiles | type) != "number") or
           ($pr.changedFiles != ($pr.changedFiles | floor)) or ($pr.changedFiles < 0) then
        refuse($who + " changedFiles is missing or malformed")
      elif (($pr.files | length) != $pr.changedFiles) then
        refuse($who + " file metadata is incomplete: " + ($pr.files | length | tostring) +
               " of " + ($pr.changedFiles | tostring) + " paths returned")
      elif any($pr.files[]; (type != "object") or ((.path | type) != "string")) then
        refuse($who + " file metadata is malformed")
      else
        checked_labels($who; $pr) as $label_names |
        body_relations($who; $pr.body) as $body |
        closing_numbers($who; $pr) as $closing |
        (
          if ($body.defect != null) then
            {veto: (($body.numbers + $closing) | unique), defect: $body.defect}
          elif ($body.numbers | length) == 1 then
            ($body.numbers[0]) as $declared |
            if ($body.kinds[0] == "refs") then
              if ($closing | length) != 0 then
                {veto: (([$declared] + $closing) | unique),
                 defect: "bounded relation to issue #" + ($declared | tostring) +
                         " mixed with a closing reference to " + numbers_phrase($closing)}
              else
                {veto: [$declared], defect: null}
              end
            elif ($closing == [$declared]) then
              {veto: [$declared], defect: null}
            else
              {veto: (([$declared] + $closing) | unique),
               defect: "body relation to issue #" + ($declared | tostring) +
                       " disagrees with closingIssuesReferences (" + numbers_phrase($closing) + ")"}
            end
          elif ($closing | length) == 1 then
            {veto: $closing, defect: null}
          elif ($closing | length) == 0 then
            {veto: [], defect: "no issue relation"}
          else
            {veto: $closing, defect: "multiple closing issue relations (" + numbers_phrase($closing) + ")"}
          end
        ) as $relation |
        (any($label_names[]; . == "hold")) as $held |
        {
          veto: (if $held then [] else $relation.veto end),
          notes: (
            (if $relation.defect != null then
               [ $who + " is not a conforming relation source: " + $relation.defect +
                 "; it excludes " + numbers_phrase($relation.veto) + " and ranking continues" ]
             else [] end) +
            (if $held then
               [ $who + " carries hold: excluded from the fallback, so it no longer excludes " +
                 numbers_phrase($relation.veto) ]
             else [] end) +
            (if ($pr.isCrossRepository) or ($pr.headRepository.nameWithOwner != $repository) then
               [ $who + " head is outside " + $repository + "; its relation is read as data only" ]
             else [] end) +
            (if any($pr.files[]; .path == "scripts/corpus.manifest" or
                                 .path == "scripts/idiom.baseline" or
                                 .path == "scripts/needle.baseline") or
                any($label_names[]; . == "oracle") then
               [ $who + " touches an oracle; the separate open-oracle-PR check in §1 still applies" ]
             else [] end)
          )
        }
      end
    end;

  def checked_issue($index; $issue):
    issue_label($index; $issue) as $who |
    if (($issue | type) != "object") then
      refuse($who + " metadata is not an object")
    elif (($issue.number | type) != "number") then
      refuse($who + " number is missing or malformed")
    elif (($issue.state | type) != "string") then
      refuse($who + " state is missing or malformed")
    elif (($issue.createdAt | type) != "string") or ($issue.createdAt == "") then
      refuse($who + " creation time is missing or malformed")
    elif (($issue.author | type) != "object") or (($issue.author.login | type) != "string") then
      refuse($who + " author is missing or malformed")
    elif (($issue.labels | type) != "array") or
         any($issue.labels[]; (type != "object") or ((.name | type) != "string")) then
      refuse($who + " labels are missing or malformed")
    else
      $issue + {selector_label: $who}
    end;

  (one_array("open PR metadata"; $prs)) as $open_prs |
  (one_array("issue metadata"; $issues)) as $all_issues |
  [ $open_prs | to_entries[] | pr_result(.key; .value) ] as $pr_results |
  ([ $pr_results[] | .veto[] ] | unique) as $vetoed |
  ([ $pr_results[] | .notes[] ]) as $notes |
  [ $all_issues | to_entries[] | checked_issue(.key; .value) |
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
      refuse(.selector_label + " carries ambiguous or malformed priority labels")
    else
      . + {
        priority: (if ($valid_priorities | length) == 1
                   then ($valid_priorities[0] | ltrimstr("priority-") | tonumber)
                   else 1000000
                   end)
      }
    end |
    select(.number as $number | any($vetoed[]; . == $number) | not)
  ] as $candidates |
  {
    notes: $notes,
    status: (if ($candidates | length) == 0 then "empty" else "selected" end),
    issue: (if ($candidates | length) == 0 then null
            else ($candidates | sort_by([.priority, .createdAt, .number]) | .[0].number)
            end)
  }
'

SELECTOR_ERR="$(mktemp)"
trap 'rm -f "$SELECTOR_ERR"' EXIT

if ! RESULT="$(
  jq -ner \
    --arg repository "$REPOSITORY" \
    --arg login "$LOGIN" \
    --slurpfile prs "$PRS_JSON" \
    --slurpfile issues "$ISSUES_JSON" \
    "$SELECTOR_JQ" </dev/null 2>"$SELECTOR_ERR"
)"; then
  sed -e 's/^jq: error[^:]*: //' "$SELECTOR_ERR" >&2
  exit 2
fi

printf '%s\n' "$RESULT" | jq -r '.notes[]?' >&2

case "$(printf '%s\n' "$RESULT" | jq -r '.status')" in
  selected)
    printf '%s\n' "$RESULT" | jq -er '.issue' || {
      echo "refusing same-account lane fallback: selector produced no issue number" >&2
      exit 2
    }
    ;;
  empty)
    echo "no eligible issue authored by $LOGIN" >&2
    exit 3
    ;;
  *)
    echo "refusing same-account lane fallback: selector produced an unknown status" >&2
    exit 2
    ;;
esac
