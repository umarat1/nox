#!/usr/bin/env python3
"""2.3.1: build geosite-ads-other.srs = geosite category-ads-all (SagerNet/sing-geosite, from
v2fly domain-list-community) minus Google/Yandex/Mail.ru/VK/myTarget hosts, which have their own
toggles in «Блокировка рекламы». Usage: make-ads-other.py <sing-box> <category-ads-all.srs> <out.srs>"""
import json, re, subprocess, sys, tempfile, os
sb, src, out = sys.argv[1:4]
VENDOR = re.compile(r'(^|\.)(google|googleapis|gstatic|doubleclick|googlesyndication|googleadservices|googletagmanager|'
                    r'googletagservices|google-analytics|app-measurement|admob|2mdn|youtube|ytimg|googlevideo|'
                    r'yandex|ya|yastatic|yandexadexchange|yandexmetrica|yandex-metrica|adfox|'
                    r'mail|imgsmail|my|vk|vk-analytics|userapi|mycdn|ok)\.[a-z.]+$|^(ads\.yandex)$')
with tempfile.TemporaryDirectory() as d:
    j = os.path.join(d, 'a.json')
    subprocess.check_call([sb, 'rule-set', 'decompile', src, '-o', j])
    data = json.load(open(j))
    L = lambda v: [v] if isinstance(v, str) else (v or [])
    dropped = 0
    for r in data['rules']:
        for k in ('domain', 'domain_suffix'):
            if k in r:
                keep = [x for x in L(r[k]) if not VENDOR.search(x.lstrip('.'))]
                dropped += len(L(r[k])) - len(keep)
                r[k] = keep
                if not keep:
                    del r[k]
        if 'domain_regex' in r:
            keep = [x for x in L(r['domain_regex']) if not re.search(r'google|yandex|mail|vk', x)]
            dropped += len(L(r['domain_regex'])) - len(keep)
            r['domain_regex'] = keep
            if not keep:
                del r['domain_regex']
    data['rules'] = [r for r in data['rules'] if any(k in r for k in ('domain', 'domain_suffix', 'domain_regex', 'domain_keyword'))]
    json.dump(data, open(j, 'w'))
    subprocess.check_call([sb, 'rule-set', 'compile', j, '-o', out])
    print('dropped', dropped, 'vendor entries ->', out)
