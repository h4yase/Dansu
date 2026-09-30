extends RefCounted
class_name TranslationCSV

var translations: Array[Translation] = []
var error := ""

func read(path: String) -> bool:
	translations.clear()
	error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "Could not open the translation CSV."
		return false
	var header := file.get_csv_line()
	if header.size() < 2 or header[0].trim_prefix("\ufeff") != "keys" or header[1] != "en":
		error = "The CSV must begin with keys,en and use UTF-8 encoding."
		return false
	var columns: Array[int] = []
	var known_locales := TranslationServer.get_all_languages()
	var locales: PackedStringArray = []
	for column in range(1, header.size()):
		if header[column] == "notes":
			continue
		var locale := TranslationServer.standardize_locale(header[column].strip_edges())
		if not known_locales.has(locale.get_slice("_", 0)) or locales.has(locale):
			error = "The CSV contains an invalid or duplicate language code."
			return false
		var translation := Translation.new()
		translation.locale = locale
		translations.append(translation)
		columns.append(column)
		locales.append(locale)
	var keys: PackedStringArray = []
	var allowed_keys := GameText.Key.keys()
	var row_number := 1
	while not file.eof_reached():
		var row := file.get_csv_line()
		row_number += 1
		if row.size() == 1 and row[0].is_empty():
			continue
		if row.size() != header.size() or row[0].is_empty() or keys.has(row[0]):
			error = "Invalid or duplicate translation at CSV row %d." % row_number
			return false
		keys.append(row[0])
		if not allowed_keys.has(row[0]):
			continue
		var original := row[1]
		if original.is_empty():
			error = "Missing English translation at CSV row %d." % row_number
			return false
		for index in range(columns.size()):
			var value := row[columns[index]]
			if value.is_empty():
				continue
			if not _same_placeholders(original, value):
				error = "Keep the original placeholders at CSV row %d." % row_number
				return false
			translations[index].add_message(row[0], value)
	return true

static func _same_placeholders(source: String, translated: String) -> bool:
	var pattern := RegEx.create_from_string("%[-+0 #]*[0-9]*(?:\\.[0-9]+)?[sdifxXocv]|%%")
	var expected: PackedStringArray = []
	var actual: PackedStringArray = []
	for match_value in pattern.search_all(source):
		expected.append(match_value.get_string())
	if expected.is_empty():
		return true
	for match_value in pattern.search_all(translated):
		actual.append(match_value.get_string())
	return expected == actual and not pattern.sub(translated, "", true).contains("%")
