shader_type canvas_item;
// AD-149 actor hit flash: fills the sprite silhouette with flash_color; transparent pixels stay transparent.
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(tex.rgb, flash_color.rgb, flash_strength * tex.a), tex.a);
}
