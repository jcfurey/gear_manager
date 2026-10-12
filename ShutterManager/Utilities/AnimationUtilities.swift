//
//  AnimationUtilities.swift
//  ShutterManager
//

import SwiftUI

/// Collection of reusable animation utilities and view modifiers for consistent app-wide animations
enum AnimationUtilities {
    
    // MARK: - Standard Animations
    
    /// Smooth spring animation for most UI interactions
    static let smooth = Animation.spring(response: 0.4, dampingFraction: 0.8)
    
    /// Quick spring animation for immediate feedback
    static let quick = Animation.spring(response: 0.3, dampingFraction: 0.7)
    
    /// Bouncy animation for playful interactions
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.6)
    
    /// Gentle animation for subtle changes
    static let gentle = Animation.easeInOut(duration: 0.3)
    
    /// Slow animation for dramatic effects
    static let slow = Animation.easeInOut(duration: 0.6)
    
    // MARK: - Specialized Animations
    
    /// Animation for card appearances
    static let cardAppear = Animation.spring(response: 0.5, dampingFraction: 0.75)
    
    /// Animation for list item appearances
    static let listItemAppear = Animation.easeOut(duration: 0.25)
    
    /// Animation for modal presentations
    static let modalPresent = Animation.spring(response: 0.4, dampingFraction: 0.8)
    
    /// Animation for button presses
    static let buttonPress = Animation.spring(response: 0.2, dampingFraction: 0.5)
}

// MARK: - View Extensions

extension View {
    
    // MARK: - Appear Animations
    
    /// Fade in animation on appear
    func fadeIn(duration: Double = 0.3, delay: Double = 0) -> some View {
        self.modifier(FadeInModifier(duration: duration, delay: delay))
    }
    
    /// Slide in from bottom animation
    func slideInFromBottom(duration: Double = 0.4, delay: Double = 0) -> some View {
        self.modifier(SlideInFromBottomModifier(duration: duration, delay: delay))
    }
    
    /// Slide in from leading edge
    func slideInFromLeading(duration: Double = 0.4, delay: Double = 0) -> some View {
        self.modifier(SlideInFromLeadingModifier(duration: duration, delay: delay))
    }
    
    /// Scale in animation (zoom effect)
    func scaleIn(duration: Double = 0.3, delay: Double = 0) -> some View {
        self.modifier(ScaleInModifier(duration: duration, delay: delay))
    }
    
    // MARK: - Interactive Animations
    
    /// Button press animation (scale down on tap)
    func pressAnimation() -> some View {
        self.modifier(PressAnimationModifier())
    }
    
    /// Card hover animation (slight scale up)
    func cardHover() -> some View {
        self.modifier(CardHoverModifier())
    }
    
    // MARK: - Shimmer Effects
    
    /// Shimmer loading effect
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
    
    // MARK: - Rotation
    
    /// Continuous rotation animation
    func continuousRotation(duration: Double = 1.0) -> some View {
        self.modifier(ContinuousRotationModifier(duration: duration))
    }
}

// MARK: - Animation Modifiers

struct FadeInModifier: ViewModifier {
    let duration: Double
    let delay: Double
    
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: duration).delay(delay)) {
                    opacity = 1
                }
            }
    }
}

struct SlideInFromBottomModifier: ViewModifier {
    let duration: Double
    let delay: Double
    
    @State private var offset: CGFloat = 50
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: duration, dampingFraction: 0.8).delay(delay)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

struct SlideInFromLeadingModifier: ViewModifier {
    let duration: Double
    let delay: Double
    
    @State private var offset: CGFloat = -50
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: duration, dampingFraction: 0.8).delay(delay)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

struct ScaleInModifier: ViewModifier {
    let duration: Double
    let delay: Double
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: duration, dampingFraction: 0.7).delay(delay)) {
                    scale = 1.0
                    opacity = 1
                }
            }
    }
}

struct PressAnimationModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(AnimationUtilities.buttonPress, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

struct CardHoverModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
            .animation(AnimationUtilities.smooth, value: isHovered)
            .onTapGesture {
                isHovered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isHovered = false
                }
            }
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

struct ContinuousRotationModifier: ViewModifier {
    let duration: Double
    @State private var isRotating = false
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    isRotating = true
                }
            }
    }
}

// MARK: - List Item Animations

extension View {
    /// Animate a list item in on appear with a staggered delay based on its position.
    func listItemAnimation(index: Int, total: Int) -> some View {
        modifier(ListItemAppearModifier(index: index))
    }
}

/// Drives the staggered fade/slide-in for `listItemAnimation`. Holds the `appeared`
/// state the bare modifier lacked, so the view actually transitions from hidden to shown
/// (the previous implementation set opacity 0 and never restored it).
private struct ListItemAppearModifier: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        let delay = min(Double(index) * 0.05, 0.3)
        return content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay)) {
                    appeared = true
                }
            }
    }
}

// MARK: - Transition Extensions

extension AnyTransition {
    /// Custom slide and fade transition
    static var slideAndFade: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
    
    /// Scale and fade transition
    static var scaleAndFade: AnyTransition {
        .scale(scale: 0.8).combined(with: .opacity)
    }
    
    /// Pop transition (scale from center)
    static var pop: AnyTransition {
        .scale(scale: 0.5).combined(with: .opacity)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 30) {
            Text("Fade In")
                .font(.title)
                .fadeIn()
            
            Text("Slide From Bottom")
                .font(.title)
                .slideInFromBottom(delay: 0.2)
            
            Text("Slide From Leading")
                .font(.title)
                .slideInFromLeading(delay: 0.4)
            
            Text("Scale In")
                .font(.title)
                .scaleIn(delay: 0.6)
            
            Button("Press Animation") { }
            .buttonStyle(.borderedProminent)
            .pressAnimation()
            
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue)
                .frame(width: 200, height: 100)
                .overlay(Text("Card Hover").foregroundColor(.white))
                .cardHover()
            
            Text("Shimmer Effect")
                .font(.title)
                .shimmer()
            
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 40))
                .continuousRotation()
        }
        .padding()
    }
}
