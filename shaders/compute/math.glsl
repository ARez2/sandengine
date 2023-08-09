// Gold Noise ©2015 dcerisano@standard3d.com
// - based on the Golden Ratio
// - uniform normalized distribution
// - fastest static noise generator function (also runs at low precision)
// - use with indicated fractional seeding method

const float PHI = 1.61803398874989484820459; // Φ = Golden Ratio 
float gold_noise(in vec2 xy, in float seed) {
    return fract(tan(distance(xy*PHI, xy)*seed)*xy.x);
}



// From Chris Wellons Hash Prospector
// https://nullprogram.com/blog/2018/07/31/
// https://www.shadertoy.com/view/WttXWX
uint hashi(inout uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

// Modified to work with 4 values at once
uvec4 hash4i(inout uint y)
{
    uvec4 x = y * uvec4(213u, 2131u, 21313u, 213132u);
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    y = x.x;
    return x;
}

vec2 old_hash2( vec2 p ) // replace this by something better
{
	p = vec2( dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)) );
	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float hash(inout uint x)
{
    return float( hashi(x) ) / float( 0xffffffffU );
}

vec2 hash2(inout uint x)
{
    return vec2(hash(x), hash(x));
}

vec3 hash3(inout uint x)
{
    return vec3(hash(x), hash(x), hash(x));
}

vec4 hash4(inout uint x)
{
    return vec4( hash4i(x) ) / float( 0xffffffffU );
    //return vec4(hash(x), hash(x), hash(x), hash(x));
}

vec4 hash42(uvec2 p)
{
    uint x = p.x*2131u + p.y*2131u*2131u;
    return vec4( hash4i(x) ) / float( 0xffffffffU );
    //return vec4(hash(x), hash(x), hash(x), hash(x));
}

vec4 hash43(uvec3 p)
{
    uint x = p.x*461u + p.y*2131u + p.z*2131u*2131u;
    return vec4( hash4i(x) ) / float( 0xffffffffU );
    //return vec4(hash(x), hash(x), hash(x), hash(x));
}


float _noise( in vec2 p )
{
    const float K1 = 0.366025404; // (sqrt(3)-1)/2;
    const float K2 = 0.211324865; // (3-sqrt(3))/6;

	vec2  i = floor( p + (p.x+p.y)*K1 );
    vec2  a = p - i + (i.x+i.y)*K2;
    float m = step(a.y,a.x); 
    vec2  o = vec2(m,1.0-m);
    vec2  b = a - o + K2;
	vec2  c = a - 1.0 + 2.0*K2;
    vec3  h = max( 0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
	vec3  n = h*h*h*h*vec3( dot(a,old_hash2(i+0.0)), dot(b,old_hash2(i+o)), dot(c,old_hash2(i+1.0)));
    return 0.25 + 0.5*dot( n, vec3(70.0) );
}

float noise(vec2 p, int octaves, float lacunarity, float frequency) {
    float f = 0.0;
    
    vec2 p2 = p;
    for (int o = 1; o < octaves + 1; o++) {
        f += 1.0 / float(o) * _noise(p2 * frequency);
        p2 *= lacunarity;
    }
    return f;
}

float noise(vec2 p) {
    return noise(p, 1, 2.0, 0.1);
}


vec2 rotatePoint(vec2 pt, float rot) {
  return mat2(cos(rot), -sin(rot), sin(rot), cos(rot)) * pt;
}

vec2 rotatePoint(vec2 pt, float rot, vec2 origin) {
  return rotatePoint(pt - origin, rot) + origin;
}



ivec2[4] getNeighbours(ivec2 pos) {
    ivec2 neighs[4] = {
        pos + UP,
        pos + LEFT,
        pos + RIGHT,
        pos + DOWN,
    };
    return neighs;
}

ivec2[4] getOnlyDiagonalNeighbours(ivec2 pos) {
    ivec2 neighs[4] = {
        pos + UPRIGHT,
        pos + UPLEFT,
        pos + DOWNRIGHT,
        pos + DOWNLEFT,
    };
    return neighs;
}


#define NEIGH_IDX_UP 0
#define NEIGH_IDX_UPLEFT 1
#define NEIGH_IDX_UPRIGHT 2
#define NEIGH_IDX_LEFT 3
#define NEIGH_IDX_RIGHT 4
#define NEIGH_IDX_DOWN 5
#define NEIGH_IDX_DOWNLEFT 6
#define NEIGH_IDX_DOWNRIGHT 7

ivec2[8] getDiagonalNeighbours(ivec2 pos) {
    ivec2 neighs[8] = {
        pos + DOWN,
        pos + UP,
        pos + DOWNLEFT,
        pos + UPLEFT,
        pos + DOWNRIGHT,
        pos + UPRIGHT,
        pos + RIGHT,
        pos + LEFT,
    };
    return neighs;
}