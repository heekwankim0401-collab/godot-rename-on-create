@tool
extends EditorPlugin

# Test runner for Rename on Create. NOT part of the add-on; do not ship it.
#
# Drives a real editor session through create / paste / duplicate / instance /
# undo-redo / change type / reparent / new-root scenarios and checks whether the
# Scene dock enters rename mode. It sends synthetic key events, does not save
# any scene, and quits the editor when done.
#
# It only runs when the RT_OUT environment variable is set (path of the results
# file); otherwise it does nothing. RT_SHOTS (optional) is a folder for
# screenshots. RT_SKIP11=1 skips the last step, which turns the add-on off and on
# again. See the README section "Automated editor test".

## Give up, write what we have and quit after this many seconds.
const WATCHDOG_SECONDS := 420.0

var _lines := PackedStringArray()
var _fails := 0
var _finished := false
var _dock: Node
var _ste: Node
var _tree: Tree


func _enter_tree() -> void:
	if OS.get_environment("RT_OUT").is_empty():
		return
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_run.call_deferred()


func _on_watchdog() -> void:
	if _finished:
		return
	_fails += 1
	_log("FAIL  watchdog: the run did not finish (a step probably hit a script error)")
	_finish()


func _log(s: String) -> void:
	print("[RT] ", s)
	_lines.append(s)


