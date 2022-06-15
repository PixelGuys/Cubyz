package cubyz.utils.interpolation;

import cubyz.utils.Logger;
import org.joml.Vector3d;
import org.joml.Vector3f;

public class EntityInterpolation {
	private final Vector3d[] lastPosition = new Vector3d[128];
	private final Vector3d[] lastVelocity = new Vector3d[128];
	private final short[] lastTimes = new short[128];
	private int frontIndex = 0;
	private int currentPoint = -1;
	public final Vector3f rotation;
	public final Vector3d position;
	public final Vector3d velocity = new Vector3d();

	public EntityInterpolation(Vector3d initialPosition, Vector3f initialRotation) {
		position = initialPosition;
		rotation = initialRotation;
	}

	public void updatePosition(Vector3d position, Vector3d velocity, Vector3f rotation, short time) {
		frontIndex = (frontIndex + 1)%lastPosition.length;
		lastPosition[frontIndex] = position;
		lastVelocity[frontIndex] = velocity;
		lastTimes[frontIndex] = time;
		this.rotation.set(rotation);
	}

	private static double[] evaluateSplineAt(double t, double tScale, double p0, double m0, double p1, double m1) {
		//  https://en.wikipedia.org/wiki/Cubic_Hermite_spline#Unit_interval_(0,_1)
		t /= tScale;
		m0 *= tScale;
		m1 *= tScale;
		double t2 = t*t;
		double t3 = t2*t;
		double a0 = p0;
		double a1 = m0;
		double a2 = -3*p0 - 2*m0 + 3*p1 - m1;
		double a3 = 2*p0 + m0 - 2*p1 + m1;
		return new double[] {
			a0 + a1*t + a2*t2 + a3*t3, // value
			(a1 + 2*a2*t + 3*a3*t2)*tScale, // first derivative
		};
	}

	public void update(short time, short lastTime) {

		if(currentPoint != -1 && (short)(lastTimes[currentPoint] - time) <= 0) {
			// Jump to the last used value and adjust the time to start at that point.
			lastTime = lastTimes[currentPoint];
			position.set(lastPosition[currentPoint]);
			velocity.set(lastVelocity[currentPoint]);
			currentPoint = -1;
		}

		double deltaTime = ((short)(time - lastTime))/1000.0;
		if(deltaTime < 0) {
			Logger.error("Experienced time travel. Current time: "+time+" Last time: "+lastTime);
			deltaTime = 0;
		}

		if(currentPoint == -1) {
			// Need a new point:
			short smallestTime = Short.MAX_VALUE;
			int smallestIndex = -1;
			for(int i = 0; i < lastTimes.length; i++) {
				if(lastVelocity[i] == null) continue;
				//                                 ↓ Only using a future time value that is far enough away to prevent jumping.
				if((short)(lastTimes[i] - time) >= 50 && (short)(lastTimes[i] - time) < smallestTime) {
					smallestTime = (short)(lastTimes[i] - time);
					smallestIndex = i;
				}
			}
			currentPoint = smallestIndex;
		}

		if(currentPoint == -1) {
			// Just move on with the current velocity.
			position.x += velocity.x*deltaTime;
			position.y += velocity.y*deltaTime;
			position.z += velocity.z*deltaTime;
			// Add some drag to prevent moving far away on short connection loss.
			velocity.x *= Math.pow(0.5, deltaTime);
			velocity.y *= Math.pow(0.5, deltaTime);
			velocity.z *= Math.pow(0.5, deltaTime);
		} else {
			// Interpolates using cubic splines.
			double tScale = ((short)(lastTimes[currentPoint] - lastTime))/1000.0;
			double t = ((short)(time - lastTime))/1000.0;
			double[] newX = evaluateSplineAt(t, tScale, position.x, velocity.x, lastPosition[currentPoint].x, lastVelocity[currentPoint].x);
			double[] newY = evaluateSplineAt(t, tScale, position.y, velocity.y, lastPosition[currentPoint].y, lastVelocity[currentPoint].y);
			double[] newZ = evaluateSplineAt(t, tScale, position.z, velocity.z, lastPosition[currentPoint].z, lastVelocity[currentPoint].z);
			position.set(newX[0], newY[0], newZ[0]);
			velocity.set(newX[1], newY[1], newZ[1]);
		}
	}
}
