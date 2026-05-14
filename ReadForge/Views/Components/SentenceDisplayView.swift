//
//  SentenceDisplayView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI

struct SentenceDisplayView: View {
    let sentence: String
    let isAnimating: Bool
    
    var body: some View {
        ScrollView {
            Text(sentence)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.15), value: isAnimating)
        }
    }
}
