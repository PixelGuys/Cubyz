package io.cubyz.ndt;

import static io.cubyz.CubyzLogger.logger;

/**
 * NDT (Named Data Tag)
 * @author zenith391
 */
@Deprecated
public class NDTTag {

	protected byte type;
	protected byte[] content;
	protected int expectedLength;
	
	public byte getType() {
		return type;
	}
	
	public boolean validate() {
		return content.length == expectedLength;
	}
	
	public void setBytes(byte[] bytes) {
		content = bytes;
	}
	
	public void setByte(int index, byte b) {
		content[index] = b;
	}
	
	public byte[] getData() {
		return content;
	}
	
	public static NDTTag fromBytes(byte[] bytes) {
		byte[] tagBytes = NDTContainer.subArray(1, bytes.length, bytes);
		if (bytes[0] == NDTConstants.TYPE_INT) {
			NDTInteger ndt = new NDTInteger();
			ndt.setBytes(tagBytes);
			return ndt;
		}
		if (bytes[0] == NDTConstants.TYPE_LONG) {
			NDTLong ndt = new NDTLong();
			ndt.setBytes(tagBytes);
			return ndt;
		}
		if (bytes[0] == NDTConstants.TYPE_FLOAT) {
			NDTFloat ndt = new NDTFloat();
			ndt.setBytes(tagBytes);
			return ndt;
		}
		if (bytes[0] == NDTConstants.TYPE_STRING) {
			NDTString ndt = new NDTString();
			ndt.setBytes(tagBytes);
			return ndt;
		}
		if (bytes[0] == NDTConstants.TYPE_CONTAINER) {
			return new NDTContainer(tagBytes);
		}
		logger.warning("Unknown NDT tag type: " + bytes[0]);
		return null;
	}
	
}
