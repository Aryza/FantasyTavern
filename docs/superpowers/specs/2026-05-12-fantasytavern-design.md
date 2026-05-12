# FantasyTavern — Design Spec

**Date:** 2026-05-12
**Status:** Draft, awaiting review

## Summary

Native macOS app (Swift/SwiftUI) for solo fantasy worldbuilding. Plain-file storage (Markdown + JSON per world folder), wiki-style `[[links]]` between entities, sidebar-with-tabs UI, ⌘K command palette, custom fields per entity type, horizontal timelines, image-backed maps with pins, auto-snapshots. No AI features.

## Goals

- Single-user, offline-first worldbuilding tool.
- Portable: world folders readable/editable outside the app.
- Many worlds, sidebar switcher.
- Seven entity types, all wiki-linkable: characters, locations, lore, items, timeline events, languages, journal.
- Low friction: open app → write → links resolve → save is automatic.

## Non-Goals (v1)

- No multi-user collaboration, no cloud sync (folders work with iCloud / Dropbox externally if user wants).
- No AI / LLM features.
- No hex-grid map editor. (Deferred to v2.)
- No PDF export. (Deferred to v2.)
- No map layers. (Deferred to v2.)
- No iPad/iOS build.

## Tech Stack

- Swift 5.10+, SwiftUI for shell, AppKit (`NSTextView`) wrapped for hybrid markdown editor.
- macOS 14+ minimum (SwiftData / latest SwiftUI APIs available; not used for storage).
- Storage: plain files (Markdown with YAML front-matter + JSON). No DB in v1; optional SQLite cache deferred.
- Build: Xcode project + local Swift packages for `Core/*` modules.

## On-Disk Format

```
~/Documents/FantasyTavern/
  Aetheria/                        # world folder
    world.json                     # world meta: name, calendar, color, schema overrides
    characters/
      lyra-stormwind.md
    locations/
      silvermoon.md
    lore/
    items/
    timeline/
      events.json                  # ordered events
    languages/
    journal/
      2026-05-12.md
    maps/
      overworld.png
      overworld.json               # pins[{x,y,locationId,label}]
    .fantasytavern/
      snapshots/                   # auto-snapshots (zip per snapshot)
```

Entity file format:

```markdown
---
id: lyra-stormwind
type: character
name: Lyra Stormwind
tags: [noble, ranger]
fields:
  race: half-elf
  age: 87
  alignment: NG
created: 2026-05-12T10:00:00Z
updated: 2026-05-12T11:30:00Z
---
Half-elven ranger from [[Silvermoon]]. Member of [[Order of Dawn]].
```

- `id` = slug, also filename stem. Stable across renames.
- `[[Name]]` resolved by name → id at index time. Stored as written; user can use `[[Name|alias]]`.

`world.json`:

```json
{
  "name": "Aetheria",
  "color": "#7a4ab8",
  "calendar": { "yearZeroLabel": "AE", "eras": [{"id":"first-age","name":"First Age","start":-2000,"end":0}] },
  "schemaOverrides": {}
}
```

`timeline/events.json`:

```json
[
  {"id":"founding","title":"Founding of Silvermoon","date":-1452,"eraId":"first-age","body":"…","refs":["silvermoon"]}
]
```

`maps/<name>.json`:

```json
{ "image":"overworld.png", "pins":[{"x":0.42,"y":0.61,"locationId":"silvermoon","label":"Silvermoon"}] }
```

## Module Breakdown

```
FantasyTavern/                     # app target
  App/                             # @main, scene config
  Features/
    WorldBrowser/                  # sidebar
    EntityEditor/                  # tabbed editor host
    Markdown/                      # hybrid inline-render editor
    CommandPalette/                # ⌘K
    Timeline/                      # horizontal timeline
    MapView/                       # image + pins
    Snapshots/                     # snapshots UI/restore
  Core/                            # SPM packages, no UI deps
    WorldStore/                    # disk I/O, FSEvents watcher
    EntityModel/                   # value types
    WikiLinks/                     # parse, resolve, backlinks
    SearchIndex/                   # in-memory inverted index + fuzzy
    SchemaRegistry/                # field defs per type
    SnapshotService/               # zip + rotate
```

**Boundaries:**

- `WorldStore` is the only module that touches disk. Returns `Entity` values, emits change events.
- `EntityModel` is pure value types, no dependencies.
- `SearchIndex` consumes entity stream, exposes query API; no disk access.
- `WikiLinks` is pure string parsing + resolver over an id↔name map.
- Each `Features/*` depends only on `Core/*`, never on another feature.

