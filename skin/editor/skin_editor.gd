extends Control
class_name SkinEditor

const EDITOR_SCENE_PATH := "res://scenes/chart/editor/editor_scene.tscn"
const EFFECT_OPTIONS := ["none", "groove", "spin"]
const PREVIEW_SCALE_DIVISOR := 4.0
const CALCULATED_SPRITE_HEIGHT := 2000.0
const HIT_SLOT_ROW_SCENE := preload("res://scenes/skin/editor/hit_slot_row.tscn")

@export var name_line_edit: LineEdit
@export var idle_option: OptionButton
@export var left_option: OptionButton
@export var right_option: OptionButton
@export var scale_spinbox: SpinBox
@export var hits_option: OptionButton
@export var hits_add_new_button: Button
@export var skin_contents: VBoxContainer

@export var new_animation_button: Button
@export var animation_list_container: VBoxContainer
@export var animation_template: Button

@export var frames_container: HBoxContainer
@export var frame_template: TextureRect
@export var delete_frame_button: Button
@export var calculate_scale_button: Button
@export var onion_skin_button: Button
@export var preview_play_button: Button
@export var fps_line_edit: LineEdit
@export var effect_option: OptionButton
@export var save_button: Button
@export var back_to_menu_button: Button
@export var back_to_chart_button: Button

@export var import_sprite_button: Button
@export var sprite_list_container: VBoxContainer
@export var sprite_template: VBoxContainer

@export var preview_sprite: Sprite2D
@export var preview_onion_prev: Sprite2D
@export var preview_onion_next: Sprite2D
@export var drag_preview: TextureRect
@export var import_dialog: FileDialog
@export var unsaved_exit_dialog: EditorUnsavedChangesDialog

var document = SkinDocument.new()
var _preview_time := 0.0
var _preview_playing := false
var _preview_replace_hovered := false
var _onion_enabled := false
var _hit_option_rows: Array[OptionButton] = []
var _syncing := false
var _pending_return_target := ""

func _ready() -> void:
	_configure_templates()
	_connect_dialogs()
	_configure_static_options()
	_connect_ui()
	_load_document()
	_refresh_all()

