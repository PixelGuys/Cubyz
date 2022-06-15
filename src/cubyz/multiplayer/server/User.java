package cubyz.multiplayer.server;

import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.utils.Logger;
import cubyz.utils.interpolation.EntityInterpolation;
import cubyz.utils.interpolation.TimeDifference;
import cubyz.utils.math.Bits;
import cubyz.world.entity.Player;
import org.joml.Vector3d;
import org.joml.Vector3f;

/*
*   A User
* */
public class User extends UDPConnection {
	public Player player;
	private final TimeDifference difference = new TimeDifference();
	private final EntityInterpolation interpolation = new EntityInterpolation(new Vector3d(), new Vector3f());
	private short lastTime;
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

	@Override
	public void disconnect() {
		super.disconnect();
		Server.disconnect(this);
	}

	public void update() {
		short time = (short)(System.currentTimeMillis() - 200);
		time -= difference.difference;
		interpolation.update(time, lastTime);
		player.getPosition().set(interpolation.position);
		player.vx = interpolation.velocity.x;
		player.vy = interpolation.velocity.y;
		player.vz = interpolation.velocity.z;
		player.getRotation().set(interpolation.rotation);
		lastTime = time;
	}

	public void receiveData(byte[] data, int offset) {
		Vector3d position = new Vector3d(
			Bits.getDouble(data, offset),
			Bits.getDouble(data, offset + 8),
			Bits.getDouble(data, offset + 16)
		);
		Vector3d velocity = new Vector3d(
			Bits.getDouble(data, offset + 24),
			Bits.getDouble(data, offset + 32),
			Bits.getDouble(data, offset + 40)
		);
		Vector3f rotation = new Vector3f(
			Bits.getFloat(data, offset + 48),
			Bits.getFloat(data, offset + 52),
			Bits.getFloat(data, offset + 56)
		);
		short time = Bits.getShort(data, offset + 60);
		difference.addDataPoint(time);
		interpolation.updatePosition(position, velocity, rotation, time);
	}
}
