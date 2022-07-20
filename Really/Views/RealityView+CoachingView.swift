//
//  RealityView+CoachingView.swift
//  Really
//
//  Created by Reza Ali on 7/19/22.
//

import Foundation
import ARKit
import RealityKit

extension RealityView {
    func setUpCoachingOverlay() {
        coachingView = ARCoachingOverlayView(frame: frame)
        addSubview(coachingView!)
        coachingView?.session = arView.session
        coachingView?.goal = .horizontalPlane
        coachingView?.activatesAutomatically = true
        coachingView?.setActive(true, animated: true)
    }
}
