extends Node
## Two separate kinds of art, not one: "cover" (portrait, SteamGridDB Grids,
## 600x900 - what tiles use) and "hero" (wide backdrop, SteamGridDB Heroes,
## 1920x620 - what GameDetail's banner uses). Stretching a portrait cover
## across a wide hero banner looks wrong (confirmed - it did), so they're
## kept as genuinely distinct assets with their own cache entries, not one
## image reused two ways.
##
## Either kind can come from SteamGridDB (search + download) or a local file
## the user picks via a real file dialog - both end up in
## user://art/<kind>/<sha256 of game id>.<ext>, so the rest of the app just
## asks "is there a cached path for this game id and kind" and doesn't care
## which source it came from.
##
## The SteamGridDB API key is a user credential: stored only in
## user://art_settings.json (never in a bundled/committed file), sent only
## to steamgriddb.com, never printed/logged.

const API_BASE := "https://www.steamgriddb.com/api/v2"
const ART_SETTINGS_PATH := "user://art_settings.json"
const ART_CACHE_PATH := "user://art_cache.json"
const ART_DIR := "user://art/"
const HTTP_TIMEOUT_SECONDS := 12.0  ## see UpdateManager.HTTP_TIMEOUT_SECONDS - same reasoning

var _api_key: String = ""
var _cache: Dictionary = {"cover": {}, "hero": {}}  # kind -> {game_id: filename}

func _ready() -> void:
	_load_settings()
	_load_cache()

func _load_settings() -> void:
	_api_key = ""
	if FileAccess.file_exists(ART_SETTINGS_PATH):
		var file := FileAccess.open(ART_SETTINGS_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_api_key = parsed.get("steamgriddb_api_key", "")

func _save_settings() -> void:
	var file := FileAccess.open(ART_SETTINGS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"steamgriddb_api_key": _api_key}))

