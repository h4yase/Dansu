extends HBoxContainer
class_name MainMenuBottomButtons

@export var play_button: MenuBigButton
@export var edit_button: MenuBigButton
@export var new_chart_button: MenuBigButton
@export var back_button: MenuBigButton
@export var menu: DansuMainMenu

func _ready() -> void:
	play_button.activated.connect(_play)
	edit_button.activated.connect(_edit_chart)
	new_chart_button.activated.connect(_new_chart)
	back_button.activated.connect(_back)

func _play() -> void:
	if menu != null:
		menu.activate_song_action()


func _edit_chart() -> void:
	if menu != null:
		menu.open_selected_chart_editor()


func _new_chart() -> void:
	if menu != null:
		menu.open_new_chart_editor()

func _back() -> void:
	if menu != null:
		menu.return_to_main_menu()
