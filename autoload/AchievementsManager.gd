extends Node
## Read-only RetroAchievements client. Deliberately read-only: this launcher
## runs emulators as opaque external processes with no view into their
## memory, so it has no way to detect an achievement unlocking in real time
## - that detection only ever happens inside an emulator with its own native
## RetroAchievements client (RetroArch has one; most others, including every
## Switch emulator here, don't). What this CAN do, and all it tries to do,
## is ask RetroAchievements' own server "what has this user already earned
## for this game" and display it - the actual unlocking already happened
## (or didn't) inside whichever emulator the user configured with their RA
## account, same as RetroArch's own in-game overlay would show.
##
## One API call per game does the whole job: API_GetGameInfoAndUserProgress
## returns the full achievement list AND this user's earned/not-earned
## status (plus earn date) for every one of them in a single response - no
## separate "list achievements" then "list my unlocks" round trip needed.
##
## Credentials (RA username + Web API key, from the account's Settings page
## on retroachievements.org) are a user credential like the SteamGridDB key
## (ArtManager) - stored only in user://retroachievements_settings.json,
## never bundled/committed, sent only to retroachievements.org.
##
## Not yet confirmed against a real RA account/key on this machine - same
## "built but not yet exercised for real" status ArtManager's SteamGridDB
## client started in before someone's real API key and real game got used.

const API_BASE := "https://retroachievements.org/API"
const MEDIA_BASE := "https://media.retroachievements.org/Badge"
const SETTINGS_PATH := "user://retroachievements_settings.json"
const HTTP_TIMEOUT_SECONDS := 12.0  ## see UpdateManager.HTTP_TIMEOUT_SECONDS - same reasoning

var _username: String = ""
var _web_api_key: String = ""
var _console_ids: Array = []  # [{"id": int, "name": String}, ...] - fetched once per app run, rarely changes

func _ready() -> void:
	_load_settings()

func _load_settings() -> void:
	_username = ""
	_web_api_key = ""
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_username = parsed.get("username", "")
		_web_api_key = parsed.get("web_api_key", "")

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"username": _username, "web_api_key": _web_api_key}))

func has_credentials() -> bool:
	return _username.strip_edges() != "" and _web_api_key.strip_edges() != ""

func get_username() -> String:
	return _username

func get_web_api_key() -> String:
	return _web_api_key

func set_credentials(username: String, web_api_key: String) -> void:
	_username = username.strip_edges()
	_web_api_key = web_api_key.strip_edges()
	_save_settings()

## Fetches the achievement list + this user's earned status for one game,
## by RetroAchievements game id (the number in a game's retroachievements.org
## URL, e.g. retroachievements.org/game/1234 -> 1234 - set per-game in
## GameSettings -> General). Returns {"ok": bool, "message": String,
## "game_title": String, "achievements": Array} where each achievement is
## {"id", "title", "description", "points", "badge_url", "earned": bool,
## "earned_date": Variant}. A missing/invalid game id, no credentials, or
## any network failure comes back as {"ok": false, "message": ...} rather
## than a crash - same "report exactly why" standard as LaunchManager.
func fetch_achievements(game_ra_id: int) -> Dictionary:
	if not has_credentials():
		return {"ok": false, "message": "No RetroAchievements account configured - add one in Settings → Art."}
	if game_ra_id <= 0:
		return {"ok": false, "message": "No RetroAchievements game ID set for this game - add one in its Settings → General tab."}

	var url := "%s/API_GetGameInfoAndUserProgress.php?u=%s&g=%d&y=%s" % [
		API_BASE, _username.uri_encode(), game_ra_id, _web_api_key
	]
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT_SECONDS
	add_child(http)
	var err := http.request(url, ["User-Agent: launcher-app"])
	if err != OK:
		http.queue_free()
		return {"ok": false, "message": "Could not start the RetroAchievements request."}
	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	if response_code != 200:
		return {"ok": false, "message": "RetroAchievements request failed (HTTP %d)." % response_code}

	var parsed: Variant = JSON.parse_string(result[3].get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "message": "RetroAchievements returned something unexpected - wrong game ID?"}
	if parsed.get("Achievements", null) == null:
		return {"ok": false, "message": "No achievement set found for that game ID."}

	var achievements: Array = []
	var achievements_dict: Dictionary = parsed.get("Achievements", {})
	for key in achievements_dict:
		var entry: Dictionary = achievements_dict[key]
		var badge_name: String = entry.get("BadgeName", "")
		var earned: bool = String(entry.get("DateEarned", "")) != "" or String(entry.get("DateEarnedHardcore", "")) != ""
		achievements.append({
			"id": entry.get("ID", 0),
			"title": entry.get("Title", "?"),
			"description": entry.get("Description", ""),
			"points": entry.get("Points", 0),
			"badge_url": "%s/%s%s.png" % [MEDIA_BASE, badge_name, "" if earned else "_lock"],
			"earned": earned,
			"earned_date": entry.get("DateEarnedHardcore", entry.get("DateEarned", null)),
		})
	# Earned-first is more useful at a glance than RA's own (display-order)
	# sort, same reasoning as EmulatorDetail putting the active version first.
	achievements.sort_custom(func(a, b): return int(a["earned"]) > int(b["earned"]))

	return {
		"ok": true,
		"message": "",
		"game_title": parsed.get("Title", ""),
		"achievements": achievements,
	}

