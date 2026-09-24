extends VBoxContainer
class_name MainMenuButtons

@export var play_button: MenuBigButton
@export var edit_button: MenuBigButton
@export var options_button: MenuBigButton
@export var exit_button: MenuBigButton
@export var settings_popup: SettingsPopup
@export var menu: DansuMainMenu

func _ready() -> void:
	play_button.activated.connect(_play)
	edit_button.activated.connect(_edit)
	options_button.activated.connect(_open_options)
	exit_button.activated.connect(_exit_game)

func _play() -> void:
	if menu != null:
		menu.begin_song_select(false)


func _edit() -> void:
	if menu != null:
		menu.begin_song_select(true)

func _open_options() -> void:
	if settings_popup != null:
		settings_popup.show_popup()


func _exit_game() -> void:
	if menu != null:
		menu.begin_exit()
