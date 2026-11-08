# retrl

A SteamOS-"Big Picture"-style game launcher for Linux, packaged as an AppImage.
Emulation-focused but not emulation-only, with controller-first navigation,
support for multiple emulators per platform, and a real auto-updater - point
any emulator at any git host's releases (GitHub or self-hosted Gitea/Forgejo)
and pick a specific version per emulator, per game (like Steam's Proton
version selector, but scoped to one game rather than one global choice).

Built with **Godot 4.x**.

## Status

Screens now closely follow the Steam Deck UI as a direct reference:

- **Shell** (`ui/screens/Shell.tscn`) — persistent frame: top bar (title +
  clock) and the slide-out side menu (Home / Library / Emulators / Recomps /
  Settings / Quit — Store/Friends/Media/Downloads/Power from the Steam
  reference are skipped, this launcher has no store or social features).
  Pages are swapped inside it by the `Navigator` autoload, so the frame never
  reloads. Also owns the "playing" state (see "A running game pauses the
  whole launcher" below).
- **Home** — a single "Recent Games" carousel across **all platforms mixed
  together**, sorted by last played for real (`LibraryScanner.record_played`,
  called whenever Play actually succeeds - nothing else ever sets
  `last_played` for a ROM-scanned game, so without this the ordering never
  moved). No platform- or emulator-picker; you land straight on your
  library. Below it, an **Emulator Updates** row: the latest release per
  emulator with a real repo configured, checked fresh on every visit (covers
  "check on each launch" since Home is always the first screen) - click a
  card to read that release's changelog and install/activate it right there.
  Hidden entirely if nothing has a working repo.
- **Library** — search box + platform tabs (+ "All") + a grid of every
  matching game, for actually browsing by platform. The "Native
  Recompilations" tab (and any other platform tab a recomp is assigned to)
  merges in recomps tracked directly (`EmulatorRegistry.recomp_ids`,
  `Library._recomps_for_platform`) alongside whatever Quiver-scanned
  recomp games are already there - same tile, same grid, pressing one
  opens **RecompDetail** instead of GameDetail. "All" stays
  `LibraryScanner.games` as-is, unchanged - this merge is deliberately
  scoped to the specific platform tab(s) a recomp belongs to.
- **Emulator Library** (`EmulatorLibrary.tscn` / `EmulatorDetail.tscn`) —
  the same idea as Library, but one tile per configured emulator rather
  than per game. Opening one (**EmulatorDetail**) shows which platforms it
  runs, a standalone **Launch** button (its active version, no game
  involved — `LaunchManager.launch_emulator_standalone`), a SteamGridDB-
  backed cover-art section (same search/upload flow as a game's Art tab,
  just the one "cover" kind — art keyed under `"emulator:<id>"` so
  `ArtManager`'s existing per-id cache needs no changes to support it), and
  every release fetched from its repo with install/"Set Active"/changelog
  actions per version — the point is seeing which version to use for a
  given game without having to open that game's Settings first. Excludes
  `integration_mode: "recomp"` entries — see **Recomp Library** below, those
  get their own section instead of showing up here too.
- **Recomp Library** (`RecompLibrary.tscn` / `RecompDetail.tscn` /
  `RecompSettings.tscn`) — a recomp (self-contained native port, no ROM,
  tracked via its own git releases the same way an emulator is) is
  presented as a game, not an emulator: one tile per recomp, opening
  **RecompDetail** — a `GameDetail`-style page (hero banner, Play, gear into
  Settings) with no "Open Emulator" button, since a recomp has no separate
  emulator to open, it only ever plays itself. The gear leads to
  **RecompSettings**, which mirrors `GameSettings`' sidebar-tabs layout but
  swaps the "Emulator" tab for a **Versions** tab (adapted from
  `EmulatorDetail`'s release-fetch/install/changelog flow) and drops
  "Emulator" entirely — there's no ROM here to pick an emulator for, only
  "which build of myself is installed/active". Art gets both cover and hero
  (like a real game), keyed under `"recomp:<id>"`, independent of any
  `"emulator:<id>"` art the same underlying entry might carry. RecompDetail
  also has a **Screenshots** tab, same gallery as GameDetail's, keyed under
  that same `"recomp:<id>"` id - no Achievements tab, though (see
  "RetroAchievements is read-only" below for why that's essentially never
  applicable to a recomp).
- **GameDetail** — a game's own page: hero banner, Play button, **Open
  Emulator** (starts the assigned emulator standalone, no ROM - for reaching
  its own settings/config screen without loading a game first; hidden for
  native/no-emulator games), last played/playtime/platform/emulator summary,
  two tabs (**Achievements** - read-only RetroAchievements, see "RetroAchievements
  is read-only" below; **Screenshots** - a gallery of whatever's been taken
  while this game was running, see "Screenshots are ours to take, not the
  emulator's" below), and the gear icon into...
- **GameSettings** — per-game settings. "General" has a **rename** field
  (`LibraryScanner.set_display_name`) - changes what's shown everywhere,
  never touches the actual ROM file or Quiver folder on disk, revertible via
  "Reset". The "Emulator" tab is the real feature: every emulator the game's
  platform supports gets its own section listing its releases (fetched live
  from GitHub via `UpdateManager`); installed versions are one click to
  switch to, not-installed ones download first. This sets a **per-game**
  override (`LibraryScanner.set_override`), independent of the platform
  default — so one Switch game can run on Eden while another runs on
  Eglantine. Renaming and the emulator override are independent and merge
  rather than clobber each other (confirmed - an earlier version of
  `set_override` replaced the whole per-game entry, which would have wiped
  a rename the moment you changed emulators).

- **AppSettings** (Settings in the side menu) — five tabs:
  - **Directories**: pick a platform, point at a path, "Add Directory".
    `LibraryScanner` scans it for files matching that platform's extensions
    and those become real library entries (real `rom_path`).
  - **Platforms**: fully user-defined, not hardcoded by us — name, comma-
    separated extensions, default emulator. Add/delete from here.
  - **Emulators**: also user-defined — name + which platform(s) it belongs
    to (checkboxes). Every emulator row - bundled or user-created - has an
    editable **Repo URL** field ("Save Repo"): paste any git host's repo URL
    (GitHub, or a self-hosted Gitea/Forgejo instance like git.eden-emu.dev)
    and an asset-pattern override, and that emulator's releases show up in
    every compatible game's GameSettings → Emulator tab. Nothing is locked
    to the repos we happened to bundle. Each row also has "Add Local
    .AppImage": point it at a file already on disk + a version label, copied
    in and chmod +x'd immediately — for when you have a build GitHub-less.
    Above the emulator list, an **"Emulators download folder"** setting -
    defaults to this app's own `user://` data dir but is fully
    user-overridable (see "Configurable install folders" below). Excludes
    recomps - see the next tab.
  - **Recomps**: its own "+ Add Recomp" form and list, deliberately
    separate from Emulators (`AppSettings._build_recomps_pane`) even though
    both ultimately call the same `EmulatorRegistry.add_emulator` /
    `_build_emulator_row` - a recomp isn't something you'd ever assign to a
    ROM the way an emulator is, it's specific to the one game it already
    is, so its "+ Add" form and repo-editable row list live here instead.
    Saving sets `integration_mode: "recomp"` and an empty
    `launch.args_template` (a bare `add_emulator()` call would otherwise
    default that to `["{rom_path}"]`, wrong for a self-contained binary
    with no ROM to pass) - everything else about the row (repo editor,
    "Add Local .AppImage", Delete) is identical to an emulator's, since
    `_build_emulator_row` doesn't actually care which kind it's given. Has
    its own **"Recomps download folder"** setting, same as Emulators'.
  - **Art**: a **"Screenshots folder"** setting (same default-as-is-but-
    overridable pattern as the two above, see `ScreenshotManager`), a
    **RetroAchievements account** section (username + Web API key - see
    "RetroAchievements is read-only" below), then your SteamGridDB API key
    (stored only in `user://art_settings.json`, never in a committed file).
    Three different credentials/paths stacked in one tab rather than three
    new tabs for one or two fields each.

Every path field anywhere in the app (ROM directories, local `.AppImage`,
the two download folders above) now has a **"Browse..."** button next to
it that opens a real system `FileDialog` (folder or file picker, as
appropriate) and fills the field — the field itself stays fully editable
too, for anyone who'd rather type or paste a path than navigate to it. See
"Every path field has a real system picker, not just a text box" below.

- **Art** (`ArtManager`) — two genuinely separate kinds, not one image reused
  two ways (stretching a portrait cover across a wide banner looked wrong -
  confirmed, it did): each game's GameSettings page has an "Art" tab with
  independent **Cover Art** (portrait, what tiles use) and **Hero Art** (wide
  banner, what GameDetail's page uses) sections, each with its own **Upload
  Image...** (a real native `FileDialog`, filtered to png/jpg/jpeg/webp/bmp)
  and SteamGridDB search-and-pick-a-thumbnail flow. Tiles render covers at a
  fixed 2:3 ratio, cropped-to-fill (`STRETCH_KEEP_ASPECT_COVERED`) rather
  than stretched, so real art never looks warped. No API key configured yet
  shows a plain hint instead of a dead search button.

Supporting autoloads: `EmulatorRegistry` (platforms + emulators are USER DATA
— `user://platforms.json` / `user://emulators.json`, full CRUD, only
one-time-seeded from `res://data/` on first run; install state incl. the
*actual* filename of each installed version, since local AppImages can be
named anything, in `user://emulator_state.json`), `LibraryScanner` (game
list, real scan + per-game overrides incl. rename and `record_played`, in
`user://library_overrides.json` / `user://settings.json`), `UpdateManager`
(real Git-releases API client incl. latest-release-per-emulator for Home's
updates row + AppImage/zip download/install, plus the local-file install
path), `LaunchManager`
(resolves the actual installed binary + args and starts it via
`OS.create_process`), `ArtManager` (SteamGridDB client + local cover/hero art
cache, `user://art_cache.json` / `user://art/cover/` / `user://art/hero/`),
`Navigator` (page stack), `InputManager` (controller detection + a real
engine gotcha fixed here: Godot's built-in `ui_accept`/`ui_cancel` actions
ship with **no joypad bindings at all by default**, keyboard-only -
confirmed via `InputMap.action_get_events` - unlike `ui_up/down/left/right`,
which do have joypad bindings; that's exactly why D-pad navigation worked
but face buttons for select/back didn't. Patched at startup by adding
`JOY_BUTTON_A`/`JOY_BUTTON_B` bindings to those actions, at Godot's
normalized Xbox-layout indices so it works for any SDL-recognized
controller, not just the specific pad this was found on).

**What's real vs. placeholder right now:**
- Real: the whole navigation flow; platforms and emulators are fully
  user-creatable/deletable/repo-editable (not fixed by us); ROM-directory
  scanning incl. the Quiver adapter; the releases fetch/download/install
  logic against **any** git host (GitHub or Gitea/Forgejo), including zip
  assets (extracted, the AppImage/binary inside picked automatically) not
  just bare AppImages; adding a local `.AppImage` directly; per-game
  emulator+version overrides (persisted); **actually launching** via
  `OS.create_process`, now with real process tracking (concurrent-launch
  refusal + whole-launcher pause while a game's running - see "A running
  game pauses the whole launcher" above) and a standalone Emulator Library
  browser independent of any one game. `eden`, `eglantine`, `pokedinner`, `lichii`, and
  `melonds` are wired to real, confirmed-working repos (`"verified": true`,
  see their JSON "notes" for exactly what was checked) - `retroarch` and
  `dolphin` still have unconfirmed placeholder repos. Verified end-to-end for
  real: the user's actual Switch/Switch2 ROM folders + Quiver install (47
  games scanned), a local-AppImage install → launch round-trip, and a full
  melonDS download → zip-extract → chmod +x → install round-trip against the
  real GitHub release (now actually installed on this machine); and real
  SteamGridDB search → fetch → download round-trips for **both** cover
  (600x900) and hero (confirmed 1920x620/3840x1240 - distinct cached files,
  distinct paths, never cross-used) against the user's real API key and an
  actual library game (Astral Chain - now has real cover + hero art on this
  machine), plus the local-upload path for both kinds.
- Placeholder: if no ROM directories are configured, the library falls back
  to `data/sample_library.json` (fictional titles); a game with no art set
  yet still falls back to the flat accent-colored rect + initial.

## Running it

1. Godot 4.x is installed via GodotLauncher at `~/Godot/Editors/`.
2. Open the project: run the `Godot_v4.x-stable_linux.x86_64` binary for
   whichever installed version, `--path` pointed at this directory (or open
   `project.godot` through GodotLauncher).
3. Run (F5). Controller: D-pad/stick + A navigates and selects, B backs out,
   Start opens the side menu. Keyboard: arrows + Enter, Escape to back out,
   M opens the side menu.

## Architecture

### Platforms and emulators are user data, not our hardcoded list

`res://data/platforms.json` and `res://data/emulator_definitions/*.json` are
only a **one-time seed** copied into `user://platforms.json` /
`user://emulators.json` the first time the app runs (see
`EmulatorRegistry._ensure_seeded`). After that, those bundled files are never
read again — everything the app shows comes from the user:// copies, which
`EmulatorRegistry.add_platform/update_platform/delete_platform` and the
equivalent `*_emulator` functions mutate directly. The AppSettings screen is
just a UI over that CRUD; there's no code path where a platform or emulator
is fixed by us.

Schema per emulator: `platforms` (ids it runs), `source`
(`{"type": "git_releases", "repo": "owner/name", "api_base": "...", "asset_pattern": "*.AppImage"}`
or `{"type": "none"}` for a manually-managed one).

### Library adapters (Quiver)

Some tools don't hand you a flat folder of ROM files - Quiver downloads each
recomp into its own subfolder (`<Quiver install>/Apps/<FolderName>/`) with no
consistent executable filename across apps. A platform's directory is scanned
by its `library_adapter` field instead of extension-matching when one is set
(`adapters/quiver_adapter.gd`, dispatched from `LibraryScanner`) - this is
**separate** from `default_emulator`: a recomp's `default_emulator` is `null`
because launching bypasses Quiver and runs the game's own binary directly;
`library_adapter: "quiver"` only controls *how its directory gets scanned*.

Figured out by inspecting a real Quiver install rather than guessing: reads
Quiver's own `apps.json` catalog for clean titles, `LastPlayed.txt` for real
recency data, and resolves each app's actual executable via (in order)
`selected_executable.txt`, a `.desktop` file's `Exec=` line, or
`installed-build.txt`'s filename fuzzy-matched against the folder (needed for
at least one real app, whose current build wasn't the only binary left in its
folder and wasn't executable - Quiver doesn't always chmod +x, so the adapter
does it). Verified against a real install (3 apps, all three resolution
strategies each hit on a different real app, correctly skipped the stale
`selected_executable.txt` path when Quiver's Apps directory had moved).
Another `library_adapter` tool would need its own adapter the same way -
there's no generic algorithm for "manages its own folder layout".

### Recomps are tracked like emulators, presented like games

A native recompilation port (e.g. a faithful source port of a specific
game) doesn't fit the "one emulator plays many ROMs" shape - it's a single
self-contained game that happens to ship its own versioned releases on a
git host, same as an emulator does. On disk, a recomp we track directly is
just another `emulator_definitions/*.json` entry with
`integration_mode: "recomp"` and an empty `launch.args_template` (no
`{rom_path}` to fill in) - it reuses `EmulatorRegistry`'s CRUD, install
state, and `UpdateManager`'s git-releases fetch/cache/download/changelog
machinery verbatim, no parallel registry needed.

On screen, though, it's presented as a game, not an emulator: it's
excluded from `EmulatorLibrary`'s grid and from `GameSettings`' per-game
"which emulator should this ROM use" tab (`EmulatorRegistry.
emulators_for_platform` and the `EmulatorLibrary._rebuild_grid` loop both
check `EmulatorRegistry.is_recomp`) - a standalone recomp isn't a ROM
player, so it must never show up as an assignable "emulator" for some
*other* game on the platform (offering "The Oracles Project" as an
emulator choice for an unrelated Quiver-scanned recomp would be
nonsensical - it only ever plays itself), and showing it in both Emulator
Library *and* its own Recomp Library would just be confusing. Instead it
gets its own **Recomp Library** section (see "Status" above) -
`RecompLibrary`/`RecompDetail`/`RecompSettings` are the recomp-shaped
mirror of `Library`/`GameDetail`/`GameSettings`, built by copying those
screens' structure rather than teaching the emulator screens a second
display mode.

This is deliberately distinct from the `quiver` entry's
`integration_mode: "library_adapter"` (see "Library adapters (Quiver)"
above) - `quiver` manages *other* recomps that are already installed
externally and scans their folders; a `recomp`-mode entry is a recomp we
track and install ourselves, directly, the same way we track Eden or
melonDS. `top` (thibautbus/top, "The Oracles Project" - a native port of
Oracle of Ages/Seasons) is the first one wired up this way, and its full
download → install → active-version → Play-enabled round-trip has been
run for real on this machine (RecompSettings' Versions tab, then verified
Play un-disables on RecompDetail) and cleaned back up afterward - not just
a confirmed repo/asset-pattern match. `v1.4.0` and `v1.3.0` each resolve a
real `linux-x86_64.AppImage` download URL; `v1.2.0` and older only ship a
`.tar.gz` for Linux. `.tar.gz` extraction is supported now (see "Any git
host's releases API" above), but `top`'s `asset_pattern` is deliberately
scoped to `*linux-x86_64.AppImage` only, so those older versions still
correctly show "No matching asset" - a pattern choice, not a format
limitation (one `asset_pattern` can't match two different extensions at
once, so picking "whichever every recent release actually has" is the
simplest option here, same as `pokedinner`'s own AppImage-only pattern
above).

### Configurable install folders

Every emulator and recomp install used to be hardcoded under this app's
own `user://emulators/<id>/<version>/` - fine as a default, but not
everyone wants multi-gigabyte emulator builds living inside
`~/.local/share/godot/app_userdata/...` rather than on a bigger drive or a
folder they already organize their emulators in. `EmulatorRegistry` now
holds two independently-configurable roots - `emulators_install_dir()` and
`recomps_install_dir()` (`user://install_paths.json`, each `""` meaning
"use the default") - and `version_install_dir(id, version)` (used by both
`UpdateManager.install_version`/`install_local_file` and
`EmulatorRegistry.delete_installed_version`) resolves through whichever
one applies via `install_root_for(id)` (`EmulatorRegistry.is_recomp`
decides). Recomps default to their own `user://recomps/`, not
`user://emulators/`, matching the rest of the recomp/emulator split above
(own art-key namespace, own library section) even though nothing was
actually installed under the old shared path yet to migrate.

Set from AppSettings → Emulators ("Emulators download folder" / "Recomps
download folder", each with Save and Reset to Default). Changing either
only affects where *new* installs/updates land from then on - anything
already installed stays exactly where it was, nothing gets moved
automatically. Verified for real: pointed `recomps_install_dir` at a
scratch folder, downloaded `top` v1.4.0 for real, confirmed the AppImage
landed under the custom folder (not the default), then reset and deleted
it.

### Every path field has a real system picker, not just a text box

Every place in the app where you'd type a file or folder path - ROM
directories, "Add Local .AppImage", and the two install folders above -
now has a **"Browse..."** button (`AppSettings._add_browse_button`) next
to the text field that opens a real `FileDialog` (`ACCESS_FILESYSTEM`,
folder or file mode as appropriate) and writes the chosen path into that
same field. The field stays fully editable on its own too - this is
additive, not a replacement, for anyone who'd rather paste/type a path
(e.g. one reached over a network mount the picker won't show, or just
faster than navigating to it). Art upload (`ArtManager`, GameSettings/
EmulatorDetail/RecompSettings) already used a real `FileDialog` with no
text field at all, so it needed no change here.

Since this install was seeded long before `top` existed,
`EmulatorRegistry._merge_new_bundled_emulators` (run every `reload()`,
tracked via `user://emulator_seed_ids_seen.json`) adds any bundled
definition this install has never seen before into `user://emulators.json`
- otherwise a new bundled emulator/recomp would only ever reach a *fresh*
install's one-time seed, never one already running. It's one-way (an id
once seen is never re-added), so deleting `top` from Settings sticks
rather than having it reappear on the next launch.

### Any git host's releases API, not just GitHub - but releases, not source

`UpdateManager.parse_repo_url` turns a pasted URL into `{repo, api_base}`:
`github.com` gets `api.github.com`; any other host is assumed to run a
Gitea/Forgejo-compatible API at `<host>/api/v1` (common for self-hosted
emulator-project git instances - confirmed working against
`git.eden-emu.dev`, which Eden/PokeDinner are hosted on). Both expose the
same REST shape (`tag_name`, `name`, `assets[].browser_download_url`), so one
code path in `UpdateManager.list_releases` handles both. This is deliberately
**releases-only**, not generic git-clone-and-build - building arbitrary
source trees (unknown build systems, missing deps) is too fragile for an
AppImage-packaged launcher to rely on. A release asset can be a bare
`.AppImage` (chmod +x'd on install), a `.zip` (extracted, the `.AppImage`
or best-guess binary inside picked automatically and chmod +x'd - confirmed
necessary for real: melonDS only ships its Linux build zipped), or a
`.tar.gz`/`.tgz` (same idea, via `_extract_targz_and_resolve_binary` -
confirmed necessary for real: Pokopia Recomp's Linux releases ship as
`linux-x64.tar.gz`, no `.zip` or bare-binary asset exists). Godot has no
built-in tar/gzip reader, so that path shells out to the system `tar`
rather than reading it directly like `ZIPReader` does for `.zip` - same
Linux-only-target assumption already made for the `chmod`/`rm` calls
elsewhere here. Since `tar` leaves files on disk rather than handing back
an in-memory entry list, resolving which extracted file is "the binary"
is a real recursive directory walk (`_find_binary_in_dir`) rather than one
flat loop over archive entries - same priority order as the zip path
(a `*.AppImage` entry first, else the first non-"obviously support file"
entry) but checked one directory at a time, top level before recursing,
so a nested `assets/` folder's files are never picked over the actual
binary sitting next to them. Other archive formats (`.7z`, `.rar`, ...)
still aren't handled.

### Art: cover and hero are two separate assets, never cross-used

`ArtManager` has one generic kind-parameterized core (`_get_path`,
`_set_local`, `_install`, `_search_images`, kind = `"cover"` or `"hero"`),
but the cache and the files are genuinely split -
`user://art/cover/<sha256 of game id>.<ext>` vs. `user://art/hero/<same
hash>.<ext>`, two separate top-level keys in `user://art_cache.json`. This
isn't just an API nicety: the first version used one shared image for both,
and a 600x900 portrait cover stretched across a wide hero banner looked
obviously wrong (confirmed - that's what prompted the split). Whether an
image came from SteamGridDB or a local upload doesn't matter past that point
- `GameTileFactory` asks for the cover path, `GameDetail` asks for the hero
path, neither knows or cares where it came from. Game ids are full
filesystem paths (ROM files) or Quiver app directories, not filesystem-safe
on their own, hence the hash.

SteamGridDB search is a two-step flow mirroring their API: `search()` hits
`/search/autocomplete/{title}` for candidate games, then `get_grids(id)` /
`get_heroes(id)` hit `/grids/game/{id}?dimensions=600x900` or
`/heroes/game/{id}` respectively (ids/thumbnails come back from search, not
full images) - GameSettings' Art tab shows the first few candidates'
thumbnails for whichever kind before committing to a full-res download.

Tile art is rendered at a fixed 2:3 ratio (`GameTileFactory.ASPECT_RATIO`,
matching SteamGridDB's 600x900 grids) with `STRETCH_KEEP_ASPECT_COVERED`
(crop-to-fill, aspect preserved) rather than `STRETCH_SCALE` (stretch,
aspect ignored) - real art never looks warped even if its exact source
resolution doesn't perfectly match 2:3 (a locally-uploaded image, say).

GameDetail's hero banner is sized at SteamGridDB's actual hero ratio,
1920:620 (`GameDetail.HERO_ASPECT_RATIO`), derived from the viewport width
at `_ready()` rather than a fixed pixel height - it's noticeably taller than
an arbitrary fixed banner height, pushing the Play/meta row further down the
page, which is the deliberate tradeoff (showing the hero uncropped beats a
short banner).

### Every page must grab_focus() on load, or a controller is stuck

Home/Library always called `grab_focus()` on their first tile; GameDetail,
GameSettings, and AppSettings didn't - so there was never a focused control
for a controller's D-pad to move *from*, meaning no button on those three
pages was reachable at all with a controller (confirmed via
`get_viewport().gui_get_focus_owner()` returning null before the fix, a
real control after). All three now grab focus on their first interactive
control at the end of `_ready()`. This is a pattern every new screen needs
to follow, not just a one-off fix.

### Every HTTPRequest needs an explicit timeout - a concurrent fan-out hung indefinitely

Godot's `HTTPRequest.timeout` defaults to `0` (none). All five creation
sites (`UpdateManager`, `ArtManager`) now set `HTTP_TIMEOUT_SECONDS` (12s)
explicitly, so one unresponsive host can't freeze a request forever.

That surfaced while building Home's "Emulator Updates" row: the first
version fanned out all 8 emulators' requests concurrently (start every
`HTTPRequest`, await each `request_completed` after) to avoid summing their
latencies. It hung indefinitely in practice - multiple simultaneous
`HTTPRequest` children under one node never all resolved, even with a
timeout set, root cause not fully isolated. The working, sequential version
(`await list_releases(...)` one emulator at a time, the same function
GameSettings already used successfully) fetches all 8 in a few real seconds
- a hang that breaks every future Home visit is categorically worse than a
few extra seconds, so simple-and-working stayed over clever-and-broken.
`get_latest_releases_for_all_emulators` is sequential for this reason, not
as an oversight.

### Releases are cached - GitHub's unauthenticated API caps out at 60/hour

Confirmed for real on this machine: `curl https://api.github.com/rate_limit`
came back `"remaining": 0`. GitHub throttles unauthenticated REST calls to
60/hour **per IP**, and Home's "checked fresh on every visit" design
(above) means every visit re-fetches all 8 configured emulators - a few
visits in a dev/play session burns the whole budget. Gitea/Forgejo hosts
(Eden, PokeDinner's `git.eden-emu.dev`) have no such cap, which is exactly
why GitHub-hosted emulators (Eglantine, Lichii, melonDS) can go quiet on
Home/GameSettings while the self-hosted ones keep working - same code
path, different host limits, not a bug in the request itself.

`UpdateManager.list_releases` now caches each repo's releases to
`user://releases_cache.json` (keyed by `"api_base|repo"`) for
`CACHE_TTL_SECONDS` (10 min) - revisiting Home/GameSettings/Emulator
Library within that window costs zero extra API calls. A live fetch that
fails for any reason (rate-limited or otherwise) now falls back to
whatever's cached, even if stale, rather than returning `[]` - so a
temporary 403 no longer makes an emulator disappear from the UI the way it
did before. The 403-specifically-rate-limited case is also logged
distinctly (checks `X-RateLimit-Remaining: 0` in the response headers) so
it reads differently from a genuinely bad/private/renamed repo in the
Godot console.

### A running game pauses the whole launcher

Confirmed as a real problem on this machine's SteamOS-style gamescope
session: launching an emulator was fire-and-forget (`OS.create_process`,
no tracking at all), so the launcher's own window kept receiving and
acting on controller input the whole time a game was running - D-pad/face-
button presses kept navigating/selecting *here* instead of the game,
occasionally firing Play again and ending up with two emulators running at
once.

`LaunchManager` now tracks the single running process (`OS.is_process_running`,
polled every second via a `Timer` - Godot has no child-process-exit signal)
and refuses a second launch outright while one is active (`is_game_running`)
- this is the actual hard stop for "two games at once," independent of
whatever input does or doesn't reach the launcher in a given session.
`game_started(label)` / `game_stopped()` signals let `Shell` react: while a
game's running, `get_tree().paused = true` freezes every `_process`/
`_input`/`_gui_input` callback in the whole page tree in one call (the
mechanism behind any Godot pause menu - every node's default
`PROCESS_MODE_PAUSABLE` means none of them run while paused, no per-screen
changes needed), a full-screen "Playing <name>" overlay covers everything
as a visible confirmation, and the window is minimized as a best-effort
nudge for the compositor to hand input focus to the emulator's own window.
`LaunchManager` itself (and its poll `Timer`) is `PROCESS_MODE_ALWAYS` so
it keeps running *while* everything else is paused - otherwise nothing
would ever notice the game exited and un-pause.

The window-minimize part is a best-effort addition, not a confirmed fix -
gamescope/Steam Input's input-routing policy for a child process launched
from inside a Steam "non-Steam game" entry is outside anything this app
can control (minimizing can't be exercised meaningfully outside a real
gamescope session). The pause + concurrent-launch refusal are the parts
actually guaranteed to hold regardless of that.

### RetroAchievements is read-only

This launcher runs emulators as opaque external processes with no view
into their memory, so it has no way to detect an achievement unlocking in
real time - that detection only ever happens inside an emulator with its
own native RetroAchievements client (RetroArch has one; every Switch
emulator here, melonDS, and Dolphin don't). `AchievementsManager` doesn't
try: it's a read-only client for RA's own Web API
(`API_GetGameInfoAndUserProgress`), which in one call returns a game's
full achievement list *and* this user's already-earned status for each -
no ROM hashing needed on our side at all, since we're not identifying the
game ourselves, just asking "what does RA's server already know". The
game's RA id (the number in its retroachievements.org URL) is set per game
in GameSettings -> General (`LibraryScanner.set_retroachievements_id`) -
manually, or via a **"Search"** button (`AchievementsManager.search_games`)
that looks up RA's own console-id list by platform name, pulls that
console's game list, and ranks candidates by a simple normalized-title
match (strip `[...]`/`(...)` tags and punctuation, then exact ->
one-contains-the-other -> shared-word-count scoring - not RA's own ROM-
hash identification, just enough to shortlist candidates for a human to
pick from). Manual entry stays right there either way, same "search, pick
one, or type it yourself" shape as the SteamGridDB art search below it -
useful both for platforms Search can't help with (Switch/Switch2 have no
matching RA console at all) and for fixing a wrong pick. Credentials
(username + Web API key, from the account's own Settings page) live in
`user://retroachievements_settings.json`, same treatment as ArtManager's
SteamGridDB key. Practically, this means the Achievements tab shows real,
live data for a game played through an RA-aware emulator *if that
emulator's own RA login already unlocked things*, and will show "no
achievements"/an empty set for essentially every Switch game in this
library, since RA's catalog skews almost entirely classic-console.

### Screenshots are ours to take, not the emulator's

"Have each emulator save its own screenshots into a per-game folder" isn't
generically possible - every emulator has a different (often global, not
per-game) screenshot setting, and this app's whole model is user-defined,
arbitrary emulators with zero emulator-specific code. So `ScreenshotManager`
takes the screenshot itself, shelling out to a system tool (Godot has no
"capture whatever's on screen" API of its own - it can only capture its
own viewport, which isn't what's showing once an emulator's window is up)
straight into `user://screenshots/<sha256 of game id>/`, a folder it fully
controls independent of any emulator. Tries, in order: `grim` (the natural
fit for a bare wlroots/Wayland session), `spectacle` (KDE's tool - confirmed
working for real on this machine, `spectacle -b -n -o <path>` produced a
real PNG, exit 0), then `scrot` (X11) as a last resort. The folder itself
is user-overridable from Settings -> Art, same default-but-overridable
pattern as the emulator/recomp install folders.

The hotkey that triggers a capture (Select/Back held + Y/Triangle, or F12)
lives in `LaunchManager._unhandled_input`, which works because that node
is already `PROCESS_MODE_ALWAYS` for the poll timer's sake - Shell pausing
the rest of the tree for the "playing" state doesn't stop this one
listener from being *called*. What's genuinely unconfirmed is whether the
input *event* ever reaches it while the window is minimized and unfocused
during actual gameplay, which is a separate question from our own pause
state entirely: keyboard focus is strictly one-window-at-a-time on
basically any compositor, so F12 almost certainly won't fire for real.
Controller input has a real chance, since Godot's Linux joypad backend
reads raw `evdev` device nodes directly rather than through window-focus-
gated input messages - but "has a real chance" isn't "confirmed", and this
is exactly the kind of thing that needs testing on the real handheld
rather than assumed (same honesty bar as the window-minimize note above).
If the combo turns out not to fire during real gameplay, the fallback is
a literal button on the "Playing" overlay itself (which does have real
input, being part of Shell) - strictly worse since it needs tabbing back
to the launcher first, but guaranteed to work.

### GameDetail/RecompDetail needed a real scroll, not just a hero height cap

Confirmed broken for real: adding the Achievements/Screenshots tabs put
real content and real `.png` files on disk (verified directly - 89 real
achievements fetched, a real screenshot file found at the exact expected
path) that nonetheless never appeared on screen. Root cause wasn't the
data layer at all, it was layout: `Hero`'s height was computed purely from
viewport *width* (`width / 1920:620`), with zero relationship to viewport
*height*, and the fixed rows below it (Play button row, meta, status, tab
buttons - each a surprisingly tall ~88px in this theme's large controller-
friendly fonts) were laid out in a plain, non-scrolling `MarginContainer`.
Add those up against a real screen that isn't itself roughly 1920:620-
shaped, and the tab content's *starting position* ends up below the
visible window - not merely short on room, actually unreachable, with no
way to scroll to it, since nothing above it could scroll either. A
`custom_minimum_size` floor on the tab area alone doesn't fix that - a
minimum size can't rescue content whose starting Y position is already
past the bottom of the screen.

Two changes, together: `_hero_height()` (`GameDetail`/`RecompDetail`) now
caps Hero to `min(width / ratio, height * 0.4)` instead of width alone, so
it can't dominate the page on a shorter/wider-than-expected real screen.
More importantly, the whole body below Hero - actions row, meta, status,
tabs, *and* tab content together - now lives inside one `ContentScroll`
(`Layout > Hero, ContentScroll > ContentMargin > Content > ...`), the same
single-big-scroll-area shape `GameSettings`/`AppSettings`/`EmulatorDetail`
already use successfully. Worst case now is "scroll past the Play button
to reach Achievements on an unusually short screen," which is recoverable
- never "structurally unreachable, no matter what," which is what a fixed-
height container with no scroll ability at all actually was.

### Three more real bugs caught by actually using the feature

All three confirmed on this machine, not just reasoned about:

- **Achievement rows weren't focusable at all.** `_make_achievement_row`
  originally returned a plain `HBoxContainer` for its richer custom visual
  (badge + title + points + description) - but a bare `HBoxContainer` has
  `focus_mode = FOCUS_NONE`, so there was nothing in the whole pane for a
  controller's D-pad to land on, which is exactly why only a mouse wheel
  could scroll it. Fixed the same way `GameTileFactory` already builds a
  tile's rich custom visual with real click/focus behavior: a flat
  `Button` hosting plain child Controls (with `mouse_filter =
  MOUSE_FILTER_IGNORE` on the decorative children so clicks still reach
  the button) instead of `Button.text`/`.icon`. Also added the same
  `_grab_first_focusable`-on-tab-show call every other tabbed screen here
  already has (`GameSettings`/`AppSettings`/`EmulatorDetail`) - `GameDetail`
  and `RecompDetail` were missing it entirely for their new tabs, so even
  with focusable rows, nothing would have claimed focus when a tab
  opened. Verified for real: a synthesized Down-key event (not just
  flipping `Input.action_press`, which doesn't trigger Viewport's actual
  GUI focus-navigation pipeline) moved focus from one achievement row to
  the next.
- **The screenshot dialog could balloon past its configured size.**
  `TextureRect`'s default `expand_mode` (`EXPAND_KEEP_SIZE`) makes the
  control's own minimum size track the texture's *native* pixel
  dimensions, not the `custom_minimum_size` set alongside it - so a real
  1920x1080+ screenshot demanded that much space from its container
  regardless of the dialog's configured 900x640. Fixed by setting
  `expand_mode = EXPAND_IGNORE_SIZE` (same property every other image
  preview in this app - `ArtManager`'s previews, `GameTileFactory`'s tiles
  - already set, which is exactly why this bug was new to the screenshot
  dialog specifically). Confirmed for real: dialog now renders at ~876x714
  for an actual screenshot, not blown up to native resolution.
- **Capture grabbed every monitor on a multi-monitor setup.** `spectacle`'s
  default is `-f`/fullscreen, which on this machine's real dual-monitor
  setup produced one 5760x5373 image stitched across both screens.
  `ScreenshotManager` now passes `-m` (current monitor - whichever one has
  the cursor, the best available proxy for "the one with the game," since
  spectacle has no simpler way to ask specifically for that) - confirmed
  for real: a plain `-m` capture came back 1920x1080, a single real
  monitor's resolution, not the stitched combination.

## Roadmap

- **Confirm the screenshot hotkey fires during real gameplay** — capture
  itself is confirmed (`spectacle` works for real on this machine), but
  whether Select+Y/F12 actually reaches `LaunchManager._unhandled_input`
  while the window is minimized/unfocused during an actual play session
  hasn't been tested yet - see "Screenshots are ours to take" above
- **Edit for Platforms** — AppSettings currently only has Add + Delete for
  platforms; changing an existing one means delete + recreate (Emulators got
  a real edit path via the per-row repo editor)
- **`retroarch`/`dolphin` repos** — still unconfirmed placeholders; same
  treatment as the 5 confirmed emulators whenever they're needed for real
- **Other archive formats** — `.zip` and `.tar.gz`/`.tgz` extraction both
  exist now (`UpdateManager.install_version`); `.7z`/`.rar` still aren't
  handled
- **Quiver icon art** — Quiver's own `apps.json` has real `appIconUrl`s per
  recomp; not wired into ArtManager yet, so those still need a manual
  SteamGridDB search or upload like anything else
- **Button glyphs** — controller-brand-aware button icons; still text-only
  hints ("A / Enter", "B / Esc") everywhere
- **Playtime tracking** — PID/exit tracking and a "Playing..." pause state
  now exist (see "A running game pauses the whole launcher" above), but
  nothing writes playtime back anywhere yet (Quiver's own `LastPlayed.txt`
  is read, not written; ROM-scanned games have no playtime source at all)
- **A known, not-yet-reproduced UI bug**: after adding a local AppImage
  version, a game's GameSettings screen was once seen with unlabeled version-
  picker buttons. Couldn't repro it in an automated pass (fresh page load and
  a live rebuild both rendered correct text) - hardened `_set_row_text`
  against the most likely cause (missing-key access instead of defensive
  `.get()`), but flagging that the root cause isn't confirmed. If it recurs,
  the exact screen-to-screen navigation sequence that triggered it would help.
- **AppImage packaging** — Godot Linux export preset, `AppRun`/`.desktop`/icon,
  `appimagetool` build script (not yet installed on this machine)

## License

Copyright (C) 2026 gpj252

retrl is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License, version 3, as published by the Free
Software Foundation. It is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; see the [LICENSE](LICENSE) file for details.

Forks and modified versions are welcome, and must stay open source under the
same license.
