#!/usr/bin/env python3
"""Normalize public PokéAPI move metadata into the native, ID-keyed presentation registry."""
import csv
import hashlib
import io
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def main():
    catalog = json.loads((ROOT/'server/data/move-catalog.json').read_text())
    revision = catalog['sourceRevision']
    names = ['move_meta','move_meta_ailments','move_meta_stat_changes','stats']
    def fetch(name):
        url = f'https://raw.githubusercontent.com/PokeAPI/pokeapi/{revision}/data/v2/csv/{name}.csv'
        with urllib.request.urlopen(url, timeout=60) as response: data = response.read(2_000_000)
        return name, data
    with ThreadPoolExecutor(max_workers=4) as pool: sources = list(pool.map(fetch,names))
    tables = {name:list(csv.DictReader(io.StringIO(data.decode()))) for name,data in sources}
    ailments = {r['id']:r['identifier'] for r in tables['move_meta_ailments']}
    stats = {r['id']:r['identifier'] for r in tables['stats']}
    metadata = {r['move_id']:r for r in tables['move_meta']}
    overrides = {52:'projectile',53:'stream',83:'vortex',126:'burst',257:'wave',315:'burst',
                 56:'stream',55:'stream',57:'wave',58:'stream',59:'burst',85:'bolt',87:'strike',
                 240:'weather',241:'weather',258:'weather',201:'weather',334:'shield',182:'shield',
                 14:'boost',45:'pulse',105:'heal',71:'drain',72:'drain',202:'drain'}
    definitions = {}
    for key,move in catalog['moves'].items():
        row = metadata.get(key,{})
        traits = {field:(int(row[field]) if row.get(field) else None) for field in
                  ['min_hits','max_hits','min_turns','max_turns','drain','healing','crit_rate','ailment_chance','flinch_chance','stat_chance']}
        traits['ailment'] = ailments.get(row.get('meta_ailment_id'),'none')
        traits['statChanges'] = [dict(stat=stats[r['stat_id']],change=int(r['change'])) for r in tables['move_meta_stat_changes'] if r['move_id']==key]
        style = overrides.get(move['id'])
        if style is None:
            style = 'heal' if (traits['healing'] or 0)>0 else 'drain' if (traits['drain'] or 0)>0 else 'pulse' if move['damageClass']=='status' else 'contact' if move['damageClass']=='physical' else 'bolt' if move['type']=='electric' else 'projectile'
        definitions[key] = dict(move,traits=traits,presentation=dict(style=style,color=move['type']))
    result = dict(source=catalog['source'],versionGroup=catalog['versionGroup'],
                  traitScope='Pinned source metadata; not versioned Gen V rules or simulated outcomes',
                  sourceSHA256={name+'.csv':hashlib.sha256(data).hexdigest() for name,data in sources},moves=definitions)
    out = ROOT/'Sources/PokeTokenBar/Resources/MoveDefinitions.json'
    out.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
    print(f'{len(definitions)} move definitions written; metadata is informational, not battle execution')

if __name__=='__main__': main()
