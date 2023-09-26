// This is a shader for drawing various shapes on a flat 2D plane
// Useful for simple 2D games and UI programs
#include "common.h"

// SDF shapes need some padding to allow for softening
#define SDF_PADDING (2)

// Shape types
#define ST_Rectangle (0)
#define ST_Circle (1)
#define ST_Line (2)

struct VS_Input {
	uint vertex_id: SV_VERTEXID;

	uint shape_info: INFO;
	float softness: SOFT;
	// RECT: position + size
	// LINE: points
	// CIRCLE: position + radius[0]
	float2 coord[2]: COORD;
	RGBA_UNORM color: COL;

	// Only for rectangles
	// TODO: have 4 instead of 1 (maybe even [4]u16)
	float corner_radius: RAD;

	// For untextured shapes
	float outline_size: OUTLINE;
	// For textured shapes
	uint anti_aliasing: AA;
	uint tex_slot: TEX_SLOT;
	uint2 tex_pos: TEX_POS;
	uint2 tex_size: TEX_SIZE;
};

struct PS_Input {
	LINEAR float4 position: SV_POSITION;

	// Unpacked shape_info
	FLAT uint shape_type: ST;
	FLAT float softness: SOFT;
	FLAT float2 coord[2]: COORD;
	FLAT float4 color: COL;
	// Only for rectangles
	FLAT float corner_radius: RAD;

	FLAT bool textured: TEXTURED;
	// For untextured shapes
	FLAT float outline_size: OUTLINE;
	// For textured shapes
	FLAT uint anti_aliasing: AA;
	FLAT uint tex_slot: TEX_SLOT;
	LINEAR float2 tex_pos: TEX_POS;
	// Prevents texture from being sampled outside this range, regardless of vertices (useful for soft SDFs)
	FLAT float4 tex_bounds: TEX_BOUNDS;
};

struct PS_Output {
	float4 color: SV_TARGET;
};

cbuffer Constants: register(b0) {
	uint2 framebuffer_size;
};

SamplerState pointsampler: register(s0);

Texture2DArray<RGBA_UNORM> textures: register(t0);


PS_Input vs_main(VS_Input input) {
	uint2 index = { input.vertex_id & 2, (input.vertex_id << 1 & 2) ^ 3 };

	PS_Input output = (PS_Input)0;

	output.shape_type = get_bits(input.shape_info, 0, 16);
	output.textured = get_bits(input.shape_info, 16, 16);

	if (output.textured) {
		output.anti_aliasing = input.anti_aliasing;
		output.tex_slot = input.tex_slot;

		// Get vertex texture position
		float4 tex_coord;
		tex_coord.x = input.tex_pos.x;
		tex_coord.y = input.tex_pos.y;
		tex_coord.z = tex_coord.x + input.tex_size[0];
		tex_coord.w = tex_coord.y + input.tex_size[1];

		// For proper interpolation
		tex_coord.xy -= SDF_PADDING;
		tex_coord.zw += SDF_PADDING;
		output.tex_pos = float2(tex_coord[index[0]], tex_coord[index[1]]);
	}

	output.softness = input.softness;
	output.color = input.color;
	output.corner_radius = input.corner_radius;
	output.coord = input.coord;

	float2 pos = 0;
	switch (output.shape_type) {
		case ST_Rectangle: {
			// Get vertex position
			float4 coord;
			coord.xy = input.coord[0];
			coord.zw = input.coord[0] + input.coord[1];
			coord.xy -= SDF_PADDING;
			coord.zw += SDF_PADDING;
			pos = float2(coord[index[0]], coord[index[1]]);

			// Avoids SDF padding pixels, since textures are not SDF
			output.tex_bounds = float4(input.coord[0], input.coord[0] + input.coord[1]);
		} break;

		case ST_Circle: {
			// Get vertex position
			float4 coord;
			coord.xy = input.coord[0] - input.coord[1][0];
			coord.zw = input.coord[0] + input.coord[1][0];
			coord.xy -= SDF_PADDING;
			coord.zw += SDF_PADDING;
			pos = float2(coord[index[0]], coord[index[1]]);

			// TODO: Textured, tex_bounds
		} break;

		case ST_Line: {
			float2 d = normalize(input.coord[1] - input.coord[0]);
			float2 n = float2(-d.y, d.x);

			float extendAmount = SDF_PADDING + input.softness;
			float z = (input.outline_size) + SDF_PADDING;

			// Extend the starting and ending points of the line
			float2 extendedA = input.coord[0] - d * extendAmount;
			float2 extendedB = input.coord[1] + d * extendAmount;

			// Now, create 4 points for the extended rectangle
			float2 quad[4];
			quad[0] = extendedA + n * z;
			quad[1] = extendedA - n * z;
			quad[2] = extendedB + n * z;
			quad[3] = extendedB - n * z;

			pos = quad[input.vertex_id];
		} break;
	}

	output.position = normalize_pos(pos, framebuffer_size);

	output.outline_size = input.outline_size;

	return output;
}

