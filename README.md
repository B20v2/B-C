# Forge & Frontline

A Roblox nation-builder / war game in the style of *Build and Conquer*. Build a city, run an economy, refine oil into fuel, research weapons, mass-produce missiles, drones and armour, then travel to the mainland to capture strategic points and strike other nations.

Every asset is procedurally built from clean, low-poly parts. The UI is drawn entirely in code. There are **no external asset IDs**, so the game works the moment you open it.

## Quick start

**Option A: just open it**
1. Open `build/ForgeAndFrontline.rbxlx` in Roblox Studio.
2. Press **Play**. In Studio, store purchases are free so you can test every perk.

**Option B: develop with Rojo**
```bash
rokit install                      # installs rojo + lune from rokit.toml
rojo serve                         # then connect from the Rojo Studio plugin
rojo build -o build/ForgeAndFrontline.rbxlx   # or rebuild the place file
```

## Before you publish (checklist)

1. **Data saving:** Game Settings → Security → *Enable Studio Access to API Services*. Without it, Studio shows a yellow "data not saved" chip and nothing persists.
2. **Server size:** set Max Players to **8** (one island per player, `Config.MaxPlots`).
3. **Monetization:** create the game passes and developer products listed below on the Creator Hub, then paste each ID into `src/shared/Catalog/Products.luau`. Items with `id = 0` show "not on sale" in live servers.
4. **Group reward:** set `Config.GroupId` in `src/shared/Config.luau` (0 disables it).
5. **Codes:** edit `Config.Codes` (`FORGE`, `FRONTLINE` and `RELEASE` ship as examples).
6. **Audio (optional):** the game uses sounds that ship with Roblox. Swap in your own IDs in `src/client/Controllers/Sounds.luau`.

## How it plays

| System | What happens |
|---|---|
| **Build menu** (`B`) | Civilian (Housing, Roads, Utilities, Industry, Services) and Military (Research, Buildings, Air Defense, Missiles, Drones) tabs, with 3D model thumbnails, price and build-time chips, locked badges, a Standard / Eastern / European faction toggle, and Delete `2`, Undo `3`, Drag `4`, Move `5`, Rotate `6`/`R` tools. |
| **Economy** | Pay day every 60 s. Taxes scale with population and happiness; shops, offices and factories add income; buildings cost upkeep. |
| **Utilities** | Workers, power (MW) and water are pooled per nation. Shortages slow every building that needs them. Buildings without road access run at half speed. |
| **Happiness** | Leisure, commerce, education and health coverage raise it. Pollution, shortages and damaged buildings lower it. It drives tax income and population growth. |
| **Oil → fuel → war** | Oil pumps fill national storage. Refineries refine fuel, and **fuel trucks visibly drive** it to military factories. The destination is either Auto (most free space) or one you pick, as in the refinery panel. |
| **Production** | Military factories build missiles, drones and vehicles from a queue. Each item costs cash up front, steel when it starts, and burns fuel while it builds. |
| **Research** | Labs generate RP. The Civil and Military trees unlock buildings and weapons. The missile ladder (SRBM → GLCM → MRBM → Cluster → Hypersonic) also needs confirmed **hits**. |
| **Travel / war map** | A top-down strategic camera over the mainland or any nation. The hotbar shows stock counts and reload state; the reticle shows the blast radius; click to launch. |
| **Air defense** | CIWS, SAM and long-range SAM intercept incoming strikes in range (radar adds 25%). Interceptors visibly meet missiles mid-air. |
| **Units** | Marder, Leopard, HIMARS, Gepard and more, plus faction variants. Units deploy through the tunnel to the mainland. Drag-box select, right-click to move. They fight automatically and wear down garrisons. |
| **Conquest** | Seven strategic points: Capital, Airport, Oil Field, Nuclear Plant, City, Port, Military Base. Knock the garrison to 0, hold the ring, and capture it for cash, oil, power, steel or RP bonuses. |
| **PvP** | Opt-in toggle, with a 20-minute shield for new nations. Attacking locks you PvP ON for 3 minutes. Hits knock buildings out (they are repaired, never deleted) and pay you war spoils. |

