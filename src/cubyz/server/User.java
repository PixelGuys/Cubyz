package cubyz.server;

import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.utils.Logger;
import cubyz.world.entity.Player;

/*
*   A User
* */
public class User extends UDPConnection {
	public Player player;
	public String name;

	public User(UDPConnectionManager manager, String ip, int remotePort) {
		super(manager, ip, remotePort);
		Protocols.HANDSHAKE.serverSide(this);
		try {
			synchronized(this) {
				this.wait();
			}
		} catch(InterruptedException e) {
			Logger.error(e);
		}
	}
}