func _load_cache() -> void:
	_cache = {"cover": {}, "hero": {}}
	if FileAccess.file_exists(ART_CACHE_PATH):
		var file := FileAccess.open(ART_CACHE_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_cache["cover"] = parsed.get("cover", {})
			_cache["hero"] = parsed.get("hero", {})

func _save_cache() -> void:
	var file := FileAccess.open(ART_CACHE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(_cache))

func has_api_key() -> bool:
	return _api_key.strip_edges() != ""

func get_api_key() -> String:
	return _api_key

func set_api_key(key: String) -> void:
	_api_key = key.strip_edges()
	_save_settings()

# --- generic, kind-parameterized core (kind = "cover" or "hero") ----------

## Local filesystem path (not res:///user://) to cached art of this kind for
## this game, or "" if none is cached (or the cached file is missing).
func _get_path(kind: String, game_id: String) -> String:
	var filename: String = _cache.get(kind, {}).get(game_id, "")
	if filename == "":
		return ""
	var path := ART_DIR.path_join(kind).path_join(filename)
	return ProjectSettings.globalize_path(path) if FileAccess.file_exists(path) else ""

func _remove(kind: String, game_id: String) -> void:
	var filename: String = _cache.get(kind, {}).get(game_id, "")
	if filename != "":
		var path := ART_DIR.path_join(kind).path_join(filename)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_cache[kind].erase(game_id)
		_save_cache()

func _set_local(kind: String, game_id: String, source_path: String) -> Dictionary:
	if not FileAccess.file_exists(source_path):
		return {"ok": false, "message": "File not found: %s" % source_path}
	var ext := source_path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg", "webp", "bmp"]:
		return {"ok": false, "message": "Unsupported image type: .%s (use png/jpg/jpeg/webp/bmp)" % ext}

	var dir := ART_DIR.path_join(kind)
	DirAccess.make_dir_recursive_absolute(dir)
	var filename := "%s.%s" % [game_id.sha256_text(), ext]
	var dest_path := dir.path_join(filename)
	var src := FileAccess.open(source_path, FileAccess.READ)
	if src == null:
		return {"ok": false, "message": "Could not read %s" % source_path}
	var bytes := src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(dest_path, FileAccess.WRITE)
	if dst == null:
		return {"ok": false, "message": "Could not write %s" % dest_path}
	dst.store_buffer(bytes)
	dst.close()

	_cache[kind][game_id] = filename
	_save_cache()
	return {"ok": true, "message": "Art updated."}

func _install(kind: String, game_id: String, image_url: String) -> Dictionary:
	var bytes := await download_bytes(image_url)
	if bytes.is_empty():
		return {"ok": false, "message": "Download failed: %s" % image_url}

	var ext := image_url.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg", "webp"]:
		ext = "png"
	var dir := ART_DIR.path_join(kind)
	DirAccess.make_dir_recursive_absolute(dir)
	var filename := "%s.%s" % [game_id.sha256_text(), ext]
	var dst := FileAccess.open(dir.path_join(filename), FileAccess.WRITE)
	if dst == null:
		return {"ok": false, "message": "Could not write %s" % dir.path_join(filename)}
	dst.store_buffer(bytes)
	dst.close()

	_cache[kind][game_id] = filename
	_save_cache()
	return {"ok": true, "message": "Art updated."}

func _search_images(kind: String, steamgriddb_id: int) -> Array:
	if not has_api_key():
		return []
	var endpoint := "heroes" if kind == "hero" else "grids"
	var dims := "" if kind == "hero" else "?dimensions=600x900"
	var url := "%s/%s/game/%d%s" % [API_BASE, endpoint, steamgriddb_id, dims]
	var parsed: Variant = await _get_json(url)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.get("success", false):
		return []
	var results: Array = []
	for entry in parsed.get("data", []):
		results.append({"id": entry.get("id", 0), "url": entry.get("url", ""), "thumb": entry.get("thumb", "")})
	return results

# --- cover art (portrait, 600x900 - tiles) --------------------------------

func get_art_path(game_id: String) -> String:
	return _get_path("cover", game_id)

func has_art(game_id: String) -> bool:
	return get_art_path(game_id) != ""

func remove_art(game_id: String) -> void:
	_remove("cover", game_id)

func set_local_art(game_id: String, source_path: String) -> Dictionary:
	return _set_local("cover", game_id, source_path)

## Candidate cover images for a SteamGridDB game id. Returns Array of
## {"id": int, "url": String, "thumb": String} (portrait 600x900 grids).
func get_grids(steamgriddb_id: int) -> Array:
	return await _search_images("cover", steamgriddb_id)

func install_grid(game_id: String, image_url: String) -> Dictionary:
	return await _install("cover", game_id, image_url)

# --- hero art (wide backdrop, 1920x620 - GameDetail banner) ---------------

func get_hero_path(game_id: String) -> String:
	return _get_path("hero", game_id)

func has_hero(game_id: String) -> bool:
	return get_hero_path(game_id) != ""

func remove_hero(game_id: String) -> void:
	_remove("hero", game_id)

func set_local_hero(game_id: String, source_path: String) -> Dictionary:
	return _set_local("hero", game_id, source_path)

## Candidate hero/backdrop images for a SteamGridDB game id. Returns Array
## of {"id": int, "url": String, "thumb": String} (wide ~1920x620 heroes).
func get_heroes(steamgriddb_id: int) -> Array:
	return await _search_images("hero", steamgriddb_id)

func install_hero(game_id: String, image_url: String) -> Dictionary:
	return await _install("hero", game_id, image_url)

# --- shared ----------------------------------------------------------------

## Autocomplete search for a game title. Returns Array of {"id": int,
## "name": String}, or [] on any failure (no key, no network, no matches).
func search(title: String) -> Array:
	if not has_api_key() or title.strip_edges() == "":
		return []
	var url := "%s/search/autocomplete/%s" % [API_BASE, title.uri_encode()]
	var parsed: Variant = await _get_json(url)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.get("success", false):
		return []
	var results: Array = []
	for entry in parsed.get("data", []):
		results.append({"id": entry.get("id", 0), "name": entry.get("name", "")})
	return results

## Downloads raw image bytes from any URL (used both for SteamGridDB
## thumbnails to preview and full-res images to install).
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

func _get_json(url: String) -> Variant:
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT_SECONDS
	add_child(http)
	var err := http.request(url, ["Authorization: Bearer %s" % _api_key])
	if err != OK:
		http.queue_free()
		return null
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if response_code != 200:
		push_warning("[ArtManager] request failed (HTTP %d): %s" % [response_code, url])
		return null
	return JSON.parse_string(body.get_string_from_utf8())
