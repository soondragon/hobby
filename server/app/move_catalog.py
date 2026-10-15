"""Pinned public Pokédex metadata; independent of player-owned game state."""
from functools import lru_cache
import json
from pathlib import Path


@lru_cache(maxsize=1)
def catalog():
    value = json.loads((Path(__file__).resolve().parents[1]/'data'/'move-catalog.json').read_text())
    if value['versionGroup'] != 'black-2-white-2' or len(value['species']) != 649:
        raise ValueError('Invalid move catalog')
    return value


def move_details(move_ids):
    moves = catalog()['moves']
    return [moves[str(mid)] for mid in move_ids if str(mid) in moves]


def species_moves(species_id):
    data = catalog()
    species = data['species'].get(str(species_id))
    if not species: return None
    grouped = {}
    for row in species['learnset']:
        grouped.setdefault(row['moveID'], []).append(dict(methodID=row['methodID'], level=row['level']))
    return dict(speciesID=species_id, nameKo=species['nameKo'], versionGroup=data['versionGroup'],
                source=data['source'], moves=[dict(**data['moves'][str(mid)], learnMethods=methods) for mid, methods in grouped.items()])
