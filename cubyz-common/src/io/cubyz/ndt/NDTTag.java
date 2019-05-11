package io.cubyz.ndt;

/**
 * NDT (Named Data Tag)
 * @author zenith391
 *
 */
public class NDTTag {

	protected byte type;
	protected byte[] content;
	protected short contentLength;
	
	public byte getType() {
		return type;
	}
	
	public boolean validate() {
		return content.length == contentLength;
	}
	
	public void setBytes(byte[] bytes) {
		content = bytes;
		contentLength = (short) bytes.length;
	}
	
}