## Data Flow

**Open world:**

1. User picks folder (or selects from "recent worlds" in sidebar).
2. `WorldStore.open(url)` scans `characters/`, `locations/`, etc. Parses each `.md` (YAML front-matter + body).
3. Emits an `Entity` stream. `SearchIndex` builds inverted index; `WikiLinks` builds id↔name map.
4. UI renders sidebar tree from in-memory `World`.

**Edit & save:**

1. User edits in an `EntityEditor` tab. Save debounced 500 ms.
2. `WorldStore.save(entity)` writes `.md` atomically (write temp file, rename).
3. `SearchIndex` updates that entity's tokens incrementally. `WikiLinks` re-resolves `[[...]]` in the updated body.
4. Any open tab showing backlinks to this entity re-renders.

**External edit (FSEvents watcher):**

1. File mutation outside app fires watcher.
2. Re-parse the single file. Update index + backlinks.
3. If file open in tab with no unsaved changes → reload silently.
4. If unsaved → conflict banner: `[Reload from disk] [Keep mine] [Show diff]`.

**Wiki-link click:**

- `[[Silvermoon]]` resolved via `WikiLinks.resolve("Silvermoon")` → entity id → open in new tab (focus existing tab if already open).
- Unresolved → rendered red. Click → "Create [[Silvermoon]] as: [Location ▾]" prompt; creates stub entity and resolves.

**Auto-snapshot:**

- Timer every 10 min. If world dirty since last snapshot, zip world folder (excluding `.fantasytavern/`) into `.fantasytavern/snapshots/{ISO-timestamp}.zip`.
- Retention: all from last 24 h, hourly for last 7 d, daily for last 30 d, then prune.

## UI Layout

Single window, three regions:

- **Left sidebar (220 px):** worlds list (collapsible per world). Inside each world: entity types as sections with counts (`👤 Characters (12)`). Click a type → list of entities in main area's first column; click an entity → opens in a tab.
- **Main area:** browser-style tab bar across the top. Each tab = an open entity, timeline, or map view. ⌘W closes, ⌘T new tab from palette, ⌘1..9 jumps between tabs.
- **Right inspector pane (collapsible, 260 px):** custom fields form for the current entity, tags editor, backlinks list, metadata (created/updated).

Toolbar (window top): world switcher, ⌘K invoker, new-entity menu.

## Editor (Hybrid Markdown)

`NSTextView`-backed view wrapped in SwiftUI.

- Inline rendering: `**bold**` typed → asterisks dim/hide, bold visible; caret enters token → syntax revealed; caret leaves → re-hides. Same for `*italic*`, `~~strike~~`, `` `code` ``, `# heading`, `- list`, `> quote`, `---`.
- `[[Wiki Link]]` rendered as styled pill; click open; ⌘-click new tab; typing `[[` opens autocomplete with entity names + "Create new…".
- Inline images via `![](maps/overworld.png)`.
- No tables in v1.
- Body = freeform prose only. Custom fields edited in inspector pane, not body.

Shortcuts: ⌘B bold, ⌘I italic, ⌘L wikilink picker, ⌘K palette (not editor), ⌘\\ toggle inspector.

## Custom Fields & Schema

`SchemaRegistry` defines fields per entity type. Defaults bundled; user can override per world via `world.json.schemaOverrides`.

Default schema:

```json
{
  "character": [
    {"key":"race","label":"Race","type":"string"},
    {"key":"age","label":"Age","type":"int"},
    {"key":"alignment","label":"Alignment","type":"enum","options":["LG","NG","CG","LN","TN","CN","LE","NE","CE"]},
    {"key":"status","label":"Status","type":"enum","options":["alive","dead","unknown"]}
  ],
  "location": [
    {"key":"kind","label":"Kind","type":"enum","options":["city","town","village","dungeon","region","landmark"]},
    {"key":"population","label":"Population","type":"int"},
    {"key":"climate","label":"Climate","type":"string"}
  ],
  "item": [
    {"key":"rarity","label":"Rarity","type":"enum","options":["common","uncommon","rare","very-rare","legendary","artifact"]},
    {"key":"attunement","label":"Attunement","type":"bool"}
  ],
  "lore": [],
  "language": [{"key":"family","label":"Family","type":"string"}],
  "journal": [{"key":"date","label":"Date","type":"date"}]
}
```

