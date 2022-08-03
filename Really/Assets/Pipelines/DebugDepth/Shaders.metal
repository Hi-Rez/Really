typedef struct {
    float4 color; // color
    float2x2 orientationTransform;
    float2 orientationOffset;
} DebugDepthUniforms;

fragment float4 debugDepthFragment(VertexData in [[stage_in]],
                                   constant DebugDepthUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                                   texture2d<float, access::sample> depthTexture [[texture(FragmentTextureCustom0)]]) {
    constexpr sampler s = sampler(min_filter::linear, mag_filter::linear);
    const float2 uv = 1.0 - in.uv;
    const float2 depthUV = uniforms.orientationTransform * uv + uniforms.orientationOffset;
    const float depth = depthTexture.sample(s, depthUV).r;
    return float4(depth, 0.0, 0.0, 1.0);
}
