package io.cubyz.client;

import static org.lwjgl.opengl.GL13C.*;

import org.joml.FrustumIntersection;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;

import io.cubyz.ClientSettings;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.math.CubyzMath;
import io.cubyz.util.FastList;
import io.cubyz.world.BlockSpatial;
import io.cubyz.world.NormalChunk;
import io.jungle.FrameBuffer;
import io.jungle.InstancedMesh;
import io.jungle.Mesh;
import io.jungle.ShadowMap;
import io.jungle.Spatial;
import io.jungle.Texture;
import io.jungle.Window;
import io.jungle.game.Context;
import io.jungle.renderers.Renderer;
import io.jungle.renderers.Transformation;
import io.jungle.util.DirectionalLight;
import io.jungle.util.PointLight;
import io.jungle.util.ShaderProgram;
import io.jungle.util.SpotLight;
import io.jungle.util.Utils;

/**
 *  The renderer which will be used for zenith's shadow system once completed.
 */

@SuppressWarnings("unchecked")
public class ZenithsRenderer implements Renderer {

	private ShaderProgram shaderProgram;
	private ShaderProgram depthShaderProgram;

	private static final float Z_NEAR = 0.01f;
	private static final float Z_FAR = 1000.0f;
	private boolean inited = false;
	private boolean doRender = true;
	public boolean orthogonal;
	private Transformation transformation;
	private String shaders = "";
	private Matrix4f prjViewMatrix = new Matrix4f();
	private FrustumIntersection frustumInt = new FrustumIntersection();
	public static ShadowMap shadowMap;

	public static final int MAX_POINT_LIGHTS = 0;
	public static final int MAX_SPOT_LIGHTS = 0;
	public static final Vector3f VECTOR3F_ZERO = new Vector3f(0, 0, 0);
	private float specularPower = 16f;

