#!/bin/bash
# Daily refresh: harvest Grok Bot post URLs from community-site catalogues, verify via X oEmbed,
# enrich via syndication/fxTwitter, rebuild wall, redeploy to Vercel.
# Archive mode: caches live in $D/cache (committed to the repo), so every post ever collected
# stays on the wall permanently and the count is monotonic across sandbox rebuilds.
set -u
D=/home/sandbox/grokbot-wall
CACHE="$D/cache"
RX='https?://(x|twitter)\.com/[A-Za-z0-9_]+/status/[0-9]+'
mkdir -p "$CACHE/oembed" "$CACHE/synd" "$CACHE/fx" /tmp/site

# --- 1. harvest: static seed pages ---
{ curl -sL -m 20 "https://usegrokbot.com/en"
  curl -sL -m 20 "https://usegrokbot.com/en/use-cases"
  curl -sL -m 20 "https://usegrokbot.com/en/templates"
  curl -sL -m 20 "https://grokbot.dev/wall/"
  curl -sL -m 20 "https://grokbot.dev/integrations/x/"
  curl -sL -m 20 "https://grokbot.dev/marketplace/"
} | grep -oE "$RX" > /tmp/urls_seed.txt || true

# --- 1b. harvest: usegrokbot discover case pages (from sitemap) ---
curl -sL -m 20 "https://usegrokbot.com/sitemap.xml" | grep -oE '<loc>[^<]*' | sed 's/<loc>//' | grep '/en/discover/' > /tmp/pages_discover.txt || true
while read -r p; do curl -sL -m 15 "$p"; done < /tmp/pages_discover.txt | grep -oE "$RX" > /tmp/urls_discover.txt || true

# --- 1c. harvest: grokbot.dev use-case pages (via pagination) ---
> /tmp/gd_pages.txt
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  path="/use-cases/"; [ "$i" -gt 1 ] && path="/use-cases/$i/"
  curl -sL -m 15 "https://grokbot.dev$path" | grep -oE 'href="/use-cases/[a-z0-9-]+/"' | sed 's/href="//;s/"$//' >> /tmp/gd_pages.txt
done
sort -u /tmp/gd_pages.txt | grep -vE '^/use-cases/([0-9]+)?/$' > /tmp/gd_case_pages.txt
while read -r p; do curl -sL -m 15 "https://grokbot.dev$p"; done < /tmp/gd_case_pages.txt | grep -oE "$RX" > /tmp/urls_cases.txt || true

cat /tmp/urls_seed.txt /tmp/urls_discover.txt /tmp/urls_cases.txt 2>/dev/null | sort -u > /tmp/urls.txt
URLS=$(wc -l < /tmp/urls.txt)

# --- 2. verify via oEmbed (archive: fetch only posts not already cached; keep only successes) ---
fetch_oembed() {
  u="$1"
  id=$(echo "$u" | grep -oE '[0-9]+$')
  [ -f "$CACHE/oembed/$id.json" ] && return 0
  enc=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$u")
  out=$(curl -sL -m 15 "https://publish.twitter.com/oembed?url=$enc&omit_script=1")
  case "$out" in *'"html"'*) printf '%s' "$out" > "$CACHE/oembed/$id.json";; esac
}
export CACHE
cat /tmp/urls.txt | xargs -P 6 -I{} bash -c "$(declare -f fetch_oembed); fetch_oembed {}" 2>/dev/null || \
while read -r u; do fetch_oembed "$u"; done < /tmp/urls.txt

# --- 3. enrich via syndication (only missing) ---
cat /tmp/urls.txt | xargs -P 6 -I{} bash -c 'id=$(echo "{}" | grep -oE "[0-9]+$"); [ -f "'"$CACHE"'/synd/$id.json" ] || python3 "'"$D"'/fetch_synd.py" "$id" >/dev/null 2>&1' || true

# --- 3b. long-form (note tweet) text via fxTwitter (only missing) ---
for f in "$CACHE"/synd/*.json; do
  id=$(basename "$f" .json)
  if grep -q '"note_tweet"' "$f" && [ ! -f "$CACHE/fx/$id.json" ]; then
    python3 "$D/fetch_fx.py" "$id" >/dev/null 2>&1 || true
  fi
done

# --- 4. build ---
python3 "$D/build_wall.py"
cp /downloads/grokbot-wall.html /tmp/site/index.html

# Deployment is intentionally separate so the long harvest/build phase never holds a credential.
CARDS=$(grep -o 'class="card"' /downloads/grokbot-wall.html | wc -l)
echo "urls_harvested=$URLS build_cards=$CARDS"
