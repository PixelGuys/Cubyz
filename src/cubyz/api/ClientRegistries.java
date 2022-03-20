package cubyz.api;

import cubyz.gui.MenuGUI;

/**
 * Stores all Registries that are only relevant for the client.
 */

public final class ClientRegistries {
	private ClientRegistries () {} // No instances allowed.

	public static final Registry<MenuGUI> GUIS = new Registry<MenuGUI>();
}
