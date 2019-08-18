package io.cubyz.math;

/**
 * 64-bits number with more precise decimal arithmetic.
 */
public class FloatingInteger extends Number {

	private static final long serialVersionUID = 6305609879087404987L;
	
	private int num;
	private float rel;
	
	public FloatingInteger() {
		
	}
	
	public FloatingInteger(int num, float rel) {
		this.num = num;
		this.rel = rel;
	}
	
	@Override
	public double doubleValue() {
		return num + rel;
	}

	@Override
	public float floatValue() {
		return num + rel;
	}

	@Override
	public int intValue() {
		return num;
	}

	@Override
	public long longValue() {
		return num;
	}
	
	public float getDecimal() {
		return rel;
	}
	
	public int getInteger() {
		return num;
	}
	
	public void add(float arg) {
		rel += arg;
		int floor = (int) Math.floor(rel);
		if(floor != 0) {
			num += floor;
			rel -= floor;
		}
	}
	
	public void mul(int arg) {
		num *= arg;
		rel *= arg;
		int floor = (int) Math.floor(rel);
		if (floor != 0) {
			num += floor;
			rel -= floor;
		}
	}
	
	public void sub(float arg) {
		add(-arg);
	}

}
