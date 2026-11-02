#!/usr/bin/env python3
"""Supplementary freshness harvest: community catalogues lag, so also discover
recent Grok Bot posts from the Bot Lodge daily digest and the official @bot
timeline via a public nitter mirror. Digest/mirror pages are discovery only:
every candidate is verified through the same oEmbed + syndication routes as the
catalogue harvest, and only posts whose text (or quoted text) is actually about
Grok Bot - or that come from the official @bot account - enter the archive cache.
"""
import json, math, os, re, subprocess, sys, urllib.parse, urllib.request

D = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(D, 'cache')
RX_URL = re.compile(r'https?://(?:x|twitter)\.com/[A-Za-z0-9_]+/status/[0-9]+')
RX_TOPIC = re.compile(r'grok\s?bot|grokbot|x\.ai/bot|@bot\b', re.I)
SOURCES = [
    'https://botlodge.vercel.app/today/',
    'https://nitter.jaydenha.uk/bot',
]

def get(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        return urllib.request.urlopen(req, timeout=15).read().decode('utf-8', 'replace')
    except Exception:
        return ''

def b36(n):
    chars = '0123456789abcdefghijklmnopqrstuvwxyz'; r = ''
    while n > 0: r = chars[n % 36] + r; n //= 36
    return r or '0'

def js36(x):
    ip = int(x); fp = x - ip; s = b36(ip)
    if fp > 0:
        s += '.'
        for _ in range(20):
            fp *= 36; d = int(fp); s += '0123456789abcdefghijklmnopqrstuvwxyz'[d]; fp -= d
            if fp == 0: break
    return s

def tok(tid):
    return re.sub(r'(0+|\.)', '', js36((int(tid) / 1e15) * math.pi))

def oembed(url):
    enc = urllib.parse.quote(url, safe='')
    try:
        out = get(f'https://publish.twitter.com/oembed?url={enc}&omit_script=1')
        return out if '"html"' in out else None
    except Exception:
        return None

def synd(tid):
    out = subprocess.run(['curl', '-s', '-m', '15',
        f'https://cdn.syndication.twimg.com/tweet-result?id={tid}&lang=en&token={tok(tid)}',
        '-H', 'User-Agent: Mozilla/5.0'], capture_output=True, text=True).stdout
    try:
        d = json.loads(out)
        return d if d.get('__typename') == 'Tweet' and 'text' in d and str(d.get('id_str')) == str(tid) else None
    except Exception:
        return None

def main():
    urls = set()
    for src in SOURCES:
        page = get(src)
        urls.update(RX_URL.findall(page))
        urls.update('https://x.com' + m for m in re.findall(r'/(?:[A-Za-z0-9_]+)/status/[0-9]+', page) if src.find('nitter') >= 0)
    added = 0
    for u in sorted(urls):
        tid = u.rsplit('/', 1)[-1]
        if not tid.isdigit():
            continue
        if os.path.exists(f'{CACHE}/oembed/{tid}.json'):
            continue
        d = synd(tid)
        if not d:
            continue
        sn = (d.get('user') or {}).get('screen_name', '')
        text = d.get('text', '')
        qt = (d.get('quoted_tweet') or {}).get('text', '') or ''
        if sn.lower() != 'bot' and not RX_TOPIC.search(text) and not RX_TOPIC.search(qt):
            continue
        oe = oembed(u)
        if not oe:
            continue
        json.dump(d, open(f'{CACHE}/synd/{tid}.json', 'w'))
        with open(f'{CACHE}/oembed/{tid}.json', 'w') as f:
            f.write(oe)
        added += 1
    print(f'fresh_harvest: {len(urls)} candidates, {added} new on-topic posts cached')

if __name__ == '__main__':
    main()
