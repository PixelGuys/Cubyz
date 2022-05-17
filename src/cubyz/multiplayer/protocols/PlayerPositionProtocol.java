package cubyz.multiplayer.protocols;

import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.server.Server;
import cubyz.utils.math.Bits;
import org.joml.Vector3d;

/**
 * Continuously sends the player position to the server.
 */
public class PlayerPositionProtocol extends Protocol {
	public PlayerPositionProtocol() {
		super((byte)4, false);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		assert length == 24 : "Invalid length for player position data.";
		Server.world.player.setPosition(new Vector3d(
			Bits.getDouble(data, offset),
			Bits.getDouble(data, offset+8),
			Bits.getDouble(data, offset+16)
		));
	}

	public void send(UDPConnection conn, Vector3d pos) {
		byte[] data = new byte[24];
		Bits.putDouble(data, 0, pos.x);
		Bits.putDouble(data, 8, pos.y);
		Bits.putDouble(data, 16, pos.z);
		conn.send(this, data);
	}
}