## Monetization

| Game pass | Default price | Perk |
|---|---|---|
| 2x Cash | 449 | Doubles pay day and offline earnings |
| VIP | 299 | +25% income, gold `[VIP]` chat tag, 2x offline time, +10 unit cap |
| Fast Construction | 249 | 2x build, research and factory speed |
| Eastern Military Pack | 399 | Tor-M2, S-300, S-400, OTR launcher, Swarm Rack, BMP-3, T-90, Tor-M |
| European Military Pack | 399 | Crotale NG, SAMP/T, Storm Battery, Falcon Ramp, VBCI, Leclerc, CAESAR |
| Factory Expansion | 149 | +3 queue slots per factory, +20 unit cap |
| Billboard | 99 | Up to 6 billboards with your own (filtered) message |

| Developer product | Default price | Effect |
|---|---|---|
| Starter Pack (one time) | 99 | $150k, 10 SRBMs and 30 min of 2x cash. It is the hero offer in the store. |
| Cash packs ×4 | 49 – 999 | **Scale with income** (10 min to 8 h of pay, with a floor), so they stay worth buying at every stage. |
| 2x Cash Boost | 99 | 30 minutes; buying again stacks the time. |
| Instant Construction / Research | 39 / 79 | Finishes now |
| Supply Drop | 149 | Fills every unlocked stockpile |
| Emergency Repairs | 25 | Repairs everything for free |

**Retention:** objective chain (24 steps, used as the tutorial), daily streak (7-day cycle that scales with income), 10-minute playtime gifts, offline earnings with a welcome-back popup, a group reward, codes, and a +10% Roblox Premium bonus. Receipts are idempotent (the purchase ID is stored before `PurchaseGranted`).

## Project layout

```
src/shared/            ReplicatedStorage.Shared
  Config.luau          every global balance number
  Catalog/             Buildings, Weapons, Units, Research, Products, Quests, WarMap
  ModelBuilder.luau    procedural clean low-poly assets (buildings, vehicles, missiles, map)
  Net.luau             declared remotes + rate-limited server handlers
  Util/                Grid, Format, Ballistics (synced flight paths), Unlocks
src/server/            ServerScriptService.Server
  Main.server.luau     bootstrap, player lifecycle
  Services/            Data (session-locked DataStore), Plot, Build, Economy, Logistics,
                       Production, Research, Unit, Conquest, Combat, Monetization,
                       Reward, State (diffed state sync), Nations (runtime registry)
src/client/            StarterPlayerScripts.Client
  Main.client.luau     UI layers auto-scaled from a 1600x900 design (phone to 4K)
  UI/                  Theme, Lib (declarative helpers), Icons (frame-drawn, no images)
  Controllers/         HUD, BuildMenu, Placement, BuildingPanel, ResearchUI, WarView,
                       UnitView, Effects, Animator, ShopUI, RewardsUI, ArmyUI, Modal...
tests/                 Lune test suites (see below)
```

All gameplay is **server-authoritative**. The client only sends requests, and every one is validated for grid space, cash, research, passes, limits and rate. Adding content is data-only: add an entry to a catalog, and pick an existing `model` style or add one to `ModelBuilder`.

## Tests

```bash
./tests/run.sh
```
Builds the place, then runs three Lune suites:
- **shared_smoke:** catalog cross-references, grid math, formatting, and every procedural model.
- **server_sim:** the real server with mocked Roblox services. Two players join, build, grow, research, refine, produce, strike, fight PvP, capture, buy, claim rewards, then leave and rejoin with everything restored.
- **client_sim:** the real client UI driven against that simulated server. It opens every window, panel, tab, tool and the war view, and launches a missile.

`luau-lsp analyze` (Roblox definitions) also runs clean over `src/`.
