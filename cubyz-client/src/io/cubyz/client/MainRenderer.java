package io.cubyz.client;

import static org.lwjgl.opengl.GL13C.*;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3f;

import io.cubyz.CubyzLogger;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.ItemEntity;
import io.cubyz.entity.Player;
import io.cubyz.items.ItemBlock;
import io.cubyz.math.CubyzMath;
import io.cubyz.math.Vector3fi;
import io.cubyz.util.FastList;
import io.cubyz.world.BlockSpatial;
import io.cubyz.world.Chunk;
import io.jungle.InstancedMesh;
import io.jungle.Mesh;
import io.jungle.Spatial;
import io.jungle.Window;
import io.jungle.game.Context;
import io.jungle.renderers.Renderer;
import io.jungle.renderers.Transformation;
import io.jungle.util.DirectionalLight;
import io.jungle.util.PointLight;
import io.jungle.util.ShaderProgram;
import io.jungle.util.SpotLight;
import io.jungle.util.Utils;

// Renderer that is used when easyLighting is enabled.

@SuppressWarnings("unchecked")
public class MainRenderer implements Renderer {

	private ShaderProgram shaderProgram;

	private static final float Z_NEAR = 0.01f;
	private static final float Z_FAR = 1000.0f;
	private boolean inited = false;
	private boolean doRender = true;
	public boolean orthogonal;
	private Transformation transformation;
	private String shaders = "";
	private Matrix4f prjViewMatrix = new Matrix4f();
	private FrustumIntersection frustumInt = new FrustumIntersection();

	public static final int MAX_POINT_LIGHTS = 0;
	public static final int MAX_SPOT_LIGHTS = 0;
	public static final Vector3f VECTOR3F_ZERO = new Vector3f(0, 0, 0);

	private static final float PI = (float)Math.PI;
	private static final float PI_HALF = PI/2;

	public MainRenderer() {

	}

	public Transformation getTransformation() {
		return transformation;
	}

	public void setShaderFolder(String shaders) {
		this.shaders = shaders;
	}

	public void unloadShaders() throws Exception {
		shaderProgram.unbind();
		shaderProgram.cleanup();
		shaderProgram = null;
		System.gc();
	}

	public void setDoRender(boolean doRender) {
		this.doRender = doRender;
	}

	public void loadShaders() throws Exception {
		shaderProgram = new ShaderProgram();
		shaderProgram.createVertexShader(Utils.loadResource(shaders + "/vertex.vs"));
		shaderProgram.createFragmentShader(Utils.loadResource(shaders + "/fragment.fs"));
		shaderProgram.link();
		shaderProgram.createUniform("projectionMatrix");
		shaderProgram.createUniform("modelViewNonInstancedMatrix");
		shaderProgram.createUniform("viewMatrixInstanced");
		shaderProgram.createUniform("texture_sampler");
		shaderProgram.createUniform("break_sampler");
		shaderProgram.createUniform("ambientLight");
		shaderProgram.createUniform("selectedNonInstanced");
		shaderProgram.createUniform("isInstanced");
		shaderProgram.createUniform("materialHasTexture");
		shaderProgram.createFogUniform("fog");
		
		System.gc();
	}

	@Override
	public void init(Window window) throws Exception {
		transformation = new Transformation();
		window.setProjectionMatrix(transformation.getProjectionMatrix((float) Math.toRadians(70.0f), window.getWidth(),
				window.getHeight(), Z_NEAR, Z_FAR));
		loadShaders();

		inited = true;
	}

	public void clear() {
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
	}

