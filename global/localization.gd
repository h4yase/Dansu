extends Node

const MESSAGES_PATH := "res://translations/messages.csv"

var available_locales: PackedStringArray = ["en"]

func _ready() -> void:
	var csv := TranslationCSV.new()
	if csv.read(MESSAGES_PATH):
		for translation in csv.translations:
			if translation.get_message_count() == 0:
				continue
			TranslationServer.add_translation(translation)
			if not available_locales.has(translation.locale):
				available_locales.append(translation.locale)
	else:
		push_warning(csv.error)
	available_locales.sort()
	var locale := Config.language
	TranslationServer.set_locale(locale if available_locales.has(locale) else "en")
