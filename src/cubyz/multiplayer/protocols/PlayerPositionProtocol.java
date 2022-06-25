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
		assert length == 62 : "Invalid length for player position data.";
		((User)conn).receiveData(data, offset);
	}

	private short lastPositionSent = 0;

	public void send(UDPConnection conn, Player player, short time) {
		if(time - lastPositionSent < 50 && time - lastPositionSent >= 0) {
			return; // Only send at most once every 50 ms.
		}
		lastPositionSent = time;
		byte[] data = new byte[62];
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
		Bits.putShort(data, 60, time);
		conn.send(this, data);
	}
}