func _process(delta: float) -> void:
	_update_drag_preview()
	_update_preview_animation(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if unsaved_exit_dialog != null and unsaved_exit_dialog.visible:
			return
		_return_to_default_target()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_update_drag_feedback(get_global_mouse_position())
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag()

func _configure_templates() -> void:
	if animation_template != null:
		animation_template.visible = false
	if frame_template != null:
		frame_template.visible = false
	if sprite_template != null:
		sprite_template.visible = false

func _connect_dialogs() -> void:
	if import_dialog != null:
		import_dialog.files_selected.connect(_on_sprite_files_selected)
	if unsaved_exit_dialog != null:
		unsaved_exit_dialog.save_requested.connect(_on_unsaved_exit_save_requested)
		unsaved_exit_dialog.discard_requested.connect(_return_to_pending_target)

func _configure_static_options() -> void:
	if scale_spinbox != null:
		scale_spinbox.min_value = 0.000001
		scale_spinbox.max_value = 1000.0
		scale_spinbox.step = 0.000001
		scale_spinbox.allow_greater = true

	if effect_option != null:
		effect_option.clear()
		for effect_name in EFFECT_OPTIONS:
			effect_option.add_item(effect_name)

func _connect_ui() -> void:
	name_line_edit.text_changed.connect(_on_name_changed)
	idle_option.item_selected.connect(_on_idle_selected)
	left_option.item_selected.connect(_on_left_selected)
	right_option.item_selected.connect(_on_right_selected)
	scale_spinbox.value_changed.connect(_on_scale_changed)
	hits_option.item_selected.connect(_on_hit_slot_option_selected.bind(0))
	hits_add_new_button.pressed.connect(_on_add_hit_slot_pressed)
	new_animation_button.pressed.connect(_on_new_animation_pressed)
	delete_frame_button.pressed.connect(_on_delete_frame_pressed)
	calculate_scale_button.pressed.connect(_on_calculate_scale_pressed)
	onion_skin_button.pressed.connect(_on_toggle_onion_pressed)
	preview_play_button.toggled.connect(_on_preview_play_toggled)
	fps_line_edit.text_submitted.connect(_on_fps_submitted)
	fps_line_edit.focus_exited.connect(_on_fps_focus_exited)
	effect_option.item_selected.connect(_on_effect_selected)
	save_button.pressed.connect(_on_save_pressed)
	back_to_menu_button.pressed.connect(_return_to_menu)
	back_to_chart_button.pressed.connect(_return_to_chart)
	import_sprite_button.pressed.connect(_on_import_pressed)

func _load_document() -> void:
	var request = Game.skin_editor_request
	if request == null:
		request = SkinEditorContext.new()
		request.open_mode = SkinEditorContext.OpenMode.CUSTOM
		request.return_target = SkinEditorContext.ReturnTarget.MENU
		request.skin_file_path = SkinSerialization.ensure_custom_skin_path()
		request.previous_custom_skin_path = Config.custom_skin_path

	Game.skin_editor_request = null

	document = SkinDocument.new()
	document.context = request
	if request.skin_file_path == "":
		var target_directory = request.chart_folder_path
		if request.open_mode == SkinEditorContext.OpenMode.CHART and target_directory != "":
			target_directory = SkinSerialization.get_chart_skin_root_path(target_directory).path_join("new_skin")
		if target_directory == "":
			target_directory = ProjectSettings.globalize_path("user://skins")
		document.create_empty(request.open_mode, target_directory)
	else:
		if not document.load_from_file(request.skin_file_path, request.open_mode):
			return
		document.context = request
	if not document.skin_data.animations.is_empty():
		document.context.selected_animation_index = 0
		document.context.selected_frame_index = 0
	_update_back_buttons()

func _update_back_buttons() -> void:
	var return_target = document.context.return_target
	back_to_menu_button.visible = return_target == SkinEditorContext.ReturnTarget.MENU
	back_to_chart_button.visible = return_target == SkinEditorContext.ReturnTarget.EDITOR

func _refresh_all() -> void:
	_syncing = true
	_refresh_metadata_ui()
	_rebuild_hit_slot_rows()
	_rebuild_animation_list()
	_rebuild_frame_list()
	_rebuild_sprite_list()
	_apply_preview_scale()
	_refresh_preview()
	_syncing = false
	UIFocusUtils.disable_focus_recursive(self)

func _refresh_metadata_ui() -> void:
	name_line_edit.text = document.skin_data.skin_name
	scale_spinbox.value = document.skin_data.scale if document.skin_data != null else 1.0
	_populate_animation_option(idle_option, false, document.skin_data.idle)
	_populate_animation_option(left_option, true, document.skin_data.left)
	_populate_animation_option(right_option, true, document.skin_data.right)
	_populate_animation_option(hits_option, false, _get_hit_animation(0))

	var selected_animation = document.get_selected_animation()
	fps_line_edit.text = str(selected_animation.fps) if selected_animation != null else ""
	_select_effect_option(selected_animation.effect if selected_animation != null else "none")
	onion_skin_button.text = "toggle onion skin (%s)" % ("on" if _onion_enabled else "off")
	_update_preview_play_button(selected_animation)

func _populate_animation_option(option_button: OptionButton, allow_none: bool, selected_animation) -> void:
	if option_button == null:
		return
	option_button.clear()
	if allow_none:
		option_button.add_item("None", -1)
	for animation in document.skin_data.animations:
		if animation == null:
			continue
		option_button.add_item(_get_animation_option_label(animation), int(animation.id))

	var selected_id := int(selected_animation.id) if selected_animation != null else -1
	var index := option_button.get_item_index(selected_id)
	if index == -1:
		index = 0 if option_button.item_count > 0 else -1
	if index >= 0:
		option_button.select(index)

func _get_animation_option_label(animation) -> String:
	return "%d: %s" % [int(animation.id), animation.name]

func _select_effect_option(effect_name: String) -> void:
	if effect_option == null:
		return
	var index := 0
	for item_index in range(effect_option.item_count):
		if effect_option.get_item_text(item_index) == effect_name:
			index = item_index
			break
	effect_option.select(index)

func _rebuild_hit_slot_rows() -> void:
	for option_button in _hit_option_rows:
		if option_button != null and is_instance_valid(option_button):
			var parent = option_button.get_parent()
			if parent != null:
				parent.queue_free()
	_hit_option_rows.clear()

	_populate_animation_option(hits_option, false, _get_hit_animation(0))

	for hit_index in range(1, document.skin_data.hits.size()):
		var row := HIT_SLOT_ROW_SCENE.instantiate() as SkinHitSlotRow
		skin_contents.add_child(row)
		skin_contents.move_child(row, hits_add_new_button.get_index())
		row.setup("hit %d" % (hit_index + 1))
		row.option_selected.connect(_on_hit_slot_option_selected.bind(hit_index))
		row.remove_requested.connect(_on_remove_hit_slot_pressed.bind(hit_index))
		_populate_animation_option(row.option_button, false, _get_hit_animation(hit_index))
		_hit_option_rows.append(row.option_button)

func _get_hit_animation(hit_index: int):
	if hit_index < 0 or hit_index >= document.skin_data.hits.size():
		return null
	return document.skin_data.hits[hit_index]

func _rebuild_animation_list() -> void:
	for child in animation_list_container.get_children():
		if child != animation_template:
			child.queue_free()

	for index in range(document.skin_data.animations.size()):
		var animation = document.skin_data.animations[index]
		var item = animation_template.duplicate()
		item.visible = true
		item.selected.connect(_on_animation_selected)
		item.name_changed.connect(_on_animation_name_changed)
		item.remove_requested.connect(_on_animation_remove_requested)
		item.setup(animation, index, index == document.context.selected_animation_index)
		animation_list_container.add_child(item)

func _rebuild_frame_list() -> void:
	for child in frames_container.get_children():
		if child != frame_template:
			child.queue_free()

	var animation = document.get_selected_animation()
	if animation == null:
		return

	var frame_count = animation.frames.size()
	if frame_count == 0:
		document.context.selected_frame_index = -1
		return
	document.context.selected_frame_index = clampi(document.context.selected_frame_index, 0, frame_count - 1)

	for index in range(frame_count):
		var item = frame_template.duplicate()
		item.visible = true
		item.selected.connect(_on_frame_selected)
		item.drag_started.connect(_on_frame_drag_started)
		item.hovered.connect(_on_frame_hovered)
		item.released.connect(_on_frame_released)
		var is_drop_target := false
		var drop_after := false
		if document.context.drag_kind == SkinEditorContext.DragKind.SPRITE:
			is_drop_target = document.context.drag_reorder_target_index == index
			drop_after = document.context.drag_reorder_target_index == frame_count and index == frame_count - 1
			if drop_after:
				is_drop_target = true
		item.setup(animation.frames[index], index, index == document.context.selected_frame_index, is_drop_target, drop_after)
		frames_container.add_child(item)

func _rebuild_sprite_list() -> void:
	for child in sprite_list_container.get_children():
		if child != sprite_template:
			child.queue_free()

	for file_name in document.get_sprite_file_names():
		var item = sprite_template.duplicate()
		item.visible = true
		item.pressed.connect(_on_sprite_pressed)
		item.drag_started.connect(_on_sprite_drag_started)
		item.setup(file_name, document.skin_data.load_texture(file_name), file_name == document.context.selected_sprite_file_name)
		sprite_list_container.add_child(item)

func _refresh_preview() -> void:
	var animation = document.get_selected_animation()
	if animation == null or animation.frames.is_empty():
		preview_sprite.texture = null
		preview_onion_prev.texture = null
		preview_onion_next.texture = null
		preview_onion_prev.visible = false
		preview_onion_next.visible = false
		_preview_playing = false
		_update_preview_play_button(null)
		_update_preview_drop_state()
		return

	var selected_frame_index := clampi(document.context.selected_frame_index, 0, animation.frames.size() - 1)
	var frame_index := _get_preview_frame_index(animation)
	preview_sprite.texture = animation.frames[frame_index]
	_update_preview_drop_state()

	if not _onion_enabled:
		preview_onion_prev.visible = false
		preview_onion_next.visible = false
		return

	preview_onion_prev.visible = selected_frame_index > 0
	preview_onion_next.visible = selected_frame_index < animation.frames.size() - 1
	preview_onion_prev.texture = animation.frames[selected_frame_index - 1] if selected_frame_index > 0 else null
	preview_onion_next.texture = animation.frames[selected_frame_index + 1] if selected_frame_index < animation.frames.size() - 1 else null

func _get_preview_frame_index(animation) -> int:
	if animation == null or animation.frames.is_empty():
		return -1
	if animation.fps <= 0.0:
		return clampi(document.context.selected_frame_index, 0, animation.frames.size() - 1)
	var animation_length = max(1.0 / animation.fps, animation.total_time)
	var wrapped_time := fmod(_preview_time, animation_length)
	return clampi(animation.get_index(wrapped_time), 0, animation.frames.size() - 1)

func _update_preview_animation(delta: float) -> void:
	var animation = document.get_selected_animation()
	if animation == null or animation.frames.is_empty():
		return
	if not _preview_playing:
		return
	if animation.fps <= 0.0:
		return
	_preview_time += delta
	_refresh_preview()

func _apply_preview_scale() -> void:
	var scale_value = document.skin_data.scale if document.skin_data != null else 1.0
	if scale_value <= 0.0:
		scale_value = 1.0
	var scale_vector = Vector2.ONE * scale_value / PREVIEW_SCALE_DIVISOR
	preview_sprite.scale = scale_vector
	preview_onion_prev.scale = scale_vector
	preview_onion_next.scale = scale_vector

func _on_name_changed(value: String) -> void:
	if _syncing:
		return
	document.skin_data.skin_name = value
	document.mark_dirty()

func _on_idle_selected(index: int) -> void:
	if _syncing:
		return
	document.skin_data.idle = _get_animation_from_option(idle_option, index)
	if document.skin_data.idle == null and not document.skin_data.animations.is_empty():
		document.skin_data.idle = document.skin_data.animations[0]
	document.mark_dirty()

func _on_left_selected(index: int) -> void:
	if _syncing:
		return
	document.skin_data.left = _get_animation_from_option(left_option, index)
	document.mark_dirty()

func _on_right_selected(index: int) -> void:
	if _syncing:
		return
	document.skin_data.right = _get_animation_from_option(right_option, index)
	document.mark_dirty()

func _on_scale_changed(value: float) -> void:
	if _syncing:
		return
	document.skin_data.scale = value
	document.mark_dirty()
	_apply_preview_scale()

func _on_hit_slot_option_selected(index: int, hit_slot_index: int) -> void:
	if _syncing:
		return
	var option_button := hits_option if hit_slot_index == 0 else _hit_option_rows[hit_slot_index - 1]
	while document.skin_data.hits.size() <= hit_slot_index:
		document.skin_data.hits.append(document.skin_data.idle)
	document.skin_data.hits[hit_slot_index] = _get_animation_from_option(option_button, index)
	document.mark_dirty()

func _on_add_hit_slot_pressed() -> void:
	var default_animation = document.get_selected_animation()
	if default_animation == null:
		default_animation = document.skin_data.idle
	if default_animation == null:
		return
	document.skin_data.hits.append(default_animation)
	document.mark_dirty()
	_refresh_all()

func _on_remove_hit_slot_pressed(hit_slot_index: int) -> void:
	if hit_slot_index < 0 or hit_slot_index >= document.skin_data.hits.size():
		return
	document.skin_data.hits.remove_at(hit_slot_index)
	document.mark_dirty()
	_refresh_all()

func _on_new_animation_pressed() -> void:
	var animation := PlayerAnimation.new()
	animation.id = document.get_next_animation_id()
	animation.name = "new animation"
	animation.fps = 10.0
	animation.effect = "none"
	animation.return_idle = true

	var sprite_files := document.get_sprite_file_names()
	if not sprite_files.is_empty():
		var file_name := sprite_files[0]
		animation.frames_file_name.append(file_name)
		var texture = document.skin_data.load_texture(file_name)
		if texture != null:
			animation.frames.append(texture)

	document.skin_data.animations.append(animation)
	document.context.selected_animation_index = document.skin_data.animations.size() - 1
	document.context.selected_frame_index = 0 if not animation.frames.is_empty() else -1
	if document.skin_data.idle == null:
		document.skin_data.idle = animation
	document.mark_dirty()
	_set_preview_playing(false)
	_preview_time = 0.0
	_refresh_all()

func _on_animation_selected(index: int) -> void:
	document.context.selected_animation_index = index
	var animation = document.get_selected_animation()
	document.context.selected_frame_index = 0 if animation != null and not animation.frames.is_empty() else -1
	_set_preview_playing(false)
	_preview_time = 0.0
	_refresh_all()

func _on_animation_name_changed(index: int, value: String) -> void:
	if index < 0 or index >= document.skin_data.animations.size():
		return
	document.skin_data.animations[index].name = value
	document.mark_dirty()

func _on_animation_remove_requested(index: int) -> void:
	if index < 0 or index >= document.skin_data.animations.size():
		return
	var removed = document.skin_data.animations[index]
	document.skin_data.animations.remove_at(index)
	var next_hits: Array[PlayerAnimation] = []
	for animation in document.skin_data.hits:
		if animation != removed:
			next_hits.append(animation)
	document.skin_data.hits = next_hits
	if document.skin_data.idle == removed:
		document.skin_data.idle = document.skin_data.animations[0] if not document.skin_data.animations.is_empty() else null
	if document.skin_data.left == removed:
		document.skin_data.left = null
	if document.skin_data.right == removed:
		document.skin_data.right = null
	if document.skin_data.jump == removed:
		document.skin_data.jump = document.skin_data.idle
	if document.skin_data.land == removed:
		document.skin_data.land = document.skin_data.idle

	document.context.selected_animation_index = clampi(document.context.selected_animation_index, 0, document.skin_data.animations.size() - 1)
	if document.skin_data.animations.is_empty():
		document.context.selected_animation_index = -1
		document.context.selected_frame_index = -1
	document.mark_dirty()
	_refresh_all()

func _on_frame_selected(index: int) -> void:
	document.context.selected_frame_index = index
	var animation = document.get_selected_animation()
	if animation != null and animation.fps > 0.0:
		_preview_time = float(index) / animation.fps
	_refresh_all()

func _on_frame_drag_started(index: int) -> void:
	document.context.drag_kind = SkinEditorContext.DragKind.FRAME
	document.context.drag_frame_index = index
	document.context.drag_reorder_target_index = index
	_update_drag_feedback(get_global_mouse_position())

func _on_frame_hovered(index: int) -> void:
	if document.context.drag_kind != SkinEditorContext.DragKind.FRAME:
		return
	document.context.drag_reorder_target_index = index

func _on_frame_released(index: int) -> void:
	if document.context.drag_kind == SkinEditorContext.DragKind.FRAME:
		document.context.drag_reorder_target_index = index

func _move_selected_frame(from_index: int, to_index: int) -> void:
	var animation = document.get_selected_animation()
	if animation == null:
		return
	if from_index < 0 or from_index >= animation.frames.size():
		return
	if to_index < 0 or to_index >= animation.frames.size():
		return

	var moved_texture = animation.frames[from_index]
	var moved_file_name = animation.frames_file_name[from_index]
	animation.frames.remove_at(from_index)
	animation.frames_file_name.remove_at(from_index)
	animation.frames.insert(to_index, moved_texture)
	animation.frames_file_name.insert(to_index, moved_file_name)

	document.context.drag_frame_index = to_index
	document.context.selected_frame_index = to_index
	document.mark_dirty()
	_rebuild_frame_list()
	_refresh_preview()

func _replace_frame_sprite(frame_index: int, sprite_file_name: String) -> void:
	var animation = document.get_selected_animation()
	if animation == null:
		return
	if frame_index < 0 or frame_index >= animation.frames.size():
		return
	var texture = document.skin_data.load_texture(sprite_file_name)
	if texture == null:
		return
	animation.frames[frame_index] = texture
	animation.frames_file_name[frame_index] = sprite_file_name
	document.context.selected_frame_index = frame_index
	document.context.selected_sprite_file_name = sprite_file_name
	document.mark_dirty()
	_rebuild_frame_list()
	_rebuild_sprite_list()
	_refresh_preview()

func _insert_frame_sprite(insert_index: int, sprite_file_name: String) -> void:
	var animation = document.get_selected_animation()
	if animation == null:
		return
	var texture = document.skin_data.load_texture(sprite_file_name)
	if texture == null:
		return
	var target_index := clampi(insert_index, 0, animation.frames.size())
	animation.frames.insert(target_index, texture)
	animation.frames_file_name.insert(target_index, sprite_file_name)
	document.context.selected_frame_index = target_index
	document.context.selected_sprite_file_name = sprite_file_name
	document.mark_dirty()
	_rebuild_frame_list()
	_rebuild_sprite_list()
	_refresh_preview()

func _on_delete_frame_pressed() -> void:
	var animation = document.get_selected_animation()
	if animation == null or animation.frames.is_empty():
		return
	var index := clampi(document.context.selected_frame_index, 0, animation.frames.size() - 1)
	animation.frames.remove_at(index)
	animation.frames_file_name.remove_at(index)
	if animation.frames.is_empty():
		document.context.selected_frame_index = -1
	else:
		document.context.selected_frame_index = clampi(index, 0, animation.frames.size() - 1)
	document.mark_dirty()
	_refresh_all()

func _on_calculate_scale_pressed() -> void:
	var animation = document.get_selected_animation()
	if animation == null or animation.frames.is_empty():
		return
	var selected_frame_index := clampi(document.context.selected_frame_index, 0, animation.frames.size() - 1)
	var selected_texture: Texture2D = animation.frames[selected_frame_index]
	if selected_texture == null:
		return
	var texture_height := selected_texture.get_height()
	if texture_height <= 0:
		return
	document.skin_data.scale = CALCULATED_SPRITE_HEIGHT / float(texture_height)
	document.mark_dirty()
	_refresh_all()

func _on_toggle_onion_pressed() -> void:
	_onion_enabled = not _onion_enabled
	_refresh_metadata_ui()
	_refresh_preview()

func _on_fps_submitted(value: String) -> void:
	_commit_fps_text(value)

func _on_fps_focus_exited() -> void:
	_commit_fps_text(fps_line_edit.text)

func _commit_fps_text(value: String) -> void:
	if _syncing:
		return
	var animation = document.get_selected_animation()
	if animation == null:
		return
	var next_fps := maxf(0.1, value.to_float())
	if is_equal_approx(animation.fps, next_fps):
		return
	animation.fps = next_fps
	document.mark_dirty()
	_preview_time = 0.0
	_refresh_preview()

func _on_effect_selected(index: int) -> void:
	if _syncing:
		return
	var animation = document.get_selected_animation()
	if animation == null:
		return
	animation.effect = effect_option.get_item_text(index)
	document.mark_dirty()

func _on_import_pressed() -> void:
	if import_dialog != null:
		import_dialog.popup_centered_ratio(0.7)

func _on_sprite_files_selected(paths: PackedStringArray) -> void:
	var imported := SkinSerialization.import_sprite_files(document, paths)
	if imported.is_empty():
		return
	document.mark_dirty()
	if document.context.selected_sprite_file_name == "":
		document.context.selected_sprite_file_name = imported[0]
	_rebuild_sprite_list()

func _on_sprite_pressed(file_name: String) -> void:
	document.context.selected_sprite_file_name = file_name
	# Click-to-append is intentionally disabled for now; frame edits use drag/drop only.
	_rebuild_sprite_list()

func _on_sprite_drag_started(file_name: String) -> void:
	document.context.selected_sprite_file_name = file_name
	document.context.drag_kind = SkinEditorContext.DragKind.SPRITE
	document.context.drag_sprite_file_name = file_name
	document.context.drag_reorder_target_index = -1
	_show_drag_preview(document.skin_data.load_texture(file_name))
	_update_drag_feedback(get_global_mouse_position())
	_rebuild_sprite_list()

func _show_drag_preview(texture_value: Texture2D) -> void:
	if texture_value == null:
		return
	drag_preview.texture = texture_value
	drag_preview.visible = true
	_update_drag_preview()

func _hide_drag_preview() -> void:
	drag_preview.visible = false
	drag_preview.texture = null

func _update_drag_preview() -> void:
	if drag_preview == null or not drag_preview.visible:
		return
	drag_preview.global_position = get_global_mouse_position() + Vector2(18, 18)

func _get_animation_from_option(option_button: OptionButton, index: int):
	if option_button == null or index < 0:
		return null
	return document.skin_data.get_animation_via_id(option_button.get_item_id(index))

func _on_preview_play_toggled(toggled_on: bool) -> void:
	_set_preview_playing(toggled_on)

func _set_preview_playing(is_playing: bool) -> void:
	var animation = document.get_selected_animation()
	_preview_playing = is_playing and animation != null and not animation.frames.is_empty() and animation.fps > 0.0
	if _preview_playing and document.context.selected_frame_index >= 0:
		_preview_time = float(document.context.selected_frame_index) / animation.fps
	_refresh_preview()
	_update_preview_play_button(animation)

func _update_preview_play_button(animation) -> void:
	if preview_play_button == null:
		return
	var can_play = animation != null and not animation.frames.is_empty() and animation.fps > 0.0
	if not can_play:
		_preview_playing = false
	preview_play_button.disabled = not can_play
	preview_play_button.set_pressed_no_signal(_preview_playing)
	preview_play_button.text = "stop preview" if _preview_playing else "play preview"

func _update_preview_drop_state() -> void:
	preview_sprite.modulate = Color(0.7, 1.0, 0.75, 1.0) if _preview_replace_hovered else Color.WHITE

func _finish_drag() -> void:
	if document.context.drag_kind == SkinEditorContext.DragKind.NONE:
		return
	if document.context.drag_kind == SkinEditorContext.DragKind.SPRITE:
		if _preview_replace_hovered:
			_replace_frame_sprite(document.context.selected_frame_index, document.context.drag_sprite_file_name)
		elif document.context.drag_reorder_target_index >= 0:
			_insert_frame_sprite(document.context.drag_reorder_target_index, document.context.drag_sprite_file_name)
	document.context.clear_drag()
	document.context.drag_reorder_target_index = -1
	_preview_replace_hovered = false
	_hide_drag_preview()
	_update_preview_drop_state()
	_rebuild_frame_list()

func _update_drag_feedback(mouse_position: Vector2) -> void:
	if document.context.drag_kind == SkinEditorContext.DragKind.NONE:
		return
	if document.context.drag_kind == SkinEditorContext.DragKind.SPRITE:
		var next_replace_hovered := _is_mouse_over_preview(mouse_position)
		var next_drop_index := -1 if next_replace_hovered else _get_frame_drop_index(mouse_position)
		var changed = next_replace_hovered != _preview_replace_hovered or next_drop_index != document.context.drag_reorder_target_index
		_preview_replace_hovered = next_replace_hovered
		document.context.drag_reorder_target_index = next_drop_index
		if changed:
			_update_preview_drop_state()
			_rebuild_frame_list()
		return
	if document.context.drag_kind == SkinEditorContext.DragKind.FRAME:
		var drop_index := _get_frame_drop_index(mouse_position)
		if drop_index < 0:
			return
		document.context.drag_reorder_target_index = drop_index
		var from_index = document.context.drag_frame_index
		var target_index := drop_index
		if target_index > from_index:
			target_index -= 1
		if target_index != from_index:
			_move_selected_frame(from_index, target_index)

func _is_mouse_over_preview(mouse_position: Vector2) -> bool:
	var preview_rect := _get_preview_rect()
	return preview_rect.has_area() and preview_rect.has_point(mouse_position)

func _get_preview_rect() -> Rect2:
	if preview_sprite == null or preview_sprite.texture == null:
		return Rect2()
	var _size := preview_sprite.texture.get_size() * preview_sprite.scale.abs()
	return Rect2(preview_sprite.global_position - (_size * 0.5), _size)

func _get_frame_drop_index(mouse_position: Vector2) -> int:
	var animation = document.get_selected_animation()
	if animation == null:
		return -1
	var frames_scroll := frames_container.get_parent() as Control
	if frames_scroll == null:
		return -1
	var scroll_rect := frames_scroll.get_global_rect().grow(12.0)
	if not scroll_rect.has_point(mouse_position):
		return -1
	var frame_items := _get_frame_items()
	if frame_items.is_empty():
		return 0
	for item in frame_items:
		var rect = item.get_global_rect()
		if mouse_position.x <= rect.position.x + (rect.size.x * 0.5):
			return item.index
	return frame_items.size()

func _get_frame_items() -> Array:
	var items: Array = []
	for child in frames_container.get_children():
		if child != frame_template:
			items.append(child)
	return items

func _on_save_pressed() -> bool:
	if document.skin_data.animations.is_empty():
		return false
	SkinValidation.ensure_unique_animation_ids(document.skin_data)
	SkinValidation.cleanup_player_slots(document.skin_data)
	if document.skin_data.idle == null and not document.skin_data.animations.is_empty():
		document.skin_data.idle = document.skin_data.animations[0]
	if document.skin_data.idle == null:
		return false

	var old_path = document.file_path
	var old_reference_name = document.context.referenced_skin_file_name
	if document.context.open_mode == SkinEditorContext.OpenMode.CUSTOM:
		old_reference_name = old_path.get_file()
	elif old_reference_name == "" and old_path != "":
		old_reference_name = old_path.get_base_dir().get_file()
	var preferred_name = document.skin_data.skin_name.strip_edges()
	if preferred_name == "":
		if document.context.open_mode == SkinEditorContext.OpenMode.CHART:
			preferred_name = old_reference_name
		else:
			preferred_name = old_path.get_base_dir().get_file()
	preferred_name = preferred_name.validate_filename()
	if preferred_name == "":
		preferred_name = "skin"

	var target_path = old_path
	if document.context.open_mode == SkinEditorContext.OpenMode.CHART:
		var current_skin_name = document.directory_path.get_file()
		if old_path == "" or current_skin_name != preferred_name:
			target_path = SkinSerialization.make_unique_chart_skin_file_path(document.context.chart_folder_path, preferred_name)
	else:
		var current_skin_name = document.directory_path.get_file()
		if old_path == "" or old_path.get_file() != SkinSerialization.CHART_SKIN_JSON_NAME or current_skin_name != preferred_name:
			target_path = SkinSerialization.make_unique_skin_file_path(document.directory_path.get_base_dir(), preferred_name)

	var saved_path := SkinSerialization.save_skin_document(document, target_path)
	if saved_path == "":
		return false

	var saved_reference_name := saved_path.get_base_dir().get_file() if document.context.open_mode == SkinEditorContext.OpenMode.CHART else saved_path.get_file()
	if document.context.open_mode == SkinEditorContext.OpenMode.CUSTOM:
		Config.custom_skin_path = ProjectSettings.localize_path(saved_path.get_base_dir())
		Config.save_config()
	else:
		if document.context.chart_folder_path != "" and old_reference_name != "":
			SkinRefCleanup.rename_skin_references(document.context.chart_folder_path, old_reference_name, saved_reference_name)
		document.context.referenced_skin_file_name = saved_reference_name
		if CM.selected_chart != null and (CM.selected_chart.file_skin == old_reference_name or CM.selected_chart.file_skin == ""):
			CM.selected_chart.file_skin = saved_reference_name

	var valid_ids := SkinValidation.get_animation_ids(document.skin_data)
	if document.context.open_mode == SkinEditorContext.OpenMode.CHART and document.context.chart_folder_path != "":
		SkinRefCleanup.clear_invalid_animation_refs_for_skin(
			document.context.chart_folder_path,
			document.context.referenced_skin_file_name,
			valid_ids,
			CM.selected_chart
		)

	if old_path != saved_path:
		SkinSerialization.delete_obsolete_skin_path(old_path, saved_path)

	_refresh_all()
	return true

func _return_to_menu() -> void:
	if _has_unsaved_changes():
		_show_unsaved_exit_dialog("menu")
		return
	_return_to_menu_now()

func _return_to_chart() -> void:
	if _has_unsaved_changes():
		_show_unsaved_exit_dialog("chart")
		return
	_return_to_chart_now()

func _return_to_default_target() -> void:
	if document.context.return_target == SkinEditorContext.ReturnTarget.EDITOR:
		_return_to_chart()
	else:
		_return_to_menu()

func _return_to_menu_now() -> void:
	Game.reopen_editor_without_chart_reload = false
	Transition.return_to_menu(0.45)

func _return_to_chart_now() -> void:
	Game.reopen_editor_without_chart_reload = true
	Transition.transition_to(EDITOR_SCENE_PATH, 0.45)

func _has_unsaved_changes() -> bool:
	return document != null and document.dirty

func _show_unsaved_exit_dialog(return_target: String) -> void:
	_pending_return_target = return_target
	if unsaved_exit_dialog == null:
		_return_to_pending_target()
		return
	unsaved_exit_dialog.open(document != null and not document.skin_data.animations.is_empty())

func _on_unsaved_exit_save_requested() -> void:
	if _on_save_pressed():
		_return_to_pending_target()

func _return_to_pending_target() -> void:
	match _pending_return_target:
		"chart":
			_return_to_chart_now()
		_:
			_return_to_menu_now()
