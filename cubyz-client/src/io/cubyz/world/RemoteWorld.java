package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;

import org.joml.Vector4f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.math.Bits;
import io.cubyz.multiplayer.GameProfile;
import io.cubyz.save.BlockChange;
import io.cubyz.world.generator.LifelandGenerator;

// TODO
@SuppressWarnings("unused")
public class RemoteWorld extends World {
	
	private Player localPlayer;
	private GameProfile localGameProfile;
	private ArrayList<Entity> entities;
	
	private ArrayList<NormalChunk> chunks;
	private Block[] blocks;
	
	private LifelandGenerator gen = new LifelandGenerator();
	private long gameTime;
	
	public RemoteWorld() {
		//localPlayer = (Player) CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player").newEntity(surface); // TODO!
		//localPlayer.setStellarTorus(this.getCurrentTorus()); TODO!
		localPlayer.getPosition().add(10, 200, 10);
		entities = new ArrayList<Entity>();
		entities.add(localPlayer);
		chunks = new ArrayList<>();
		
		blocks = new Block[CubyzRegistries.BLOCK_REGISTRY.registered().length];
		for (RegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			blocks[b.ID] = b;
		}
	}
	
	public ArrayList<BlockChange> transformData(byte[] data) {
		int size = Bits.getInt(data, 8);
		ArrayList<BlockChange> list = new ArrayList<BlockChange>(size);
		for (int i = 0; i < size; i++) {
			list.add(new BlockChange(data, 12 + (i << 4), null)); // TODO
		}
		return list;
	}
	
	@Override
	public Player getLocalPlayer() {
		return localPlayer;
	}
	
	@Override
	public void update() {
		Entity[] ent = getCurrentTorus().getEntities();
		for (Entity en : ent) {
			en.update();
		}
	}

	public Block[] getBlocks() {
		return blocks;
	}

	@Override
	public long getGameTime() {
		return gameTime;
	}

	@Override
	public void setGameTime(long time) {
		this.gameTime = time;
	}

	@Override
	public void cleanup() {
		
	}
	
	public void worldData(int seed) {
		this.setSeed(seed);
	}
	
	public void submit(int x, int z, byte[] data) {
		/*Chunk ck = new Chunk(x, z, this, transformData(data)); TODO!
		for (int i = 0; i < chunks.size(); i++) {
			if (chunks.get(i).getX() == x && chunks.get(i).getZ() == z) {
				chunks.remove(i);
			}
		}
		chunks.add(0, ck);
		ck.generateFrom(gen);
		ck.load();
		if (getCurrentTorus().getHighestBlock(localPlayer.getPosition().x, localPlayer.getPosition().z) != -1)
			localPlayer.getPosition().y = getCurrentTorus().getHighestBlock(localPlayer.getPosition().x, localPlayer.getPosition().z)+1;
		ck.applyBlockChanges();*/
	}

	@Override
	public Surface getCurrentTorus() {
		// TODO Auto-generated method stub
		return null;
	}

	@Override
	public List<StellarTorus> getToruses() {
		// TODO Auto-generated method stub
		return null;
	}

}
