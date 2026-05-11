#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <github-username-or-org>" >&2
  exit 1
fi

OWNER="$1"
IMAGE_OWNER="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/clipmate-relay.xml"

sed -i.bak \
  -e "s#ghcr.io/your-name/clipmate-relay#ghcr.io/$IMAGE_OWNER/clipmate-relay#g" \
  -e "s#ghcr.io/你的GitHub用户名/clipmate-relay#ghcr.io/$IMAGE_OWNER/clipmate-relay#g" \
  -e "s#github.com/your-name/clipmate#github.com/$OWNER/clipmate#g" \
  -e "s#github.com/你的GitHub用户名/clipmate#github.com/$OWNER/clipmate#g" \
  "$TEMPLATE"
rm -f "$TEMPLATE.bak"

echo "Updated $TEMPLATE for GitHub owner: $OWNER"
echo "Docker image owner: $IMAGE_OWNER"
