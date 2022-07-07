package cubyz.multiplayer.client;

import cubyz.client.Cubyz;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.world.ClientWorld;
import cubyz.world.World;
import pixelguys.json.JsonObject;

public class ServerConnection extends UDPConnection {
	public final ClientWorld world;
	public ServerConnection(UDPConnectionManager manager, ClientWorld world, String ip, int remotePort) {
		super(manager, ip, remotePort);
		this.world = world;
	}
	
	public void doHandShake(String name) {
		Protocols.HANDSHAKE.clientSide(this, name);
	}

	@Override
	public void disconnect() {
		if(!disconnected) {
			super.disconnect();
			Cubyz.world.cleanup();
		}
	}
}
