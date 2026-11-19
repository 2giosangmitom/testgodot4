// PSX unlit surface: signs, screens, sky cards, emissive tubes. Still snapped, affine and fogged
// (set fog_mult = 0 for sky cards). emit_level (instance uniform) dims it to off_level.
shader_type spatial;
render_mode unshaded, cull_back;

#define PSX_UNLIT
#include "res://render/shaders/psx_common.gdshaderinc"
#include "res://render/shaders/psx_body.gdshaderinc"
