package cubyz.command;

import cubyz.api.Resource;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.Logger;

public class InviteCommand extends CommandBase {

	{
		name = "/invite";
		expectedArgs = new String[1];
		expectedArgs[0] = "ip:port";
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "invite");
	}

	@Override
	public void commandExecute(CommandSource source, String[] args) {
		if(Server.world != null && args.length == 2) {
			new Thread(() -> {
				try {
					Server.connect(new User(Server.connectionManager, args[1]));
				} catch(Exception e) {
					Logger.error(e);
				}
			}).start();
		}
	}

}
