extends Node
## Lists and installs emulator releases from a Git host's releases API.
## Not GitHub-only: GitHub and self-hosted Gitea/Forgejo instances (common
## in the emulation scene - e.g. git.eden-emu.dev) both expose a near-
## identical REST shape (tag_name, name, assets[].browser_download_url), so
## one code path handles both, keyed by "source.api_base". Any emulator -
## bundled or user-created - can point at any host; nothing here is
## GitHub-specific. A bad/unreachable repo just yields an empty release
## list, not a crash.
##
## Releases are cached to disk (user://releases_cache.json, keyed by
## "api_base|repo") with a long TTL - confirmed necessary for real: GitHub's
## unauthenticated REST API caps out at 60 requests/hour per IP, and this
## machine hit that (api.github.com/rate_limit showed 0 remaining) just from
## normal use - Home used to re-check every configured emulator on every
## single visit (Navigator recreates the Home scene on every nav back to
## it), so a handful of visits burned the whole budget in minutes. Gitea/
## Forgejo hosts (Eden, PokeDinner) have no such cap, which is exactly why
## "the two outside GitHub keep working, GitHub ones stop" - same code path,
## different host limits. Fix is two-pronged: CACHE_TTL_SECONDS is now a full
## day (see startup_check_for_updates - Home only calls that, once per app
## run, instead of hitting this directly), and a live fetch that fails
## (rate-limited or otherwise) falls back to the last cached release list
## instead of going blank, so a temporary 403 doesn't make an emulator
## vanish from Home/GameSettings.
const GITHUB_API_BASE := "https://api.github.com"
const RELEASES_CACHE_PATH := "user://releases_cache.json"
const CHECK_LOG_PATH := "user://update_check_log.json"
## How long a cached release list is served without re-hitting the network -
## effectively "check once a day". Settings → Emulators has a "Check for
## Updates Now" button (UpdateManager.force_check_for_updates) for anyone who
## wants a fresh look sooner than that.
const CACHE_TTL_SECONDS := 86400.0
## Metadata HTTPRequests (list_releases) get this - found necessary for
## real: without a timeout, a single unresponsive host hangs that request
## forever (Godot's HTTPRequest default timeout is 0 = none), which
## silently blocked the whole "Emulator Updates" row (and would block any
## single-repo fetch too). Releases JSON is tiny, so 12s is generous here.
const HTTP_TIMEOUT_SECONDS := 12.0
## install_version's actual asset download used to reuse HTTP_TIMEOUT_SECONDS
## too - wrong for this one, and confirmed as the real cause of "downloads
## sometimes/always fail": Godot's HTTPRequest.timeout is a hard wall-clock
## cap on the *entire* request (connect through full body), not an idle
## timer - it cancels with RESULT_TIMEOUT even mid-download. Reproduced
## directly against Lichii's real 111MB Linux AppImage: it was still
## downloading at 11.9s (107MB already on disk) when the 12s cap killed it.
## Eglantine's similarly ~109MB AppImage sits right at that same edge -
## "sometimes fails, retry works" - while Lichii's (103-140MB depending on
## variant) sits consistently past it - "always fails, every version".
## melonDS/Eden's assets are small enough (~1-35MB) to never hit this.
## 120s comfortably covers every asset size seen here even on a slow link.
const DOWNLOAD_TIMEOUT_SECONDS := 120.0

var _releases_cache: Dictionary = {}  # "api_base|repo" -> {"releases": Array, "fetched_at": float}
var _check_log: Dictionary = {}  # {"checked_at": float, "results": Array}
var _startup_check_done: bool = false
var _last_check_results: Array = []

func _ready() -> void:
	_load_releases_cache()
	_load_check_log()

