package io.cubyz.ui;

// This class represents a GUI that can be created via a mod.
// An example for such a GUI is the inventory GUI.

public abstract class ModGUI extends MenuGUI {	
	public abstract void close(); // What should happen when the GUI is closed?
}
