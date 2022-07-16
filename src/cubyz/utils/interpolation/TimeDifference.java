package cubyz.utils.interpolation;

public class TimeDifference {
	public short difference = 0;
	private boolean firstValue = true;

	public void addDataPoint(short time) {
		short currentTime = (short)System.currentTimeMillis();
		short timeDifference = (short)(currentTime - time);
		if(firstValue) {
			difference = timeDifference;
			firstValue = false;
		}
		if((short)(timeDifference - difference) > 0) {
			difference++;
		} else if((short)(timeDifference -  difference) < 0) {
			difference--;
		}
	}

	public void reset() {
		difference = 0;
		firstValue = true;
	}
}
