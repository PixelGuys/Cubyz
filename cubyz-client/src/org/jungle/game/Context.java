package org.jungle.game;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.jungle.Camera;
import org.jungle.Mesh;
import org.jungle.Spatial;
import org.jungle.Window;
import org.jungle.hud.Hud;

public class Context {

	private Window win;
	private Game game;
	private Camera camera;
	private Hud hud;
	private Map<Mesh, List<Spatial>> meshMap;
	
	public Context(Game g, Camera c) {
		camera = c;
		game = g;
		win = g.win;
		meshMap = new HashMap<>();
		hud = new Hud();
	}
	
	public void setSpatials(Spatial[] gameItems) {
		meshMap.clear();
	    int numGameItems = gameItems != null ? gameItems.length : 0;
	    for (int i=0; i<numGameItems; i++) {
	        Spatial gameItem = gameItems[i];
	        for (Mesh mesh : gameItem.getMeshes()) {
		        List<Spatial> list = meshMap.get(mesh);
		        if ( list == null ) {
		            list = new ArrayList<>();
		            meshMap.put(mesh, list);
		        }
		        list.add(gameItem);
	        }
	    }
	}
	
	public Map<Mesh, List<Spatial>> getMeshMap() {
		return meshMap;
	}
	
	public Hud getHud() {
		return hud;
	}
	
	public void setHud(Hud hud) {
		this.hud = hud;
	}
	
	public Spatial[] getSpatials() {
		ArrayList<Spatial> spl = new ArrayList<>();
		for (Mesh mesh : meshMap.keySet()) {
			List<Spatial> sp = meshMap.get(mesh);
			for (Spatial s : sp) {
				spl.add(s);
			}
		}
		return spl.toArray(new Spatial[spl.size()]);
	}
	
	public void addSpatial(Spatial s) {
		for (Mesh mesh : s.getMeshes()) {
	        List<Spatial> list = meshMap.get(mesh);
	        if ( list == null ) {
	            list = new ArrayList<>();
	            meshMap.put(mesh, list);
	        }
	        list.add(s);
		}
	}
	
	public void removeSpatial(Spatial s) {
		for (Mesh mesh : meshMap.keySet()) {
			List<Spatial> sp = meshMap.get(mesh);
			if (sp.contains(s)) {
				sp.remove(s);
			}
		}
	}

	public Window getWindow() {
		return win;
	}

	public Game getGame() {
		return game;
	}

	public Camera getCamera() {
		return camera;
	}

}