float rect_sdf(float2 absolute_pixel_position, float2 rect_center, float2 float_size, float corner_radius) {
	// Change coordinate space so that the rectangle's center is at the origin,
	// taking advantage of the problem's symmetry.
	float2 pixel_position = abs(absolute_pixel_position - rect_center);

	// Shrink rectangle by the corner radius.
	float2 shrunk_corner_position = float_size - corner_radius;

	// Determine the distance vector from the pixel to the rectangle corner,
	// disallowing negative components to simplify the three cases.
	float2 pixel_to_shrunk_corner = max(float2(0, 0), pixel_position - shrunk_corner_position);
	float distance_to_shrunk_corner = length(pixel_to_shrunk_corner);

	// Subtract the corner radius from the calculated distance to produce a
	// rectangle having the desired size.
	return distance_to_shrunk_corner - corner_radius;
}

// distance of point x from line ab
float line_sdf(float2 a, float2 b, float2 p)
{
    float2 pa = p - a, ba = b - a;
    float2 pb = p - b, ab = a - b;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

bool is_point_in_rect(float2 p, float4 rect) {
    // Check if p is to the right of the top-left corner and to the left of the bottom-right corner
    bool in_x = (p.x >= rect.x && p.x <= rect.z);

    // Check if p is below the top-left corner and above the bottom-right corner
    bool in_y = (p.y >= rect.y && p.y <= rect.w);

    // If both conditions are met, the point is within the rectangle
    return in_x && in_y;
}

PS_Output ps_main(PS_Input input) {
	PS_Output output = (PS_Output)0;
	output.color = input.color;

	float2 sample_pos = input.position.xy;

	if (input.textured) {
		if (!is_point_in_rect(sample_pos, input.tex_bounds)) {
			discard;
			return output;
		}

		// Texture sampling
		float3 texture_size;
		textures.GetDimensions(texture_size[0], texture_size[1], texture_size[2]);
		float2 pix = input.tex_pos;

		switch (input.anti_aliasing) {
			case AA_Linear:
			{} break;

			case AA_Crisp:
			{
				pix = aa_crisp(pix);
			} break;

			case AA_Smooth:
			{
				pix = aa_smooth(pix);
			} break;
		}

		float4 sample = textures.Sample(pointsampler, float3(pix / texture_size.xy, input.tex_slot));

		// 8 for above, 5 for fluctuating
		// for (uint i = 0; i < 250 * 8; i += 1) {
		// 	sample += float4(0.0001, 0.0001, 0.0001, 0.0001); // or some other small operation
		// }

		output.color *= sample;
	}

	switch(input.shape_type) {
		case ST_Rectangle: {
			float2 rect_half_size = input.coord[1] / 2;
			float2 rect_center = input.coord[0] + rect_half_size;
			float2 softness_padding = float2(max(0, input.softness - 1), max(0, input.softness - 1));

			// Hollow rectangle
			if (input.outline_size > 0) {
				float2 interior_float_size = rect_half_size - input.outline_size;
				// reduction factor for the internal corner radius.
				// not 100% sure the best way to go about this, but this is the best thing I've found so far!
				//
				// this is necessary because otherwise it looks weird
				float interior_radius_reduce_f = min(interior_float_size.x / rect_half_size.x, interior_float_size.y / rect_half_size.y);
				float interior_corner_radius = input.corner_radius * interior_radius_reduce_f * interior_radius_reduce_f;

				// calculate sample distance from "interior"
				float inside_d = rect_sdf(sample_pos, rect_center, interior_float_size - softness_padding, interior_corner_radius);

				// map distance => factor
				float border_factor = smoothstep(0, input.softness, inside_d);
				output.color *= border_factor;
			}

			// Rounding
			float dist = rect_sdf(sample_pos, rect_center, rect_half_size - softness_padding, input.corner_radius);
			float sdf_factor = 1 - smoothstep(0, input.softness, dist);
			output.color *= sdf_factor;
		} break;

		case ST_Circle: {
			float2 center = input.coord[0];
			float radius = input.coord[1][0];

			float dist = distance(center, sample_pos) - radius;

			// Hollow circle
			if (input.outline_size > 0) {
				float sdf_inner = smoothstep(0, input.softness, dist + input.outline_size);
				float sdf_outer = smoothstep(0, input.softness, dist);
				float sdf_factor = sdf_inner - sdf_outer;
				output.color *= sdf_factor;
			} else {
				float sdf_factor = 1 - smoothstep(0, input.softness, dist);
				output.color *= sdf_factor;
			}
		} break;

		case ST_Line: {
			float2 a = input.coord[0];
			float2 b = input.coord[1];
			float half_thickness = input.outline_size * 0.5;

			float dist = line_sdf(a, b, sample_pos) - half_thickness;
			float sdf_factor = 1 - smoothstep(0, input.softness, dist);

			output.color *= sdf_factor;

			// output.color = input.color;

			// if (sdf_factor <= 0.5) {
			// 	output.color = float4(0, 0, 1, 1);
			// }
		} break;
	}

	return output;
}
