package cubyz.command;

import org.joml.Vector3d;

import cubyz.api.Resource;
import cubyz.world.entity.Player;

public class TPCommand extends CommandBase {

	{
		name = "tp";
		expectedArgs = new String[3];
		expectedArgs[0] = "<x>";
		expectedArgs[1] = "<y>";
		expectedArgs[2] = "<z>";
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "tp");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if (args.length < 4) {
			source.feedback("Usage: tp <x> <y> <z>");
			return;
		}
		if (!(source instanceof Player)) {
			source.feedback("'tp' must be executed by a player");
			return;
		}
		Player player = (Player)source;
		player.setPosition(new Vector3d(Double.parseDouble(args[1]), Double.parseDouble(args[2]), Double.parseDouble(args[3])));
	}
}
