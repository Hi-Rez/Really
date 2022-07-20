//
//  RealityView+PostProcessing.swift
//  Really
//
//  Created by Reza Ali on 7/19/22.
//

import Foundation
import RealityKit

extension RealityView {
    func setupPostProcessing() {
        arView.renderCallbacks.prepareWithDevice = self.postProcessSetupCallback
        arView.renderCallbacks.postProcess = self.postProcess
        arView.cameraMode = .ar
        arView.environment.background = .cameraFeed()
    }
    
    // MARK: -
    func postProcess(context: ARView.PostProcessContext) {
        updateSatin(context: context)
//        postEffectNone(context: context)
    }
    
    /// This postprocess method is a simple pass-through that doesn't change what RealityKit renders.
    /// When an app has a postprocess render callback function registered, the callback must encode to
    /// `targetColorTexture` or nothing renders. This method uses a blit encoder to copy the
    /// rendered RealityKit scene contained in`sourceColorTexture` to the render output
    /// (`targetColorTexture`).
    func postEffectNone(context: ARView.PostProcessContext) {
        let blitEncoder = context.commandBuffer.makeBlitCommandEncoder()
        blitEncoder?.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
        blitEncoder?.endEncoding()
    }
}