	FastList<Spatial>[] map = (FastList<Spatial>[]) new FastList[0];
	
	
	/**
	 * Renders a Cubyz world.
	 * @param window the window to render in
	 * @param ctx the Context object (will soon be replaced)
	 * @param ambientLight the ambient light to use
	 * @param directionalLight the directional light to use
	 * @param chunks the chunks being displayed
	 * @param blocks the type of blocks used (or available) in the displayed chunks
	 * @param entities the entities to render
	 * @param spatials the special objects to render (that are neither entity, neither blocks, like sun and moon, or rain)
	 * @param localPlayer The world's local player
	 */
	public void render(Window window, Context ctx, Vector3f ambientLight, DirectionalLight directionalLight,
			Chunk[] chunks, Block[] blocks, Entity[] entities, Spatial[] spatials, Player localPlayer, int worldAnd) {
		if (window.isResized()) {
			glViewport(0, 0, window.getWidth(), window.getHeight());
			window.setResized(false);
			
			if (orthogonal) {
				window.setProjectionMatrix(transformation.getOrthoProjectionMatrix(1f, -1f, -1f, 1f, Z_NEAR, Z_FAR));
			} else {
				window.setProjectionMatrix(transformation.getProjectionMatrix(ctx.getCamera().getFov(), window.getWidth(),
						window.getHeight(), Z_NEAR, Z_FAR));
			}
		}
		if (!doRender)
			return;
		clear();
		ctx.getCamera().setViewMatrix(transformation.getViewMatrix(ctx.getCamera()));
		
		Spatial selected = null;
		int selectedBlock = -1;
		float breakAnim = 0f;
		if (blocks.length != map.length) {
			map = (FastList<Spatial>[]) new FastList[blocks.length];
			int arrayListCapacity = 10;
			for (int i = 0; i < map.length; i++) {
				map[i] = new FastList<Spatial>(arrayListCapacity, Spatial.class);
			}
		}
		// Don't create a new ArrayList every time to reduce re-allocations:
		for (int i = 0; i < map.length; i++) {
			map[i].clear();
		}
		
		
		// Uses FrustumCulling on the chunks.
		prjViewMatrix.set(window.getProjectionMatrix());
		prjViewMatrix.mul(ctx.getCamera().getViewMatrix());
		// TODO: RayAabIntersection
		
		frustumInt.set(prjViewMatrix);
		if(localPlayer != null) {
			// Store the position locally to prevent glitches when the updateThread changes the position.
			Vector3fi pos = localPlayer.getPosition();
			int x0 = pos.x;
			float relX = pos.relX;
			int z0 = pos.z;
			float relZ = pos.relZ;
			float y0 = pos.y + Player.cameraHeight;
			for (Chunk ch : chunks) {
				if (!frustumInt.testAab(ch.getMin(pos, worldAnd), ch.getMax(pos, worldAnd)))
					continue;
				int length = ch.getVisibles().size;
				BlockInstance[] vis = ch.getVisibles().array;
				for (int i = 0; i < length; i++) {
					BlockInstance bi = vis[i];
					if(bi != null) { // Sometimes block changes happen while rendering.
						float x = CubyzMath.matchSign((bi.getX() - x0) & worldAnd, worldAnd) - relX;
						float y = bi.getY() - y0;
						float z = CubyzMath.matchSign((bi.getZ() - z0) & worldAnd, worldAnd) - relZ;
						// Do the frustum culling directly here.
						if(frustumInt.testSphere(x, y, z, 0.866025f)) {
							// Only draw blocks that have at least one face facing the player.
							if(bi.getBlock().isTransparent() || // Ignore transparent blocks in the process, so the surface of water can still be seen from below.
									(x > 0.5001f && !bi.neighborEast) ||
									(x < -0.5001f && !bi.neighborWest) ||
									(y > 0.5001f && !bi.neighborDown) ||
									(y < -0.5001f && !bi.neighborUp) ||
									(z > 0.5001f && !bi.neighborSouth) ||
									(z < -0.5001f && !bi.neighborNorth)) {
								if(bi.getBlock().mode == null) {
									Spatial tmp = (Spatial) bi.getSpatial();
									tmp.setPosition(x, y, z);
									ch.getCornerLight(bi.getX() & 15, bi.getY(), bi.getZ() & 15, ambientLight, tmp.light);
									if (tmp.isSelected()) {
										selected = tmp;
										selectedBlock = bi.getID();
										breakAnim = bi.getBreakingAnim();
										continue;
									}
									map[bi.getID()].add(tmp);
								} else if(bi.getBlock().mode == Block.RotationMode.TORCH) {
									byte data = bi.blockData;
									if((data & 0b1) != 0) {
										Spatial tmp = new BlockSpatial((BlockSpatial) bi.getSpatial());
										tmp.setPosition(x + 0.4f, y + 0.2f, z);
										ch.getCornerLight(bi.getX() & 15, bi.getY(), bi.getZ() & 15, ambientLight, tmp.light);
										tmp.setRotation(0, 0, -0.3f);
										if (tmp.isSelected()) {
											selected = tmp;
											selectedBlock = bi.getID();
											breakAnim = bi.getBreakingAnim();
											continue;
										}
										map[bi.getID()].add(tmp);
									}
									if((data & 0b10) != 0) {
										Spatial tmp = new BlockSpatial((BlockSpatial) bi.getSpatial());
										tmp.setPosition(x - 0.4f, y + 0.2f, z);
										ch.getCornerLight(bi.getX() & 15, bi.getY(), bi.getZ() & 15, ambientLight, tmp.light);
										tmp.setRotation(0, 0, 0.3f);
										if (tmp.isSelected()) {
											selected = tmp;
											selectedBlock = bi.getID();
											breakAnim = bi.getBreakingAnim();
											continue;
										}
										map[bi.getID()].add(tmp);
									}
									if((data & 0b100) != 0) {
										Spatial tmp = new BlockSpatial((BlockSpatial) bi.getSpatial());
										tmp.setPosition(x, y + 0.2f, z + 0.4f);
										ch.getCornerLight(bi.getX() & 15, bi.getY(), bi.getZ() & 15, ambientLight, tmp.light);
										tmp.setRotation(0.3f, 0, 0);
										if (tmp.isSelected()) {
											selected = tmp;
											selectedBlock = bi.getID();
											breakAnim = bi.getBreakingAnim();
											continue;
										}
										map[bi.getID()].add(tmp);
									}
									if((data & 0b1000) != 0) {
										Spatial tmp = new BlockSpatial((BlockSpatial) bi.getSpatial());
										tmp.setPosition(x, y + 0.2f, z - 0.4f);
										ch.getCornerLight(bi.getX() & 15, bi.getY(), bi.getZ() & 15, ambientLight, tmp.light);
										tmp.setRotation(-0.3f, 0, 0);
										if (tmp.isSelected()) {
											selected = tmp;
											selectedBlock = bi.getID();
											breakAnim = bi.getBreakingAnim();
											continue;
										}
										map[bi.getID()].add(tmp);
									}
									if((data & 0b10000) != 0) {
										Spatial tmp = (Spatial) bi.getSpatial();
										tmp.setPosition(x, y, z);
										ch.getCornerLight(bi.getX() & 15, bi.getY(), bi.getZ() & 15, ambientLight, tmp.light);
										if (tmp.isSelected()) {
											selected = tmp;
											selectedBlock = bi.getID();
											breakAnim = bi.getBreakingAnim();
											continue;
										}
										map[bi.getID()].add(tmp);
									}
								} else if(bi.getBlock().mode == Block.RotationMode.LOG) {
									byte data = bi.blockData;
									Spatial tmp = (Spatial)bi.getSpatial();
									tmp.setPosition(x, y, z);
									ch.getCornerLight(bi.getX() & 15, bi.getY(), bi.getZ() & 15, ambientLight, tmp.light);
									switch(data) {
										default:
											break;
										case 1:
											tmp.setRotation(PI, 0, 0);
											break;
										case 2:
											tmp.setRotation(0, 0, -PI_HALF);
											break;
										case 3:
											tmp.setRotation(0, 0, PI_HALF);
											break;
										case 4:
											tmp.setRotation(PI_HALF, 0, 0);
											break;
										case 5:
											tmp.setRotation(-PI_HALF, 0, 0);
											break;
									}
									if (tmp.isSelected()) {
										selected = tmp;
										selectedBlock = bi.getID();
										breakAnim = bi.getBreakingAnim();
										continue;
									}
									map[bi.getID()].add(tmp);
								} else {
									CubyzLogger.instance.warning("You are stupid! You added a new rotation mode and forgot to update the renderer!");
								}
							}
						}
					}
				}
			}
		}
		
		// sort distances for correct render of transparent blocks
		Vector3f tmpa = new Vector3f();
		Vector3f tmpb = new Vector3f();
		for (int i = 0; i < blocks.length; i++) {
			Block b = blocks[i];
			if (b != null && b.isTransparent()) {
				map[b.ID].sort((sa, sb) -> {
					ctx.getCamera().getPosition().sub(sa.getPosition(), tmpa);
					ctx.getCamera().getPosition().sub(sb.getPosition(), tmpb);
					return (int) Math.signum(tmpa.lengthSquared() - tmpb.lengthSquared());
				});
			}
		}
		
		renderScene(ctx, ambientLight, null /* point light */, null /* spot light */, directionalLight, map, blocks, entities, spatials,
				localPlayer, selected, selectedBlock, breakAnim);
		if (ctx.getHud() != null) {
			ctx.getHud().render(window);
		}
	}
	
