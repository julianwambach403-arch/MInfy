shader_type spatial;
// Flach liegende Buchseite. Das Bild wird mit Papierrand eingepasst,
// zur Buchmitte (Falz) hin wird es leicht dunkler wie bei einem echten Buch.
render_mode unshaded, cull_back;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 fit = vec4(0.0, 0.0, 1.0, 1.0);   // Bildbereich auf der Seite (x0,y0,x1,y1)
uniform vec2 src = vec2(0.0, 1.0);             // genutzter x-Bereich im Bild (für Doppelseiten)
uniform float has_tex = 0.0;
uniform float spine_left = 1.0;                // 1 = Falz links (rechte Seite), 0 = Falz rechts
uniform vec3 paper : source_color = vec3(0.96, 0.95, 0.91);
uniform float brightness = 1.0;

vec3 page_color(vec2 uv) {
	vec3 c = paper;
	if (has_tex > 0.5 && uv.x >= fit.x && uv.x <= fit.z && uv.y >= fit.y && uv.y <= fit.w) {
		vec2 t = (uv - fit.xy) / (fit.zw - fit.xy);
		t.x = mix(src.x, src.y, t.x);
		c = texture(tex, t).rgb;
	} else if (has_tex < 0.5) {
		// Ladeanzeige: dezente Linien
		c *= 0.97 + 0.03 * step(0.5, fract(uv.y * 30.0));
	}
	return c;
}

void fragment() {
	vec2 uv = UV;
	vec3 c = page_color(uv);
	float d = spine_left > 0.5 ? uv.x : 1.0 - uv.x;
	float gutter = mix(0.72, 1.0, smoothstep(0.0, 0.09, d));
	ALBEDO = c * gutter * brightness;
}
