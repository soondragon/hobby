from app.move_catalog import catalog, species_moves
import pytest
import httpx
from app.main import create_app


def test_pinned_complete_gen_v_catalog_and_historical_metadata():
    data=catalog()
    assert len(data['species'])==649 and len(data['moves'])==559
    assert len(data['sourceRevision'])==40 and len(data['sourceSHA256'])==10
    assert data['moves']['53']['power']==95  # Gen V, not the later nerf to 90.
    assert data['moves']['56']['power']==120
    assert data['moves']['53']['nameKo']=='화염방사'
    for species in data['species'].values():
        assert species['learnset']
        assert all(str(row['moveID']) in data['moves'] for row in species['learnset'])
    charizard=species_moves(6)
    flame=next(m for m in charizard['moves'] if m['id']==53)
    assert dict(methodID=1,level=47) in flame['learnMethods']
    assert species_moves(650) is None


@pytest.mark.asyncio
async def test_public_pokedex_is_bounded_public_metadata_only():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=create_app(object())),base_url='http://test') as client:
        result=await client.get('/api/pokedex/6/moves')
        assert result.status_code==200
        assert result.json()['nameKo']=='리자몽'
        assert all(k not in result.text for k in ['ownerID','seed','access_token','github_id'])
        assert (await client.get('/api/pokedex/650/moves')).status_code==404
