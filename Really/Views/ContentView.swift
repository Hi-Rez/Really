//
//  ContentView.swift
//  Really
//
//  Created by Reza Ali on 7/12/22.
//

import Combine
import RealityKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        return ARViewContainer().edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {
    public typealias UIViewType = RealityView

    func makeUIView(context: Context) -> RealityView {
        let view = RealityView(frame: .zero)
        view.setupPostProcessing()
        return view
    }

    func updateUIView(_ uiView: RealityView, context: Context) {}
}
