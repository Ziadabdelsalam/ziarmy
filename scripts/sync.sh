#!/usr/bin/env bash
# Sync ziarmy: skill masters (~/.agents/skills) -> plugin, plugin agents -> ~/.claude/agents.
# Run after editing the skills, then bump the version in .claude-plugin/*.json and push.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="${ZIARMY_SKILLS_DIR:-$HOME/.agents/skills}"

for s in dev-team deploy-team; do
  if [ ! -d "$SKILLS/$s" ]; then
    echo "master not found: $SKILLS/$s (set ZIARMY_SKILLS_DIR to override)" >&2
    exit 1
  fi
  rm -rf "$ROOT/skills/$s"
  cp -R "$SKILLS/$s" "$ROOT/skills/"
  echo "synced skill: $s"
done

mkdir -p "$HOME/.claude/agents"
cp "$ROOT"/agents/*.md "$HOME/.claude/agents/"
echo "installed agents to ~/.claude/agents: $(ls "$ROOT"/agents/*.md | xargs -n1 basename | tr '\n' ' ')"

if command -v claude >/dev/null 2>&1; then
  claude plugin validate "$ROOT"
fi

if git -C "$ROOT" diff --quiet; then
  echo "no changes."
else
  echo "changes staged for review — remember to bump the version in .claude-plugin/*.json before pushing."
fi
