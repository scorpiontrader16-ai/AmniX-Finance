import sys, json, re

data = sys.stdin.read().strip()
for doc in re.split(r'\n(?=\{)', data):
    try:
        o = json.loads(doc)
        if o.get('kind') != 'Application':
            continue
        n = o.get('metadata', {}).get('name', '?')
        p = o.get('spec', {}).get('source', {}).get('path', '')
        if p and p not in ('', 'null'):
            print(n + '|' + p)
    except:
        pass
