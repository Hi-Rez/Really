#include "Library/Blend.metal"

typedef struct {
    float4 color; // color
    float bloom; // slider,0,5,3.0
} BloomUniforms;

fragment float4 bloomFragment(VertexData in [[stage_in]],
                              constant BloomUniforms &uniforms
                              [[buffer(FragmentBufferMaterialUniforms)]],
                              texture2d<float, access::sample> renderTex
                              [[texture(FragmentTextureCustom0)]],
                              texture2d<float, access::sample> renderBlurTex
                              [[texture(FragmentTextureCustom1)]],
                              texture2d<float, access::sample> blurMaskTex
                              [[texture(FragmentTextureCustom2)]]) {
    const float2 uv = in.uv;
    constexpr sampler s = sampler(min_filter::linear, mag_filter::linear);

    const float4 renderSample = renderTex.sample(s, uv);
    const float4 renderBlurSample = renderBlurTex.sample(s, uv);
    const float4 blurMaskSample = blurMaskTex.sample(s, uv);
  
    float4 color = uniforms.color * renderSample;
    color.rgb += blendAdd(color.rgb, renderBlurSample.rgb, uniforms.bloom * blurMaskSample.r);
    return color;
}
