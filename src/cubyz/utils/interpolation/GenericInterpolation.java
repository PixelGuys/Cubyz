package cubyz.utils.interpolation;

import cubyz.utils.Logger;

public class GenericInterpolation {
	private final double[][] lastPosition = new double[128][];
	private final double[][] lastVelocity = new double[128][];
	private final short[] lastTimes = new short[128];
	private int frontIndex = 0;
	private int currentPoint = -1;
	public double[] outPosition;
	public double[] outVelocity;

	public GenericInterpolation(double[] initialPosition) {
		outPosition = initialPosition;
		outVelocity = new double[initialPosition.length];
	}

	public GenericInterpolation(double[] initialPosition, double[] initialVelocity) {
		outPosition = initialPosition;
		outVelocity = initialVelocity;
	}

	public void updatePosition(double[] position, double[] velocity, short time) {
		assert position.length == velocity.length;
		frontIndex = (frontIndex + 1)%lastPosition.length;
		lastPosition[frontIndex] = position;
		lastVelocity[frontIndex] = velocity;
		lastTimes[frontIndex] = time;
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
			(a1 + 2*a2*t + 3*a3*t2)/tScale, // first derivative
		};
	}

	public void update(short time, short lastTime) {
		if(currentPoint != -1 && (short)(lastTimes[currentPoint] - time) <= 0) {
			// Jump to the last used value and adjust the time to start at that point.
			lastTime = lastTimes[currentPoint];
			int length = Math.min(lastPosition[currentPoint].length, outPosition.length);
			System.arraycopy(outPosition, 0, lastPosition[currentPoint], 0, length);
			System.arraycopy(outVelocity, 0, lastVelocity[currentPoint], 0, length);
			currentPoint = -1;
		}

		double deltaTime = ((short)(time - lastTime))/1000.0;
		if(deltaTime < 0) {
			Logger.error("Experienced time travel. Current time: " + time + " Last time: " + lastTime);
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
			for(int i = 0; i < outPosition.length; i++) {
				// Just move on with the current velocity.
				outPosition[i] += outVelocity[i]*deltaTime;
				// Add some drag to prevent moving far away on short connection loss.
				outVelocity[i] *= Math.pow(0.5, deltaTime);
			}
		} else {
			double tScale = ((short)(lastTimes[currentPoint] - lastTime))/1000.0;
			double t = ((short)(time - lastTime))/1000.0;
			for(int i = 0; i < Math.min(lastPosition[currentPoint].length, outPosition.length); i++) {
				if(outVelocity[i] == 0 && lastVelocity[currentPoint][i] == 0) {
					// Use linear interpolation when velocity is zero to avoid wobbly movement.
					outPosition[i] += (lastPosition[currentPoint][i] - outPosition[i])*t/tScale;
				} else {
					// Use cubic interpolation to interpolate the velocity as well.
					double[] newValue = evaluateSplineAt(t, tScale, outPosition[i], outVelocity[i], lastPosition[currentPoint][i], lastVelocity[currentPoint][i]);
					// Just move on with the current velocity.
					outPosition[i] = newValue[0];
					// Add some drag to prevent moving far away on short connection loss.
					outVelocity[i] = newValue[1];
				}
			}
		}
	}
}
