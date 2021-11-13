package cubyz.world.handler;

public interface BlockVisibilityChangeHandler {

	public void onBlockAppear(int b, int x, int y, int z);
	public void onBlockHide(int b, int x, int y, int z);
	
}
