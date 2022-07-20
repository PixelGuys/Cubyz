package cubyz.multiplayer.server;

import cubyz.Constants;
import cubyz.command.CommandSource;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.utils.interpolation.GenericInterpolation;
import cubyz.utils.interpolation.TimeDifference;
import cubyz.utils.math.Bits;
import cubyz.world.entity.Player;
import org.joml.Vector3f;

/*
*   A User
* */
public class User extends UDPConnection implements CommandSource {
	public Player player;
	private final TimeDifference difference = new TimeDifference();
	private final GenericInterpolation interpolation = new GenericInterpolation(new double[3]);
	private short lastTime;
	public String name;
	public int renderDistance;
	public float LODFactor;
	public boolean receivedFirstEntityData = false;
	public final String ipPort;

	public Thread waitingThread;

	public User(UDPConnectionManager manager, String ipPort) throws InterruptedException {
		super(manager, ipPort);
		this.ipPort = ipPort;
		Protocols.HANDSHAKE.serverSide(this);
		synchronized(this) {
			waitingThread = Thread.currentThread();
			this.wait();
			waitingThread = null;
		}
	}

	@Override
	public void disconnect() {
		super.disconnect();
		Server.disconnect(this);
	}

	public void initPlayer(String name) {
		this.name = name;
		assert(player == null);
		player = Server.world.findPlayer(this);
		interpolation.outPosition[0] = player.getPosition().x;
		interpolation.outPosition[1] = player.getPosition().y;
		interpolation.outPosition[2] = player.getPosition().z;
		interpolation.outVelocity[0] = player.vx;
		interpolation.outVelocity[1] = player.vy;
		interpolation.outVelocity[2] = player.vz;
	}

	public void update() {
		short time = (short)(System.currentTimeMillis() - Constants.ENTITY_LOOKBACK);
		time -= difference.difference;
		interpolation.update(time, lastTime);
		player.getPosition().x = interpolation.outPosition[0];
		player.getPosition().y = interpolation.outPosition[1];
		player.getPosition().z = interpolation.outPosition[2];
		player.vx = interpolation.outVelocity[0];
		player.vy = interpolation.outVelocity[1];
		player.vz = interpolation.outVelocity[2];
		lastTime = time;
	}

	public void receiveData(byte[] data, int offset) {
		double[] position = new double[] {
			Bits.getDouble(data, offset),
			Bits.getDouble(data, offset + 8),
			Bits.getDouble(data, offset + 16)
		};
		double[] velocity = new double[]{
			Bits.getDouble(data, offset + 24),
			Bits.getDouble(data, offset + 32),
			Bits.getDouble(data, offset + 40)
		};
		Vector3f rotation = new Vector3f(
			Bits.getFloat(data, offset + 48),
			Bits.getFloat(data, offset + 52),
			Bits.getFloat(data, offset + 56)
		);
		player.getRotation().set(rotation);
		short time = Bits.getShort(data, offset + 60);
		difference.addDataPoint(time);
		interpolation.updatePosition(position, velocity, time);
	}

	@Override
	public void feedback(String feedback) {
		Protocols.CHAT.send(this, "#ffff00"+feedback);
	}
}
