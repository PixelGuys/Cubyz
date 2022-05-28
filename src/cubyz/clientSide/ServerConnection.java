package cubyz.clientSide;

import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.UDPConnectionManager;
import pixelguys.json.JsonObject;

public class ServerConnection extends UDPConnection {
	public JsonObject handShakeResult; // TODO: Find a cleaner way to do this.
	public ServerConnection(UDPConnectionManager manager, String ip, int receivePort, String name){
		super(manager, ip, receivePort);
	}
	
	public JsonObject doHandShake(String name) {
		Protocols.HANDSHAKE.clientSide(this, name);
		return handShakeResult;
	}
}
