from typing import Annotated, Literal
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field, StrictBool, field_validator, model_validator

Counter = Annotated[int, Field(strict=True, ge=0, le=9_000_000_000_000_000)]
Species = Annotated[int, Field(strict=True, ge=1, le=649)]
Identifier = Annotated[str, Field(min_length=1, max_length=128, pattern=r"^[A-Za-z0-9_-]+$")]
Rarity = Literal["common", "uncommon", "rare", "legendary"]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class IndividualValues(StrictModel):
    hp: Annotated[int, Field(ge=0, le=31)]
    attack: Annotated[int, Field(ge=0, le=31)]
    defense: Annotated[int, Field(ge=0, le=31)]
    specialAttack: Annotated[int, Field(ge=0, le=31)]
    specialDefense: Annotated[int, Field(ge=0, le=31)]
    speed: Annotated[int, Field(ge=0, le=31)]


class KnownMove(StrictModel):
    name: Annotated[str, Field(min_length=1, max_length=100, pattern=r"^[a-z0-9-]+$")]
    learnedAtLevel: Annotated[int, Field(ge=0, le=100)]


class IndividualProfile(StrictModel):
    instanceID: Identifier
    seed: Annotated[int, Field(ge=0, le=18_446_744_073_709_551_615)]
    gender: Literal["male", "female", "genderless"] | None = None
    ivs: IndividualValues
    abilitySlot: Annotated[int, Field(ge=1, le=3)] | None = None
    abilityName: Annotated[str, Field(max_length=100, pattern=r"^[a-z0-9-]+$")] | None = None
    abilityIsHidden: StrictBool
    level: Annotated[int, Field(ge=1, le=100)]
    growthTokens: Counter
    moves: Annotated[list[KnownMove], Field(max_length=100)]


class ActivePokemon(StrictModel):
    baseID: Species
    pathIDs: Annotated[list[Species], Field(min_length=1, max_length=10)]
    plannedPathIDs: Annotated[list[Species], Field(min_length=1, max_length=10)]
    stageIndex: Annotated[int, Field(ge=0, le=9)]
    usedAtStage: Counter
    rarity: Rarity
    totalForms: Annotated[int, Field(ge=1, le=10)]
    isShiny: StrictBool = False
    nature: Annotated[str, Field(max_length=32)] | None = None
    unownForm: Annotated[str, Field(max_length=12)] | None = None
    profile: IndividualProfile | None = None
    hasGrowthBoost: StrictBool = False
    dittoDisguise: Species | None = None
    dittoRevealed: StrictBool = False

    @model_validator(mode="after")
    def valid_stage(self):
        if self.stageIndex >= len(self.pathIDs):
            raise ValueError("Invalid growth stage")
        return self


class CollectionEntry(StrictModel):
    id: Identifier
    baseID: Species
    finalID: Species
    chainOrder: Annotated[list[Species], Field(min_length=1, max_length=10)]
    rarity: Rarity
    caughtAt: Annotated[int | float, Field(ge=-1e10, le=1e11)] | None = None
    isShiny: StrictBool = False
    nature: Annotated[str, Field(max_length=32)] | None = None
    unownForm: Annotated[str, Field(max_length=12)] | None = None
    profile: IndividualProfile | None = None
    names: dict[str, dict[str, str]] | None = None
    namesVersion: Annotated[int, Field(ge=0, le=100)] | None = None
    releasedAt: Annotated[int | float, Field(ge=-1e10, le=1e11)] | None = None

    @field_validator("names")
    @classmethod
    def bounded_names(cls, value):
        if value is not None:
            if len(value) > 10:
                raise ValueError("Too many names")
            for species, names in value.items():
                if not species.isdecimal() or not 1 <= int(species) <= 649 or len(names) > 32:
                    raise ValueError("Invalid names")
                if any(len(language) > 16 or len(name) > 128 for language, name in names.items()):
                    raise ValueError("Invalid names")
        return value


class CompanionSave(StrictModel):
    installBaselineSet: StrictBool = False
    usedSinceInstall: Counter = 0
    spentTokens: Counter = 0
    eggUsage: Counter = 0
    eggTier: Rarity | None = None
    pendingHatchID: Species | None = None
    pendingUnownForm: Annotated[str, Field(max_length=12)] | None = None
    claimedTodayTokensByProvider: dict[str, Counter] | None = None
    lastDate: Annotated[str, Field(max_length=10, pattern=r"^(?:|\d{4}-\d{2}-\d{2})$")] = ""
    active: ActivePokemon | None = None
    representativeSpeciesID: Species | None = None
    representativeUnownForm: Annotated[str, Field(max_length=12)] | None = None
    dex: Annotated[list[CollectionEntry], Field(max_length=10000)] = Field(default_factory=list)
    collectedFinals: Annotated[list[str], Field(max_length=10000)] = Field(default_factory=list)
    language: Literal["ko", "en", "ja", "es", "fr", "pt", "de", "ru"] = "en"
    inventory: dict[Literal["rareCandy", "mint", "shinyCharm"], Annotated[int, Field(ge=0, le=1000000)]] = Field(default_factory=dict)
    candyGrantTier: dict[str, Annotated[int, Field(ge=0, le=1000000)]] = Field(default_factory=dict)
    candyWindowEpoch: dict[str, str] = Field(default_factory=dict)
    candyFeatureSeeded: StrictBool = False

    @model_validator(mode="after")
    def validate_ledgers(self):
        if self.spentTokens > self.usedSinceInstall:
            raise ValueError("Spent balance exceeds earned balance")
        if len({entry.id for entry in self.dex}) != len(self.dex):
            raise ValueError("Duplicate individual ID")
        for mapping in [self.claimedTodayTokensByProvider or {}, self.candyGrantTier, self.candyWindowEpoch]:
            if len(mapping) > 1000 or any(len(k) > 256 for k in mapping):
                raise ValueError("Ledger exceeds limits")
        if any(len(v) > 128 for v in self.candyWindowEpoch.values()):
            raise ValueError("Ledger exceeds limits")
        if any(len(value) > 128 for value in self.collectedFinals):
            raise ValueError("Collection exceeds limits")
        return self


class RuleSettings(StrictModel):
    growthDifficulty: Annotated[float, Field(ge=0.1, le=2)] = 1.0
    shopDifficulty: Annotated[float, Field(ge=0.1, le=2)] = 1.0


class SaveCommand(StrictModel):
    schemaVersion: Literal[1]
    expectedRevision: Annotated[int, Field(ge=0, le=9_000_000_000_000_000)]
    requestID: UUID
    operation: Literal["save"]
    state: CompanionSave
    rules: RuleSettings = Field(default_factory=RuleSettings)
