package io.cubyz.math;

/**
 * 128-bits number with more precise decimal arithmetic.
 */
public class DoubleFloatingLong extends Number {

	private static final long serialVersionUID = 6305609879087404987L;
	
	private long num;
	private double rel;
	
	@Override
	public double doubleValue() {
		return num + rel;
	}

	@Override
	public float floatValue() {
		return num + (float) rel;
	}

	@Override
	public int intValue() {
		return (int) num;
	}

	@Override
	public long longValue() {
		return num;
	}
	
	public double getDecimal() {
		return rel;
	}
	
	public long getInteger() {
		return num;
	}
	
	public void add(double arg) {
		rel += arg;
		long floor = (long) Math.floor(rel);
		if (floor != 0) {
			num += floor;
			rel -= floor;
		}
	}
	
	public void mul(long arg) {
		num *= arg;
		rel *= arg;
		long floor = (long) Math.floor(rel);
		if (floor != 0) {
			num += floor;
			rel -= floor;
		}
	}
	
	public void sub(double arg) {
		add(-arg);
	}

}
