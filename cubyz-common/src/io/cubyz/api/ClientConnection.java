package io.cubyz.api;

import io.cubyz.items.Inventory;

/**
 * Used to send events like block placing or GUI opening to the client or processes them if already on the client.
 */

public interface ClientConnection {
	public void openGUI(String name, Inventory inv);
}
