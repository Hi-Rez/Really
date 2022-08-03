typedef struct {
    float4 color; // color
    float2x2 orientationTransform;
    float2 orientationOffset;
} DepthPassThroughUniforms;

typedef struct {
    float4 position [[position]];
    float3 worldPosition;
    float3 cameraPosition;
    float2 viewportSize;
} CustomVertexData;

vertex CustomVertexData depthPassThroughVertex( Vertex in [[stage_in]],
    constant VertexUniforms &vertexUniforms [[buffer( VertexBufferVertexUniforms )]] )
{
    CustomVertexData out;
    out.worldPosition = float3(vertexUniforms.modelMatrix * in.position);
    out.position = vertexUniforms.modelViewProjectionMatrix * in.position;
    out.cameraPosition = vertexUniforms.worldCameraPosition;
    out.viewportSize = vertexUniforms.viewport.zw;
    return out;
}

fragment float4 depthPassThroughFragment(CustomVertexData in [[stage_in]],
                                   constant DepthPassThroughUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                                   texture2d<float, access::sample> depthTexture [[texture(FragmentTextureCustom0)]]) {
    constexpr sampler s = sampler(min_filter::linear, mag_filter::linear);
    const float2 uv = in.position.xy / in.viewportSize;
    const float2 depthUV = uniforms.orientationTransform * uv + uniforms.orientationOffset;
    const float arDepth = depthTexture.sample(s, depthUV).r;
    float worldDepth = length(in.worldPosition - in.cameraPosition);
    if(arDepth < worldDepth) {
        discard_fragment();
    }
    return uniforms.color;
}
