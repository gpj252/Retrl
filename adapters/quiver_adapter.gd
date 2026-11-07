class_name QuiverAdapter
extends RefCounted
## Quiver doesn't store a flat folder of ROM files - it downloads each
## recomp into its own subfolder under <quiver_install>/Apps/<FolderName>/,
## and there's no single consistent executable filename across apps.
## Figured out by inspecting a real Quiver install (apps.json catalog,
## installed-build.txt, selected_executable.txt, .desktop files) rather
## than guessing - see README for what was confirmed vs. assumed.
##
## Resolving which file in a folder is "the game" uses, in order:
##   1. selected_executable.txt (Quiver's own record - just the basename,
##      since the absolute path it stores can go stale if Quiver's Apps
##      directory moves, which it has done in testing)
##   2. a .desktop file's Exec= line
##   3. installed-build.txt's first line (the installed archive's filename,
##      extension stripped) matched against files in the folder - this is
##      the only thing that correctly found Wario Land's current build in
##      testing, since Quiver didn't chmod +x it and it wasn't the only
##      binary in the folder (older versions were left behind, abandoned)
##   4. last resort: newest-modified file that isn't an obviously-non-binary
##      extension (txt/json/log/image/license/etc)
## Whatever is found gets chmod +x'd, since Quiver doesn't reliably do that
## itself (confirmed: the active Wario Land build was not executable).

const CATALOG_FILENAME := "apps.json"
const _ARCHIVE_EXTENSIONS := [".zip", ".tar.gz", ".tar", ".7z", ".rar"]
const _SKIP_EXTENSIONS := ["txt", "json", "log", "png", "jpg", "jpeg", "ico", "desktop", "md", "ini", "pak", "patch", "o2r", "lock", "cfg", "dll"]

static func scan(apps_dir: String, platform_id: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var catalog_titles := _load_catalog_titles(apps_dir)

	var dir := DirAccess.open(apps_dir)
	if dir == null:
		push_warning("[QuiverAdapter] cannot open Quiver Apps directory: %s" % apps_dir)
		return found

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var app_dir := apps_dir.path_join(folder_name)
			var binary_path := _resolve_executable(app_dir)
			if binary_path != "":
				found.append({
					"id": app_dir,
					"title": catalog_titles.get(folder_name, _title_from_folder(folder_name)),
					"platform_id": platform_id,
					"rom_path": binary_path,
					"last_played": _read_last_played(app_dir),
					"playtime_hours": 0.0,
				})
			else:
				push_warning("[QuiverAdapter] couldn't find an executable for %s - skipped" % folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()
	return found

static func _load_catalog_titles(apps_dir: String) -> Dictionary:
	var catalog_path := apps_dir.trim_suffix("/").get_base_dir().path_join(CATALOG_FILENAME)
	var result := {}
	if not FileAccess.file_exists(catalog_path):
		return result
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return result
	for entry in parsed.get("apps", []):
		if typeof(entry) == TYPE_DICTIONARY and entry.has("folderName") and entry.has("name"):
			result[entry["folderName"]] = entry["name"]
	return result

static func _title_from_folder(folder_name: String) -> String:
	# "WarioLandSuperMarioLand3-BigodO" -> take the part before the
	# porter/author suffix, then space out the CamelCase as a best effort.
	var base := folder_name.split("-")[0]
	var result := ""
	for i in base.length():
		var c := base[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower():
			result += " "
		result += c
	return result.strip_edges()

static func _read_last_played(app_dir: String) -> Variant:
	var path := app_dir.path_join("LastPlayed.txt")
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.open(path, FileAccess.READ).get_as_text().strip_edges()
	return text if text != "" else null

static func _resolve_executable(app_dir: String) -> String:
	var candidate := _from_selected_executable(app_dir)
	if candidate == "":
		candidate = _from_desktop_file(app_dir)
	if candidate == "":
		candidate = _from_installed_build(app_dir)
	if candidate == "":
		candidate = _fallback_newest_binary(app_dir)
	if candidate != "":
		OS.execute("chmod", ["+x", ProjectSettings.globalize_path(candidate)])
	return candidate

static func _from_selected_executable(app_dir: String) -> String:
	var path := app_dir.path_join("selected_executable.txt")
	if not FileAccess.file_exists(path):
		return ""
	var recorded := FileAccess.open(path, FileAccess.READ).get_as_text().strip_edges()
	if recorded == "":
		return ""
	var candidate := app_dir.path_join(recorded.get_file())
	return candidate if FileAccess.file_exists(candidate) else ""

static func _from_desktop_file(app_dir: String) -> String:
	var dir := DirAccess.open(app_dir)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".desktop"):
			var text := FileAccess.open(app_dir.path_join(file_name), FileAccess.READ).get_as_text()
			for line in text.split("\n"):
				if line.begins_with("Exec="):
					var exe_name: String = line.substr(5).strip_edges().split(" ")[0]
					var candidate := app_dir.path_join(exe_name)
					dir.list_dir_end()
					return candidate if FileAccess.file_exists(candidate) else ""
		file_name = dir.get_next()
	dir.list_dir_end()
	return ""

static func _from_installed_build(app_dir: String) -> String:
	var path := app_dir.path_join("installed-build.txt")
	if not FileAccess.file_exists(path):
		return ""
	var first_line := FileAccess.open(path, FileAccess.READ).get_as_text().split("\n")[0].strip_edges()
	if first_line == "":
		return ""
	var base := first_line
	for ext in _ARCHIVE_EXTENSIONS:
		if base.to_lower().ends_with(ext):
			base = base.substr(0, base.length() - ext.length())
			break

	var dir := DirAccess.open(app_dir)
	if dir == null:
		return ""
	var exact := ""
	var prefix_match := ""
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.to_lower() == base.to_lower():
				exact = file_name
			elif prefix_match == "" and file_name.to_lower().begins_with(base.to_lower()):
				prefix_match = file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	var chosen := exact if exact != "" else prefix_match
	return app_dir.path_join(chosen) if chosen != "" else ""

static func _fallback_newest_binary(app_dir: String) -> String:
	var dir := DirAccess.open(app_dir)
	if dir == null:
		return ""
	var best := ""
	var best_mtime := -1
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			if ext not in _SKIP_EXTENSIONS and not ext.begins_with("so"):
				var full := app_dir.path_join(file_name)
				var mtime := FileAccess.get_modified_time(full)
				if mtime > best_mtime:
					best_mtime = mtime
					best = full
		file_name = dir.get_next()
	dir.list_dir_end()
	return best
