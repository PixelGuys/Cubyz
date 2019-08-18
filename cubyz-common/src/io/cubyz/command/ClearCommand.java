package io.cubyz.command;

import io.cubyz.api.Resource;
import io.cubyz.entity.Player;
import io.cubyz.items.Inventory;

public class ClearCommand extends CommandBase {

	{
		name = "clear";
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "clear");
	}

	@Override public void setID(int ID) {}

	@Override
	public void commandExecute(ICommandSource source, String[] args) {
		if (source.getWorld() == null) {
			source.feedback("'give' must be executed by a player");
			return;
		}
		Player local = source.getWorld().getLocalPlayer();
		Inventory inv = local.getInventory();
		for (int i = 0; i < 36; i++) {
			if (inv.getAmount(i) != 0) {
				// TODO remove item
			}
		}
	}

}
