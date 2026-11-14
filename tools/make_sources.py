# Компактные данные «где взять рецепт» для аддона из tools/sources/wow_forever_professions.json
# (данные Wowhead WoW Forever + Seemeta, собраны 14.11.2026).
# python3 tools/make_sources.py  ->  addon/WolfichMarket/RecipeSources.lua
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, 'sources', 'wow_forever_professions.json'), encoding='utf-8'))
OUT = os.path.join(HERE, '..', 'addon', 'WolfichMarket', 'RecipeSources.lua')

def s(v):
    return '"' + str(v).replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'
def num(v):
    if v is None: return 'nil'
    if isinstance(v, float) and v.is_integer(): v = int(v)
    return str(v)

TYPES = {'trainer': 'T', 'vendor': 'V', 'drop': 'D', 'quest': 'Q', 'auto': 'A', 'pickpocket': 'P', 'fishing': 'F', 'crafted': 'C', 'recipe_item': 'I'}
REP = {'Friendly': 1, 'Honored': 2, 'Revered': 3, 'Exalted': 4}
npcs, zones, quests, items, factions = set(), set(), set(), set(), []

def fac(name):
    if name not in factions: factions.append(name)
    return factions.index(name) + 1

def sd_list(lst):
    out = []
    for x in lst or []:
        t = x.get('type')
        if t == 'npc': npcs.add(x['id']); out.append('{"n",%d,%s}' % (x['id'], num(x.get('zone'))))
        elif t == 'quest': quests.add(x['id']); out.append('{"q",%d}' % x['id'])
        elif t == 'object': out.append('{"o",%s,%s}' % (s(x.get('name_ru') or x.get('name_en') or ''), num(x.get('zone'))))
        elif x.get('zone'): zones.add(x['zone']); out.append('{"z",%d}' % x['zone'])
        if x.get('zone'): zones.add(x['zone'])
    return '{' + ','.join(out) + '}' if out else None

def recipe_item(ri):
    it = ri['item']; items.add(it['id'])
    f = ['id=%d' % it['id']]
    if it.get('requiredSkill'): f.append('sk=%d' % it['requiredSkill'])
    if ri.get('vendors'):
        v = []
        for x in ri['vendors']:
            npcs.add(x['npc']); v.append('{%d,%s,%s}' % (x['npc'], num(x.get('costCopper')), num(x.get('stock', -1))))
        f.append('v={' + ','.join(v) + '}')
    if ri.get('drops'):
        dr = []
        for x in ri['drops'][:5]:
            npcs.add(x['npc']); dr.append('{%d,%s}' % (x['npc'], num(x.get('chancePct'))))
        f.append('d={' + ','.join(dr) + '}')
        if ri.get('dropSourcesTotal'): f.append('dn=%d' % ri['dropSourcesTotal'])
    if ri.get('worldDrop'): f.append('wd=true')
    if ri.get('quests'):
        for q in ri['quests']: quests.add(q)
        f.append('q={' + ','.join(str(q) for q in ri['quests']) + '}')
    if ri.get('containedInObject'):
        o = []
        for x in ri['containedInObject'][:4]:
            zs = [z for z in (x.get('zones') or []) if z]
            for z in zs: zones.add(z)
            o.append('{%s,%s}' % (s(x.get('name_ru') or x.get('name_en') or ''), num(zs[0] if zs else None)))
        f.append('o={' + ','.join(o) + '}')
    if ri.get('pickPocketedFrom'):
        pp = []
        for x in ri['pickPocketedFrom'][:4]:
            npcs.add(x['id']); pp.append(str(x['id']))
        f.append('pp={' + ','.join(pp) + '}')
    if ri.get('fishedIn'):
        zs = []
        for x in ri['fishedIn'][:4]:
            for z in (x.get('zones') or [])[:1]:
                if z: zones.add(z); zs.append(str(z))
        if zs: f.append('fz={' + ','.join(zs) + '}')
    sd = sd_list(ri.get('sourceDetails'))
    if sd: f.append('sd=' + sd)
    return '{' + ','.join(f) + '}'

