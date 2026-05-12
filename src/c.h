// used for text rendering and layouting
#include <freetype/ftadvanc.h>
#include <freetype/ftbbox.h>
#include <freetype/ftbitmap.h>
#include <freetype/ftcolor.h>
#include <freetype/ftlcdfil.h>
#include <freetype/ftsizes.h>
#include <freetype/ftstroke.h>
#include <freetype/fttrigon.h>
#include <freetype/ftsynth.h>
#include <hb.h>
#include <hb-ft.h>

// used for rendering, windowing and inputs
#include <glad/gl.h>
// NOTE(blackedout): glad is currently not used on macOS, so use Vulkan header from the Vulkan-Headers repository instead
#ifdef __MACH__
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_beta.h>
#else
#include <glad/vulkan.h>
#endif
#include <GLFW/glfw3.h>

// used for reading and writing image files
#include <stb/stb_image.h>
#include <stb/stb_image_write.h>

// used for loading models
#include <cgltf.h>

// used for virtual memory management on Windows
#ifdef _WIN32
#include <memoryapi.h>
#endif

// used for TLS
#include <mbedtls/debug.h>
#include <mbedtls/ssl.h>

// used to handle sockets in Windows
#ifdef _WIN32
#include <winsock2.h>
#endif

// used in file monitoring
#ifdef _WIN32
#include <windows.h>
#elif defined __linux__
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <errno.h>
#endif

// used for audio
#include <miniaudio.h>
#define STB_VORBIS_HEADER_ONLY
#include <stb/stb_vorbis.h>

// used to compile shaders to SPIR-V
#include <glslang/Include/glslang_c_interface.h>
#include <glslang/Public/resource_limits_c.h>
