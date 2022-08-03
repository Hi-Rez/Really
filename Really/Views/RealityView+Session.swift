//
//  RealityView+Session.swift
//  Really
//
//  Created by Reza Ali on 7/19/22.
//

import ARKit
import Foundation

extension RealityView: ARSessionDelegate {
    func configureWorldTracking() {
        arView.automaticallyConfigureSession = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection.insert(.horizontal)
        configuration.planeDetection.insert(.vertical)
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        configuration.sceneReconstruction = .mesh

        arView.session.run(configuration)
        arView.renderOptions.insert(.disableMotionBlur)
        arView.renderOptions.insert(.disablePersonOcclusion)
        arView.renderOptions.insert(.disableGroundingShadows)
        arView.renderOptions.insert(.disableDepthOfField)
        arView.renderOptions.insert(.disableAREnvironmentLighting)

        arView.environment.sceneUnderstanding.options.insert(.occlusion)
    }
}
