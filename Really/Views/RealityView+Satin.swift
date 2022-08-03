//
//  RealityView+Satin.swift
//  Really
//
//  Created by Reza Ali on 7/19/22.
//

import ARKit
import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders
import ModelIO
import RealityKit
import Satin
import simd

extension RealityView {
    func getOrientation() -> UIInterfaceOrientation? {
        return window?.windowScene?.interfaceOrientation
    }
    
    func setupSatin(device: MTLDevice) {
        setupSatinMesh()
//        setupDebugMesh()
        setupFilters(device: device)
        setupDepthTextureCache(device: device)
    }
    
    func setupFilters(device: MTLDevice) {
        blurFilter = MPSImageGaussianBlur(device: device, sigma: 48.0)
        blurFilter.edgeMode = .clamp
        scaleFilter = MPSImageBilinearScale(device: device)
    }

    func setupSatinMesh() {
        DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
            let asset = MDLAsset(url: self.modelURL, vertexDescriptor: SatinModelIOVertexDescriptor, bufferAllocator: nil)
            
            // I manually pick out the screen
            let parent = asset.object(at: 0)
            if let child = parent.children[2] as? MDLMesh {
                let geo = Geometry()
                
                let vertexData = child.vertexBuffers[0].map().bytes.bindMemory(to: Vertex.self, capacity: child.vertexCount)
                geo.vertexData = Array(UnsafeBufferPointer(start: vertexData, count: child.vertexCount))
                guard let submeshes = child.submeshes, let first = submeshes.firstObject, let sub: MDLSubmesh = first as? MDLSubmesh else { return }
                let indexDataPtr = sub.indexBuffer(asIndexType: .uInt32).map().bytes.bindMemory(to: UInt32.self, capacity: sub.indexCount)
                geo.indexData = Array(UnsafeBufferPointer(start: indexDataPtr, count: sub.indexCount))
                
                let material = DepthPassThroughMaterial(pipelinesURL: pipelinesURL)
                material.depthBias = DepthBias(bias: 1000, slope: 1000, clamp: 1000)
                
                material.onUpdate = { [weak self] in
                    guard let self = self, let frame = self.session.currentFrame, let orientation = self.orientation else { return }
                    let orientationTransform = frame.displayTransform(for: orientation, viewportSize: .init(width: self.renderTexture.width, height: self.renderTexture.height)).inverted()
                    material.set("Orientation Transform", simd_float2x2(
                        .init(Float(orientationTransform.a), Float(orientationTransform.b)),
                        .init(Float(orientationTransform.c), Float(orientationTransform.d))
                    ))
                    material.set("Orientation Offset", simd_make_float2(Float(orientationTransform.tx), Float(orientationTransform.ty)))
                    material.updateUniforms()
                }
                
                material.onBind = { [weak self] (renderEncoder: MTLRenderCommandEncoder) in
                    guard let self = self, let cvDepthTexture = self.capturedDepthTexture else { return }
                    renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(cvDepthTexture), index: FragmentTextureIndex.Custom0.rawValue)
                }
                
                satinMesh = Mesh(geometry: geo, material: material)
                
                if let childTransform = child.transform {
                    satinMesh.localMatrix = childTransform.matrix
                    satinMesh.scale = simd_float3(repeating: 100.0)
                }
                
                satinMeshContainer.add(satinMesh)
                satinScene.add(satinMeshContainer)
            } else {
                fatalError("Failed to load mesh")
            }
        }
    }
    
    func setupDebugMesh() {
        let debugMaterial = DebugDepthMaterial(pipelinesURL: pipelinesURL)
        
        debugMaterial.onUpdate = { [weak self] in
            guard let self = self, let frame = self.session.currentFrame, let orientation = self.orientation else { return }
            let orientationTransform = frame.displayTransform(for: orientation, viewportSize: .init(width: self.renderTexture.width, height: self.renderTexture.height)).inverted()
            debugMaterial.set("Orientation Transform", simd_float2x2(
                .init(Float(orientationTransform.a), Float(orientationTransform.b)),
                .init(Float(orientationTransform.c), Float(orientationTransform.d))
            ))
            debugMaterial.set("Orientation Offset", simd_make_float2(Float(orientationTransform.tx), Float(orientationTransform.ty)))
            debugMaterial.updateUniforms()
        }
        
        debugMaterial.onBind = { [weak self] (renderEncoder: MTLRenderCommandEncoder) in
            guard let self = self, let cvDepthTexture = self.capturedDepthTexture else { return }
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(cvDepthTexture), index: FragmentTextureIndex.Custom0.rawValue)
        }
        
        let debugMesh = Mesh(geometry: QuadGeometry(), material: debugMaterial)
        
        let dist: Float = -1.0
        debugMesh.position = [0, 0, dist]
        debugMesh.onUpdate = { [weak self] in
            guard let self = self else { return }
            let theta = degToRad(self.satinCamera.fov * 0.5)
            let aspect = self.satinCamera.aspect // w / h
            let halfHeight = dist * tan(theta)
            let halfWidth = aspect * halfHeight
            debugMesh.scale = [halfWidth, halfHeight, 1.0]
        }
        
        satinScene.add(debugMesh, false)
        satinCamera.add(debugMesh)
    }
    
    func setupRenderer(_ context: Context) {
        satinScene.visible = false
        satinRenderer = Renderer(context: context, scene: satinScene, camera: satinCamera)
        satinRenderer.colorLoadAction = .clear
        satinRenderer.depthLoadAction = .load
    }
    
    func setupPostProcessor(_ context: Context) {
        postMaterial = BloomMaterial(pipelinesURL: pipelinesURL)
        postProcessor = PostProcessor(context: context, material: postMaterial)
    }
    
    func updateSatinContext(context: ARView.PostProcessContext) {
        if _updateContext {
            let satinRendererContext = Context(context.device, 1, context.compatibleTargetTexture!.pixelFormat, .depth32Float)
            setupRenderer(satinRendererContext)
            let postProcessingContext = Context(context.device, 1, context.compatibleTargetTexture!.pixelFormat)
            setupPostProcessor(postProcessingContext)
            _updateContext = false
        }
    }
    
    func updateTextures(context: ARView.PostProcessContext) {
        let width = Int(Float(context.targetColorTexture.width) * renderScale)
        let height = Int(Float(context.targetColorTexture.height) * renderScale)
        
        if let blurTexture = blurTexture, blurTexture.width != width || blurTexture.height != height {
            _updateTextures = true
        }
        
        if _updateTextures {
            blurTexture = createTexture("Blur Texture", width, height, context.compatibleTargetTexture!.pixelFormat, context.device)
            renderTexture = createTexture("Render Texture", width, height, context.compatibleTargetTexture!.pixelFormat, context.device)
            _updateTextures = false
        }
    }
    
    // MARK: - Depth
        
    func updateDepthTexture(context: ARView.PostProcessContext) {
        guard let frame = session.currentFrame else { return }
        if let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap {
            if let depthTexturePixelFormat = setMTLPixelFormat(basedOn: depthMap) {
                capturedDepthTexture = createDepthTexture(fromPixelBuffer: depthMap, pixelFormat: depthTexturePixelFormat, planeIndex: 0)
            }
        }
    }
    
    func setupDepthTextureCache(device: MTLDevice) {
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedDepthTextureCache = textureCache
    }
    
    func createDepthTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedDepthTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    func setMTLPixelFormat(basedOn pixelBuffer: CVPixelBuffer!) -> MTLPixelFormat? {
        if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32 {
            return .r32Float
        } else if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 {
            return .r8Uint
        } else {
            return nil
        }
    }
    
    func updateSize(context: ARView.PostProcessContext) {
        let width = Float(context.sourceColorTexture.width)
        let height = Float(context.sourceColorTexture.height)
        let widthRender = width * renderScale
        let heightRender = height * renderScale
        
        // because we don't need a full size render because we are going to blur it
        satinRenderer.resize((widthRender, heightRender))
        
        // this will composite our textures with a bloom material / shader
        postProcessor.resize((width, height))
    }
    
    func updateCamera(context: ARView.PostProcessContext) {
        // you may have to check for orientation changes to make sure the textures & orientation are the right size.
        if let _ = session.currentFrame {
            satinCamera.viewMatrix = arView.cameraTransform.matrix.inverse
            satinCamera.projectionMatrix = context.projection
            satinScene.visible = true
        }
    }
    
    func updateSatin(context: ARView.PostProcessContext) {
        updateSatinContext(context: context)
        updateTextures(context: context)
        updateDepthTexture(context: context)
        updateSize(context: context)
        updateCamera(context: context)
        
        if let model = modelEntity {
            let worldTransform = model.convert(transform: model.transform, to: nil)
            satinMeshContainer.localMatrix = worldTransform.matrix
        }
                    
        let commandBuffer = context.commandBuffer
        let targetColorTexture = context.compatibleTargetTexture!
        let sourceColorTexture = context.sourceColorTexture
        
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = renderTexture
        rpd.depthAttachment.texture = context.sourceDepthTexture

        satinRenderer.setClearColor([0.0, 0.0, 0.0, 0.0])
        satinRenderer.draw(
            renderPassDescriptor: rpd,
            commandBuffer: commandBuffer
        )
        
        blurFilter.encode(
            commandBuffer: commandBuffer,
            sourceTexture: renderTexture,
            destinationTexture: blurTexture
        )

        scaleFilter.encode(
            commandBuffer: commandBuffer,
            sourceTexture: sourceColorTexture,
            destinationTexture: renderTexture
        )

        blurFilter.encode(
            commandBuffer: commandBuffer,
            inPlaceTexture: &renderTexture
        )

        postMaterial.sourceTexture = sourceColorTexture
        postMaterial.sourceBlurTexture = renderTexture
        postMaterial.blurTexture = blurTexture

        postProcessor.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: targetColorTexture
        )
    }
    
    func createTexture(_ label: String,
                       _ width: Int,
                       _ height: Int,
                       _ pixelFormat: MTLPixelFormat,
                       _ device: MTLDevice,
                       _ usage: MTLTextureUsage = [.renderTarget, .shaderRead, .shaderWrite],
                       _ storageMode: MTLStorageMode = .private,
                       _ resourceOptions: MTLResourceOptions = .storageModePrivate) -> MTLTexture?
    {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.sampleCount = 1
        descriptor.textureType = .type2D
        descriptor.usage = usage
        descriptor.storageMode = .private
        descriptor.resourceOptions = resourceOptions
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        return texture
    }
}