## Best-effort auto-detect: searches RA's own game list for this console
## for titles that look like `title`, so a game ID doesn't have to be
## looked up and typed in by hand every time. Returns {"ok": bool,
## "message": String, "results": Array} where results is
## [{"id": int, "title": String}, ...], best match first. This is a title
## match, not a ROM hash match (RA's actual identification method, which
## we deliberately don't do - see this file's header) - good enough for a
## "pick the right one" list, not guaranteed to be exact, which is exactly
## why GameSettings keeps manual entry right alongside it rather than
## replacing it.
func search_games(title: String, platform_name: String) -> Dictionary:
	if not has_credentials():
		return {"ok": false, "message": "No RetroAchievements account configured - add one in Settings → Art.", "results": []}
	if title.strip_edges() == "":
		return {"ok": false, "message": "No title to search for.", "results": []}

	var console_id := await _console_id_for_platform(platform_name)
	if console_id <= 0:
		return {"ok": false, "message": "RetroAchievements has no console matching \"%s\"." % platform_name, "results": []}

	var games: Array = await _fetch_game_list(console_id)
	if games.is_empty():
		return {"ok": false, "message": "Couldn't fetch %s's game list from RetroAchievements." % platform_name, "results": []}

	var query := _normalize_title(title)
	var scored: Array = []
	for game in games:
		var candidate_title: String = game.get("Title", "")
		var score := _match_score(query, _normalize_title(candidate_title))
		if score > 0:
			scored.append({"id": game.get("ID", 0), "title": candidate_title, "score": score})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])

	if scored.is_empty():
		return {"ok": false, "message": "No RetroAchievements match found for \"%s\" on %s." % [title, platform_name], "results": []}
	return {"ok": true, "message": "", "results": scored.slice(0, 8)}

## RA console id for our platform name (e.g. "Nintendo 64" -> RA's own
## "Nintendo 64" console id) - matched by name rather than a hardcoded id
## table, since RA's numeric console ids aren't something we've verified
## against a real account and a wrong hardcoded number would fail silently
## different ways on different platforms. Switch/Switch2 won't match
## anything - RA has no such console - which is expected, not a bug.
func _console_id_for_platform(platform_name: String) -> int:
	var consoles: Array = await _fetch_console_ids()
	var normalized_platform := _normalize_title(platform_name)
	for console in consoles:
		if _normalize_title(console.get("Name", "")) == normalized_platform:
			return console.get("ID", 0)
	# Loose fallback - a platform named "Nintendo GameCube" should still
	# find an RA console literally named "GameCube", etc.
	for console in consoles:
		var console_name := _normalize_title(console.get("Name", ""))
		if console_name != "" and (console_name in normalized_platform or normalized_platform in console_name):
			return console.get("ID", 0)
	return 0

func _fetch_console_ids() -> Array:
	if not _console_ids.is_empty():
		return _console_ids
	var url := "%s/API_GetConsoleIDs.php?y=%s" % [API_BASE, _web_api_key]
	var parsed: Variant = await _get_json(url)
	if typeof(parsed) == TYPE_ARRAY:
		_console_ids = parsed
	return _console_ids

func _fetch_game_list(console_id: int) -> Array:
	var url := "%s/API_GetGameList.php?y=%s&i=%d&f=1" % [API_BASE, _web_api_key, console_id]
	var parsed: Variant = await _get_json(url)
	return parsed if typeof(parsed) == TYPE_ARRAY else []

func _get_json(url: String) -> Variant:
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT_SECONDS
	add_child(http)
	var err := http.request(url, ["User-Agent: launcher-app"])
	if err != OK:
		http.queue_free()
		return null
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = result[1]
	if response_code != 200:
		return null
	return JSON.parse_string(result[3].get_string_from_utf8())

## Lowercased, with bracketed/parenthetical tags ("[010015...]", "(USA)",
## "(Switch 2 Edition)") and punctuation stripped - ROM-scanned titles and
## RA's own titles both carry noise like this that would otherwise sink an
## exact-match search.
func _normalize_title(title: String) -> String:
	var re := RegEx.new()
	re.compile("[\\[\\(][^\\]\\)]*[\\]\\)]")
	var cleaned: String = re.sub(title, "", true)
	re.compile("[^a-z0-9 ]")
	cleaned = re.sub(cleaned.to_lower(), " ", true)
	re.compile("\\s+")
	cleaned = re.sub(cleaned, " ", true)
	return cleaned.strip_edges()

## Simple word-overlap score, not a real string-distance metric - exact
## match scores highest, then "one fully contains the other", then just
## counts shared words. Good enough to rank a short candidate list for a
## human to pick from, not trying to be a precise fuzzy matcher.
func _match_score(query: String, candidate: String) -> int:
	if query == "" or candidate == "":
		return 0
	if query == candidate:
		return 1000
	if candidate.begins_with(query) or query.begins_with(candidate):
		return 500
	if candidate.find(query) != -1 or query.find(candidate) != -1:
		return 250
	var query_words: PackedStringArray = query.split(" ", false)
	var candidate_words: PackedStringArray = candidate.split(" ", false)
	var shared := 0
	for word in query_words:
		if word.length() > 2 and word in candidate_words:
			shared += 1
	return shared

## Raw image bytes for a badge URL - same shape as ArtManager.download_bytes.
func download_bytes(url: String) -> PackedByteArray:
	if url == "":
		return PackedByteArray()
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT_SECONDS
	add_child(http)
	var err := http.request(url, ["User-Agent: launcher-app"])
	if err != OK:
		http.queue_free()
		return PackedByteArray()
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = result[1]
	if response_code != 200:
		return PackedByteArray()
	return result[3]