func _check(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails += 1
	_log(("PASS  " if cond else "FAIL  ") + label + ("" if detail.is_empty() else "   [" + detail + "]"))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _send_key(window: Window, keycode: Key, ctrl := false, shift := false, unicode := 0) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		ev.unicode = unicode if pressed else 0
		ev.window_id = window.get_window_id()
		Input.parse_input_event(ev)
		await _frames(2)


func _type_text(window: Window, text: String) -> void:
	for ch in text:
		var upper := ch.to_upper()
		await _send_key(window, OS.find_keycode_from_string(upper), false, ch == upper and ch != ch.to_lower(), ch.unicode_at(0))


func _main() -> Window:
	return get_tree().root


func _rename_line_edit() -> LineEdit:
	for c in _tree.get_children(true):
		if c is Popup:
			for le in c.find_children("*", "LineEdit", true, false):
				return le
	return null


func _is_renaming() -> bool:
	var le := _rename_line_edit()
	if le == null:
		return false
	var popup := le.get_window()
	return popup.visible and le.visible and le.has_focus()


# Presses Esc in a rename box left open, so one failed step does not break the
# keyboard shortcuts used by the next ones.
func _close_rename_if_open() -> void:
	if _is_renaming():
		await _send_key(_rename_line_edit().get_window(), KEY_ESCAPE)
		await _frames(6)


# Renaming, and the name box holds the expected default name of the new node
# (so a rename left open by an earlier step does not count).
func _is_renaming_text(expected: String) -> bool:
	return _is_renaming() and _rename_line_edit().text == expected


func _rename_info() -> String:
	var le := _rename_line_edit()
	if le == null:
		return "no line edit"
	var popup := le.get_window()
	return "popup.visible=%s embedded=%s le.focus=%s text='%s' sel='%s' os_focus(main=%s popup=%s)" % [popup.visible, popup.is_embedded(), le.has_focus(), le.text, le.get_selected_text(), _main().has_focus(), popup.has_focus()]


func _create_dialog() -> Window:
	for d in _dock.find_children("*", "CreateDialog", false, false):
		return d
	return null


func _select(nodes: Array) -> void:
	var sel := EditorInterface.get_selection()
	sel.clear()
	for n in nodes:
		sel.add_node(n)
	await _frames(6)
	_tree.grab_focus()
	await _frames(2)


func _confirm_dialog(type_name: String) -> bool:
	var dialog := _create_dialog()
	await _frames(6)
	if dialog == null or not dialog.visible:
		_check("create dialog opened", false)
		return false
	var search = dialog.gui_get_focus_owner()
	if not (search is LineEdit):
		_log("      dialog focus owner is not a LineEdit: " + str(search))
		return false
	search.text = type_name
	search.text_changed.emit(type_name)
	await _frames(10)
	await _send_key(dialog, KEY_ENTER)
	await _frames(20)
	return true


func _create_via_dialog(type_name: String) -> bool:
	_tree.grab_focus()
	await _frames(2)
	await _send_key(_main(), KEY_A, true)
	return await _confirm_dialog(type_name)


# Opens the Scene dock context menu and picks the item with the given editor
# icon. Tool IDs differ between Godot versions; the icons do not.
func _context_tool(icon_name: String) -> void:
	_ste.emit_signal("rmb_pressed", _tree.get_screen_position() + Vector2(40, 40))
	await _frames(4)
	var icon := EditorInterface.get_editor_theme().get_icon(icon_name, "EditorIcons")
	for m in _dock.find_children("*", "PopupMenu", false, false):
		if not m.visible:
			continue
		for i in m.item_count:
			if m.get_item_icon(i) == icon:
				var id: int = m.get_item_id(i)
				m.hide()
				m.id_pressed.emit(id)
				return
		m.hide()
	_check("context menu item '%s' found" % icon_name, false)


func _shot(label: String) -> void:
	var dir := OS.get_environment("RT_SHOTS")
	if dir.is_empty():
		return
	_main().get_texture().get_image().save_png(dir.path_join(label + "_main.png"))
	var le := _rename_line_edit()
	if le and le.get_window().visible and not le.get_window().is_embedded():
		le.get_window().get_texture().get_image().save_png(dir.path_join(label + "_popup.png"))


# Finds a visible "Create Root Node" button by its editor icon (UI may be localized).
func _root_button(icon_name: String) -> Button:
	var icon := EditorInterface.get_editor_theme().get_icon(icon_name, "EditorIcons")
	for b in _dock.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.icon == icon and not b.text.is_empty():
			return b
	return null


func _names(n: Node) -> String:
	var out := PackedStringArray()
	for c in n.get_children():
		out.append("%s:%s" % [c.name, c.get_class()])
	return ", ".join(out)


func _run() -> void:
	await _frames(120)
	_dock = get_tree().root.find_children("*", "SceneTreeDock", true, false)[0]
	for e in _dock.find_children("*", "SceneTreeEditor", true, false):
		var p: Node = e.get_parent()
		var in_window := false
		while p and p != _dock:
			if p is Window:
				in_window = true
			p = p.get_parent()
		if not in_window:
			_ste = e
			break
	for c in _ste.get_children():
		if c is Tree:
			_tree = c
	_log("Godot %s, single_window=%s" % [Engine.get_version_info().string, get_tree().root.gui_embed_subwindows])
	_check("plugin connected to node_created", _dock.get_signal_connection_list("node_created").size() > 0)

	# 0. Opening a scene.
	EditorInterface.open_scene_from_path("res://test/main.tscn")
	await _frames(40)
	var root := EditorInterface.get_edited_scene_root()
	_check("0 open scene: no rename", root != null and root.name == "Main" and not _is_renaming(), _rename_info())

	# 1. Create via dialog, type a name.
	await _select([root])
	await _create_via_dialog("Sprite2D")
	_check("1 create: rename editor opened", _is_renaming_text("Sprite2D"), _rename_info())
	var le := _rename_line_edit()
	_check("1 create: default name selected", le != null and le.text == "Sprite2D" and le.get_selected_text() == "Sprite2D", _rename_info())
	_shot("01_create")
	if le and _is_renaming():
		await _type_text(le.get_window(), "Player")
		await _send_key(le.get_window(), KEY_ENTER)
		await _frames(10)
	_check("1 create: typed name applied", root.has_node("Player") and not _is_renaming(), _names(root))

	# 2. Create via dialog, Esc keeps default name.
	await _select([root])
	await _create_via_dialog("Node2D")
	_check("2 create: rename editor opened", _is_renaming_text("Node2D"), _rename_info())
	le = _rename_line_edit()
	if le and _is_renaming():
		await _send_key(le.get_window(), KEY_ESCAPE)
		await _frames(10)
	_check("2 esc: default name kept, editor closed", root.has_node("Node2D") and not _is_renaming(), _names(root))

	# 3. Duplicate.
	var existing := root.get_node("Existing")
	await _select([existing])
	var before := root.get_child_count()
	await _send_key(_main(), KEY_D, true)
	await _frames(20)
	_check("3 duplicate: no rename", root.get_child_count() == before + 1 and not _is_renaming(), _names(root) + " | " + _rename_info())

	# 4. Copy + paste.
	await _select([existing])
	await _send_key(_main(), KEY_C, true)
	await _frames(4)
	await _send_key(_main(), KEY_V, true)
	await _frames(20)
	_check("4 paste: no rename", existing.get_child_count() == 1 and not _is_renaming(), _names(existing) + " | " + _rename_info())

	# 5. Instantiate a scene.
	await _select([root])
	before = root.get_child_count()
	_dock.call("instantiate", "res://test/instance_me.tscn")
	await _frames(20)
	_check("5 instantiate: no rename", root.has_node("InstanceMe") and not _is_renaming(), _names(root) + " | " + _rename_info())

	# 6. Undo / redo of Create Node.
	await _select([root])
	await _create_via_dialog("Node3D")
	le = _rename_line_edit()
	if le and _is_renaming():
		await _send_key(le.get_window(), KEY_ESCAPE)
		await _frames(6)
	var had_it := root.has_node("Node3D")
	_tree.grab_focus()
	await _send_key(_main(), KEY_Z, true)
	await _frames(15)
	var undone := not root.has_node("Node3D")
	await _send_key(_main(), KEY_Z, true, true)
	await _frames(25)
	_check("6 undo/redo create: no rename on redo", had_it and undone and root.has_node("Node3D") and not _is_renaming(), "had=%s undone=%s redone=%s %s" % [had_it, undone, root.has_node("Node3D"), _rename_info()])

	# 7. Change Type.
	await _select([existing])
	await _context_tool("Reload") # Change Type
	await _confirm_dialog("Marker2D")
	var changed := root.get_node_or_null("Existing")
	_check("7 change type: no rename", changed != null and changed.get_class() == "Marker2D" and not _is_renaming(), _names(root) + " | " + _rename_info())

	# 8. Reparent to New Node.
	var player := root.get_node_or_null("Player")
	if player == null:
		_check("8 reparent to new node: skipped, 'Player' missing (step 1 failed)", false)
	else:
		await _select([player])
		await _context_tool("ReparentToNewNode")
		await _confirm_dialog("Node2D")
		await _frames(70)
		var new_parent := player.get_parent()
		var info := "parent=%s %s" % [new_parent.name, _rename_info()]
		if Engine.get_version_info().hex >= 0x040400:
			# 4.4+ selects the moved nodes afterwards, so nothing is renamed.
			_check("8 reparent to new node: no rename", new_parent != root and not _is_renaming(), info)
		else:
			# 4.2-4.3 leave the new parent selected, so it is renamed.
			_check("8 reparent to new node (4.2-4.3): new parent renamed", new_parent != root and _is_renaming_text(str(new_parent.name)), info)
	await _close_rename_if_open()

	# 9. New scene, "Other Node" root via dialog.
	await _send_key(_main(), KEY_N, true)
	await _frames(30)
	var other: Button = _root_button("Add")
	var button_2d: Button = null
	_check("9 new scene: empty", EditorInterface.get_edited_scene_root() == null and other != null)
	if other:
		other.pressed.emit()
		await _confirm_dialog("Node3D")
		_check("9 other node root: rename editor opened", _is_renaming_text("Node3D"), _rename_info())
		_shot("09_other_node_root")
		le = _rename_line_edit()
		if le and _is_renaming():
			await _type_text(le.get_window(), "World")
			await _send_key(le.get_window(), KEY_ENTER)
			await _frames(10)
		var r := EditorInterface.get_edited_scene_root()
		_check("9 other node root: typed name applied", r != null and r.name == "World", str(r.name if r else "null"))

	# 10. New scene, "2D Scene" button (documented as not covered).
	await _close_rename_if_open()
	await _send_key(_main(), KEY_N, true)
	await _frames(30)
	button_2d = _root_button("Node2D")
	_check("10 new scene: 2D Scene button found", button_2d != null)
	if button_2d:
		button_2d.pressed.emit()
		await _frames(30)
		_check("10 2D Scene button: no rename (documented limit)", EditorInterface.get_edited_scene_root() != null and not _is_renaming(), _rename_info())

	# 11. Disable / re-enable the plugin.
	if not OS.get_environment("RT_SKIP11").is_empty():
		_finish()
		return
	await _close_rename_if_open()
	EditorInterface.set_plugin_enabled("rename_on_create", false)
	await _frames(10)
	EditorInterface.open_scene_from_path("res://test/main.tscn")
	await _frames(20)
	root = EditorInterface.get_edited_scene_root()
	await _select([root])
	await _create_via_dialog("Node")
	_check("11 plugin disabled: no rename", not _is_renaming(), _rename_info())
	le = _rename_line_edit()
	EditorInterface.set_plugin_enabled("rename_on_create", true)
	await _frames(10)
	await _select([root])
	await _create_via_dialog("Timer")
	_check("11 plugin re-enabled: rename editor opened", _is_renaming_text("Timer"), _rename_info())
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_log("RESULT: %d failure(s)" % _fails)
	var f := FileAccess.open(OS.get_environment("RT_OUT"), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	await _frames(5)
	get_tree().quit()
