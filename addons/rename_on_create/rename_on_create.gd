@tool
extends EditorPlugin

## Puts a node into rename mode in the Scene dock right after it is created
## with the "Create New Node" dialog (godot-proposals#2850).
##
## A node counts as newly created only when, in the same call stack, the Scene
## dock emits `node_created` AND its Create New Node dialog emits `create`:
## - paste, duplicate and opening a scene never emit `node_created`;
## - instancing a scene and redoing "Create Node" (Godot 4.4+) do emit it,
##   but never go through the dialog;
## - "Change Type" goes through the dialog but never emits `node_created`.
## The two signals may arrive in either order, so both just record what they
## saw and a deferred `_resolve()` decides.

## How many frames to wait for the Scene dock to show and select the new node.
const MAX_WAIT_FRAMES := 60

enum { WAIT, READY, ABORT }

var _dock: Node = null # SceneTreeDock (an editor class not exposed to scripts).
var _create_dialog: Node = null # The dock's CreateDialog ("Create New Node").
var _scene_tree: Tree = null # The Tree inside the dock's SceneTreeEditor.

var _created_node_id := 0
var _dialog_confirmed := false
var _resolve_queued := false

var _pending_node_id := 0
var _frames_left := 0


func _enter_tree() -> void:
	set_process(false)
	_dock = _find_scene_tree_dock()
	if _dock:
		_create_dialog = _find_create_dialog(_dock)
		_scene_tree = _find_scene_tree(_dock)
	if not (_dock and _create_dialog and _scene_tree):
		push_warning("Rename on Create: could not find the Scene dock's Create New Node dialog or tree. The plugin does nothing in this Godot version.")
		_dock = null
		_create_dialog = null
		_scene_tree = null
		return
	_dock.connect("node_created", _on_node_created)
	_create_dialog.connect("create", _on_create_dialog_create)


func _exit_tree() -> void:
	set_process(false)
	_pending_node_id = 0
	if is_instance_valid(_dock) and _dock.is_connected("node_created", _on_node_created):
		_dock.disconnect("node_created", _on_node_created)
	if is_instance_valid(_create_dialog) and _create_dialog.is_connected("create", _on_create_dialog_create):
		_create_dialog.disconnect("create", _on_create_dialog_create)
	_dock = null
	_create_dialog = null
	_scene_tree = null


func _process(_delta: float) -> void:
	if _step():
		set_process(false)


func _on_node_created(node: Node) -> void:
	_created_node_id = node.get_instance_id()
	_queue_resolve()


func _on_create_dialog_create() -> void:
	_dialog_confirmed = true
	_queue_resolve()


func _queue_resolve() -> void:
	if _resolve_queued:
		return
	_resolve_queued = true
	_resolve.call_deferred()


func _resolve() -> void:
	var node_id := _created_node_id
	var confirmed := _dialog_confirmed
	_created_node_id = 0
	_dialog_confirmed = false
	_resolve_queued = false
	if node_id == 0 or not confirmed:
		return
	var node := instance_from_id(node_id) as Node
	if node == null or not node.scene_file_path.is_empty():
		return # Freed, or an instanced scene rather than a new node.
	_pending_node_id = node_id
	_frames_left = MAX_WAIT_FRAMES
	if not _step():
		set_process(true)


## Tries to start renaming the pending node.
## Returns true when there is nothing left to wait for.
func _step() -> bool:
	if _pending_node_id == 0:
		return true
	var node := instance_from_id(_pending_node_id) as Node
	var state := _rename_state(node)
	if state == WAIT and _frames_left > 0:
		_frames_left -= 1
		return false
	_pending_node_id = 0
	if state == READY:
		# Same calls as the Scene dock's own Rename command (F2).
		if not _scene_tree.has_focus():
			_scene_tree.grab_focus()
		_scene_tree.edit_selected()
	return true


func _rename_state(node: Node) -> int:
	if node == null or not node.is_inside_tree() or not is_instance_valid(_scene_tree):
		return ABORT
	var selection := EditorInterface.get_selection().get_selected_nodes()
	if selection.size() != 1 or selection[0] != node:
		return ABORT # Something else is selected, e.g. after "Reparent to New Node".
	if not _scene_tree.is_visible_in_tree():
		# Up to Godot 4.6 the dock swaps its "Create Root Node" view for the tree
		# one frame after a root is created. If the dock tab is hidden instead,
		# this simply runs out of frames, like the built-in Rename doing nothing.
		return WAIT
	var item := _scene_tree.get_selected()
	if item == null or item.get_metadata(0) != node.get_path():
		return WAIT # The dock rebuilds its tree a little later.
	if not _is_item_shown(item):
		return WAIT
	return READY


func _is_item_shown(item: TreeItem) -> bool:
	var parent := item.get_parent()
	while parent:
		if parent.collapsed:
			return false
		parent = parent.get_parent()
	return true


func _find_scene_tree_dock() -> Node:
	for dock in get_tree().root.find_children("*", "SceneTreeDock", true, false):
		if dock.has_signal("node_created"):
			return dock
	return null


func _find_create_dialog(dock: Node) -> Node:
	for dialog in dock.find_children("*", "CreateDialog", false, false):
		if dialog.has_signal("create"):
			return dialog
	return null


func _find_scene_tree(dock: Node) -> Tree:
	for editor in dock.find_children("*", "SceneTreeEditor", true, false):
		if _has_window_between(editor, dock):
			continue # e.g. the tree inside the Reparent dialog.
		for child in editor.get_children():
			if child is Tree:
				return child
	return null


func _has_window_between(node: Node, ancestor: Node) -> bool:
	var parent := node.get_parent()
	while parent and parent != ancestor:
		if parent is Window:
			return true
		parent = parent.get_parent()
	return false