func _load_check_log() -> void:
	_check_log = {}
	if not FileAccess.file_exists(CHECK_LOG_PATH):
		return
	var file := FileAccess.open(CHECK_LOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_check_log = parsed

func _save_check_log() -> void:
	var file := FileAccess.open(CHECK_LOG_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(_check_log))

func _record_check_log(results: Array) -> void:
	var entries: Array = []
	for entry in results:
		entries.append({
			"emulator_id": entry.get("emulator_id", ""),
			"emulator_name": entry.get("emulator_name", ""),
			"tag": entry.get("tag", ""),
			"is_installed": entry.get("is_installed", false),
			"is_active": entry.get("is_active", false),
		})
	_check_log = {"checked_at": Time.get_unix_time_from_system(), "results": entries}
	_save_check_log()

## Unix timestamp of the last time a check actually ran (startup or manual),
## or 0 if it's never run.
func last_checked_at() -> float:
	return float(_check_log.get("checked_at", 0))

## Human-readable "when" for Settings → Emulators (e.g. "3 hr ago").
func last_checked_text() -> String:
	var checked_at := last_checked_at()
	if checked_at <= 0:
		return "Never"
	var diff := Time.get_unix_time_from_system() - checked_at
	if diff < 60:
		return "Just now"
	if diff < 3600:
		return "%d min ago" % int(diff / 60)
	if diff < 86400:
		return "%d hr ago" % int(diff / 3600)
	return "%d day(s) ago" % int(diff / 86400)

## Runs the "what's new" check exactly once per app run - meant to be called
## from Home's _ready. Calling it again later (e.g. navigating back to Home,
## which recreates the scene and re-runs _ready) just returns the same
## in-memory result instead of checking again; this is what used to burn
## through GitHub's rate limit (see the comment at the top of this file).
## A fresh network fetch per-repo still only happens if that repo's cache is
## stale (see CACHE_TTL_SECONDS), so even the first call of a new day mostly
## serves cache for anything checked within the last 24h.
func startup_check_for_updates() -> Array:
	if _startup_check_done:
		return _last_check_results
	_startup_check_done = true
	_last_check_results = await get_latest_releases_for_all_emulators()
	_record_check_log(_last_check_results)
	return _last_check_results

## Settings → Emulators' "Check for Updates Now" button - ignores every
## repo's cache and hits the network for all of them.
func force_check_for_updates() -> Array:
	_startup_check_done = true
	_last_check_results = await get_latest_releases_for_all_emulators(true)
	_record_check_log(_last_check_results)
	return _last_check_results

func _load_releases_cache() -> void:
	_releases_cache = {}
	if not FileAccess.file_exists(RELEASES_CACHE_PATH):
		return
	var file := FileAccess.open(RELEASES_CACHE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_releases_cache = parsed

func _save_releases_cache() -> void:
	var file := FileAccess.open(RELEASES_CACHE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(_releases_cache))

func _cache_key(repo: String, api_base: String) -> String:
	return "%s|%s" % [api_base, repo]

## Cached releases only if still within CACHE_TTL_SECONDS, else null.
func _fresh_cached_releases(key: String) -> Variant:
	var entry: Dictionary = _releases_cache.get(key, {})
	if entry.is_empty():
		return null
	var age: float = Time.get_unix_time_from_system() - float(entry.get("fetched_at", 0))
	if age > CACHE_TTL_SECONDS:
		return null
	return entry.get("releases", [])

## Whatever's cached regardless of age - the fallback for a failed live
## fetch, since stale data beats no data for "is there an update" purposes.
func _any_cached_releases(key: String) -> Array:
	return _releases_cache.get(key, {}).get("releases", [])

func _store_releases_cache(key: String, releases: Array) -> void:
	_releases_cache[key] = {"releases": releases, "fetched_at": Time.get_unix_time_from_system()}
	_save_releases_cache()

## True if the response headers show GitHub/Gitea's rate limit is exhausted
## (X-RateLimit-Remaining: 0) - lets a 403 from that be logged distinctly
## from a genuinely bad/private repo.
func _is_rate_limited(headers: PackedStringArray) -> bool:
	for header in headers:
		if header.to_lower().begins_with("x-ratelimit-remaining:") and header.ends_with("0"):
			return true
	return false

## Parses a pasted repo URL (GitHub or a self-hosted Gitea/Forgejo instance)
## into {"repo": "owner/name", "api_base": "...", "host": "..."}, or {} if
## it doesn't look like a host/owner/repo URL at all. GitHub gets the
## github.com REST API; anything else is assumed Gitea/Forgejo-compatible
## (most self-hosted emulator-project git hosts are) at "<host>/api/v1" -
## if that assumption is wrong for a given host, releases just come back
## empty rather than crashing, same as any other unreachable source.
func parse_repo_url(url: String) -> Dictionary:
	var cleaned := url.strip_edges()
	if cleaned.ends_with(".git"):
		cleaned = cleaned.substr(0, cleaned.length() - 4)
	for prefix in ["https://", "http://"]:
		if cleaned.begins_with(prefix):
			cleaned = cleaned.substr(prefix.length())
			break
	var parts := cleaned.split("/")
	if parts.size() < 3 or parts[0] == "" or parts[1] == "" or parts[2] == "":
		return {}
	var host: String = parts[0]
	var repo := "%s/%s" % [parts[1], parts[2]]
	# Treat GitHub's API host as GitHub too, not a Gitea/Forgejo host named
	# "api.github.com" - without this, a GitHub api_base ever displayed back
	# as a URL and re-saved (see AppSettings._display_repo_url) would get
	# misread here and rewritten as "https://api.github.com/api/v1", a URL
	# with no matching route - confirmed on disk for 3 real emulators.
	var api_base := GITHUB_API_BASE if host in ["github.com", "api.github.com", "www.github.com"] else "https://%s/api/v1" % host
	return {"repo": repo, "api_base": api_base, "host": host}

## Returns an Array of {"tag": String, "name": String, "body": String,
## "assets": Array} (body is the release notes/changelog, raw markdown as
## GitHub/Gitea store it - not rendered). Served from cache when fresh
## (see CACHE_TTL_SECONDS); on a failed live fetch (bad repo, no network,
## rate-limited, ...) falls back to whatever's cached (even stale) rather
## than going empty, and only returns [] if nothing's ever been cached for
## this repo. Pass force_refresh to skip the cache (e.g. a user-initiated
## refresh) and always hit the network.
func list_releases(repo: String, api_base: String = GITHUB_API_BASE, force_refresh: bool = false) -> Array:
	if repo.find("/") == -1:
		return []
	var key := _cache_key(repo, api_base)
	if not force_refresh:
		var fresh: Variant = _fresh_cached_releases(key)
		if fresh != null:
			return fresh

	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT_SECONDS
	add_child(http)
	var url := "%s/repos/%s/releases" % [api_base, repo]
	var err := http.request(url, ["User-Agent: launcher-app", "Accept: application/vnd.github+json"])
	if err != OK:
		http.queue_free()
		return _any_cached_releases(key)
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = result[1]
	var headers: PackedStringArray = result[2]
	var body: PackedByteArray = result[3]
	if response_code != 200:
		if response_code == 403 and _is_rate_limited(headers):
			push_warning("[UpdateManager] %s (%s) hit the host's rate limit - serving cached releases if any" % [repo, api_base])
		else:
			push_warning("[UpdateManager] releases fetch for %s (%s) failed (HTTP %d)" % [repo, api_base, response_code])
		return _any_cached_releases(key)
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY:
		return _any_cached_releases(key)
	var releases: Array = []
	for entry in parsed:
		releases.append({
			"tag": entry.get("tag_name", ""),
			"name": entry.get("name", entry.get("tag_name", "")),
			"body": entry.get("body", ""),
			"assets": entry.get("assets", []),
		})
	_store_releases_cache(key, releases)
	return releases

## Latest release per emulator that has a real repo configured, for Home's
## "Emulator Updates" row. Call via startup_check_for_updates (once per app
## run) or force_check_for_updates (Settings' manual button), not directly -
## those wrap this with the once-a-day/once-per-run gating. Emulators with
## no repo, or whose fetch fails/returns nothing, are silently skipped -
## this is a "here's what's new" row, not an error log.
##
## Returns Array of {"emulator_id", "emulator_name", "tag", "name", "body",
## "asset_pattern", "release": Dictionary (the raw release, for installing),
## "is_installed": bool, "is_active": bool}.
func get_latest_releases_for_all_emulators(force_refresh: bool = false) -> Array:
	# Sequential, deliberately - a concurrent "fan out all requests, await
	# each after" version was tried and hung indefinitely in practice
	# (multiple simultaneous HTTPRequest children never resolving, cause
	# not fully isolated), while this sequential version reliably fetches
	# all 8 real configured emulators in a few seconds. A hang that corrupts
	# every future Home visit is categorically worse than a few extra
	# seconds of wait, so simple and working wins over clever and broken.
	var results: Array = []
	for emulator_id in EmulatorRegistry.emulators:
		var emulator: Dictionary = EmulatorRegistry.get_emulator(emulator_id)
		var source: Dictionary = emulator.get("source", {})
		var repo: String = source.get("repo", "")
		if repo == "":
			continue
		var api_base: String = source.get("api_base", GITHUB_API_BASE)
		var releases: Array = await list_releases(repo, api_base, force_refresh)
		if releases.is_empty():
			continue
		var latest: Dictionary = releases[0]
		var tag: String = latest.get("tag", "")
		if tag == "":
			continue
		results.append({
			"emulator_id": emulator_id,
			"emulator_name": emulator.get("name", emulator_id),
			"tag": tag,
			"name": latest.get("name", tag),
			"body": latest.get("body", ""),
			"asset_pattern": source.get("asset_pattern", "*.AppImage"),
			"release": latest,
			"is_installed": EmulatorRegistry.is_version_installed(emulator_id, tag),
			"is_active": EmulatorRegistry.emulator_state.get(emulator_id, {}).get("active", null) == tag,
		})
	return results

## Finds the first release asset whose filename matches a glob-ish pattern
## like "*.AppImage" (the only wildcard supported is "*").
func find_asset_url(release: Dictionary, pattern: String) -> String:
	var regex_pattern := "^" + pattern.replace(".", "\\.").replace("*", ".*") + "$"
	var re := RegEx.new()
	if re.compile(regex_pattern) != OK:
		return ""
	for asset in release.get("assets", []):
		var asset_name: String = asset.get("name", "")
		if re.search(asset_name) != null:
			return asset.get("browser_download_url", "")
	return ""

func is_installing(emulator_id: String, version: String) -> bool:
	return _installing.get(emulator_id + "@" + version, false)

var _installing: Dictionary = {}

## Downloads a release asset and installs it under
## EmulatorRegistry.version_install_dir(emulator_id, version) - the
## emulators or recomps download folder (AppSettings → Emulators), whichever
## this entry is, by default under this app's own user:// data dir but
## user-overridable. A bare .AppImage asset is chmod +x'd directly; a .zip
## asset is extracted and the AppImage/binary inside is resolved (see
## _extract_zip_and_resolve_binary) - confirmed necessary for real: melonDS
## only ships its Linux AppImage zipped, no bare-AppImage asset exists. A
## .tar.gz/.tgz asset goes through _extract_targz_and_resolve_binary instead
## (shells out to `tar`, Godot has no built-in reader for it) - confirmed
## necessary for real: Pokopia Recomp's Linux releases ship as
## linux-x64.tar.gz, no .zip or bare-binary asset exists. Other archive
## formats (.7z, .rar, ...) still aren't handled.
func install_version(emulator_id: String, version: String, download_url: String) -> bool:
	if download_url == "":
		return false
	var key := emulator_id + "@" + version
	_installing[key] = true

	var dir_path := EmulatorRegistry.version_install_dir(emulator_id, version)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file_name := download_url.get_file()
	var dest_path := dir_path.path_join(file_name)

	var http := HTTPRequest.new()
	http.timeout = DOWNLOAD_TIMEOUT_SECONDS
	add_child(http)
	http.download_file = dest_path
	var err := http.request(download_url, ["User-Agent: launcher-app"])
	if err != OK:
		http.queue_free()
		_installing.erase(key)
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	_installing.erase(key)

	var response_code: int = result[1]
	if response_code != 200:
		push_warning("[UpdateManager] download of %s failed (HTTP %d)" % [download_url, response_code])
		return false

	var binary_filename := file_name
	if file_name.to_lower().ends_with(".zip"):
		binary_filename = _extract_zip_and_resolve_binary(dest_path, dir_path)
		if binary_filename == "":
			push_warning("[UpdateManager] extracted %s but couldn't find a runnable file inside" % file_name)
			return false
	elif file_name.to_lower().ends_with(".tar.gz") or file_name.to_lower().ends_with(".tgz"):
		binary_filename = _extract_targz_and_resolve_binary(dest_path, dir_path)
		if binary_filename == "":
			push_warning("[UpdateManager] extracted %s but couldn't find a runnable file inside" % file_name)
			return false
	elif file_name.to_lower().ends_with(".appimage"):
		OS.execute("chmod", ["+x", ProjectSettings.globalize_path(dest_path)])

	EmulatorRegistry.mark_version_installed(emulator_id, version, binary_filename)
	return true

const _ARCHIVE_SKIP_EXTENSIONS := ["txt", "md", "json", "png", "jpg", "jpeg", "ico", "license", "desktop", "ini", "dll", "so", "cfg"]

## Extracts every entry of a downloaded zip into dir_path, deletes the zip,
## and returns the relative path (within dir_path) of whichever file looks
## like the actual thing to run: prefer a *.AppImage entry, else the only
## non-"obviously support file" entry, else the first such entry found.
## Returns "" if nothing suitable was found.
func _extract_zip_and_resolve_binary(zip_path: String, dir_path: String) -> String:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return ""

	var appimage_entry := ""
	var fallback_entry := ""
	for entry_path in reader.get_files():
		if entry_path.ends_with("/"):
			continue
		var data := reader.read_file(entry_path)
		var out_path := dir_path.path_join(entry_path)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var out_file := FileAccess.open(out_path, FileAccess.WRITE)
		if out_file == null:
			continue
		out_file.store_buffer(data)
		out_file.close()

		if entry_path.to_lower().ends_with(".appimage") and appimage_entry == "":
			appimage_entry = entry_path
		elif fallback_entry == "" and entry_path.get_extension().to_lower() not in _ARCHIVE_SKIP_EXTENSIONS:
			fallback_entry = entry_path
	reader.close()
	DirAccess.remove_absolute(zip_path)

	var chosen := appimage_entry if appimage_entry != "" else fallback_entry
	if chosen != "":
		OS.execute("chmod", ["+x", ProjectSettings.globalize_path(dir_path.path_join(chosen))])
	return chosen

## Same idea as _extract_zip_and_resolve_binary, but for .tar.gz/.tgz -
## confirmed necessary for real: Pokopia Recomp's Linux releases ship as
## linux-x64.tar.gz, no bare binary or .zip asset exists. Godot has no
## built-in tar/gzip reader (unlike ZIPReader), so this shells out to the
## system `tar` - same Linux-only-target assumption already made for the
## chmod/rm calls elsewhere in this file. Deletes the archive afterward,
## same as the zip path.
func _extract_targz_and_resolve_binary(archive_path: String, dir_path: String) -> String:
	var globalized_archive := ProjectSettings.globalize_path(archive_path)
	var globalized_dir := ProjectSettings.globalize_path(dir_path)
	var output: Array = []
	var exit_code := OS.execute("tar", ["-xzf", globalized_archive, "-C", globalized_dir], output, true)
	if exit_code != 0:
		push_warning("[UpdateManager] tar extraction of %s failed (exit %d): %s" % [archive_path, exit_code, output])
		return ""
	DirAccess.remove_absolute(archive_path)

	var chosen := _find_binary_in_dir(globalized_dir)
	if chosen != "":
		OS.execute("chmod", ["+x", globalized_dir.path_join(chosen)])
	return chosen

## Walks an extracted archive's directory tree looking for the thing to
## run - same priority as the zip path (a *.AppImage entry first, else the
## first non-"obviously support file" entry) but as a real filesystem walk
## rather than one flat archive-entry list, since a .tar.gz commonly nests
## everything under one top-level folder (unlike the flat zips handled so
## far) and `tar` gives us files on disk, not an in-memory entry list to
## iterate. Returns a path relative to `root`, or "" if nothing suitable
## was found anywhere in the tree.
func _find_binary_in_dir(root: String, relative: String = "") -> String:
	var current := root.path_join(relative) if relative != "" else root
	var dir := DirAccess.open(current)
	if dir == null:
		return ""

	var appimage_entry := ""
	var fallback_entry := ""
	var subdirs: Array = []
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if entry_name.begins_with("."):
			entry_name = dir.get_next()
			continue
		var entry_relative := relative.path_join(entry_name) if relative != "" else entry_name
		if dir.current_is_dir():
			subdirs.append(entry_relative)
		elif entry_name.to_lower().ends_with(".appimage") and appimage_entry == "":
			appimage_entry = entry_relative
		elif fallback_entry == "" and entry_name.get_extension().to_lower() not in _ARCHIVE_SKIP_EXTENSIONS:
			fallback_entry = entry_relative
		entry_name = dir.get_next()
	dir.list_dir_end()

	if appimage_entry != "":
		return appimage_entry
	if fallback_entry != "":
		return fallback_entry
	for subdir in subdirs:
		var found := _find_binary_in_dir(root, subdir)
		if found != "":
			return found
	return ""

## Copies a local .AppImage the user already has on disk in as an installed
## "release" of an emulator - no network involved. Lets someone use an
## emulator build they downloaded themselves (or one we don't know a GitHub
## repo for yet) immediately, without waiting on the GitHub releases flow.
func install_local_file(emulator_id: String, version: String, source_path: String) -> Dictionary:
	if version.strip_edges() == "":
		return {"ok": false, "message": "Give this version a label (e.g. \"local\" or \"1.2.3\")."}
	if not FileAccess.file_exists(source_path):
		return {"ok": false, "message": "File not found: %s" % source_path}
	if not source_path.to_lower().ends_with(".appimage"):
		return {"ok": false, "message": "Only .AppImage files are supported right now."}

	var dir_path := EmulatorRegistry.version_install_dir(emulator_id, version)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file_name := source_path.get_file()
	var dest_path := dir_path.path_join(file_name)

	var src := FileAccess.open(source_path, FileAccess.READ)
	if src == null:
		return {"ok": false, "message": "Could not read source file: %s" % source_path}
	var bytes := src.get_buffer(src.get_length())
	src.close()

	var dst := FileAccess.open(dest_path, FileAccess.WRITE)
	if dst == null:
		return {"ok": false, "message": "Could not write to %s" % dest_path}
	dst.store_buffer(bytes)
	dst.close()

	OS.execute("chmod", ["+x", ProjectSettings.globalize_path(dest_path)])
	EmulatorRegistry.mark_version_installed(emulator_id, version, file_name)
	return {"ok": true, "message": "Added %s as version '%s'." % [file_name, version]}
