shader_type spatial;
// Das Blatt, das gerade umgeblättert wird. Es ist am Falz (x = 0) befestigt und
// biegt sich beim Umblättern wie Papier: Der Winkel nimmt entlang des Blatts
// linear zu, die Form ist also ein Kreisbogen (geschlossen integriert).
// theta = 0: liegt rechts, theta = PI: liegt links.
render_mode unshaded, cull_disabled;

uniform float theta = 0.0;
uniform float curl = 0.0;          // zusätzliche Biegung (rad über die Blattbreite)
uniform float width = 0.22;
uniform sampler2D front_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D back_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 front_fit = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 back_fit = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 front_src = vec2(0.0, 1.0);
uniform vec2 back_src = vec2(0.0, 1.0);
uniform float front_has = 0.0;
uniform float back_has = 0.0;
uniform vec3 paper : source_color = vec3(0.96, 0.95, 0.91);
uniform float brightness = 1.0;

varying float shade;

void vertex() {
	float u = clamp(VERTEX.x / width, 0.0, 1.0);   // 0 am Falz, 1 an der Außenkante
	float k = curl;
	float a = theta + k * u;
	vec2 p;
	if (abs(k) < 0.001) {
		p = vec2(cos(theta), sin(theta)) * u;
	} else {
		p = vec2(sin(theta + k * u) - sin(theta), cos(theta) - cos(theta + k * u)) / k;
	}
	VERTEX = vec3(p.x * width, VERTEX.y, p.y * width + 0.0015);
	NORMAL = vec3(-sin(a), 0.0, cos(a));
	// Licht von vorne oben: senkrecht stehendes Papier wird etwas dunkler
	shade = 0.78 + 0.22 * abs(cos(a));
}

vec3 sample_page(sampler2D t, vec4 fit, vec2 src, float has, vec2 uv) {
	if (has > 0.5 && uv.x >= fit.x && uv.x <= fit.z && uv.y >= fit.y && uv.y <= fit.w) {
		vec2 s = (uv - fit.xy) / (fit.zw - fit.xy);
		s.x = mix(src.x, src.y, s.x);
		return texture(t, s).rgb;
	}
	return paper;
}

void fragment() {
	vec3 c;
	if (FRONT_FACING) {
		c = sample_page(front_tex, front_fit, front_src, front_has, UV);
	} else {
		c = sample_page(back_tex, back_fit, back_src, back_has, vec2(1.0 - UV.x, UV.y));
	}
	ALBEDO = c * shade * brightness;
}
