#include "Library/Blend.metal"

typedef struct {
    float4 color; // color
    float bloom; // slider,0,5,3.0
} BloomUniforms;

fragment float4 bloomFragment(VertexData in [[stage_in]],
                              constant BloomUniforms &uniforms
                              [[buffer(FragmentBufferMaterialUniforms)]],
                              texture2d<float, access::sample> sourceTex
                              [[texture(FragmentTextureCustom0)]],
                              texture2d<float, access::sample> renderTex
                              [[texture(FragmentTextureCustom1)]],
                              texture2d<float, access::sample> blurTex
                              [[texture(FragmentTextureCustom2)]]) {
    const float2 uv = in.uv;
    constexpr sampler s = sampler(min_filter::linear, mag_filter::linear);

    const float4 sourceSample = sourceTex.sample(s, uv);
    const float4 renderSample = renderTex.sample(s, uv);
    const float4 blurSample = blurTex.sample(s, uv);
  
    float4 color = uniforms.color * sourceSample;
    color.rgb += blendAdd(color.rgb, renderSample.rgb, uniforms.bloom * blurSample.a);
    return color;
}
