#include "common.h"

// Padding for shadows
#define SHADOW_PADDING (1)

struct VS_Input {
	uint vertex_id: SV_VERTEXID;

	float2 pos: POS;
	float scale: SCALE;
	RGBA_UNORM color: COL;
	uint sdf: SDF;
	uint2 bmp_pos: BMP_POS;
	uint2 bmp_size: BMP_SIZE;
};

struct PS_Input {
	LINEAR float4 pos: SV_POSITION;

	FLAT float scale: SCALE;
	FLAT float4 color: COL;
	FLAT uint tex_slot: TEX_SLOT;
	LINEAR float2 tex_pos: TEX_POS;
};

struct PS_Output {
	float4 color: SV_TARGET;
};

cbuffer Constants: register(b0) {
	uint2 framebuffer_size;
};

SamplerState pointsampler: register(s0);

Texture2D<RGBA_UNORM> glyph_atlas: register(t0);

PS_Input vs_main(VS_Input input) {
	uint2 index = { input.vertex_id & 2, (input.vertex_id << 1 & 2) ^ 3 };

	PS_Input output = (PS_Input)0;

	// Vertex position
	float4 coord;
	coord.xy = input.pos;
	coord.zw = input.pos + (input.bmp_size * input.scale);
	coord.xy -= SHADOW_PADDING;
	coord.zw += SHADOW_PADDING;
	float2 pos = float2(coord[index[0]], coord[index[1]]);
	output.pos = normalize_pos(pos, framebuffer_size);

	output.scale = input.scale;
	output.color = input.color;

	// Texture position
	float4 tex_coord;
	tex_coord.xy = input.bmp_pos;
	tex_coord.zw = input.bmp_pos + input.bmp_size;
	tex_coord.xy -= SHADOW_PADDING;
	tex_coord.zw += SHADOW_PADDING;
	output.tex_pos = float2(tex_coord[index[0]], tex_coord[index[1]]);

	return output;
}

PS_Output ps_main(PS_Input input) {
	PS_Output output = (PS_Output)0;
	output.color = input.color;

	float2 pix = input.tex_pos;
	if (input.scale == 1) {
		pix = aa_crisp(pix);
	} else if (input.scale >= 1) {
		pix = aa_smooth(pix);
	}

	float2 texture_size;
	glyph_atlas.GetDimensions(texture_size[0], texture_size[1]);
	float4 sample = glyph_atlas.Sample(pointsampler, pix / texture_size);
	// for (uint i = 0; i < 250 * 12; i += 1) {
	// 	sample = textures.Sample(pointsampler, pix / texture_size);
	// }
	output.color *= sample;

	return output;
}
