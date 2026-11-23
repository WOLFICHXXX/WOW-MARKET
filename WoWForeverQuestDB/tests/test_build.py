import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('builder',Path(__file__).resolve().parents[1]/'build_db.py')
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class QuestBuildTests(unittest.TestCase):
    def test_build_and_search(self):
        quests={
        '116':{'id':116,'name':'Dry Times','questLevel':15,'requiredLevel':12,'requiredRaces':4294967373,'areaId':44,
               'objectivesText':['Barkeep needs four drinks'],'startedBy':{'npcs':[346]},'finishedBy':{'npcs':[346]},
               'objectives':{'items':[[1262,1],[1941,1]]},
               'preQuestSingle':[54],'rewards':{'items':[{'itemId':1270,'amount':1}], 'money':{'bonus':600,'multiplier':1,'difficulty':4}}},
        '2':{'id':2,'name':"Sharptalon's Claw",'questLevel':30,'requiredLevel':20,'requiredRaces':8589934770,'startedBy':{'items':[16305]}}}
        fdb={'116':{'id':116,'name':'Dry Times','side':'a','source':'forever','zone':{'n':'Redridge Mountains','m':1433},
                    'starts':{'type':'npc','id':346,'name':'Barkeep Daniels','location':{'uiMapId':1433,'x':26.4,'y':44.7,'zone':'Redridge','source':'seen in WoW Forever'},'source':'seen in WoW Forever'},
                    'ends':{'type':'npc','id':346,'name':'Barkeep Daniels','location':{'uiMapId':1433,'x':26.4,'y':44.7,'zone':'Redridge','source':'seen in WoW Forever'},'source':'seen in WoW Forever'},
                    'chain':{'previous':[{'questId':12,'relation':'Complete first','source':'Classic data (CMaNGOS)'}]}},
             '9':{'id':9,'name':'The Killing Fields','side':'h','level':15,'zone':{'n':'Westfall','m':1436}}}
        zones=[{'areaId':44,'uiMapId':1433,'questCount':1}]
        localizations={
          'quest': {116: {'title': ('Засуха','QuestieDB Forever ruRU base'),
                          'objective': ('Соберите четыре напитка','QuestieDB Forever ruRU trace')}},
          'npc': {346: {'title': ('Кабатчик Дэниэлс','QuestieDB Forever ruRU base')}},
          'item': {1270: {'title': ('Плащ мечника','QuestieDB Forever ruRU base')}},
        }
        with tempfile.TemporaryDirectory() as td:
            stats=mod.parse(quests,zones,fdb,td,allow_tiny=True,localizations=localizations)
            self.assertEqual(stats['rows'],3)
            self.assertEqual(stats['foreverdb_only_count'],1)
            self.assertEqual(stats['actor_coordinate_rows'],2)
            self.assertEqual(stats['ru_quest_titles'],1)
            self.assertEqual(stats['ru_quest_objectives'],1)
            self.assertEqual(stats['forever_observed_coordinate_rows'],2)
            self.assertEqual(stats['ru_reward_item_rows'],1)
            with sqlite3.connect(Path(td)/'wow_forever_quests.sqlite') as db:
                self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0],'ok')
                self.assertEqual(db.execute('SELECT faction FROM quests WHERE id=116').fetchone()[0],'Альянс')
                self.assertEqual(db.execute('SELECT faction FROM quests WHERE id=2').fetchone()[0],'Орда')
                self.assertEqual(db.execute('SELECT count(*) FROM rewards WHERE quest_id=116').fetchone()[0],2)
                self.assertEqual(db.execute('SELECT count(*) FROM quest_links WHERE quest_id=116').fetchone()[0],2)
                x,y=db.execute('SELECT x,y FROM actors WHERE quest_id=116 AND x IS NOT NULL LIMIT 1').fetchone()
                self.assertEqual((x,y),(26.4,44.7))
                full_json=db.execute('SELECT questie_raw_json FROM quests WHERE id=116').fetchone()[0]
                self.assertIn('Barkeep needs',full_json)
                title,objective=db.execute('SELECT title_ru,objective_text_ru FROM quests WHERE id=116').fetchone()
                self.assertEqual(title,'Засуха')
                self.assertEqual(objective,'Соберите четыре напитка')
                self.assertEqual(db.execute("SELECT count(*) FROM actors WHERE name_ru='Кабатчик Дэниэлс'").fetchone()[0],4)
                self.assertEqual(db.execute("SELECT count(*) FROM actors WHERE coordinate_quality='forever_observed'").fetchone()[0],2)
                self.assertEqual(db.execute("SELECT item_name_ru FROM rewards WHERE item_id=1270").fetchone()[0],'Плащ мечника')
                if stats['fts_enabled']:
                    self.assertEqual(db.execute("SELECT id FROM quest_search WHERE quest_search MATCH 'Засуха'").fetchone()[0],116)
            self.assertTrue((Path(td)/'quests_browser.html').read_text('utf-8').find('The Killing Fields')>0)
            self.assertIn('Засуха',(Path(td)/'quests_browser.html').read_text('utf-8'))
            self.assertIn('id="coords"',(Path(td)/'quests_browser.html').read_text('utf-8'))
            self.assertTrue((Path(td)/'quests.csv').stat().st_size>100)

    def test_ru_lua_parsing_and_field_fallback(self):
        base='''if GetLocale() ~= "ruRU" then return end
l10n.questLookup["ruRU"] = loadstring([[return {
[116] = {"Засуха", {"Принесите бочонок \\"Мерло\\"."}},
[636] = {nil, nil},
[7] = {"Нападение на лагерь кобольдов", {"Убейте 10 кобольдов."}},
}]])'''
        trace='''l10n.questLookup["ruRU"] = loadstring([[return {
[116] = {nil, {"Вернитесь к кабатчику."}},
[7] = {"Лагерь кобольдов", nil},
}]])'''
        base_rows=mod.read_ru_lua(base,'quest')
        trace_rows=mod.read_ru_lua(trace,'quest')
        ru=mod.merge_ru_files(base_rows,trace_rows)
        self.assertEqual(ru[116]['title'][0],'Засуха')
        self.assertEqual(ru[116]['objective'][0],'Вернитесь к кабатчику.')
        self.assertEqual(ru[7]['title'][0],'Лагерь кобольдов')
        self.assertEqual(ru[7]['objective'][0],'Убейте 10 кобольдов.')
        self.assertNotIn(636,ru)
        items='''l10n.itemLookup["ruRU"] = loadstring([[return {
[1270] = "Плащ мечника",
}]])'''
        self.assertEqual(mod.read_ru_lua(items,'item')[1270]['title'],'Плащ мечника')

    def test_empty_datasets_fail(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(ValueError):mod.parse({},[],{},td)

if __name__=='__main__':unittest.main()