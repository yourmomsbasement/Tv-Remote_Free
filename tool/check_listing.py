"""Checks store/LISTING.md fields against the stores' character limits."""
import re
import sys

text = open('store/LISTING.md', encoding='utf-8').read()
ok = True
for m in re.finditer(r'\*\*([^*]+?)\*\* \((\d+)\)\n(.*?)(?=\n\*\*|\n---|\Z)', text, re.S):
    name, limit, body = m.group(1), int(m.group(2)), m.group(3).strip()
    n = len(body)
    flag = 'OK ' if n <= limit else 'TOO LONG'
    ok &= n <= limit
    print(f'{flag} {name}: {n}/{limit}')
sys.exit(0 if ok else 1)
