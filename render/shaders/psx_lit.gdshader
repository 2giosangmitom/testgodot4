// PSX lit surface: vertex lighting, vertex snapping, affine UVs, 15-bit colour, linear fog.
shader_type spatial;
render_mode vertex_lighting, cull_back, diffuse_lambert, specular_disabled;

#include "res://render/shaders/psx_common.gdshaderinc"
#include "res://render/shaders/psx_body.gdshaderinc"
