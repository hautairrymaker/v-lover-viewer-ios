shader_type canvas_item;
render_mode blend_mul, unshaded;

varying vec4 slot_color;

void vertex() {
	slot_color = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV) * slot_color;
	// Transparent texels contribute identity to multiplicative blending.
	COLOR = vec4(mix(vec3(1.0), source.rgb, source.a), 1.0);
}
