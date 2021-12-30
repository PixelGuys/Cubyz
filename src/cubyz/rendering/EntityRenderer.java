package cubyz.rendering;

import java.io.IOException;

import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.Meshes;
import cubyz.client.entity.ClientEntity;
import cubyz.client.entity.ClientEntityManager;
import cubyz.utils.Utils;
import cubyz.world.entity.CustomMeshProvider;
import cubyz.world.entity.CustomMeshProvider.MeshType;

public class EntityRenderer {
	public static int loc_projectionMatrix;
	public static int loc_viewMatrix;
	public static int loc_texture_sampler;
	public static int loc_materialHasTexture;
	public static int loc_fog_activ;
	public static int loc_fog_color;
	public static int loc_fog_density;
	public static int loc_light;
	public static int loc_ambientLight;
	public static int loc_directionalLight;

	static ShaderProgram entityShader; // Entities are sometimes small and sometimes big. Therefor it would mean a lot of work to still use smooth lighting. Therefor the non-smooth shader is used for those.
	

	static void init(String shaders) throws IOException {
		if (entityShader != null)
			entityShader.cleanup();
		entityShader = new ShaderProgram(Utils.loadResource(shaders + "/entity_vertex.vs"),
				Utils.loadResource(shaders + "/entity_fragment.fs"),
				EntityRenderer.class);
	}

	public static void render(Vector3f ambientLight, DirectionalLight directionalLight, Vector3d playerPosition) {
		ClientEntity[] entities = ClientEntityManager.getEntities();
		entityShader.bind();
		entityShader.setUniform(loc_fog_activ, Cubyz.fog.isActive());
		entityShader.setUniform(loc_fog_color, Cubyz.fog.getColor());
		entityShader.setUniform(loc_fog_density, Cubyz.fog.getDensity());
		entityShader.setUniform(loc_projectionMatrix, Window.getProjectionMatrix());
		entityShader.setUniform(loc_texture_sampler, 0);
		entityShader.setUniform(loc_ambientLight, ambientLight);
		entityShader.setUniform(loc_directionalLight, directionalLight.getDirection());

		for (int i = 0; i < entities.length; i++) {
			ClientEntity ent = entities[i];
			int x = (int)(ent.position.x + 1.0f);
			int y = (int)(ent.position.y + 1.0f);
			int z = (int)(ent.position.z + 1.0f);
			if (ent != null && ent.id != Cubyz.player.id) { // don't render local player
				Mesh mesh = null;
				if (ent.type.model != null) {
					entityShader.setUniform(loc_materialHasTexture, true);
					entityShader.setUniform(loc_light, Cubyz.world.getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
					ent.type.model.render(Camera.getViewMatrix(), entityShader, ent);
					continue;
				}
				if (ent instanceof CustomMeshProvider) {
					CustomMeshProvider provider = (CustomMeshProvider) ent;
					MeshType type = provider.getMeshType();
					if (type == MeshType.ENTITY) {
						ClientEntity e = (ClientEntity) provider.getMeshId();
						mesh = Meshes.entityMeshes.get(e.type);
					}
				} else {
					mesh = Meshes.entityMeshes.get(ent.type);
				}
				
				if (mesh != null) {
					entityShader.setUniform(loc_materialHasTexture, mesh.getMaterial().isTextured());
					entityShader.setUniform(loc_light, Cubyz.world.getLight(x, y, z, ambientLight, ClientSettings.easyLighting));
					
					mesh.renderOne(() -> {
						Vector3d position = ent.getRenderPosition().sub(playerPosition);
						Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)position.x, (float)position.y, (float)position.z), ent.rotation, 1), Camera.getViewMatrix());
						entityShader.setUniform(loc_viewMatrix, modelViewMatrix);
					});
				}
			}
		}
	}
}
