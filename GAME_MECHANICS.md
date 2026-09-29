# Prospecting — mechanics that affect this macro

Notes on the game's actual mechanics, kept here because several of them change what
the macro must do. Corrections welcome; anything wrong here means the macro is wrong.

## Digging: a hold, released on a HORIZONTAL gauge

Digging shows **a horizontal gauge with a moving slider**. You must **release** so the
slider sits inside the **green indicator**. A "Perfect" dig gives 100% material quality
and increases the weight and value of what you find; missing lowers sand quality and the
weight of everything after it.

Two consequences for the macro:

1. The dig is a **hold-then-release**, not a click. `dig` holds the left mouse button and
   releases after a computed time - see below.
2. The gauge is **horizontal**. Any future attempt to detect the green zone directly must
   look at a horizontal strip, not a vertical one. (An earlier version of this project
   spent real effort hunting a vertical slider that does not exist.)

### How `dig` picks its hold length

```
hold = Round(66900 / (digSpeed + 9))      clamped to 60..4000 ms
```

The slider's travel is a function of your **Dig Speed** stat, so the hold length that
lands in the green can be computed from that stat instead of read off the screen. This is
how the established macro for this game does it. Set your stat per line (`dig 140`) or
leave the default. If digs are landing early or late, this number is what to change.

Watching the gauge directly would be exact where the formula is an approximation - that is
the next improvement, and `await` / `clickimg` already exist as the pattern for it.

## Shovel Toughness gates the biome, and failure is silent

Every biome has a strict **Toughness Level**. If the shovel's Dig Strength/Toughness is
below the area's requirement, **you cannot extract anything from that ground at all**.

For the macro this is the worst kind of failure: it walks, it clicks, it digs, and it
yields nothing - which looks exactly like a broken macro. So `_TierCheck()` reads
`maps/tiers.ini` and warns at startup when the active map is above your tier. Set your
tier once in `settings/vortex_config.ini`:

```
[options]
shovelTier=4        ; 0 = not set, which disables the check
```

Progression advice from the game: upgrade the **shovel** first to unlock higher-paying
biomes, then the pan for extraction speed and luck.

## Panning: repeated clicks

Filling the pan triggers the panning minigame **where you stand** — but panning itself
requires standing in water. Repeatedly clicking shakes the pan; each click advances the
shake bar by your pan's **Shake Strength** and **Shake Speed**. That is the `click N`
line in each path file. The count matters more than the timing.

## Luck is a reroll, not a percentage

The game rolls a random number (lower = rarer), then rerolls it once per point of Luck and
keeps the **rarest** result. There is a built-in decay for common items so they never
become impossible. Relevant to the macro only in that a luck-focused loadout changes how
often a run is worth repeating - not to its input sequence.

## Biome toughness reference

| Biome | Toughness |
|-------|-----------|
| Rubble Creek, Sluice Shack, Spawn, Town, Store, Dock | none |
| Sunset Beach | T3 |
| Crystal Cavern River, Fortune River, Fortune River Delta | T4 |
| Azuralite Oasis | T5 |
| Fungal Marsh / Wastes | T7 |

Tiers for the remaining maps are not documented in the available progression data, so
`tiers.ini` deliberately omits them. A guessed tier could block a biome you can actually
work, which is worse than not checking.

## Other systems (recorded for completeness, no macro impact yet)

- **Prospector Kit**: 1 necklace, 1 charm, up to 8 rings. Crafted at a Blacksmith anvil.
- **Glowing Altar** (Rubble Creek Deposits): hold Aurorite/Etherite with the tool equipped
  to apply a random permanent enchant. Target `Lucky` / `Blessed` (+10 base luck).
- **Hidden Crystal Caverns shop**: behind the waterfall, gated on Emerald + Diamond +
  Starfire. Sells the Worldshaker Pan and Earth Breaker Shovel.
- **Sluices**: placed in moving water, harvest continuously including offline.
- **Treasure maps**: equip one and follow the on-screen arrow until it points down.
- **World relics**: Rainstone (River Rapids), Solar Token (Solar Flare), Snow Globe
  (blizzard, +5000 Luck), Mythic Summon / Void Shard (11x money via Voidtorn).
