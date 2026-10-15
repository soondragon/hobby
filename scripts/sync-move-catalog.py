#!/usr/bin/env python3
"""Build a reproducible Gen V catalog from pinned, public PokéAPI source CSVs."""
import argparse
import csv
import hashlib
import io
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import urllib.request

FILES = ['moves', 'pokemon_moves', 'move_names', 'move_flavor_text', 'move_changelog', 'types', 'type_names', 'pokemon_species_names', 'version_groups', 'move_targets']


def build(revision: str, destination: Path):
    if not re.fullmatch(r'[a-f0-9]{40}', revision): raise ValueError('A pinned commit SHA is required')
    cache = Path.home()/'.cache'/'trainer-catalog'/revision
    cache.mkdir(parents=True, exist_ok=True)
    hashes = {}
    def load(name):
        path = cache/(name+'.csv')
        if not path.exists():
            url = f'https://raw.githubusercontent.com/PokeAPI/pokeapi/{revision}/data/v2/csv/{name}.csv'
            with urllib.request.urlopen(url, timeout=90) as response: data = response.read(100_000_000)
            path.write_bytes(data)
        data = path.read_bytes()
        return name, data, hashlib.sha256(data).hexdigest()
    with ThreadPoolExecutor(max_workers=4) as workers:
        sources = list(workers.map(load, FILES))
    tables = {}
    for name, data, digest in sources:
        hashes[name+'.csv'] = digest
        tables[name] = list(csv.DictReader(io.StringIO(data.decode('utf-8'))))
    group = next(int(r['id']) for r in tables['version_groups'] if r['identifier']=='black-2-white-2')
    def localized(table, key, language_key='local_language_id'):
        return {int(r[key]):r['name'] for r in tables[table] if r[language_key]=='3'}
    names = localized('move_names','move_id')
    type_names = localized('type_names','type_id')
    species_names = localized('pokemon_species_names','pokemon_species_id')
    targets = {int(r['id']):r['identifier'] for r in tables['move_targets']}
    types = {int(r['id']):r['identifier'] for r in tables['types']}
    changes = sorted(tables['move_changelog'],key=lambda r:int(r['changed_in_version_group_id']))
    moves = {}
    for raw in tables['moves']:
        if int(raw['generation_id'])>5 or not raw['pp']: continue
        row = dict(raw)
        # Changelog values describe the value BEFORE that version. Restore each field independently.
        for field in ['power','pp','accuracy','type_id','priority','target_id']:
            previous = next((r[field] for r in changes if r['move_id']==row['id'] and int(r['changed_in_version_group_id'])>group and r.get(field)), None)
            if previous is not None: row[field] = previous
        mid = int(row['id'])
        prose = [r for r in tables['move_flavor_text'] if r['move_id']==row['id'] and int(r['version_group_id'])<=group and r['language_id'] in ('3','9')]
        prose.sort(key=lambda r:(r['language_id']=='3',int(r['version_group_id'])),reverse=True)
        moves[str(mid)] = dict(id=mid,name=row['identifier'],nameKo=names.get(mid,row['identifier']),
            type=types[int(row['type_id'])],typeKo=type_names.get(int(row['type_id']),''),
            damageClass={'1':'status','2':'physical','3':'special'}[row['damage_class_id']],
            power=int(row['power']) if row['power'] else None,accuracy=int(row['accuracy']) if row['accuracy'] else None,
            pp=int(row['pp']),priority=int(row['priority']),target=targets[int(row['target_id'])],
            description=' '.join(prose[0]['flavor_text'].split()) if prose else '')
    species = {str(i):dict(id=i,nameKo=species_names.get(i,str(i)),learnset=[]) for i in range(1,650)}
    seen = set()
    for row in tables['pokemon_moves']:
        pid,mid=int(row['pokemon_id']),int(row['move_id'])
        if row['version_group_id']!=str(group) or not 1<=pid<=649 or str(mid) not in moves:continue
        key=(pid,mid,int(row['pokemon_move_method_id']),int(row['level']))
        if key in seen:continue
        seen.add(key)
        species[str(pid)]['learnset'].append(dict(moveID=mid,methodID=key[2],level=key[3]))
    for pokemon in species.values(): pokemon['learnset'].sort(key=lambda r:(r['level'],r['moveID'],r['methodID']))
    assert all(p['learnset'] for p in species.values())
    result=dict(versionGroup='black-2-white-2',source=f'https://github.com/PokeAPI/pokeapi/tree/{revision}',sourceRevision=revision,sourceSHA256=hashes,moves=moves,species=species)
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
    print(json.dumps(dict(species=len(species),moves=len(moves),learnsetRows=len(seen),versionGroup=group,bytes=destination.stat().st_size)))


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--revision',required=True)
    parser.add_argument('--output',type=Path,default=Path('server/data/move-catalog.json'))
    args=parser.parse_args()
    build(args.revision,args.output)
