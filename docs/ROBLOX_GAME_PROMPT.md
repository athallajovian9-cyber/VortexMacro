# Claude prompt — build a Roblox prospecting game

Copy everything below the line into Claude.

Note before you do: the mechanics here are documented from the real game *Prospecting*
as a DESIGN REFERENCE. Game mechanics are not copyrightable, but its art, models,
audio, UI, logos and the name itself are — do not copy those. Build your own
presentation on top of these systems.

---

You are building a Roblox game in Luau. Work inside Roblox Studio. Your job is a
playable, server-authoritative vertical slice first — not a finished game. Read this
whole brief, then propose the structure before writing code.

## The game

A prospecting / mining game. The player digs sand, pans it in water to reveal
minerals, sells them, and upgrades gear to reach richer biomes. The loop is short and
repeatable; the depth comes from gear stats and area gating.

**Core loop:** dig sand → pan it → sell minerals → buy better shovel/pan → reach a
higher-toughness biome → repeat.

## The mechanics that define the game

These are what make it good. Get these right before adding content.

### 1. The dig timing minigame (the signature mechanic)

When the player digs, show a **HORIZONTAL gauge with a slider that sweeps across it**.
The player must release the mouse button while the slider is inside a **green zone**.
The gauge is horizontal — not vertical.

- Hit the green zone → a "Perfect" dig. The sand carries **100% quality**, which raises
  both the rarity roll and the sell weight of everything found from it.
- Miss → lower quality, lighter and less valuable results. Missing should feel like a
  real loss, not a rounding error.

The slider's travel SPEED is driven by the player's **Dig Speed** stat, so a faster
shovel means a faster sweep and a harder window. This is the core skill expression —
tune it so it is learnable, never random. Server-authoritative: the server decides
whether the release was inside the zone, with enough latency tolerance that normal
ping does not make it unfair.

### 2. Panning

Filling the pan with sand triggers the panning minigame. Panning REQUIRES standing in
water. The player shakes the pan by clicking repeatedly; each click advances a shake
bar by the pan's **Shake Strength**, and **Shake Speed** sets how fast those clicks can
be. When the bar completes, the minerals are revealed. The pan has a **Capacity** that
sets how much sand one fill holds, and a **Luck** stat that feeds the roll below.

### 3. Luck is a REROLL, not a percentage

Do not implement luck as "+5% rare chance". Implement it as the real thing:

1. For each mineral, generate a random number where LOWER is RARER.
2. Reroll it once per point of Luck.
3. Keep the rarest (lowest) of all the rolls.

This produces the correct feel: more luck means reliably better results, and its value
compounds with itself. Add a **decay factor for common items** so that at very high
luck the common drops do not become literally impossible — otherwise the loot table
degenerates.

### 4. Shovel Toughness gates biomes

Every biome has a **Toughness Level**. If the shovel's **Dig Strength** is below the
biome's requirement, the player **cannot extract anything there**. This should be
communicated clearly up front (show the requirement, refuse the dig with a visible
reason) — an unexplained "nothing happens" is indistinguishable from a bug and players
will assume the game is broken.

Progression order: upgrade the SHOVEL first to unlock higher-paying biomes, then the
PAN to speed up extraction and boost luck.

### 5. Gear and stats

Two tool families, each with real stats that change play, not just numbers:

- **Shovels:** Dig Strength (biome access), Dig Speed (timing difficulty), Toughness.
- **Pans:** Luck, Capacity, Shake Strength, Shake Speed, Modifier Boost, Size Boost.

Higher tiers cost dramatically more and should visibly change how the game plays.
Make the cheap early tiers forgiving and the late tiers demanding.

### 6. Character loadout

A "Prospector Kit" UI with slots: **1 necklace, 1 charm, up to 8 rings**. Crafted from
raw minerals at a Blacksmith anvil using blueprints. Early-game craftables should give
survival and speed buffs, not just tiny stat bumps.

### 7. Enchanting

An altar in a specific zone. The player brings a high-tier ore, holds it, equips the
tool, and interacts with the altar to apply a **random permanent** bonus. Target
outcomes are `Lucky` and `Blessed` (+10 base luck). Make rerolling enchantments a
long-term goal.

## World structure

Zones gated by toughness, so progress is legible:

- **Starter:** safe, no requirement. Town, shops, a beginner sluice shack.
- **Early:** first real coastal biome (suggest ~T3).
- **Mid:** the central river hub and its delta, a coastal beach (~T3–T4).
- **High:** volcanic ash flats, a subterranean cavern river (~T4).
- **Endgame:** a glowing oasis inside the caves (~T5), and a swamp/marsh (~T7).

Include at least one **secret shop** gated behind a multi-item requirement, holding the
best gear in the game. Secrets give exploration a point.

## Supporting systems

- **Sluices** — placeable in flowing water, harvest slowly and **continuously including
  while the player is offline**. This is the retention mechanic; make offline earnings
  capped but meaningful.
- **Treasure maps** — occasionally found while panning. Equipping one projects a
  tracking arrow on screen; follow it until it points straight down ("X marks the
  spot"). Cap how many can be held, and sell capacity upgrades.
- **World relics** — rare consumables that change the world for everyone in the server
  temporarily: heavier river flow, a solar flare that boosts modifier spawns and ore
  size, a blizzard granting a flat luck bonus, and a rarer one opening a high-multiplier
  rift. Server-wide events are what make a public server feel alive.

## Engineering requirements

- **Server-authoritative.** Every roll, every mineral, every currency change happens on
  the server. The client sends intents ("I released the slider at t"), never outcomes.
  Assume a modified client. Validate timings server-side with tolerance for latency.
- **Luau, idiomatic.** ModuleScripts for systems, not one giant script. Use
  `--!strict` where practical.
- **Client = presentation + input.** The gauge, the arrow, the shake bar and all
  animations live on the client; the server owns the results.
- **Saving.** DataStores for inventory, gear, stats, sluice state. Handle load failure,
  retry, and session locking. Never lose a player's progress on a bad save.
- **Remotes.** Prefer `RemoteEvent` for one-off actions and `UnreliableRemoteEvent` for
  high-frequency cosmetic telemetry. Never trust a client-supplied number that affects
  economy.
- **Anti-exploit.** Rate-limit remote calls. A player cannot pan faster than their
  shake stats allow, cannot dig in a biome above their toughness, and cannot produce a
  mineral the server did not generate.

## How to work

1. **Propose the structure first**: folder layout, the ModuleScript list, and the remote
   contract. Wait for approval before writing the full game.
2. **Build a vertical slice** before content: one biome, one shovel, one pan, the dig
   minigame, the panning minigame, selling, and a save that survives a rejoin. That
   slice should be genuinely fun before anything else is added.
3. **Placeholder art is fine.** Do not block on assets. Use parts and simple colours.
   Never fake a screenshot or describe visuals as working when they are not built.
4. **Tune, then test.** State the numbers you chose (sweep speed, green zone width, luck
   curve, toughness gates) and why. For each one say what you would change if it plays
   badly.
5. **Report honestly.** If something is untested, say so. Do not claim a system works
   because the code was written — say what you ran and what it did.

## Acceptance criteria for the first milestone

- A player can join, dig with the timing minigame, pan in water, sell, and buy an
  upgrade — with all outcomes decided server-side.
- The luck system is a reroll with common-item decay, not a percentage.
- Digging above the shovel's toughness is refused with a visible, specific reason.
- Progress survives leaving and rejoining.
- The dig minigame feels skill-based, not random: a practiced player should hit Perfect
  most of the time.
