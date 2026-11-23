#!/usr/bin/env python3
"""Build provenance-aware WoW Forever quest database from public source snapshots.

Sources:
  tyler3497/forever-quests data/quests.json, data/zones.json, foreverdb/data/quests.json
Questie/Trinity/Norgannon are curated, ForeverDB source is an independent enrichment.
Requires Python 3.9+ stdlib only. Requires network for first run; supports offline caches.
"""
import argparse
import csv
import datetime as dt
import html
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

BASE = "https://raw.githubusercontent.com/tyler3497/forever-quests/main/"
FILES = {"quests.json": "data/quests.json", "zones.json": "data/zones.json", "foreverdb_quests.json": "foreverdb/data/quests.json"}
VERSION = "1.0.0"
ALLIANCE_CLASSIC = sum(1 << (r-1) for r in [1, 3, 4, 7, 11, 22])
HORDE_CLASSIC = sum(1 << (r-1) for r in [2, 5, 6, 8, 9, 10])


def download(url, dest):
    headers = {"User-Agent": "WolfichForeverQuestDB/1.0 (+public-data; contact via repository)", "Accept": "application/json"}
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=75) as r:
                if r.status != 200: raise RuntimeError(f"HTTP {r.status}: {url}")
                data = r.read()
                if len(data) < 50: raise RuntimeError(f"File too small: {url}")
                json.loads(data.decode("utf-8-sig"))
                dest.parent.mkdir(parents=True, exist_ok=True)
                tmp = dest.with_suffix(".tmp")
                tmp.write_bytes(data)
                tmp.replace(dest)
                return
        except (urllib.error.URLError, TimeoutError, ValueError, RuntimeError) as exc:
            if attempt == 2: raise RuntimeError(f"Cannot download {url}: {exc}") from exc
            time.sleep(attempt + 1)


def j(v):
    return json.dumps(v, ensure_ascii=False, separators=(",", ":")) if v is not None else None


def as_id(x):
    try: return int(x)
    except (TypeError, ValueError): return None


def faction(q, f):
    side = (f or {}).get("side")
    side = str(side or "").lower()
    if side in ("a", "alliance"): return "Альянс", "ForeverDB"
    if side in ("h", "horde"): return "Орда", "ForeverDB"
    if side in ("both", "ah", "a+h", "all"): return "Обе", "ForeverDB"
    if side in ("n", "neutral"): return "Обе", "ForeverDB"
    mask = as_id((q or {}).get("requiredRaces")) or 0
    if mask == 0: return "Обе", "маска рас без ограничений"
    a, h = bool(mask & ALLIANCE_CLASSIC), bool(mask & HORDE_CLASSIC)
    if a and h: return "Обе", "эвристика маски рас (проверить новые расы)"
    if a: return "Альянс", "эвристика маски рас (проверить новые расы)"
    if h: return "Орда", "эвристика маски рас (проверить новые расы)"
    return "Неизвестно", "новые расы; не интерпретируется автоматически"


