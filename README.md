English | [한국어](README.ko.md)

# Rename on Create

A small Godot 4 editor plugin. When you create a node with the **Create New Node**
dialog, the Scene dock opens the new node's name for editing right away. You
can type the name at once, with no <kbd>F2</kbd> or <kbd>Enter</kbd> first.

This implements [godot-proposals#2850](https://github.com/godotengine/godot-proposals/issues/2850)
("Automatically select rename when creating a new node") as an add-on. The proposal
was closed in favour of [godot#49521](https://github.com/godotengine/godot/pull/49521)
plus the existing <kbd>Enter</kbd>/<kbd>F2</kbd> shortcut. Several people in that
thread asked for the automatic behaviour as an opt-in. Installing this plugin is that opt-in.

## Installation

1. Copy the `addons/rename_on_create/` folder into your project's `addons/` folder.
2. Open **Project > Project Settings > Plugins** and enable **Rename on Create**.

Requires **Godot 4.2 or later**, because the plugin uses the `EditorInterface` singleton.
See [Compatibility](#compatibility) for which versions have actually been tested.

## Behaviour

The plugin acts when the Create New Node dialog creates a node. You can open that
dialog with <kbd>Ctrl+A</kbd>, the **+** button, **Add Child Node...** in the
context menu, or **Other Node** on an empty scene. After you confirm:

- The new node is selected in the Scene dock (the editor already does this) and
  its name opens in the inline editor with all of the text selected.
- Type to replace the name and press <kbd>Enter</kbd> to confirm.
- <kbd>Esc</kbd> keeps the default name. Clicking somewhere else in the editor
  confirms whatever is in the box. If you typed nothing, that is the default name.

The rename itself is the editor's normal rename, the same one that
<kbd>F2</kbd> starts, so undo/redo and name validation work as usual.

It does **not** act on any of these:

| Action | Why it is skipped |
| --- | --- |
| Paste, duplicate | Not a new node from the dialog |
| Instantiate child scene, drag a `.tscn` in | Comes from a scene file, not the dialog |
| Opening or switching scenes | Nothing is created |
| Undo / redo of "Create Node" | No dialog involved |
| Change Type | Replaces an existing node |
| Reparent to New Node | Selection goes back to the moved nodes (see limitations) |
| **2D Scene / 3D Scene / User Interface** root buttons | These buttons do not use the dialog |

## Known limitations

- **<kbd>Ctrl+A</kbd> right after creating a node.** While the name box is open,
  <kbd>Ctrl+A</kbd> selects the text, as in any text field. It does not open Create
  New Node again. If you usually press <kbd>Ctrl+A</kbd> several times in a row,
  press <kbd>Enter</kbd> or <kbd>Esc</kbd> before each one. This was the main
  objection in the proposal thread.
- **Root quick buttons are not covered.** The 2D Scene, 3D Scene and User Interface
  buttons (and favourites shown there) make the root without the dialog, so the
  plugin cannot tell them apart from other root changes. After one of them, press
  <kbd>F2</kbd> or <kbd>Enter</kbd>. Since godot#49521 the Scene dock already has focus.
  **Other Node** does use the dialog, so it is covered.
- **Reparent to New Node is not covered.** It uses the same dialog, but the editor
  selects the reparented nodes afterwards, not the new parent. The plugin only
  renames a new node that is the one selected node.
- **No per-user switch.** To stop the behaviour, disable the plugin in Project Settings.
- **Scene dock must be visible.** If another dock tab is in front of it, nothing
  happens. The built-in rename has the same rule.
- **Uses editor internals.** Godot has no public API for this. The plugin finds the
  Scene dock (`SceneTreeDock`) and its `node_created` signal, the dock's
  `CreateDialog` and its `create` signal, and the `Tree` inside the dock's
  `SceneTreeEditor`. These are internal and may change in a future Godot version.
  If the plugin cannot find them, it prints a warning and does nothing.

## How it works

- A node counts as newly created only when two things happen in the same call
  stack: the Scene dock emits `node_created`, and the dock's Create New Node
  dialog emits `create`. Either one alone is not enough:
  - Instancing a scene emits `node_created`, and so does redo in Godot 4.4+.
    Neither goes through the dialog.
  - Change Type emits `create`, but no `node_created`.
  - Paste, duplicate and opening a scene emit neither.
- The two signals can arrive in either order. Each one records what it saw, and
  one deferred check decides.
- The plugin then waits a few frames for the dock to rebuild its tree. When the
  new node is the one selected item, it calls `Tree.grab_focus()` and
  `Tree.edit_selected()`, the same calls as the dock's own Rename command.

## Compatibility

- **Tested in a running editor:** Godot 4.7.2 stable (official build) on Windows 11.
  It was tested in both the default multi-window mode and single-window mode,
  using the automated test below: 20 checks, all passing.
  - In multi-window mode, the rename box's own window had OS keyboard focus
    after each create, so real typing goes there.
  - The test runner sent the key presses itself. Nobody typed them on a
    physical keyboard.
- **Source-checked only:** Godot 4.2, 4.3, 4.4, 4.5 and 4.6 have the same signals
  and dock structure, but nobody has run the plugin in those versions yet.

## Test project

This folder is itself a small Godot project with the plugin already enabled.
Open the folder in Godot 4 and open `test/main.tscn`.

1. Press <kbd>Ctrl+A</kbd>, pick a node and press <kbd>Enter</kbd>. The name editor
   should open.
2. Try paste, duplicate (<kbd>Ctrl+D</kbd>), instancing `test/instance_me.tscn`, and
   undo/redo. The name editor should not open for any of them.

### Automated editor test

`addons/rename_on_create_test/` holds a separate editor plugin that drives the
editor through all the cases in the [Behaviour](#behaviour) table. It is **not**
part of the add-on, so don't copy it into your own project. It is disabled by default.

1. Enable **Rename on Create test runner** in Project Settings > Plugins. It does
   nothing in a normal editor session.
2. From this folder, start the editor with `RT_OUT` set, using the `_console`
   build so you can see the output:

   ```powershell
   $env:RT_OUT = "$PWD\test_results.txt"; & "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" -e --path .
   ```

The editor opens, runs the checks without saving any scene, writes
`test_results.txt` and quits. If a step breaks, a watchdog still writes the
results and quits after 7 minutes. Add `--single-window` to the command to test
single-window mode.

Keep in mind:

- The runner sends key events to the editor windows directly. It does not go
  through the real keyboard. Each result line records whether the editor windows
  had OS focus.
- Like any editor session, the run creates `.godot/`. It also re-saves
  `project.godot`, because it turns the add-on off and on again.
- The runner uses some internal editor IDs from Godot 4.7.2, so it may need
  adjusting for other versions.

## License

MIT. See [LICENSE](LICENSE).
