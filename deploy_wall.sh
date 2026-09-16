#!/bin/bash
set -eu
TOKEN=${VERCEL_TOKEN:?VERCEL_TOKEN must be supplied in the environment}
SITE=/tmp/site/index.html
[ -f "$SITE" ]
SHA=$(sha1sum "$SITE" | cut -d' ' -f1); SIZE=$(wc -c < "$SITE")
curl -s -m 30 -X POST "https://api.vercel.com/v2/files" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/octet-stream" -H "x-vercel-digest: $SHA" --data-binary @"$SITE" > /dev/null
curl -s -m 45 -X POST "https://api.vercel.com/v13/deployments?forceNew=1" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "{\"name\":\"grokbot-wall\",\"files\":[{\"file\":\"index.html\",\"sha\":\"$SHA\",\"size\":$SIZE}],\"projectSettings\":{\"framework\":null}}" > /tmp/deploy.json
DPLID=$(jq -r '.id // empty' /tmp/deploy.json)
if [ -n "$DPLID" ]; then
  for A in grokbot-wall.vercel.app grokbot-wall-rvaraghav-5036s-projects.vercel.app; do
    curl -s -m 20 -X POST "https://api.vercel.com/v2/deployments/$DPLID/aliases" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "{\"alias\":\"$A\"}" > /dev/null
  done
fi
STATE=$(jq -r '.readyState // .error.code // "?"' /tmp/deploy.json)
sleep 5
CODE=$(curl -sL -m 20 "https://grokbot-wall.vercel.app" -o /tmp/site_check.html -w "%{http_code}")
CARDS=$(grep -c 'class="card"' /tmp/site_check.html || true)
TITLE=$(grep -o '<title>[^<]*' /tmp/site_check.html | head -1)
echo "deploy_state=$STATE verify_http=$CODE cards=$CARDS title='$TITLE'"
