#!/usr/bin/env bash
#
# Move a Tessera task between board states on GitHub Projects.
# Requires the GitHub CLI (gh) authenticated with the 'project' scope.
#
# Usage:
#   scripts/github_board.sh list
#   scripts/github_board.sh set <issue#> <State>
#   scripts/github_board.sh open <issue#>
#
# State: Backlog | In Progress | Ready | In Review | Done
# Project: Tessera Tasks (github.com/Spidey03/tessera/projects)
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJ="PVT_kwHOA4ieuM4BkUwL"
FIELD="PVTSSF_lAHOA4ieuM4BkUwLzhjFuhY"

OPT_ID() {
  case "$1" in
    Backlog)     echo 1c349a30 ;;
    In\ Progress) echo 0815f093 ;;
    Ready)       echo aaddf12a ;;
    In\ Review)  echo fbc82185 ;;
    Done)        echo 9c832671 ;;
    *) echo "unknown state: $1 (use Backlog | In Progress | Ready | In Review | Done)" >&2; exit 1 ;;
  esac
}

case "${1:-}" in
  list)
    gh api graphql -f query='query { node(id: "'"$PROJ"'") { ... on ProjectV2 { items(first: 60) { nodes { content { ... on Issue { number title } } fieldValueByName(name: "State") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } } } } }' \
      --jq '.data.node.items.nodes[] | select(.content.number) | "\(.fieldValueByName.name // "?")\t#\(.content.number)\t\(.content.title)"' | sort
    ;;
  set)
    [ $# -eq 3 ] || { echo "usage: $0 set <issue#> <State>"; exit 1; }
    NUM="$2"; ST="$3"; OID="$(OPT_ID "$ST")"
    IID=$(gh api graphql -f query="query { repository(owner: \"Spidey03\", name: \"tessera\") { issue(number: $NUM) { id } } }" --jq '.data.repository.issue.id')
    ITEM=$(gh api graphql -f query="mutation { addProjectV2ItemById(input: { projectId: \"$PROJ\", contentId: \"$IID\" }) { item { id } } }" --jq '.data.addProjectV2ItemById.item.id')
    gh api graphql -f query="mutation { updateProjectV2ItemFieldValue(input: { projectId: \"$PROJ\", itemId: \"$ITEM\", fieldId: \"$FIELD\", value: { singleSelectOptionId: \"$OID\" } }) { projectV2Item { id } } }" >/dev/null
    echo "#$NUM -> $ST"
    ;;
  open)
    gh issue view "$2" --repo Spidey03/tessera --web
    ;;
  *)
    echo "usage: $0 {list|set <issue#> <State>|open <issue#>}"
    ;;
esac