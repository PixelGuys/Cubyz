package cubyz.multiplayer.protocols;

import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.client.ServerConnection;
import cubyz.multiplayer.server.User;
import cubyz.utils.math.Bits;

/**
 * Send the players render distance to the server.
 */
public class RenderDistanceProtocol extends Protocol {
	public RenderDistanceProtocol() {
		super((byte)9, true);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		int renderDistance = Bits.getInt(data, offset);
		float LODFactor = Bits.getFloat(data, offset+4);
		if(conn instanceof User) {
			User user = (User)conn;
			user.renderDistance = renderDistance;
			user.LODFactor = LODFactor;
		}
	}

	public void send(ServerConnection conn, int renderDistance, float LODFactor) {
		byte[] data = new byte[8];
		Bits.putInt(data, 0, renderDistance);
		Bits.putFloat(data, 4, LODFactor);
		conn.send(this, data);
	}
}