def create_tables(c):
    c.executescript("""
PRAGMA foreign_keys=ON;
CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT);
CREATE TABLE quests(
 id INTEGER PRIMARY KEY, title TEXT NOT NULL, title_ru TEXT, faction TEXT NOT NULL,
 faction_source TEXT, quest_level INTEGER, min_level INTEGER, max_level INTEGER,
 area_id INTEGER, ui_map_id INTEGER, zone_name TEXT, sort_id INTEGER,
 race_mask TEXT, class_mask TEXT, quest_flags INTEGER, special_flags INTEGER,
 source_item_id INTEGER, objective_text TEXT, source TEXT, verified_in_client INTEGER,
 source_updated TEXT, wowhead_url TEXT, foreverdb_url TEXT,
 questie_raw_json TEXT, foreverdb_raw_json TEXT
);
CREATE TABLE zones(area_id INTEGER PRIMARY KEY,ui_map_id INTEGER,quest_count INTEGER, name TEXT);
CREATE TABLE actors(
 id INTEGER PRIMARY KEY AUTOINCREMENT, quest_id INTEGER NOT NULL, role TEXT NOT NULL,
 entity_type TEXT, entity_id INTEGER, name TEXT, ui_map_id INTEGER, zone TEXT,
 x REAL, y REAL, instance TEXT, coordinate_source TEXT, players INTEGER,
 source TEXT, raw_json TEXT,
 FOREIGN KEY(quest_id) REFERENCES quests(id)
);
CREATE TABLE objectives(
 id INTEGER PRIMARY KEY AUTOINCREMENT,quest_id INTEGER NOT NULL,
 objective_type TEXT, entity_id INTEGER, required_count INTEGER,
 description TEXT, source TEXT, raw_json TEXT, FOREIGN KEY(quest_id) REFERENCES quests(id)
);
CREATE TABLE rewards(
 id INTEGER PRIMARY KEY AUTOINCREMENT,quest_id INTEGER NOT NULL,
 reward_type TEXT NOT NULL, item_id INTEGER, faction_id INTEGER, amount REAL,
 difficulty INTEGER, multiplier REAL, bonus_copper INTEGER, source TEXT, raw_json TEXT,
 FOREIGN KEY(quest_id) REFERENCES quests(id)
);
CREATE TABLE quest_links(
 id INTEGER PRIMARY KEY AUTOINCREMENT, quest_id INTEGER NOT NULL,
 other_quest_id INTEGER NOT NULL, relation TEXT NOT NULL, detail TEXT, source TEXT,
 FOREIGN KEY(quest_id) REFERENCES quests(id)
);
CREATE INDEX idx_quest_faction_level ON quests(faction,quest_level);
CREATE INDEX idx_quest_area ON quests(area_id);
CREATE INDEX idx_actor_quest_role ON actors(quest_id,role);
CREATE INDEX idx_reward_quest ON rewards(quest_id);
CREATE INDEX idx_objective_quest ON objectives(quest_id);
CREATE INDEX idx_questlinks_quest ON quest_links(quest_id);
CREATE INDEX idx_actors_location ON actors(ui_map_id,x,y);
""")
    try:
        c.execute("CREATE VIRTUAL TABLE quest_search USING fts5(id UNINDEXED,title,zone_name,objective_text,tokenize='unicode61')")
        return True
    except sqlite3.OperationalError:
        return False


