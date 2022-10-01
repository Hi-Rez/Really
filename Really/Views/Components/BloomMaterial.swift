//
//  BloomMaterial.swift
//  Really
//
//  Created by Reza Ali on 8/3/22.
//

import Foundation
import Satin
import Metal

class BloomMaterial: LiveMaterial {
    var sourceTexture: MTLTexture?
    var renderTexture: MTLTexture?
    var blurTexture: MTLTexture?
    
    override func bind(_ renderEncoder: MTLRenderCommandEncoder) {
        super.bind(renderEncoder)
        renderEncoder.setFragmentTexture(sourceTexture, index: FragmentTextureIndex.Custom0.rawValue)
        renderEncoder.setFragmentTexture(renderTexture, index: FragmentTextureIndex.Custom1.rawValue)
        renderEncoder.setFragmentTexture(blurTexture, index: FragmentTextureIndex.Custom2.rawValue)
    }
}
