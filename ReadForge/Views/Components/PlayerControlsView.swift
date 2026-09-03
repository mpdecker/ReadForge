//
//  PlayerControlsView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI

struct PlayerControlsView: View {
    @Bindable var viewModel: PlayerViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // Speed Control
            speedControl
            
            // Transport Controls
            transportControls
            
            // Progress Label
            progressLabel
        }
        .padding(.vertical, 16)
        .background(.regularMaterial)
    }
    
    // MARK: - Subviews
    
    private var speedControl: some View {
        Picker("Speed", selection: $viewModel.playbackRate) {
            Text("0.75×").tag(Float(0.75))
            Text("1×").tag(Float(1.0))
            Text("1.25×").tag(Float(1.25))
            Text("1.5×").tag(Float(1.5))
            Text("2×").tag(Float(2.0))
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    // Every control below is icon-only, so each needs an explicit label: SF Symbol images carry
    // no accessible name of their own, which left VoiceOver announcing these as an unlabelled
    // "button" and made them unaddressable from UI tests.
    private var transportControls: some View {
        HStack(spacing: 44) {
            Button { viewModel.skipBack() } label: {
                Image(systemName: "gobackward.15").font(.title)
            }
            .disabled(!viewModel.canSkipBack)
            .accessibilityLabel("Skip Back")
            .accessibilityHint("Goes back fifteen seconds")

            playPauseButton

            Button { viewModel.skipForward() } label: {
                Image(systemName: "goforward.15").font(.title)
            }
            .accessibilityLabel("Skip Forward")
            .accessibilityHint("Goes forward fifteen seconds")
        }
    }

    private var playPauseButton: some View {
        let isPlaying = viewModel.playbackState == .playing
        return Button {
            viewModel.togglePlayPause()
        } label: {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 68))
                .foregroundStyle(.tint)
        }
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
    
    private var progressLabel: some View {
        Text(viewModel.progressLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
    }
}
