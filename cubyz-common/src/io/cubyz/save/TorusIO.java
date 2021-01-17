package io.cubyz.save;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;

import io.cubyz.api.Registry;
import io.cubyz.api.RegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.entity.Entity;
import io.cubyz.math.Bits;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.LocalStellarTorus;
import io.cubyz.world.LocalSurface;

import static io.cubyz.CubyzLogger.logger;

public class TorusIO {

	final File dir;
	private LocalStellarTorus torus;
	public HashMap<Block, Integer> blockPalette = new HashMap<>();

	public TorusIO(LocalStellarTorus torus, File directory) {
		dir = directory;
		if (!dir.exists()) {
			dir.mkdirs();
		}
		this.torus = torus;
	}

	public boolean hasTorusData() {
		return new File(dir, "torus.dat").exists();
	}
	
	public static <T extends RegistryElement> NDTContainer readPalette(NDTContainer paletteNDT, HashMap<T, Integer> palette, Registry<T> registry) {
		for (String key : paletteNDT.keys()) {
			T t = registry.getByID(key);
			if (t != null) {
				palette.put(t, paletteNDT.getInteger(key));
			} else {
				logger.warning("A block with ID " + key + " is used in world but isn't available.");
			}
		}
		return paletteNDT;
	}
	
	public static <T extends RegistryElement> NDTContainer storePalette(NDTContainer paletteNDT, HashMap<T, Integer> palette) {
		for (T t : palette.keySet()) {
			paletteNDT.setInteger(t.getRegistryID().toString(), palette.get(t));
		}
		return paletteNDT;
	}

	public void loadTorusData(LocalSurface surface) {
		try {
			InputStream in = new FileInputStream(new File(dir, "torus.dat"));
			byte[] len = new byte[4];
			in.read(len);
			int l = Bits.getInt(len, 0);
			byte[] dst = new byte[l];
			in.read(dst);
			
			NDTContainer ndt = new NDTContainer(dst);
			if (ndt.getInteger("version") < 2) {
				in.close();
				throw new RuntimeException("World is out-of-date");
			}
			torus.setName(ndt.getString("name"));
			readPalette(ndt.getContainer("blockPalette"), blockPalette, surface.registries.blockRegistry);
			Entity[] entities = new Entity[ndt.getInteger("entityCount")];
			for (int i = 0; i < entities.length; i++) {
				// TODO: Only load entities that are in loaded chunks.
				entities[i] = EntityIO.loadEntity(in, surface);
			}
			if (surface != null) {
				surface.setEntities(entities);
			}
			in.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
	
	public void saveTorusData(LocalSurface surface) {
		try {
			OutputStream out = new FileOutputStream(new File(dir, "torus.dat"));
			NDTContainer ndt = new NDTContainer();
			ndt.setInteger("version", 2);
			ndt.setString("name", torus.getName());
			ndt.setInteger("entityCount", surface == null ? 0 : surface.getEntities().length);
			ndt.setContainer("blockPalette", storePalette(new NDTContainer(), blockPalette));
			byte[] len = new byte[4];
			Bits.putInt(len, 0, ndt.getData().length);
			out.write(len);
			out.write(ndt.getData());
			if (surface != null) {
				for (Entity ent : surface.getEntities()) {
					if(ent != null)
						EntityIO.saveEntity(ent, out);
				}
			}
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

}
