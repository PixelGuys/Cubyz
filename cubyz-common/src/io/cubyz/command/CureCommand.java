package io.cubyz.command;

import io.cubyz.api.Resource;

/**
 * Command to set player's health to its max health.
 */
public class CureCommand extends CommandBase {

	{
		name = "cure";
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "cure");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if (source.getWorld() == null) {
			source.feedback("'cure' must be executed by a player");
			return;
		}
		source.getWorld().getLocalPlayer().health = source.getWorld().getLocalPlayer().maxHealth;
	}

}
