package io.cubyz.command;

import org.joml.Vector3f;

import io.cubyz.api.Resource;
import io.cubyz.entity.Player;

public class TPCommand extends CommandBase {

	{
		name = "tp";
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "tp");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if(args.length < 3) {
			source.feedback("Usage: tp <x> <y> <z>");
			return;
		}
		if (!(source instanceof Player)) {
			source.feedback("'clear' must be executed by a player");
			return;
		}
		Player player = (Player)source;
		player.setPosition(new Vector3f(Float.parseFloat(args[1]), Float.parseFloat(args[2]), Float.parseFloat(args[3])));
	}
}
