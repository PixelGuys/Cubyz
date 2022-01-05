package cubyz.rendering;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;

import static org.lwjgl.opengl.GL20.*;
import org.lwjgl.system.MemoryStack;

import cubyz.utils.Logger;

public class ShaderProgram {

	private final int programId;

	private int vertexShaderId;

	private int fragmentShaderId;

	//private final Map<String, Integer> uniforms;

	/**
	 * Creates the fragment shader and initializes uniform locations.
	 * @param vertexCode code of the vertex shader
	 * @param fragmentCode code of the fragment shader
	 * @param uniformLocations all uniform locations will be stored in static variables in this class. <br>
	 * The expected format is "loc_"+nameInShaderCode. dots "." are replaced by "_", to prevent issues.
	 */
	public ShaderProgram(String vertexCode, String fragmentCode, Class<?> uniformLocations) {
		programId = glCreateProgram();
		try {
			if (programId == 0) {
				throw new Exception("Could not create Shader");
			}
			//uniforms = new HashMap<>();
			createVertexShader(vertexCode);
			createFragmentShader(fragmentCode);
			link();
			if (uniformLocations != null)
				storeUniforms(uniformLocations);
		} catch(Exception e) {
			Logger.error(e);
		}
	}
	
	public void storeUniforms(Class<?> uniformLocations) {
		IntBuffer size = ByteBuffer.allocateDirect(4).asIntBuffer();
		IntBuffer type = ByteBuffer.allocateDirect(4).asIntBuffer();
		for(int i = 0;; i++) {
			String uniformName = glGetActiveUniform(programId, i, 256, size, type);
			if (uniformName.length() == 0) break; // When there is no further uniform, opengl just returns an empty string.
			try { // Try to put it into the variable of the same name from the given class.
				Field f = uniformLocations.getDeclaredField("loc_"+uniformName.replace('.', '_'));
				f.setInt(null, glGetUniformLocation(programId, uniformName));
			} catch(Exception e) {
				if(!uniformName.startsWith("gl_")) { // No warning for uniforms assigned by opengl.
					Logger.warning("Could not find variable \"loc_"+uniformName.replace('.', '_')+"\" in class \""+uniformLocations.getName()+"\" to store uniform location.");
					Logger.warning(e);
				}
			}
		}
	}

	public void setUniform(int location, Matrix4f value) {
		try (MemoryStack stack = MemoryStack.stackPush()) {
			// Dump the matrix into a float buffer
			FloatBuffer fb = stack.mallocFloat(16);
			value.get(fb);
			glUniformMatrix4fv(location, false, fb);
		}
	}

	public void setUniform(int location, int value) {
		glUniform1i(location, value);
	}
	
	public void setUniform(int location, boolean value) {
		glUniform1i(location, value ? 1 : 0);
	}

	public void setUniform(int location, float value) {
		glUniform1f(location, value);
	}

	public void setUniform(int location, Vector3f value) {
		glUniform3f(location, value.x, value.y, value.z);
	}

	public void setUniform(int location, Vector4f value) {
		glUniform4f(location, value.x, value.y, value.z, value.w);
	}

	public void createVertexShader(String shaderCode) throws Exception {
		vertexShaderId = createShader(shaderCode, GL_VERTEX_SHADER);
	}

	public void createFragmentShader(String shaderCode) throws Exception {
		fragmentShaderId = createShader(shaderCode, GL_FRAGMENT_SHADER);
	}

	protected int createShader(String shaderCode, int shaderType) throws Exception {
		int shaderId = glCreateShader(shaderType);
		if (shaderId == 0) {
			throw new Exception("Error creating shader. Type: " + shaderType);
		}

		glShaderSource(shaderId, shaderCode);
		glCompileShader(shaderId);

		if (glGetShaderi(shaderId, GL_COMPILE_STATUS) == 0) {
			throw new Exception("Error compiling shader code: " + glGetShaderInfoLog(shaderId, 1024));
		}

		glAttachShader(programId, shaderId);

		return shaderId;
	}

	public void link() throws Exception {
		glLinkProgram(programId);
		if (glGetProgrami(programId, GL_LINK_STATUS) == 0) {
			throw new Exception("Error linking Shader code: " + glGetProgramInfoLog(programId, 1024));
		}

		if (vertexShaderId != 0) {
			glDetachShader(programId, vertexShaderId);
		}
		if (fragmentShaderId != 0) {
			glDetachShader(programId, fragmentShaderId);
		}

		glValidateProgram(programId);
		if (glGetProgrami(programId, GL_VALIDATE_STATUS) == 0) {
			Logger.warning("Warning validating shader code: " + glGetProgramInfoLog(programId, 1024));
		}
	}

	public void bind() {
		glUseProgram(programId);
	}

	public void unbind() {
		glUseProgram(0);
	}

	public void cleanup() {
		if (programId != 0) {
			glDeleteProgram(programId);
		}
	}
}
