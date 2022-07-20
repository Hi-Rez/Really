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
    
    func setupSatin(_ device: MTLDevice) {
        setupSatinMesh()
        setupFilters(device)
    }
    
    func setupFilters(_ device: MTLDevice) {
        blurFilter = MPSImageGaussianBlur(device: device, sigma: 48.0)
        blurFilter.edgeMode = .clamp
        scaleFilter = MPSImageBilinearScale(device: device)
    }

    func setupSatinMesh() {
        DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
            let asset = MDLAsset(url: self.modelURL, vertexDescriptor: SatinModelIOVertexDescriptor, bufferAllocator: nil)
            
            let container = Object("Model Container")
            
            // I manually pick out the screen
            let parent = asset.object(at: 0)
            if let child = parent.children[2] as? MDLMesh {
                let geo = Geometry()
                
                let vertexData = child.vertexBuffers[0].map().bytes.bindMemory(to: Vertex.self, capacity: child.vertexCount)
                geo.vertexData = Array(UnsafeBufferPointer(start: vertexData, count: child.vertexCount))
                guard let submeshes = child.submeshes, let first = submeshes.firstObject, let sub: MDLSubmesh = first as? MDLSubmesh else { return }
                let indexDataPtr = sub.indexBuffer(asIndexType: .uInt32).map().bytes.bindMemory(to: UInt32.self, capacity: sub.indexCount)
                geo.indexData = Array(UnsafeBufferPointer(start: indexDataPtr, count: sub.indexCount))
                
                let material = Satin.BasicColorMaterial(.one, .alpha)
                let mesh = Mesh(geometry: geo, material: material)
                
                if let childTransform = child.transform {
                    mesh.localMatrix = childTransform.matrix
                    mesh.scale = simd_float3(repeating: 100.0)
                }
                            
                container.onUpdate = { [weak container, weak self] in
                    guard let self = self, let container = container, let model = self.modelEntity, let transform = model.transform else { return }
                    let worldTransform = model.convert(transform: transform, to: nil)
                    container.localMatrix = worldTransform.matrix
                }
                
                container.add(mesh)
            }
            else {
                fatalError("Failed to load mesh")
            }
            
            DispatchQueue.main.async { [unowned self] in
                self.satinScene.add(container)
            }
        }
    }
    
    func setupRenderer(_ context: Context) {
        satinScene.visible = false
        satinRenderer = Renderer(context: context, scene: satinScene, camera: satinCamera)
    }
    
    func setupPostProcessor(_ context: Context) {
        postMaterial = BloomMaterial(pipelinesURL: pipelinesURL)
        postProcessor = PostProcessor(context: context, material: postMaterial)
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
    
    func updateSize(context: ARView.PostProcessContext) {
        let width = Float(context.sourceColorTexture.width)
        let height = Float(context.sourceColorTexture.height)
        let widthRender = width * renderScale
        let heightRender = height * renderScale
        
        // because we don't need a full size render because we are going to blur it
        satinRenderer.resize((widthRender, heightRender))
        
        // this will composite our textures with a bloom material / shader
        postProcessor.resize((width, height))
        
        // you may have to check for orientation changes to make sure the textures & orientation are the right size.
        if let frame = session.currentFrame, let orientation = orientation {
            let viewportSize = CGSizeMake(CGFloat(widthRender), CGFloat(heightRender))
            satinCamera.viewMatrix = frame.camera.viewMatrix(for: orientation)
            satinCamera.projectionMatrix = frame.camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.01, zFar: 100.0)
            satinScene.visible = true
        }
    }
    
    func updateSatinContext(context: ARView.PostProcessContext) {
        if _updateContext {
            let satinContext = Context(context.device, 1, context.compatibleTargetTexture!.pixelFormat)
            setupRenderer(satinContext)
            setupPostProcessor(satinContext)
            _updateContext = false
        }
    }
    
    func updateSatin(context: ARView.PostProcessContext) {
        updateSatinContext(context: context)
        updateTextures(context: context)
        updateSize(context: context)
        
        let commandBuffer = context.commandBuffer
        let targetColorTexture = context.compatibleTargetTexture!
        let sourceColorTexture = context.sourceColorTexture
        
        satinRenderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: renderTexture
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
