#!/usr/bin/env python3
"""Extract pages/groups/options of the desktop settings tabs from Tab.cpp, so the iPad shows the same layout."""
import json, re, sys
src = open(sys.argv[1], encoding='utf-8').read()
src = re.sub(r'#if 0.*?#endif', '', src, flags=re.S)
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = '\n'.join(l for l in src.split('\n') if not l.strip().startswith('//'))
def body(name):
    i = src.index(name); i = src.index('{', i); d = 0
    for j in range(i, len(src)):
        d += (src[j] == '{') - (src[j] == '}')
        if d == 0: return src[i:j]
PAGE = re.compile(r'add_options_page\((?:L|_L)\("([^"]+)"')
TOK = re.compile(r'add_options_page\((?:L|_L)\("(?P<page>[^"]+)"|new_optgroup\((?:L|_L)\("(?P<group>[^"]+)"|'
                 r'(?:append_single_option_line|create_single_option_line|get_option|append_nozzle_scaled_option\(optgroup,\s*|append_option_line\(optgroup,\s*)\(?\s*"(?P<opt>[a-z0-9_]+)"')
def parse(names, first=None):
    pages = []
    seen = set()
    if first: pages.append({'title': first, 'groups': []})
    for n in names:
        for m in TOK.finditer(body(n)):
            if m['page']: pages.append({'title': m['page'], 'groups': []})
            elif m['group'] and pages: pages[-1]['groups'].append({'title': m['group'], 'options': []})
            elif m['opt'] and pages and m['opt'] not in seen:
                if not pages[-1]['groups']: pages[-1]['groups'].append({'title': '', 'options': []})
                pages[-1]['groups'][-1]['options'].append(m['opt']); seen.add(m['opt'])
    merged = []
    for p in pages:
        p['groups'] = [g for g in p['groups'] if g['options']]
        if p['groups']: merged.append(p)
    return merged
out = {'process': parse(['void TabPrint::build()']),
       'filament': parse(['void TabFilament::build_filament_page(const PageShp& page)', 'void TabFilament::build()'], 'Filament'),
       'printer': parse(['void TabPrinter::build_fff()', 'void TabPrinter::build_unregular_pages(bool'])}
for k, v in out.items(): print(k, [(p['title'], sum(len(g['options']) for g in p['groups'])) for p in v], file=sys.stderr)
json.dump(out, open(sys.argv[2], 'w'), ensure_ascii=False, indent=0)
