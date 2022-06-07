package cubyz.command;

import cubyz.Constants;
import cubyz.api.Resource;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.Logger;

import java.util.Arrays;

public class InviteCommand extends CommandBase {

	{
		name = "invite";
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
			String[] ipPort = args[1].split(":");
			String ip;
			int port;
			Logger.info(Arrays.toString(ipPort));
			if(ipPort.length == 1) {
				ip = ipPort[0];
				port = Constants.DEFAULT_PORT;
			} else if(ipPort.length == 2) {
				ip = ipPort[0];
				port = Integer.parseInt(ipPort[1]);
			} else {
				return;
			}
			new Thread(() -> {
				try {
					Server.users.add(new User(Server.connectionManager, ip, port));
				} catch(Exception e) {
					Logger.error(e);
				}
			}).start();
		}
	}

}
