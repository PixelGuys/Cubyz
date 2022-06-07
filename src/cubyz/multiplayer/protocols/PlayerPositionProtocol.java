package cubyz.multiplayer.protocols;

import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.rendering.Camera;
import cubyz.multiplayer.server.User;
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
		assert length == 60 : "Invalid length for player position data.";
		Player player = ((User)conn).player;
		player.setPosition(new Vector3d(
			Bits.getDouble(data, offset),
			Bits.getDouble(data, offset+8),
			Bits.getDouble(data, offset+16)
		));
		player.vx = Bits.getDouble(data, offset+24);
		player.vy = Bits.getDouble(data, offset+32);
		player.vz = Bits.getDouble(data, offset+40);
		player.getRotation().x = Bits.getFloat(data, offset+48);
		player.getRotation().y = Bits.getFloat(data, offset+52);
		player.getRotation().z = Bits.getFloat(data, offset+56);
	}

	public void send(UDPConnection conn, Player player) {
		byte[] data = new byte[60];
		Vector3d pos = player.getPosition();
		Bits.putDouble(data, 0, pos.x);
		Bits.putDouble(data, 8, pos.y);
		Bits.putDouble(data, 16, pos.z);
		Bits.putDouble(data, 24, player.vx);
		Bits.putDouble(data, 32, player.vy);
		Bits.putDouble(data, 40, player.vz);
		Bits.putFloat(data, 48, Camera.getRotation().x);
		Bits.putFloat(data, 52, Camera.getRotation().y);
		Bits.putFloat(data, 56, Camera.getRotation().z);
		conn.send(this, data);
	}
}