Field types: `string`, `int`, `bool`, `date`, `enum`, `ref` (entity link), `list<T>`.

Inspector renders a form per the active entity type's schema. "+ Add field" creates per-entity ad-hoc fields. Settings → Schemas edits per-world schema overrides (form-driven, writes to `world.json`).

## Search & Command Palette

⌘K opens floating palette over current window.

- **Find mode** (default): fuzzy query across entity name + tags + first 200 chars of body. Results grouped by type. ↑/↓ select, ↵ open in new tab, ⌘↵ open in current tab.
- **Action mode**: prefix `>` → commands like `>new character`, `>open world`, `>export markdown`, `>snapshot now`.
- **Filter syntax** inside find: `type:character race:elf #noble lyra` — tokenized, filters narrow the candidate set before fuzzy ranking.

Index: in-memory inverted token index → entity ids. Fuzzy via subsequence match with score (Sublime ⌘T behavior). Rebuilt incrementally on entity save.

## Timeline

- Per-world calendar in `world.json`: eras list, year-zero label, optional custom months/days.
- Events in `timeline/events.json`: `{id, title, date, eraId?, body, refs:[entityIds]}`.
- Horizontal view: pan (drag), zoom (⌘scroll: year / decade / century scales). Event dots on axis.
- Click event dot → popover with title, body, ref pills.
- Click empty axis at a date → "Add event here" prompt.
- Refs in event body rendered as wiki-link pills.

## Map View

- Image-backed (PNG/JPG in `maps/`). Multiple maps per world (e.g. `overworld.png`, `eastern-realms.png`).
- Pins placed by click. Pin = `{x, y, locationId, label}` (x/y normalized 0..1). Stored in sibling JSON.
- Hover pin → tooltip with location name; click → open location entity in new tab.
- Pan (drag) and zoom (pinch / ⌘scroll).
- v1: single layer only.

## Snapshots & Restore

- Auto-snapshot timer: 10 min, only if dirty.
- File → Show Snapshots: chronological list. Click → "Preview" (read-only mount of that snapshot) or "Restore" (copies snapshot contents back; current state archived first as `pre-restore-{ts}.zip`).

## Export

- File → Export → Markdown:
  - Single entity → `.md`.
  - Type folder → zipped folder.
  - Whole world → zipped folder mirroring on-disk layout.
- PDF export deferred to v2.

## Error Handling

- Per-file parse errors (bad YAML, malformed front-matter): file loads with ⚠ badge in sidebar; editor shows raw text + parse error message; app keeps running.
- Disk full / write failure: modal alert with "Retry" / "Save copy elsewhere". Unsaved edits remain in memory.
- World folder removed mid-session: tabs go read-only with banner "world unavailable; reconnect or close".
- Snapshot failure: non-blocking notification; logged; app continues.

## Testing Strategy

- **Unit tests (XCTest)** for each `Core/*` module:
  - `WorldStore` against temp directories: open, save, atomic rename, parse-error cases.
  - `WikiLinks`: parsing, resolution, dangling links, aliases, rename propagation.
  - `SearchIndex`: query correctness, fuzzy ranking, filter syntax.
  - `SchemaRegistry`: default load, override merge, type coercion.
  - `SnapshotService`: zip creation, retention pruning, restore round-trip.
- **Feature tests:** model-level state tests per feature (open tabs, edit, undo).
- **UI tests:** scripted end-to-end via XCUITest — create world, add character, add location, link character → location, save, close, reopen, verify link still resolves.
- CI: `xcodebuild test` on push (later — local-only at start).

## Open Questions

None currently. All decisions logged above are settled per brainstorming session.

## Decision Log

- Solo-only user model (Q1).
- Seven entity types in v1 (Q2).
- No AI features (Q3).
- Wiki-style `[[links]]` (Q4); typed relations deferred.
- Maps: image+pins + (deferred) layers + (deferred) hex grid (Q5, Q16, Q17).
- Swift/SwiftUI native macOS (Q6).
- Plain files storage (Q7).
- Many worlds, sidebar switcher (Q8).
- Hybrid inline markdown editor (Q9).
- Sidebar + tabbed editor layout (Q10).
- ⌘K full-text + fuzzy palette (Q11).
- Tags + custom fields per type (Q12).
- Markdown export + PDF (PDF deferred per Q17) (Q13).
- Horizontal timeline (Q14).
- Auto-snapshots (Q15).
- v1 defers: hex grid editor, PDF export, map layers (Q17).
