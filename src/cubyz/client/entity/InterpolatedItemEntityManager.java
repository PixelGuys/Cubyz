package cubyz.client.entity;

import cubyz.utils.interpolation.GenericInterpolation;
import cubyz.utils.interpolation.TimeDifference;
import cubyz.utils.math.Bits;
import cubyz.world.World;
import cubyz.world.entity.ItemEntityManager;
import cubyz.world.items.ItemStack;

public class InterpolatedItemEntityManager extends ItemEntityManager {
	private final GenericInterpolation interpolation = new GenericInterpolation(super.posxyz, super.velxyz);
	private short lastTime = (short)System.currentTimeMillis();
	private final TimeDifference timeDifference = new TimeDifference();

	public InterpolatedItemEntityManager(World world, int minCapacity) {
		super(world, minCapacity);
	}

	public void readPosition(byte[] data, int offset, int length, short time) {
		assert length%(6*8) == 0 : "length must be a multiple of 6*8";
		timeDifference.addDataPoint(time);
		double[] pos = new double[length];
		double[] vel = new double[length];
		length += offset;
		int i = 0;
		while(offset < length) {
			pos[3*i] = Bits.getDouble(data, offset);
			offset += 8;
			pos[3*i+1] = Bits.getDouble(data, offset);
			offset += 8;
			pos[3*i+2] = Bits.getDouble(data, offset);
			offset += 8;
			vel[3*i] = Bits.getDouble(data, offset);
			offset += 8;
			vel[3*i+1] = Bits.getDouble(data, offset);
			offset += 8;
			vel[3*i+2] = Bits.getDouble(data, offset);
			offset += 8;
			i++;
		}
		interpolation.updatePosition(pos, vel, time);
	}

	@Override
	public void update(float deltaTime) {
		throw new IllegalArgumentException();
	}

	public void updateInterpolationData() {
		short time = (short)(System.currentTimeMillis() - 200);
		time -= timeDifference.difference;
		interpolation.update(time, lastTime);
		lastTime = time;
	}

	@Override
	public void add(double x, double y, double z, double vx, double vy, double vz, float rotX, float rotY, float rotZ, ItemStack itemStack, int despawnTime, int pickupCooldown) {
		synchronized(this) {
			super.add(x, y, z, vx, vy, vz, rotX, rotY, rotZ, itemStack, despawnTime, pickupCooldown);
			interpolation.outVelocity = velxyz;
			interpolation.outPosition = posxyz;
		}
	}
}
