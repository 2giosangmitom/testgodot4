// PSX unlit surface, no backface culling.
shader_type spatial;
render_mode unshaded, cull_disabled;

#define PSX_UNLIT
#include "res://render/shaders/psx_common.gdshaderinc"
#include "res://render/shaders/psx_body.gdshaderinc"