lines = []
names = []
for slug, p in D['professions'].items():
    for r in p['recipes']:
        l = r['learn']
        f = []
        ts = ''.join(TYPES.get(t, '') for t in l.get('types', []))
        if ts: f.append('t="%s"' % ts)
        req = (r.get('skill') or {}).get('required')
        if req: f.append('s=%d' % req)
        if l.get('trainerCostCopper'): f.append('c=%d' % l['trainerCostCopper'])
        sm = l.get('seemeta') or {}
        if sm.get('autoLearned'): f.append('a=true')
        rep = sm.get('reputation')
        if rep and rep.get('faction'): f.append('rep={%d,%d}' % (REP.get(rep.get('standing'), 1), fac(rep['faction'])))
        if sm.get('recipeItemSkill'): f.append('rs=%d' % sm['recipeItemSkill'])
        if l.get('probablyUnavailable'): f.append('na=true')
        sd = sd_list(l.get('sourceDetails'))
        if sd: f.append('sd=' + sd)
        ris = [recipe_item(ri) for ri in (l.get('recipeItems') or [])]
        if ris: f.append('i={' + ','.join(ris) + '}')
        lines.append('[%d]={%s}' % (r['spellId'], ','.join(f)))
        if r.get('name_ru'): names.append('[%s]=%d' % (s(r['name_ru']), r['spellId']))
        if r.get('name_en'): names.append('[%s]=%d' % (s(r['name_en']), r['spellId']))

for x in D['npcs'].values():
    for z in x.get('zones') or []: zones.add(z)

def chunks(arr, n=1500):
    for i in range(0, len(arr), n): yield arr[i:i + n]

out = ['-- Сгенерировано tools/make_sources.py из данных Wowhead WoW Forever + Seemeta (14.11.2026). Не править вручную.',
       '-- Где взять рецепты: продавцы, добыча, задания, тренер, репутация.',
       'local _, ns = ...', 'local S = { r = {}, names = {}, npc = {}, zone = {}, quest = {}, item = {} }', 'ns.RS = S']
TBL = 'S.r'
for ch in chunks(lines):
    out.append(';(function() local t = S.r')
    out += ['t' + x for x in ch]
    out.append('end)()')
for ch in chunks(names, 3000):
    out.append(';(function() local t = S.names')
    out += ['t' + x for x in ch]
    out.append('end)()')
# NPC: {ru, en, первая зона, все зоны, реакция альянс, орда, уровень}
nl = []
for k in sorted(npcs):
    x = D['npcs'].get(str(k))
    if not x: continue
    zs = [z for z in (x.get('zones') or []) if z]
    rc = x.get('react') or {}
    nl.append('[%d]={%s,%s,{%s},%s,%s,%s}' % (k, s(x.get('ru') or x.get('en') or ''), s(x.get('en') or ''), ','.join(str(z) for z in zs[:4]),
                                              num(rc.get('alliance')), num(rc.get('horde')), s(x.get('level') or '')))
for ch in chunks(nl):
    out.append(';(function() local t = S.npc')
    out += ['t' + x for x in ch]
    out.append('end)()')
zl = ['[%s]={%s,%s}' % (k, s(v.get('ru') or v.get('en')), s(v.get('en') or '')) for k, v in D['zones'].items()]
out.append(';(function() local t = S.zone'); out += ['t' + x for x in zl]; out.append('end)()')
ql = []
for k in sorted(quests):
    x = D['quests'].get(str(k))
    if x: ql.append('[%d]={%s,%s,%s}' % (k, s(x.get('ru') or x.get('en')), num(x.get('level')), s(x.get('en') or '')))
out.append(';(function() local t = S.quest'); out += ['t' + x for x in ql]; out.append('end)()')
il = []
allitems = {}
for p in D['professions'].values():
    for r in p['recipes']:
        for ri in r['learn'].get('recipeItems') or []:
            it = ri['item']; allitems[it['id']] = it.get('name_ru') or it.get('name_en')
for k in sorted(items):
    if allitems.get(k): il.append('[%d]=%s' % (k, s(allitems[k])))
for ch in chunks(il):
    out.append(';(function() local t = S.item'); out += ['t' + x for x in ch]; out.append('end)()')
out.append('S.factions = {' + ','.join(s(f) for f in factions) + '}')
open(OUT, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('ok', len(lines), 'recipes', len(nl), 'npc', len(ql), 'quests', os.path.getsize(OUT) // 1024, 'KB')
