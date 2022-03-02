package cubyz.world.handler;

public interface BlockVisibilityChangeHandler {

	void onBlockAppear(int b, int x, int y, int z);
	void onBlockHide(int b, int x, int y, int z);
	
}
