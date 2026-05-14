//
//  AuthenticationView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI
import Combine

/// Main authentication coordinator view
struct AuthenticationView: View {
    @StateObject private var authService = AuthenticationService()
    @State private var currentTab: AuthTab = .signIn
    
    enum AuthTab: String, CaseIterable {
        case signIn = "signin"
        case signUp = "signup"
        
        var title: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Sign Up"
            }
        }
        
        var iconName: String {
            switch self {
            case .signIn: return "person.circle"
            case .signUp: return "person.badge.plus"
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > 600 {
                // iPad Layout - Side by side
                HStack(spacing: 0) {
                    // Left side - Welcome/Info
                    welcomeSection
                    
                    // Right side - Auth forms
                    authFormsSection
                }
            } else {
                // iPhone Layout - Stacked
                VStack(spacing: 0) {
                    // Top - Tab selector
                    authTabSelector
                    
                    // Bottom - Auth forms
                    authFormsSection
                }
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.blue.opacity(0.1), .purple.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .ignoresSafeArea(.keyboard)
        .environmentObject(authService)
    }
    
    // MARK: - Welcome Section (iPad only)
    
    private var welcomeSection: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                // Logo and Title
                VStack(spacing: 16) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.primary)
                    
                    Text("ReadForge")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.primary)
                }
                
                // Description
                VStack(spacing: 16) {
                    Text("Transform Your Documents")
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text("Convert PDFs, EPUBs, and text files into natural-sounding audio. Perfect for learning on the go.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Features
                VStack(spacing: 12) {
                    featureRow(icon: "speaker.wave.3", title: "Natural Audio", description: "High-quality text-to-speech")
                    featureRow(icon: "brain.head.profile", title: "Smart Processing", description: "AI-powered text cleanup")
                    featureRow(icon: "icloud.fill", title: "Cloud Sync", description: "Access anywhere")
                    featureRow(icon: "faceid", title: "Secure", description: "Biometric authentication")
                }
            }
            
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
    
    // MARK: - Auth Tab Selector (iPhone only)
    
    private var authTabSelector: some View {
        VStack(spacing: 0) {
            // Header with logo
            VStack(spacing: 16) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.primary)
                
                Text("ReadForge")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }
            .padding(.top, 20)
            
            // Tab selector
            HStack(spacing: 0) {
                ForEach(AuthTab.allCases, id: \.self) { tab in
                    authTabButton(for: tab)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func authTabButton(for tab: AuthTab) -> some View {
        let selected = currentTab == tab
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentTab = tab
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tab.iconName)
                    .font(.title2)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)

                Text(tab.title)
                    .font(.headline)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.primary.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    
    // MARK: - Auth Forms Section
    
    private var authFormsSection: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad - Full width form
                authFormContent
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            } else {
                // iPhone - Tab-based form
                TabView(selection: $currentTab) {
                    ForEach(AuthTab.allCases, id: \.self) { tab in
                        authFormContent
                            .tabItem {
                                Label(tab.title, systemImage: tab.iconName)
                            }
                            .tag(tab)
                    }
                }
                .accentColor(.primary)
            }
        }
        .clipped()
    }
    
    // MARK: - Auth Form Content
    
    @ViewBuilder
    private var authFormContent: some View {
        switch currentTab {
        case .signIn:
            SignInView()
        case .signUp:
            SignUpView()
        }
    }
    
    // MARK: - Feature Row Helper
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

// MARK: - Custom Styles

extension View {
    func roundedBorder() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.primary.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    func borderedProminent() -> some View {
        self
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.primary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
