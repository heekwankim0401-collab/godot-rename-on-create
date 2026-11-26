# Rename on Create

When you create a node with the **Create New Node** dialog, the Scene dock opens
the new node's name for editing right away. Type the name, then press
<kbd>Enter</kbd>. <kbd>Esc</kbd> keeps the default name.

Enable it in **Project > Project Settings > Plugins**. Requires Godot 4.2 or later.

It does not act on paste, duplicate, scene instancing, undo/redo, Change Type,
Reparent to New Node (Godot 4.4+), or the 2D Scene / 3D Scene / User Interface
root buttons.
While the name box is open, <kbd>Ctrl+A</kbd> selects the text instead of opening
Create New Node again.

Full documentation, known limitations and a Korean version:
https://github.com/heekwankim0401-collab/godot-rename-on-create

MIT License. See `LICENSE` in this folder.
