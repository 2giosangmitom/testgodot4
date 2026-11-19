// PSX lit surface, no backface culling (foliage cards, thin walls, cloth, paper).
shader_type spatial;
render_mode vertex_lighting, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://render/shaders/psx_common.gdshaderinc"
#include "res://render/shaders/psx_body.gdshaderinc"