def insert_actor(c, qid, role, entity_type, entity_id, name=None, location=None, instance=None, coord_source=None, players=None, source=None, raw=None):
    loc = location if isinstance(location, dict) else {}
    x,y = loc.get('x'),loc.get('y')
    if x is not None and (not isinstance(x,(int,float)) or x < 0 or x > 100): x=None
    if y is not None and (not isinstance(y,(int,float)) or y < 0 or y > 100): y=None
    c.execute("""INSERT INTO actors(quest_id,role,entity_type,entity_id,name,ui_map_id,zone,x,y,instance,coordinate_source,players,source,raw_json)
               VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (qid,role,entity_type,as_id(entity_id),name,as_id(loc.get('uiMapId')),loc.get('zone'),x,y,str(instance) if instance is not None else None,
             loc.get('source') or coord_source,as_id(players),source,j(raw)))


def insert_reward(c, qid, typ, row, src):
    if not isinstance(row,dict): return
    amount=row.get('amount')
    try: amount=float(amount) if amount is not None else None
    except (ValueError,TypeError): amount=None
    c.execute("""INSERT INTO rewards(quest_id,reward_type,item_id,faction_id,amount,difficulty,multiplier,bonus_copper,source,raw_json)
    VALUES(?,?,?,?,?,?,?,?,?,?)""",(qid,typ,as_id(row.get('itemId')),as_id(row.get('factionId')),amount,
         as_id(row.get('difficulty')),row.get('multiplier'),as_id(row.get('bonus')),src,j(row)))


def insert_link(c,qid,other,relation,detail=None,src='QuestieDB/TrinityDB'):
    other=as_id(other)
    if other and other!=qid: c.execute('INSERT INTO quest_links(quest_id,other_quest_id,relation,detail,source) VALUES (?,?,?,?,?)',(qid,other,relation,detail,src))


def parse(qdata, zdata, fdata, out, allow_tiny=False):
    if not isinstance(qdata,dict) or not isinstance(fdata,dict): raise ValueError('Quest JSON must be dictionaries')
    if len(qdata) < 4000 and not allow_tiny: raise ValueError(f'Questie source unexpectedly small: {len(qdata)}')
    if len(fdata) < 3000 and not allow_tiny: raise ValueError(f'ForeverDB source unexpectedly small: {len(fdata)}')
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    dest=out/'wow_forever_quests.sqlite'
    stage=dest.with_suffix('.sqlite.tmp')
    if stage.exists(): stage.unlink()
    conn=sqlite3.connect(stage)
    c=conn.cursor()
    fts=create_tables(c)
    zmap={}
    for row in zdata:
        if not isinstance(row,dict):continue
        area=as_id(row.get('areaId'))
        if area is None:continue
        zmap[area]=row
        c.execute('INSERT OR IGNORE INTO zones(area_id,ui_map_id,quest_count) VALUES (?,?,?)',(area,as_id(row.get('uiMapId')),as_id(row.get('questCount'))))
    zone_names={}
    combined=set(qdata)|set(fdata)
    c.execute('INSERT INTO meta(key,value) VALUES (?,?)',('source_repo','https://github.com/tyler3497/forever-quests'))
    c.execute('INSERT INTO meta(key,value) VALUES (?,?)',('built_utc',dt.datetime.now(dt.timezone.utc).isoformat()))
    c.execute('INSERT INTO meta(key,value) VALUES (?,?)',('schema_version',VERSION))
    for sid in sorted(combined,key=lambda x: int(x)):
        q=qdata.get(sid) or {}; f=fdata.get(sid) or {}
        qid=int(sid)
        area=as_id(q.get('areaId'))
        zi=(f.get('zone') or {}) if isinstance(f.get('zone'),dict) else {}
        zone=zi.get('n') or f.get('category')
        if area and zone:zone_names.setdefault(area,zone)
        faction_name,faction_src=faction(q,f)
        objectives='\n'.join(str(a) for a in (q.get('objectivesText') or []) if a)
        if not objectives:objectives='' # raw source still preserved
        src=('QuestieDB + ForeverDB' if q and f else 'QuestieDB/TrinityCore/NorgannonDB' if q else 'ForeverDB only')
        c.execute("""INSERT INTO quests(id,title,title_ru,faction,faction_source,quest_level,min_level,max_level,area_id,ui_map_id,zone_name,sort_id,race_mask,class_mask,quest_flags,special_flags,source_item_id,objective_text,source,verified_in_client,source_updated,wowhead_url,foreverdb_url,questie_raw_json,foreverdb_raw_json) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (qid,q.get('name') or f.get('name') or f'Quest {qid}',None,faction_name,faction_src,as_id(q.get('questLevel')) or as_id(f.get('level')),as_id(q.get('requiredLevel')) or as_id(f.get('requiredLevel')),as_id(q.get('requiredMaxLevel')),area,as_id((zmap.get(area) or {}).get('uiMapId')) or as_id(zi.get('m')),
             zone,as_id(q.get('sortId')),str(q.get('requiredRaces')) if q.get('requiredRaces') is not None else None,
             str(q.get('requiredClasses')) if q.get('requiredClasses') is not None else None,as_id(q.get('questFlags')),as_id(q.get('specialFlags')),
             as_id(q.get('sourceItemId')),objectives,src,0,f.get('updated'),f'https://www.wowhead.com/forever/quest={qid}',f.get('url'),j(q) if q else None,j(f) if f else None))
        if fts:c.execute('INSERT INTO quest_search(id,title,zone_name,objective_text) VALUES (?,?,?,?)',(qid,q.get('name') or f.get('name') or '',zone or '',objectives))
        # Quest starter and finisher source IDs; do not guess map coordinates here.
        for phase,kind in [('startedBy','start'),('finishedBy','end')]:
            entity=q.get(phase) or {}
            for group,etype in [('npcs','npc'),('objects','object'),('items','item')]:
                for ent in entity.get(group,[]):
                    insert_actor(c,qid,kind,etype,ent,source='QuestieDB raw ID',raw={'kind':group,'id':ent})
        for phase,role in [('starts','start'),('ends','end')]:
            actor=f.get(phase)
            if not isinstance(actor,dict):continue
            for rec in [actor]+[x for x in actor.get('others',[]) if isinstance(x,dict)]:
                insert_actor(c,qid,role,rec.get('type'),rec.get('id'),rec.get('name'),rec.get('location'),rec.get('instance'),
                    coord_source=rec.get('source'),players=rec.get('players'),source='ForeverDB (provenance per location)',raw=rec)
        # Objective rows preserved in full and individually indexed.
        obj=q.get('objectives') or {}
        for key,rows in obj.items():
            for row in rows if isinstance(rows,list) else [rows]:
                if isinstance(row,list):
                    val=as_id(row[0]) if row else None
                    cnt=as_id(row[1]) if len(row)>1 else None
                elif isinstance(row,dict): val=as_id(row.get('id') or row.get('itemId') or row.get('npcId'));cnt=as_id(row.get('count'))
                else: val=as_id(row);cnt=None
                c.execute('INSERT INTO objectives(quest_id,objective_type,entity_id,required_count,description,source,raw_json) VALUES (?,?,?,?,?,?,?)',(qid,key,val,cnt,None,'QuestieDB',j(row)))
        for i,txt in enumerate(q.get('objectivesText') or []):
            c.execute('INSERT INTO objectives(quest_id,objective_type,description,source,raw_json) VALUES (?,?,?,?,?)',(qid,'text',str(txt),'QuestieDB',j({'index':i,'text':txt})))
        trigger=q.get('triggerEnd') or {}
        for z in trigger.get('zones',[]):
            for xy in z.get('coords',[]):
                if len(xy)>=2:
                    insert_actor(c,qid,'exploration','zone',z.get('zoneId'),name=trigger.get('text'),location={'x':xy[0],'y':xy[1],'zone':str(z.get('zoneId')),'source':'QuestieDB triggerEnd'},source='QuestieDB',raw=z)
        rewards=q.get('rewards') or {}
        rsrc=q.get('rewardSources') or {}
        for typ,val in rewards.items():
            if isinstance(val,list):
                for rec in val:insert_reward(c,qid,typ,rec,rsrc.get(typ,'QuestieDB/TDB'))
            elif isinstance(val,dict):insert_reward(c,qid,typ,val,rsrc.get(typ,'QuestieDB/TDB'))
        # All different chain link types preserved without treating them as equivalents.
        for k in ['preQuestGroup','preQuestSingle','childQuests','inGroupWith','exclusiveTo','breadcrumbs','availableUntilCompleted','availableStartingWith','disabledByQuest']:
            v=q.get(k)
            for other in v if isinstance(v,list) else [v] if v else []:
                insert_link(c,qid,other,k)
        for k in ['nextQuestInChain','parentQuest','breadcrumbForQuestId']:
            if q.get(k):insert_link(c,qid,q[k],k)
        chain=f.get('chain') or {}
        for kind in ['previous','next']:
            for rec in chain.get(kind,[]):
                insert_link(c,qid,rec.get('questId'),f'foreverdb_{kind}',rec.get('relation'),rec.get('source','ForeverDB'))
    for area,zone in zone_names.items():
        c.execute('UPDATE zones SET name=? WHERE area_id=?',(zone,area))
    c.execute('INSERT INTO meta(key,value) VALUES (?,?)',('quest_count',str(len(combined))))
    c.execute('INSERT INTO meta(key,value) VALUES (?,?)',('questie_quest_count',str(len(qdata))))
    c.execute('INSERT INTO meta(key,value) VALUES (?,?)',('foreverdb_quest_count',str(len(fdata))))
    c.execute('INSERT INTO meta(key,value) VALUES (?,?)',('foreverdb_credit','Data from ForeverDB.net'))
    conn.commit()
    check=c.execute('PRAGMA integrity_check').fetchone()[0]
    assert check=='ok',check
    count=c.execute('SELECT count(*) FROM quests').fetchone()[0]
    assert count==len(combined)
    coords=c.execute('SELECT count(*) FROM actors WHERE x IS NOT NULL AND y IS NOT NULL').fetchone()[0]
    fdb_quests=c.execute('SELECT count(DISTINCT quest_id) FROM actors WHERE source LIKE "ForeverDB%"').fetchone()[0]
    stats={
      'rows':count,'questie_count':len(qdata),'foreverdb_count':len(fdata),
      'foreverdb_only_count':len(set(fdata)-set(qdata)),
      'actor_coordinate_rows':coords,
      'actor_coordinate_quest_count':c.execute('SELECT count(DISTINCT quest_id) FROM actors WHERE x IS NOT NULL and y IS NOT NULL').fetchone()[0],
      'foreverdb_actor_quest_count':fdb_quests,
      'reward_rows':c.execute('SELECT count(*) FROM rewards').fetchone()[0],
      'quest_link_rows':c.execute('SELECT count(*) FROM quest_links').fetchone()[0],
      'by_faction':dict(c.execute('SELECT faction,count(*) FROM quests GROUP BY faction').fetchall()),
      'quests_without_coords':c.execute('SELECT count(*) FROM quests WHERE id NOT IN (SELECT DISTINCT quest_id FROM actors WHERE x IS NOT NULL AND y IS NOT NULL)').fetchone()[0],
      'fts_enabled':fts,
      'built_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
      'warning':'Not verified against the live client. XP/money difficulty and multiplier do not equal final reward amount. Some coordinates derive from Classic data.'
    }
    with (out/'quests.csv').open('w',encoding='utf-8-sig',newline='') as fp:
        wr=csv.writer(fp);wr.writerow(['id','name_en','faction','min_level','quest_level','zone_name','area_id','ui_map_id','objectives_text','wowhead','foreverdb'])
        for row in c.execute('SELECT id,title,faction,min_level,quest_level,zone_name,area_id,ui_map_id,objective_text,wowhead_url,foreverdb_url FROM quests ORDER BY quest_level,id'):wr.writerow(row)
    with (out/'locations.csv').open('w',encoding='utf-8-sig',newline='') as fp:
        wr=csv.writer(fp);wr.writerow(['quest_id','role','type','entity_id','name','ui_map_id','zone','x','y','coordinate_source','source','players'])
        for row in c.execute('SELECT quest_id,role,entity_type,entity_id,name,ui_map_id,zone,x,y,coordinate_source,source,players FROM actors ORDER BY quest_id,role'):wr.writerow(row)
    with (out/'rewards.csv').open('w',encoding='utf-8-sig',newline='') as fp:
        wr=csv.writer(fp);wr.writerow(['quest_id','reward_type','item_id','faction_id','amount','difficulty','multiplier','bonus_copper','source'])
        for row in c.execute('SELECT quest_id,reward_type,item_id,faction_id,amount,difficulty,multiplier,bonus_copper,source FROM rewards ORDER BY quest_id'):wr.writerow(row)
    with (out/'chains.csv').open('w',encoding='utf-8-sig',newline='') as fp:
        wr=csv.writer(fp);wr.writerow(['quest_id','related_id','link_type','description','source'])
        for row in c.execute('SELECT quest_id,other_quest_id,relation,detail,source FROM quest_links ORDER BY quest_id'):wr.writerow(row)
    (out/'coverage.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding='utf-8')
    make_html(c,out,stats)
    conn.close();stage.replace(dest)
    return stats


def make_html(c,out,stats):
    # Self-contained browser with reward and location details, no server needed.
    actor_index={}
    for qid,role,typ,eid,name,mid,zone,x,y,source in c.execute('''SELECT quest_id,role,entity_type,entity_id,name,ui_map_id,zone,x,y,coordinate_source FROM actors WHERE source LIKE 'ForeverDB%' OR role='exploration' ORDER BY quest_id,role'''):
        if x is None or y is None: continue
        actor_index.setdefault(qid,[]).append({'role':role,'kind':typ,'id':eid,'name':name,'map':mid,'zone':zone,'x':x,'y':y,'source':source})
    rewards_index={}
    for qid,typ,item,rep,amount,diff,mul,bonus in c.execute('SELECT quest_id,reward_type,item_id,faction_id,amount,difficulty,multiplier,bonus_copper FROM rewards'):
        rewards_index.setdefault(qid,[]).append({'type':typ,'item':item,'rep':rep,'amount':amount,'difficulty':diff,'multiplier':mul,'bonus':bonus})
    chain_index={}
    for qid,other,relation in c.execute('SELECT quest_id,other_quest_id,relation FROM quest_links'):
        chain_index.setdefault(qid,[]).append({'id':other,'relation':relation})
    data=[]
    for q in c.execute('SELECT id,title,faction,quest_level,min_level,zone_name,objective_text FROM quests ORDER BY id'):
        data.append({'id':q[0],'name':q[1],'side':q[2],'level':q[3], 'min':q[4], 'zone':q[5], 'objective':q[6],
                     'coords':actor_index.get(q[0],[]), 'rewards':rewards_index.get(q[0],[]), 'links':chain_index.get(q[0],[])})
    blob=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('</','<\\/')
    page='''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>WoW Forever — База заданий</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{background:#10121c;color:#eee;font:15px system-ui,'Segoe UI',sans-serif;margin:0}.wrap{max-width:1160px;margin:auto;padding:24px 18px}.hero{background:linear-gradient(115deg,#211629,#102534);padding:30px;border:1px solid #3b3a51;border-radius:15px}h1{font-size:clamp(24px,4vw,37px);margin:2px 0;color:#e9c889}p{color:#aab4c4;line-height:1.5}.controls{display:grid;grid-template-columns:2fr 1fr 1fr;gap:12px;margin:20px 0}input,select{font:inherit;background:#222738;color:#fff;border:1px solid #4b5669;padding:12px;border-radius:9px;width:100%}.tablebox{overflow:auto;border:1px solid #394054;border-radius:12px}table{border-collapse:collapse;width:100%}th{background:#222638;color:#c9c2df;text-align:left}td,th{padding:11px;border-bottom:1px solid #33384a}tr{cursor:pointer}tbody tr:hover{background:#263047}.muted{font-size:12px;color:#92a0b8}.pill{font-size:12px;border:1px solid #5c677a;padding:3px 7px;border-radius:7px}.info{margin-top:15px;padding:17px 19px;border:1px solid #464254;border-radius:12px;background:#1c202e}a{color:#bda5ff}button{background:#354052;color:#fff;border:1px solid #59647b;border-radius:8px;padding:10px 15px;cursor:pointer}.flex{display:flex;justify-content:space-between;gap:12px;align-items:center}#detail{display:none;white-space:pre-wrap}@media(max-width:600px){.controls{grid-template-columns:1fr}.wrap{padding:14px}td,th{padding:7px}}
</style></head><body><div class="wrap"><section class="hero"><span class="muted">WOLFICH DATABASE · OFFLINE</span><h1>WoW Forever · Квесты</h1><p>QuestieDB + TrinityCore/NorgannonDB; источники не сверены с живым клиентом. Координаты, награды и цепочки в карточке задания. Имена приведены в языке источника.</p><div id="stats"></div></section><section class="controls"><input id="q" placeholder="Поиск задания, ID или зоны"><select id="side"><option value="">Все фракции</option><option>Альянс</option><option>Орда</option><option>Обе</option><option>Неизвестно</option></select><select id="level"><option value="">Все уровни</option><option value="1">1–10</option><option value="11">11–20</option><option value="21">21–30</option><option value="31">31–40</option><option value="41">41–50</option><option value="51">51–60</option><option value="61">61+</option></select></section><div class="flex"><p id="count"></p><div><button id="prev">Назад</button> <span id="page"></span> <button id="next">Далее</button></div></div><div class="tablebox"><table><thead><tr><th>ID</th><th>Задание</th><th>Уровень</th><th>Фракция</th><th>Зона</th></tr></thead><tbody id="rows"></tbody></table></div><div class="info" id="detail"></div><p class="muted">Источник квестов: <a href="https://github.com/tyler3497/forever-quests">forever-quests</a>. Координаты: Data from <a href="https://foreverdb.net">ForeverDB.net</a>. Выгрузка не гарантирует наличие всех заданий в текущем клиенте.</p></div><script>const DATA=''' + blob + ''';
let page=0,filtered=[];const $=id=>document.getElementById(id);const safe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function refresh(){let s=$('q').value.trim().toLowerCase(),side=$('side').value,lvl=$('level').value;filtered=DATA.filter(x=> (!s||[x.id,x.name,x.zone,x.objective].some(v=>String(v??'').toLowerCase().includes(s)))&&(!side||x.side===side)&&(!lvl||(Number(x.level||0)>=Number(lvl)&&Number(x.level||0)<(Number(lvl)===61?999:Number(lvl)+10))));page=0;render()}
function render(){let total=Math.max(1,Math.ceil(filtered.length/100));page=Math.max(0,Math.min(total-1,page));$('rows').innerHTML=filtered.slice(page*100,page*100+100).map(x=>`<tr data-id="${x.id}"><td>${x.id}</td><td>${safe(x.name)}</td><td>${x.level||'—'}</td><td><span class="pill">${safe(x.side)}</span></td><td>${safe(x.zone)}</td></tr>`).join('');$('count').textContent=`Найдено: ${filtered.length}`;$('page').textContent=`${page+1} / ${total}`;}
$('rows').onclick=e=>{let t=e.target.closest('tr');if(!t)return;let x=DATA.find(v=>v.id===Number(t.dataset.id));$('detail').style.display='block';
let points=x.coords?.length?x.coords.map(a=>`<li>${safe(a.role==='start'?'Выдача':a.role==='end'?'Сдача':'Цель')}: ${safe(a.name||a.kind||'NPC')} (${safe(a.zone||'карта '+a.map)}) <b>${a.x} / ${a.y}</b> <span class="muted">${safe(a.source||'источник неизвестен')}</span></li>`).join(''):'<li>Координат нет в этих источниках</li>';
let rewards=x.rewards?.length?x.rewards.map(r=>`<li>${safe(r.type)}: ${r.item?'предмет #'+r.item+' × '+(r.amount||1):r.rep?'репутация #'+r.rep+' +'+r.amount:r.bonus!=null?'бонус '+r.bonus+' медных; коэффициент '+(r.difficulty??'?')+'×'+(r.multiplier??'?'):'коэффициент '+(r.difficulty??'?')+'×'+(r.multiplier??'?')}</li>`).join(''):'<li>Не указаны</li>';
let chain=x.links?.length?x.links.slice(0,24).map(r=>`<li>${safe(r.relation)}: #${r.id}</li>`).join(''):'<li>Не указаны</li>';
$('detail').innerHTML=`<h3>${safe(x.name)} · #${x.id}</h3><p>${safe(x.objective||'Описание цели отсутствует в источнике')}</p><p><b>Уровень:</b> ${x.level||'—'} · <b>Доступен с:</b> ${x.min||'не указано'} · <b>Зона:</b> ${safe(x.zone)} · <b>Фракция:</b> ${safe(x.side)}</p><h4>Координаты</h4><ul>${points}</ul><h4>Награды</h4><ul>${rewards}</ul><h4>Цепочка и условия</h4><ul>${chain}</ul><a href="https://www.wowhead.com/forever/quest=${x.id}" target="_blank" rel="noopener">Открыть на Wowhead</a>`;$('detail').scrollIntoView({behavior:'smooth',block:'nearest'});};
$('q').oninput=refresh;$('side').onchange=refresh;$('level').onchange=refresh;$('prev').onclick=()=>{page--;render()};$('next').onclick=()=>{page++;render()};$('stats').textContent=`${DATA.length.toLocaleString('ru-RU')} записей · Альянс, Орда и общие`;refresh();</script></body></html>'''
    (out/'quests_browser.html').write_text(page,encoding='utf-8')


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',default='dist',help='Output directory')
    ap.add_argument('--cache',default='.source-cache',help='Raw source snapshot directory')
    ap.add_argument('--offline',action='store_true',help='Read cached sources without network')
    ap.add_argument('--allow-tiny',action='store_true',help='FOR FIXTURE TEST ONLY')
    args=ap.parse_args()
    cache=Path(args.cache)
    for local,remote in FILES.items():
        p=cache/local
        if args.offline:
            if not p.is_file(): ap.error(f'Missing cached source {p}')
        else:
            print('Downloading',remote,flush=True)
            download(BASE+remote,p)
    q=json.loads((cache/'quests.json').read_text('utf-8-sig'))
    z=json.loads((cache/'zones.json').read_text('utf-8-sig'))
    f=json.loads((cache/'foreverdb_quests.json').read_text('utf-8-sig'))
    info=parse(q,z,f,args.out,allow_tiny=args.allow_tiny)
    dest=Path(args.out)
    bundle=dest/'WoWForeverQuestDB_full.zip'
    targets=['wow_forever_quests.sqlite','quests_browser.html','quests.csv','locations.csv','rewards.csv','chains.csv','coverage.json']
    with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name in targets:z.write(dest/name,arcname=name)
        readme=Path(__file__).with_name('README_RU.md')
        if readme.exists():z.write(readme,arcname='README_RU.md')
    with zipfile.ZipFile(bundle) as z:
        if z.testzip() is not None:raise RuntimeError('ZIP integrity failed')
        if any(x not in z.namelist() for x in targets):raise RuntimeError('ZIP files missing')
    print(f'ZIP ready: {bundle} ({bundle.stat().st_size} bytes)',flush=True)
    print(json.dumps(info,ensure_ascii=False,indent=2),flush=True)

if __name__=='__main__':main()