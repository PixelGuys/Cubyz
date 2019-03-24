package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.ClientOnly;
import io.cubyz.world.World;

public class BlockInstance {

	private Block block;
	private IBlockSpatial spatial;
	private Vector3i pos;
	private World world;
	
	public World getWorld() {
		return world;
	}
	
	public void setWorld(World world) {
		this.world = world;
	}
	
	public BlockInstance(Block block) {
		this.block = block;
	}
	
	public int getID() {
		return block.ID;
	}
	
	public void update() {
		
	}
	
	public Vector3i getPosition() {
		return pos;
	}
	
	public int getX() {
		return pos.x();
	}
	
	public int getY() {
		return pos.y();
	}
	
	public int getZ() {
		return pos.z();
	}
	
	public Object getMesh() {
		if (block.getBlockPair().get("textureCache") == null) {
//			try {
//				if (block.texConverted) {
//					block._textureCache = new Texture("./res/textures/blocks/" + block.getTexture() + ".png");
//				} else {
//					block._textureCache = new Texture(TextureConverter.fromBufferedImage(
//							TextureConverter.convert(ImageIO.read(new File("./res/textures/blocks/" + block.getTexture() + ".png")),
//									block.getTexture())));
//				}
//				// Assuming mesh too is empty
//				block._meshCache = OBJLoader.loadMesh("res/models/cube.obj");
//				block._meshCache.setBoundingRadius(2.0F);
//				Material material = new Material(block._textureCache, 1.0F);
//				block._meshCache.setMaterial(material);
//			} catch (Exception e) {
//				e.printStackTrace();
//			}
			ClientOnly.createBlockMesh.accept(this.getBlock());
		}
		return block.getBlockPair().get("meshCache");
	}
	
	public Block getBlock() {
		return block;
	}
	
	public void setPosition(Vector3i pos) {
		this.pos = pos;
	}
	

	
	public BlockInstance[] getNeighbors() {
		BlockInstance[] inst = new BlockInstance[6];
		// 0 = EAST  (x - 1)
		// 1 = WEST  (x + 1)
		// 2 = NORTH (z + 1)
		// 3 = SOUTH (z - 1)
		// 4 = DOWN
		// 5 = UP
		inst[5] = world.getBlock(pos.x, pos.y + 1, pos.z);
		inst[4] = world.getBlock(pos.x, pos.y + -1, pos.z);
		inst[3] = world.getBlock(pos.x, pos.y, pos.z + -1);
		inst[2] = world.getBlock(pos.x, pos.y, pos.z + 1);
		inst[1] = world.getBlock(pos.x + 1, pos.y, pos.z);
		inst[0] = world.getBlock(pos.x + -1, pos.y, pos.z);
		return inst;
	}
	
	public BlockInstance getNeighbor(int i) {
		// 0 = EAST  (x - 1)
		// 1 = WEST  (x + 1)
		// 2 = NORTH (z + 1)
		// 3 = SOUTH (z - 1)
		// 4 = DOWN
		// 5 = UP
		switch(i) {
			case 5:
				return world.getBlock(pos.x, pos.y + 1, pos.z);
			case 4:
				return world.getBlock(pos.x, pos.y + -1, pos.z);
			case 3:
				return world.getBlock(pos.x, pos.y, pos.z + -1);
			case 2:
				return world.getBlock(pos.x, pos.y, pos.z + 1);
			case 1:
				return world.getBlock(pos.x + 1, pos.y, pos.z);
			case 0:
				return world.getBlock(pos.x + -1, pos.y, pos.z);
		}
		return null;
	}
	
	public IBlockSpatial getSpatial() {
		if (spatial == null) {
			spatial = ClientOnly.createBlockSpatial.apply(this);
		}
		return spatial;
	}
	
}
