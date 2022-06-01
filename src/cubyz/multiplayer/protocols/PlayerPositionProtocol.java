package cubyz.multiplayer.protocols;

import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.server.Server;
import cubyz.server.User;
import cubyz.utils.math.Bits;
import cubyz.world.entity.Player;
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
		assert length == 48 : "Invalid length for player position data.";
		Player player = ((User)conn).player;
		player.setPosition(new Vector3d(
			Bits.getDouble(data, offset),
			Bits.getDouble(data, offset+8),
			Bits.getDouble(data, offset+16)
		));
		player.vx = Bits.getDouble(data, offset+24);
		player.vy = Bits.getDouble(data, offset+32);
		player.vz = Bits.getDouble(data, offset+40);
	}

	public void send(UDPConnection conn, Player player) {
		byte[] data = new byte[48];
		Vector3d pos = player.getPosition();
		Bits.putDouble(data, 0, pos.x);
		Bits.putDouble(data, 8, pos.y);
		Bits.putDouble(data, 16, pos.z);
		Bits.putDouble(data, 24, player.vx);
		Bits.putDouble(data, 32, player.vy);
		Bits.putDouble(data, 40, player.vz);
		conn.send(this, data);
	}
}
