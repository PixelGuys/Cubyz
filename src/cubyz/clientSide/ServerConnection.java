package cubyz.clientSide;

import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnection;
import pixelguys.json.JsonObject;

public class ServerConnection extends UDPConnection {
	public JsonObject handShakeResult; // TODO: Find a cleaner way to do this.
	public ServerConnection(String ip, int sendPort, int receivePort, String name){
		super(ip, sendPort, receivePort);
	}
	
	public JsonObject doHandShake(String name) {
		Protocols.HANDSHAKE.clientSide(this, name);
		return handShakeResult;
	}
}
