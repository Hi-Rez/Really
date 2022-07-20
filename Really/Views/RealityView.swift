//
//  RealityView.swift
//  Really
//
//  Created by Reza Ali on 7/19/22.
//

import ARKit
import Combine
import Foundation
import RealityKit
import SwiftUI
import Satin
import MetalPerformanceShaders


class BloomMaterial: LiveMaterial {
    var sourceTexture: MTLTexture?
    var sourceBlurTexture: MTLTexture?
    var blurTexture: MTLTexture?
    
    override func bind(_ renderEncoder: MTLRenderCommandEncoder) {
        super.bind(renderEncoder)
        renderEncoder.setFragmentTexture(sourceTexture, index: FragmentTextureIndex.Custom0.rawValue)
        renderEncoder.setFragmentTexture(sourceBlurTexture, index: FragmentTextureIndex.Custom1.rawValue)
        renderEncoder.setFragmentTexture(blurTexture, index: FragmentTextureIndex.Custom2.rawValue)
    }
}

class RealityView: ARView {
    /// The main view for the app.
    var arView: ARView { return self }
    
    /// A view that guides the user through capturing the scene.
    var coachingView: ARCoachingOverlayView?
    
    // MARK: - Paths
    
    var assetsURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Assets") }
    var modelsURL: URL { assetsURL.appendingPathComponent("Models") }
    var pipelinesURL: URL { assetsURL.appendingPathComponent("Pipelines") }
    
    // MARK: - Files to load
    
    var cancellables = [AnyCancellable]()
    lazy var modelURL = modelsURL.appendingPathComponent("tv_retro.usdz")
    var modelEntity: ModelEntity?
    var modelAnchor: AnchorEntity?
    
    // MARK: - Satin
    var satinRenderer: Renderer!
    var postProcessor: PostProcessor!
    var postMaterial: BloomMaterial!
    var satinScene = Object("Satin Scene")
    var satinCamera = PerspectiveCamera(position: [0, 0, 5], near: 0.01, far: 100.0)
    var orientation: UIInterfaceOrientation?
    var _updateContext: Bool = true
    var _updateTextures: Bool = true
    var blurTexture: MTLTexture!
    var renderTexture: MTLTexture!
    var renderScale: Float = 0.5
    var blurFilter: MPSImageGaussianBlur!
    var scaleFilter: MPSImageBilinearScale!
    
    // MARK: - Initializers
    
    required init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    @available(*, unavailable)
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup and Configuration
    
    /// RealityKit calls this function before it renders the first frame. This method handles any
    /// setup work that has to be done after the ARView finishes its setup.
    func postProcessSetupCallback(device: MTLDevice) {
        setUpCoachingOverlay()
        setupOrientationAndObserver()
        setupScene()
        setupSatin(device)
        configureWorldTracking()
    }
    
    // MARK: - Private Functions
    
    private func setupScene() {
        Entity.loadModelAsync(contentsOf: modelURL)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Unable to load a model due to error \(error)")
                }
            }, receiveValue: { [self] (model: Entity) in
                if let model = model as? ModelEntity {
                    self.modelEntity = model
                    print("Congrats! Model is successfully loaded!")
                    let anchor = AnchorEntity(plane: .horizontal)
                    anchor.addChild(model)
                    self.scene.anchors.append(anchor)
                    modelAnchor = anchor
                }
            }).store(in: &cancellables)
    }
    
    func setupOrientationAndObserver() {
        orientation = getOrientation()
        NotificationCenter.default.addObserver(self, selector: #selector(RealityView.rotated), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    @objc func rotated() {
        self.orientation = getOrientation()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }
}