	public void renderScene(Context ctx, Vector3f ambientLight, PointLight[] pointLightList, SpotLight[] spotLightList,
			DirectionalLight directionalLight, FastList<Spatial>[] map, Block[] blocks, Entity[] entities, Spatial[] spatials, Player p, Spatial selected,
			int selectedBlock, float breakAnim) {
		shaderProgram.bind();
		
		shaderProgram.setUniform("fog", ctx.getFog());
		shaderProgram.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
		shaderProgram.setUniform("texture_sampler", 0);
		shaderProgram.setUniform("break_sampler", 2);
		
		Matrix4f viewMatrix = ctx.getCamera().getViewMatrix();
		shaderProgram.setUniform("viewMatrixInstanced", viewMatrix);
		
		renderLights(viewMatrix, ambientLight, pointLightList, spotLightList, directionalLight);
		
		for (int i = 0; i < blocks.length; i++) {
			if (map[i] == null)
				continue;
			Mesh mesh = Meshes.blockMeshes.get(blocks[i]);
			mesh.getMaterial().setTexture(Meshes.blockTextures.get(blocks[i]));
			shaderProgram.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
			if (selectedBlock == i) {
				map[i].add(selected);
			}
			if (mesh.isInstanced()) {
				if (breakAnim > 0f && breakAnim < 1f) {
					float step = 1f / Cubyz.breakAnimations.length;
					int breakStep = 0;
					for (float idx = step; idx < 1f; idx += step) {
						if (breakAnim < idx) {
							break;
						}
						breakStep++;
					}
					if (breakStep >= Cubyz.breakAnimations.length) {
						breakStep = Cubyz.breakAnimations.length-1;
					}
					glActiveTexture(GL_TEXTURE2);
					glBindTexture(GL_TEXTURE_2D, Cubyz.breakAnimations[breakStep].getId());
				} else {
					glActiveTexture(GL_TEXTURE2);
					glBindTexture(GL_TEXTURE_2D, 0);
				}
				InstancedMesh ins = (InstancedMesh) mesh;
				shaderProgram.setUniform("isInstanced", 1);
				ins.renderListInstanced(map[i], transformation);
			} else {
				shaderProgram.setUniform("isInstanced", 0);
				mesh.renderList(map[i], (Spatial gameItem) -> {
					Matrix4f modelViewMatrix = transformation.getModelViewMatrix(gameItem, viewMatrix);
					if (orthogonal) {
						modelViewMatrix = transformation.getOrtoProjModelMatrix(gameItem, viewMatrix);
					}
					if (gameItem.isSelected())
						shaderProgram.setUniform("selectedNonInstanced", 1f);
					shaderProgram.setUniform("modelViewNonInstancedMatrix", modelViewMatrix);
				});
				if (selectedBlock == i) {
					shaderProgram.setUniform("selectedNonInstanced", 0f);
				}
			}
		}
		
		for (int i = 0; i < entities.length; i++) {
			Entity ent = entities[i];
			if(ent instanceof ItemEntity) {
				ItemEntity itemEnt = (ItemEntity)ent;
				Mesh mesh = null;
				if(itemEnt.items.getItem() instanceof ItemBlock) {
					mesh = Meshes.blockMeshes.get(((ItemBlock)itemEnt.items.getItem()).getBlock());
					mesh.getMaterial().setTexture(Meshes.blockTextures.get(((ItemBlock)itemEnt.items.getItem()).getBlock()));
				} else {
					// TODO
				}
				if(mesh != null) {
					shaderProgram.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
					
					mesh.renderOne(() -> {
						Vector3f position = ent.getRenderPosition(p.getPosition());
						Matrix4f modelViewMatrix = transformation.getModelViewMatrix(transformation.getModelMatrix(position, ent.getRotation(), 0.2f), viewMatrix);
						shaderProgram.setUniform("isInstanced", 0);
						shaderProgram.setUniform("selectedNonInstanced", 0f);
						shaderProgram.setUniform("modelViewNonInstancedMatrix", modelViewMatrix);
					});
				}
			} else if (ent != null && ent != p && Meshes.entityMeshes.get(ent.getType()) != null) { // don't render local player
				Mesh mesh = Meshes.entityMeshes.get(ent.getType());
				shaderProgram.setUniform("material", mesh.getMaterial());
				
				mesh.renderOne(() -> {
					Vector3f position = ent.getRenderPosition(p.getPosition());
					Matrix4f modelViewMatrix = transformation.getModelViewMatrix(transformation.getModelMatrix(position, ent.getRotation(), 1f), viewMatrix);
					shaderProgram.setUniform("isInstanced", 0);
					shaderProgram.setUniform("selectedNonInstanced", 0f);
					shaderProgram.setUniform("modelViewNonInstancedMatrix", modelViewMatrix);
				});
			}
		}
		
		shaderProgram.setUniform("fog.activ", 0); // manually disable the fog
		for (int i = 0; i < spatials.length; i++) {
			Spatial spatial = spatials[i];
			Mesh mesh = spatial.getMesh();
			shaderProgram.setUniform("materialHasTexture", mesh.getMaterial().isTextured());
			mesh.renderOne(() -> {
				Matrix4f modelViewMatrix = transformation.getModelViewMatrix(
						transformation.getModelMatrix(spatial.getPosition(), spatial.getRotation(), spatial.getScale()),
						viewMatrix);
				shaderProgram.setUniform("isInstanced", 0);
				shaderProgram.setUniform("selectedNonInstanced", 0f);
				shaderProgram.setUniform("modelViewNonInstancedMatrix", modelViewMatrix);
			});
		}
		
		shaderProgram.unbind();
	}

	private void renderLights(Matrix4f viewMatrix, Vector3f ambientLight, PointLight[] pointLightList,
			SpotLight[] spotLightList, DirectionalLight directionalLight) {

		shaderProgram.setUniform("ambientLight", ambientLight);
	}

	@Override
	public void cleanup() {
		if (shaderProgram != null) {
			shaderProgram.cleanup();
		}
	}

	@Override
	public void render(Window win, Context ctx, Vector3f ambientLight, PointLight[] pointLightList,
			SpotLight[] spotLightList, DirectionalLight directionalLight) {
		throw new UnsupportedOperationException("Cubyz Renderer doesn't support this method.");
	}

	@Override
	public void setPath(String dataName, String path) {
		if (dataName.equals("shaders") || dataName.equals("shadersFolder")) {
			if (inited) {
				try {
					doRender = false;
					unloadShaders();
					shaders = path;
					loadShaders();
					doRender = true;
				} catch (Exception e) {
					e.printStackTrace();
				}
			} else {
				shaders = path;
			}
		}
	}

}
