package io.cubyz.command;

import io.cubyz.api.Resource;
import io.cubyz.entity.Player;

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
		Player player = source.getWorld().getLocalPlayer();
		player.health = player.maxHealth;
		player.hunger = player.maxHunger;
	}

}
