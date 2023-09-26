#define RGBA_UNORM float4
#define F16x2 uint
#define F16x4 uint2
#define F16x6 uint3
#define F16x8 uint4

#define IDENTITY_MATRIX float4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)

#define LINEAR linear
#define FLAT nointerpolation

#define AA_Linear (0)
#define AA_Crisp (1)
#define AA_Smooth (2)

float2 uint_to_float2(uint a) {
	float2 b;
	b.x = f16tof32(a & 0xFFFF);
	b.y = f16tof32(a >> 16);
	return b;
}

uint get_bits(uint n, uint start, uint count) {
    // Create a bitmask of the desired length
    uint mask = (1 << count) - 1;
    // Shift the number to the right to move the desired bits to the rightmost position
    // and apply the mask to extract them
    return (n >> start) & mask;
}

float4 normalize_pos(float2 pos, float2 framebuffer_size) {
	// [0;1]
	pos /= framebuffer_size;
	// [-1; 1]
	pos.x = (pos.x * 2) - 1;
	pos.y = (pos.y * -2) + 1;
	return mul(float4(pos, 0, 1), IDENTITY_MATRIX);
}

float2 aa_crisp(float2 pix) {
	return floor(pix) + 0.5;
}

float2 aa_smooth(float2 pix) {
	return floor(pix) + min(frac(pix) / fwidth(pix), 1) - 0.5;
}
