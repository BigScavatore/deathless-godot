// Materiale delle armi in prima persona.
//  - FOV proprio (viewmodel_fov), indipendente da quello della camera: il dash non deforma le armi.
//  - Profondità compressa verso il piano vicino: le armi vengono disegnate sempre davanti
//    al mondo, quindi non entrano nei muri (ma restano corrette tra loro: lama davanti all'elsa ecc.).
//  - Texture senza filtro (pixel netti), come il resto dello stile.
shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// Parti luminose (es. cristalli del bastone): emissione = texture * colore * energia.
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float viewmodel_fov : hint_range(30.0, 120.0) = 75.0;
// Frazione della profondità originale che viene mantenuta (più piccola = più "attaccata" alla camera).
uniform float depth_scale : hint_range(0.001, 1.0) = 0.02;

void vertex() {
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Stessa proiezione della camera, solo "zoomata" al FOV delle armi. Si scala invece di
	// sostituire i valori: in alcuni renderer la matrice è ribaltata (segni negativi).
	mat4 projection = PROJECTION_MATRIX;
	float zoom = (1.0 / tan(radians(viewmodel_fov) * 0.5)) / abs(projection[1][1]);
	projection[0][0] *= zoom;
	projection[1][1] *= zoom;
	POSITION = projection * view_position;
	// Profondità invertita (reverse-Z): z = w è il piano vicino. Avviciniamo tutto a quel piano.
	POSITION.z = mix(POSITION.w, POSITION.z, depth_scale);
}

void fragment() {
	vec3 tex = texture(albedo_texture, UV).rgb;
	ALBEDO = tex * albedo_color.rgb;
	EMISSION = tex * emission_color.rgb * emission_energy;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
