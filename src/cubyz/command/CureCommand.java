package cubyz.command;

import cubyz.api.Resource;
import cubyz.world.entity.Player;

/**
 * Command to set player's health to its max health.
 */

public class CureCommand extends CommandBase {

	{
		name = "cure";
		expectedArgs = new String[0];
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "cure");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if (!(source instanceof Player)) {
			source.feedback("'cure' must be executed by a player");
			return;
		}
		Player player = (Player)source;
		player.health = player.maxHealth;
		player.hunger = player.maxHunger;
	}

}