	public ZenithsRenderer() {

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
		shaderProgram.createVertexShader(Utils.loadResource(shaders + "/shadow_vertex.vs"));
		shaderProgram.createFragmentShader(Utils.loadResource(shaders + "/shadow_fragment.fs"));
		shaderProgram.link();
		shaderProgram.createUniform("projectionMatrix");
		shaderProgram.createUniform("orthoProjectionMatrix");
		shaderProgram.createUniform("modelViewNonInstancedMatrix");
		shaderProgram.createUniform("viewMatrixInstanced");
		shaderProgram.createUniform("lightViewMatrixInstanced");
		shaderProgram.createUniform("texture_sampler");
		shaderProgram.createUniform("shadowMap");
		shaderProgram.createUniform("break_sampler");
		shaderProgram.createUniform("ambientLight");
		shaderProgram.createUniform("selectedNonInstanced");
		shaderProgram.createUniform("specularPower");
		shaderProgram.createUniform("isInstanced");
		shaderProgram.createUniform("shadowEnabled");
		shaderProgram.createMaterialUniform("material");
		shaderProgram.createPointLightListUniform("pointLights", MAX_POINT_LIGHTS);
		shaderProgram.createSpotLightListUniform("spotLights", MAX_SPOT_LIGHTS);
		shaderProgram.createDirectionalLightUniform("directionalLight");
		shaderProgram.createFogUniform("fog");
		
		depthShaderProgram = new ShaderProgram();
		depthShaderProgram.createVertexShader(Utils.loadResource(shaders + "/depth_vertex.vs"));
		depthShaderProgram.createFragmentShader(Utils.loadResource(shaders + "/depth_fragment.fs"));
		depthShaderProgram.link();
		depthShaderProgram.createUniform("viewMatrixInstanced");
		depthShaderProgram.createUniform("modelLightViewNonInstancedMatrix");
		depthShaderProgram.createUniform("projectionMatrix");
		depthShaderProgram.createUniform("isInstanced");
		
		//shadowMap = new ShadowMap(1024, 1024);
		
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
			NormalChunk[] chunks, Block[] blocks, Entity[] entities, Spatial[] spatials, Player localPlayer, int worldSizeX, int worldSizeZ) {
		if (window.isResized()) {
			glViewport(0, 0, window.getWidth(), window.getHeight());
			window.setResized(false);
			
			if (orthogonal) {
				window.setProjectionMatrix(transformation.getOrthoProjectionMatrix(1f, -1f, -1f, 1f, Z_NEAR, Z_FAR));
			} else {
				window.setProjectionMatrix(transformation.getProjectionMatrix(ClientSettings.FOV, window.getWidth(),
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
		Vector3f playerPosition = null;
		if(localPlayer != null) {
			playerPosition = new Vector3f(localPlayer.getPosition()); // Use a constant copy of the player position for the whole rendering to prevent graphics bugs on player movement.
		}
		if(playerPosition != null) {
			float x0 = playerPosition.x;
			float z0 = playerPosition.z;
			float y0 = playerPosition.y + Player.cameraHeight;
			for (NormalChunk ch : chunks) {
				if (!frustumInt.testAab(ch.getMin(x0, z0, worldSizeX, worldSizeZ), ch.getMax(x0, z0, worldSizeX, worldSizeZ)))
					continue;
				int length = ch.getVisibles().size;
				BlockInstance[] vis = ch.getVisibles().array;
				for (int i = 0; i < length; i++) {
					BlockInstance bi = vis[i];
					if(bi != null) { // Sometimes block changes happen while rendering.
						float x = CubyzMath.match(bi.getX(), x0, worldSizeX);
						float z = CubyzMath.match(bi.getZ(), z0, worldSizeZ);
						if(frustumInt.testSphere(x, bi.getY(), z, 0.866025f)) {
							x = x - x0;
							float y = bi.getY() - y0;
							z = z - z0;
							// Only draw blocks that have at least one face facing the player.
							boolean[] neighbors = bi.getNeighbors();
							if(bi.getBlock().getBlockClass() == Block.BlockClass.FLUID || // Ignore fluid blocks in the process, so their surface can still be seen from below.
									(x > 0.5001f && !neighbors[0]) ||
									(x < -0.5001f && !neighbors[1]) ||
									(y > 0.5001f && !neighbors[4]) ||
									(y < -0.5001f && !neighbors[5]) ||
									(z > 0.5001f && !neighbors[2]) ||
									(z < -0.5001f && !neighbors[3])) {

								BlockSpatial[] spatial = (BlockSpatial[]) bi.getSpatials(localPlayer, worldSizeX, worldSizeZ, ch);
								if(spatial != null) {
									ch.getCornerLight(bi.getX() & 15, bi.getY(), bi.getZ() & 15, bi.light);
									for(BlockSpatial tmp : spatial) {
										if (tmp.isSelected()) {
											breakAnim = bi.getBreakingAnim();
										}
										map[bi.getID()].add(tmp);
									}
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
		
		if (shadowMap != null) { // remember it will be disableable
			renderDepthMap(directionalLight, blocks, selected, selectedBlock);
			glViewport(0, 0, window.getWidth(), window.getHeight()); // reset viewport
			if (orthogonal) {
				window.setProjectionMatrix(transformation.getOrthoProjectionMatrix(1f, -1f, -1f, 1f, Z_NEAR, Z_FAR));
			} else {
				window.setProjectionMatrix(transformation.getProjectionMatrix(ClientSettings.FOV, window.getWidth(),
						window.getHeight(), Z_NEAR, Z_FAR));
			}
			ctx.getCamera().setViewMatrix(transformation.getViewMatrix(ctx.getCamera()));
		}
		renderScene(ctx, ambientLight, null /* point light */, null /* spot light */, directionalLight, map, blocks, entities, spatials,
				localPlayer, selected, selectedBlock, breakAnim);
		if (ctx.getHud() != null) {
			ctx.getHud().render(window);
		}
	}
	
	public Matrix4f getLightViewMatrix(DirectionalLight light) {
		float lightAngleX = (float) Math.acos(light.getDirection().z);
		float lightAngleY = (float) Math.asin(light.getDirection().x);
		float lightAngleZ = 0f;
		return transformation.getLightViewMatrix(
				new Vector3f(light.getDirection()).mul(30f),
				new Vector3f(lightAngleX, lightAngleY, lightAngleZ));
	}
	
	public Matrix4f getShadowProjectionMatrix() {
		return transformation.getOrthoProjectionMatrix(-10f, 10f, -10f, 10f, 1f, 50f);
	}
	
	// for shadow map
	public void renderDepthMap(DirectionalLight light, Block[] blocks, Spatial selected, int selectedBlock) {
		FrameBuffer fbo = shadowMap.getDepthMapFBO();
		fbo.bind();
		Texture depthTexture = fbo.getDepthTexture();
		glViewport(0, 0, depthTexture.getWidth(), depthTexture.getHeight());
		glClear(GL_DEPTH_BUFFER_BIT);
		depthShaderProgram.bind();
		
		Matrix4f lightViewMatrix = getLightViewMatrix(light);
		// TODO: only create new vector if changed
		depthShaderProgram.setUniform("projectionMatrix", getShadowProjectionMatrix());
		depthShaderProgram.setUniform("viewMatrixInstanced", lightViewMatrix);
		
		for (int i = 0; i < blocks.length; i++) {
			if (map[i] == null)
				continue;
			Mesh mesh = Meshes.blockMeshes.get(blocks[i]);
			if (selectedBlock == i) {
				map[i].add(selected);
			}
			if (mesh.isInstanced()) {
				InstancedMesh ins = (InstancedMesh) mesh;
				depthShaderProgram.setUniform("isInstanced", 1);
				ins.renderListInstanced(map[i], transformation, false);
			} else {
				depthShaderProgram.setUniform("isInstanced", 0);
				mesh.renderList(map[i], (Spatial gameItem) -> {
					Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(gameItem, lightViewMatrix);
					if (orthogonal) {
						modelViewMatrix = transformation.getOrtoProjModelMatrix(gameItem);
					}
					if (gameItem.isSelected())
						depthShaderProgram.setUniform("selectedNonInstanced", 1f);
					depthShaderProgram.setUniform("modelViewNonInstancedMatrix", modelViewMatrix);
				});
				if (selectedBlock == i) {
					depthShaderProgram.setUniform("selectedNonInstanced", 0f);
				}
			}
		}
		// TODO: render entities
		depthShaderProgram.unbind();
		fbo.unbind();
	}
	
	public void renderScene(Context ctx, Vector3f ambientLight, PointLight[] pointLightList, SpotLight[] spotLightList,
			DirectionalLight directionalLight, FastList<Spatial>[] map, Block[] blocks, Entity[] entities, Spatial[] spatials, Player p, Spatial selected,
			int selectedBlock, float breakAnim) {
		shaderProgram.bind();
		
		shaderProgram.setUniform("fog", ctx.getFog());
		shaderProgram.setUniform("projectionMatrix", ctx.getWindow().getProjectionMatrix());
		shaderProgram.setUniform("texture_sampler", 0);
		shaderProgram.setUniform("break_sampler", 2);
		if (shadowMap != null) {
			shaderProgram.setUniform("orthoProjectionMatrix", getShadowProjectionMatrix());
			shaderProgram.setUniform("lightViewMatrixInstanced", getLightViewMatrix(directionalLight));
			shaderProgram.setUniform("shadowMap", 1);
			shaderProgram.setUniform("shadowEnabled", true);
		} else {
			shaderProgram.setUniform("shadowEnabled", false);
		}
		
		Matrix4f viewMatrix = ctx.getCamera().getViewMatrix();
		shaderProgram.setUniform("viewMatrixInstanced", viewMatrix);
		
		renderLights(viewMatrix, ambientLight, pointLightList, spotLightList, directionalLight);
		
		for (int i = 0; i < blocks.length; i++) {
			if (map[i] == null)
				continue;
			Mesh mesh = Meshes.blockMeshes.get(blocks[i]);
			mesh.getMaterial().setTexture(Meshes.blockTextures.get(blocks[i]));
			shaderProgram.setUniform("material", mesh.getMaterial());
			if (selectedBlock == i) {
				map[i].add(selected);
			}
			if (mesh.isInstanced()) {
				if (shadowMap != null) {
					glActiveTexture(GL_TEXTURE1);
					glBindTexture(GL_TEXTURE_2D, shadowMap.getDepthMapFBO().getDepthTexture().getId());
				}
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
				ins.renderListInstanced(map[i], transformation, false);
			} else {
				shaderProgram.setUniform("isInstanced", 0);
				mesh.renderList(map[i], (Spatial gameItem) -> {
					Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(gameItem, viewMatrix);
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
			if (ent != null && ent != p && Meshes.entityMeshes.get(ent.getType()) != null) { // don't render local player
				Mesh mesh = Meshes.entityMeshes.get(ent.getType());
				shaderProgram.setUniform("material", mesh.getMaterial());
				
				mesh.renderOne(() -> {
					Vector3f position = ent.getRenderPosition();
					Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(position, ent.getRotation(), 1f), viewMatrix);
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
			shaderProgram.setUniform("material", mesh.getMaterial());
			mesh.renderOne(() -> {
				Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(
						Transformation.getModelMatrix(spatial.getPosition(), spatial.getRotation(), spatial.getScale()),
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
		shaderProgram.setUniform("specularPower", specularPower);
		// Process Point Lights
		int numLights = pointLightList != null ? pointLightList.length : 0;
		for (int i = 0; i < numLights; i++) {
			// Get a copy of the point light object and transform its position to view
			// coordinates
			PointLight currPointLight = new PointLight(pointLightList[i]);
			Vector3f lightPos = currPointLight.getPosition();
			Vector4f aux = new Vector4f(lightPos, 1);
			aux.mul(viewMatrix);
			lightPos.x = aux.x;
			lightPos.y = aux.y;
			lightPos.z = aux.z;
			shaderProgram.setUniform("pointLights", currPointLight, i);
		}
	
		// Process Spot Ligths
		numLights = spotLightList != null ? spotLightList.length : 0;
		for (int i = 0; i < numLights; i++) {
			// Get a copy of the spot light object and transform its position and cone
			// direction to view coordinates
			SpotLight currSpotLight = new SpotLight(spotLightList[i]);
			Vector4f dir = new Vector4f(currSpotLight.getConeDirection(), 0);
			dir.mul(viewMatrix);
			currSpotLight.setConeDirection(new Vector3f(dir.x, dir.y, dir.z));
			Vector3f lightPos = currSpotLight.getPointLight().getPosition();
	
			Vector4f aux = new Vector4f(lightPos, 1);
			aux.mul(viewMatrix);
			lightPos.x = aux.x;
			lightPos.y = aux.y;
			lightPos.z = aux.z;
	
			shaderProgram.setUniform("spotLights", currSpotLight, i);
		}
		// Get a copy of the directional light object and transform its position to view
		// coordinates
		DirectionalLight currDirLight = new DirectionalLight(directionalLight);
		Vector4f dir = new Vector4f(currDirLight.getDirection(), 0);
		dir.mul(viewMatrix);
		currDirLight.setDirection(new Vector3f(dir.x, dir.y, dir.z));
		shaderProgram.setUniform("directionalLight", currDirLight);
	}

	@Override
	public void cleanup() {
		if (shaderProgram != null) {
			shaderProgram.cleanup();
		}
		if (depthShaderProgram != null) {
			depthShaderProgram.cleanup();
		}
		if (shadowMap != null) {
			shadowMap.getDepthMapFBO().cleanup();
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
