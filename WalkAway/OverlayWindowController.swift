import AppKit
import SwiftUI

// Extension to convert NSBezierPath to CGPath
extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0..<self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        
        return path
    }
}

class OverlayWindowController: NSWindowController {
    // Remove internal message list - messages will be provided by AppDelegate
    // private let motivationalMessages = [...]
    
    var currentMessage: String = "Take a break!" // This will be set by AppDelegate
    var skipCallback: (() -> Void)?
    private var timeLabel: NSTextField?
    private var messageLabel: NSTextField?
    private var visualEffectView: NSVisualEffectView?
    private var animationTimer: Timer?
    // Remove message timer - AppDelegate handles message selection
    // private var messageTimer: Timer?
    private var skipButton: NSButton?
    
    // Updated initializer to accept a specific screen
    convenience init(screen: NSScreen) {
        // Use the provided screen's frame
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        // Configure window properties
        window.level = .screenSaver // Make sure it appears above other windows
        window.backgroundColor = .clear // Using a custom view for background
        window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false // Allow interaction with the skip button
        
        // Initialize with the window
        self.init(window: window)
        
        // Set up content
        setupContentView()
    }
    
    // Default convenience init (can be removed if not needed elsewhere, 
    // but kept for now in case of future use or direct initialization needs)
    convenience init() {
        guard let mainScreen = NSScreen.main else {
            fatalError("Could not find main screen for default init")
        }
        self.init(screen: mainScreen)
    }
    
    // Remove internal random message function
    // private func getRandomMotivationalMessage() -> String { ... }
    
    private func setupContentView() {
        guard let window = self.window else { return }
        
        // Create a visual effect view for the background blur
        let visualEffectView = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        visualEffectView.material = .ultraDark 
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        self.visualEffectView = visualEffectView
        
        // Container for content
        let containerView = NSView(frame: visualEffectView.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = .clear
        
        // Create main gradient background layer with more varied colors
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = visualEffectView.bounds
        
        // Enhanced color palette with blues, olive green, grey and black
        let deepNavy = NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1.0)
        let mediumBlue = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.35, alpha: 1.0)
        let lightBlue = NSColor(calibratedRed: 0.2, green: 0.3, blue: 0.45, alpha: 1.0)
        let oliveGreen = NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.2, alpha: 0.7)
        let darkGrey = NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 0.9)
        
        // Set up gradient with our extended color palette
        gradientLayer.colors = [
            deepNavy.cgColor,
            mediumBlue.cgColor,
            lightBlue.cgColor,
            oliveGreen.cgColor,
            darkGrey.cgColor
        ]
        gradientLayer.locations = [0.0, 0.25, 0.5, 0.75, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        
        // Add accent gradient for more color depth
        let accentGradientLayer = CAGradientLayer()
        accentGradientLayer.frame = visualEffectView.bounds
        accentGradientLayer.colors = [
            NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.5, alpha: 0.2).cgColor,
            NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.0).cgColor,
            NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.2, alpha: 0.15).cgColor
        ]
        accentGradientLayer.locations = [0.0, 0.5, 1.0]
        accentGradientLayer.startPoint = CGPoint(x: 1, y: 0)
        accentGradientLayer.endPoint = CGPoint(x: 0, y: 1)
        
        // Add base gradient and accent gradients
        visualEffectView.layer?.addSublayer(gradientLayer)
        visualEffectView.layer?.addSublayer(accentGradientLayer)
        
        // Create multiple moving glow elements with different colors
        let glowLayer1 = createGlowLayer(color: NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.6, alpha: 0.15),
                                        size: 600, cornerRadius: 300, name: "blueGlow")
        let glowLayer2 = createGlowLayer(color: NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.2, alpha: 0.12),
                                        size: 500, cornerRadius: 250, name: "greenGlow")
        let glowLayer3 = createGlowLayer(color: NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.3, alpha: 0.1),
                                        size: 700, cornerRadius: 350, name: "greyGlow")
        
        visualEffectView.layer?.addSublayer(glowLayer1)
        visualEffectView.layer?.addSublayer(glowLayer2)
        visualEffectView.layer?.addSublayer(glowLayer3)
        
        // Add particle layer for small glowing particles
        let particleLayer = CALayer()
        particleLayer.frame = visualEffectView.bounds
        particleLayer.name = "particleLayer"
        visualEffectView.layer?.addSublayer(particleLayer)
        
        // Add light beams layer
        let beamsLayer = CALayer()
        beamsLayer.frame = visualEffectView.bounds
        beamsLayer.name = "beamsLayer"
        visualEffectView.layer?.addSublayer(beamsLayer)
        
        // Add decorative elements - light paths crossing the screen
        addLightPaths(to: containerView, bounds: visualEffectView.bounds)
        
        // Motivational message with shadow and styling
        let messageLabel = createStyledLabel(text: currentMessage, fontSize: 36, weight: .medium)
        messageLabel.shadow = NSShadow()
        messageLabel.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.5)
        messageLabel.shadow?.shadowOffset = NSSize(width: 0, height: 2)
        messageLabel.shadow?.shadowBlurRadius = 4
        self.messageLabel = messageLabel
        
        // Timer text with refined styling
        let timerLabel = createStyledLabel(text: "00:00", fontSize: 80, weight: .bold)
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 80, weight: .semibold)
        timerLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        self.timeLabel = timerLabel
        
        // Create a more refined glow behind the timer
        let glowView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        glowView.wantsLayer = true
        glowView.layer?.backgroundColor = NSColor.clear.cgColor
        glowView.layer?.cornerRadius = 75
        glowView.layer?.masksToBounds = false
        glowView.layer?.shadowColor = NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.7, alpha: 0.2).cgColor
        glowView.layer?.shadowOffset = .zero
        glowView.layer?.shadowRadius = 40
        glowView.layer?.shadowOpacity = 1.0
        
        // Create a properly styled skip button
        let skipButton = createSkipButton()
        self.skipButton = skipButton
        
        // Create a stack for vertical layout
        let stackView = NSStackView(views: [messageLabel, timerLabel, skipButton])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.distribution = .equalSpacing
        stackView.spacing = 40
        
        // Position the stack in the container
        containerView.addSubview(stackView)
        containerView.addSubview(glowView)
        
        // Use Auto Layout for positioning
        stackView.translatesAutoresizingMaskIntoConstraints = false
        glowView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            stackView.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.8),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.8),
            
            // Position glow behind timer
            glowView.centerXAnchor.constraint(equalTo: timerLabel.centerXAnchor),
            glowView.centerYAnchor.constraint(equalTo: timerLabel.centerYAnchor),
            glowView.widthAnchor.constraint(equalToConstant: 300),
            glowView.heightAnchor.constraint(equalToConstant: 150)
        ])
        
        // Add the container to the visual effect
        visualEffectView.addSubview(containerView)
        containerView.frame = visualEffectView.bounds
        containerView.autoresizingMask = [.width, .height]
        
        // Set the visual effect view as the content
        window.contentView = visualEffectView
        
        // Start the animations on relevant layers
        startBackgroundAnimations(
            mainGradientLayer: gradientLayer,
            accentGradientLayer: accentGradientLayer,
            particleLayer: particleLayer,
            beamsLayer: beamsLayer,
            glowLayers: [glowLayer1, glowLayer2, glowLayer3]
        )
    }
    
    private func createSkipButton() -> NSButton {
        // Create a fixed-size button to avoid hitbox issues
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 150, height: 44))
        button.title = "Skip Break"
        button.target = self
        button.action = #selector(skipButtonClicked)
        
        // Explicitly disable standard bordering behavior to remove the outline
        button.isBordered = false
        
        // Style the button using its layer
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        button.layer?.cornerRadius = 22
        button.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        button.contentTintColor = NSColor.white
        
        // Make sure it has a fixed size
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 150).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        // Add a single tracking area for hover effect
        if let existingAreas = button.trackingAreas as? [NSTrackingArea] {
            for area in existingAreas {
                button.removeTrackingArea(area)
            }
        }
        
        let trackingArea = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: ["button": button]
        )
        button.addTrackingArea(trackingArea)
        
        return button
    }
    
    private func createStyledLabel(text: String, fontSize: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0 // Unlimited lines
        label.allowsDefaultTighteningForTruncation = true
        label.cell?.truncatesLastVisibleLine = true
        return label
    }
    
    private func createGlowLayer(color: NSColor, size: CGFloat, cornerRadius: CGFloat, name: String) -> CALayer {
        let glowLayer = CALayer()
        let offset = size / 2
        glowLayer.frame = CGRect(x: -offset, y: -offset, width: size, height: size)
        glowLayer.backgroundColor = color.cgColor
        glowLayer.cornerRadius = cornerRadius
        glowLayer.shadowColor = color.cgColor
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = cornerRadius / 2
        glowLayer.shadowOpacity = 1.0
        glowLayer.name = name
        return glowLayer
    }
    
    private func addLightPaths(to view: NSView, bounds: CGRect) {
        let width = bounds.width
        let height = bounds.height
        
        // Add multiple decorative paths with different colors and opacities
        addLightPath(to: view, color: NSColor.white.withAlphaComponent(0.05), width: 1.0,
                   startPoint: CGPoint(x: 0, y: height * 0.3),
                   endPoint: CGPoint(x: width, y: height * 0.7),
                   controlPoint1: CGPoint(x: width * 0.4, y: height * 0.1),
                   controlPoint2: CGPoint(x: width * 0.6, y: height * 0.8))
        
        addLightPath(to: view, color: NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.8, alpha: 0.07), width: 1.5,
                   startPoint: CGPoint(x: width, y: height * 0.2),
                   endPoint: CGPoint(x: 0, y: height * 0.6),
                   controlPoint1: CGPoint(x: width * 0.6, y: height * 0.4),
                   controlPoint2: CGPoint(x: width * 0.3, y: height * 0.5))
        
        addLightPath(to: view, color: NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.2, alpha: 0.06), width: 1.2,
                   startPoint: CGPoint(x: width * 0.3, y: 0),
                   endPoint: CGPoint(x: width * 0.7, y: height),
                   controlPoint1: CGPoint(x: width * 0.2, y: height * 0.4),
                   controlPoint2: CGPoint(x: width * 0.8, y: height * 0.6))
        
        addLightPath(to: view, color: NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.2, alpha: 0.04), width: 2.0,
                   startPoint: CGPoint(x: width * 0.8, y: height * 0.1),
                   endPoint: CGPoint(x: width * 0.1, y: height * 0.8),
                   controlPoint1: CGPoint(x: width * 0.7, y: height * 0.5),
                   controlPoint2: CGPoint(x: width * 0.2, y: height * 0.3))
    }
    
    private func addLightPath(to view: NSView, color: NSColor, width: CGFloat, startPoint: CGPoint, endPoint: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {
        let shapeLayer = CAShapeLayer()
        let path = NSBezierPath()
        
        path.move(to: NSPoint(x: startPoint.x, y: startPoint.y))
        path.curve(to: NSPoint(x: endPoint.x, y: endPoint.y),
                  controlPoint1: NSPoint(x: controlPoint1.x, y: controlPoint1.y),
                  controlPoint2: NSPoint(x: controlPoint2.x, y: controlPoint2.y))
        
        shapeLayer.path = path.cgPath
        shapeLayer.lineWidth = width
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.fillColor = nil
        view.layer?.addSublayer(shapeLayer)
    }
    
    private func startBackgroundAnimations(mainGradientLayer: CAGradientLayer, 
                                         accentGradientLayer: CAGradientLayer,
                                         particleLayer: CALayer,
                                         beamsLayer: CALayer,
                                         glowLayers: [CALayer]) {
        // Animate main gradient colors with more color variation
        let gradientColorAnimation = CABasicAnimation(keyPath: "colors")
        
        // Enhanced color palette with more vibrant colors
        let deepNavy = NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1.0)
        let mediumBlue = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.35, alpha: 1.0)
        let lightBlue = NSColor(calibratedRed: 0.2, green: 0.3, blue: 0.45, alpha: 1.0)
        let oliveGreen = NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.2, alpha: 0.7)
        let darkGrey = NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 0.9)
        
        // Different color variations for animation
        let deepNavy2 = NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.25, alpha: 1.0)
        let mediumBlue2 = NSColor(calibratedRed: 0.15, green: 0.25, blue: 0.4, alpha: 1.0)
        let tealBlue = NSColor(calibratedRed: 0.1, green: 0.35, blue: 0.4, alpha: 0.8)
        let lightGreen = NSColor(calibratedRed: 0.2, green: 0.45, blue: 0.25, alpha: 0.65)
        let blueGrey = NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.25, alpha: 0.9)
        
        gradientColorAnimation.fromValue = [
            deepNavy.cgColor,
            mediumBlue.cgColor,
            lightBlue.cgColor,
            oliveGreen.cgColor,
            darkGrey.cgColor
        ]
        
        gradientColorAnimation.toValue = [
            deepNavy2.cgColor,
            mediumBlue2.cgColor,
            tealBlue.cgColor,
            lightGreen.cgColor,
            blueGrey.cgColor
        ]
        
        // Somewhat faster animation for more noticeable effect
        gradientColorAnimation.duration = 25.0
        gradientColorAnimation.autoreverses = true
        gradientColorAnimation.repeatCount = Float.infinity
        gradientColorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mainGradientLayer.add(gradientColorAnimation, forKey: "colorChange")
        
        // Animate gradient locations more dramatically
        let gradientLocationAnimation = CABasicAnimation(keyPath: "locations")
        gradientLocationAnimation.fromValue = [0.0, 0.25, 0.5, 0.75, 1.0]
        gradientLocationAnimation.toValue = [0.0, 0.3, 0.6, 0.8, 1.0]
        gradientLocationAnimation.duration = 18.0
        gradientLocationAnimation.autoreverses = true
        gradientLocationAnimation.repeatCount = Float.infinity
        gradientLocationAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mainGradientLayer.add(gradientLocationAnimation, forKey: "locationChange")
        
        // Animate accent gradient - more movement
        let accentGradAnimation = CABasicAnimation(keyPath: "colors")
        accentGradAnimation.fromValue = [
            NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.5, alpha: 0.2).cgColor,
            NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.0).cgColor,
            NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.2, alpha: 0.15).cgColor
        ]
        
        accentGradAnimation.toValue = [
            NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.55, alpha: 0.25).cgColor,
            NSColor(calibratedRed: 0.25, green: 0.45, blue: 0.2, alpha: 0.15).cgColor,
            NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.4, alpha: 0.1).cgColor
        ]
        
        accentGradAnimation.duration = 20.0
        accentGradAnimation.autoreverses = true
        accentGradAnimation.repeatCount = Float.infinity
        accentGradientLayer.add(accentGradAnimation, forKey: "accentColorChange")
        
        // Add position animation to the accent gradient for more movement
        let accentPositionAnimation = CABasicAnimation(keyPath: "position")
        accentPositionAnimation.fromValue = NSValue(point: NSPoint(x: 0, y: 0))
        accentPositionAnimation.toValue = NSValue(point: NSPoint(x: 100, y: 100))
        accentPositionAnimation.duration = 30.0
        accentPositionAnimation.autoreverses = true
        accentPositionAnimation.repeatCount = Float.infinity
        accentPositionAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        accentGradientLayer.add(accentPositionAnimation, forKey: "positionChange")
        
        // Animate glow layers along different paths
        for (index, glowLayer) in glowLayers.enumerated() {
            animateGlowLayer(glowLayer, pathIndex: index, bounds: visualEffectView?.bounds ?? .zero)
        }
        
        // Add light beams more frequently for more visible effect
        let beamsTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.addLightBeam(to: beamsLayer)
        }
        
        // Add first couple beams immediately for immediate effect
        addLightBeam(to: beamsLayer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.addLightBeam(to: beamsLayer)
        }
        
        // Create more particles for more visible effect
        let particleTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.addParticle(to: particleLayer)
        }
        
        // Add several particles immediately
        for _ in 0..<5 {
            addParticle(to: particleLayer)
        }
        
        // Add the timers to common run loop mode
        RunLoop.main.add(beamsTimer, forMode: .common)
        RunLoop.main.add(particleTimer, forMode: .common)
        
        // Store timers for cleanup
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 100000, repeats: false) { _ in }
        animationTimer?.invalidate() // Just a placeholder to store references
        
        // Store references to beams and particle timers
        objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: 1)!, beamsTimer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, UnsafeRawPointer(bitPattern: 2)!, particleTimer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private func animateGlowLayer(_ glowLayer: CALayer, pathIndex: Int, bounds: CGRect) {
        let width = bounds.width
        let height = bounds.height
        
        // Create a unique path for each glow
        let glowPathAnimation = CAKeyframeAnimation(keyPath: "position")
        let path = CGMutablePath()
        
        switch pathIndex % 3 {
        case 0: // Blue glow - follows a figure-8 path
            path.move(to: CGPoint(x: width * 0.2, y: height * 0.2))
            path.addCurve(
                to: CGPoint(x: width * 0.8, y: height * 0.2),
                control1: CGPoint(x: width * 0.4, y: height * 0.1),
                control2: CGPoint(x: width * 0.6, y: height * 0.1)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.8, y: height * 0.8),
                control1: CGPoint(x: width * 0.9, y: height * 0.4),
                control2: CGPoint(x: width * 0.9, y: height * 0.6)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.2, y: height * 0.8),
                control1: CGPoint(x: width * 0.6, y: height * 0.9),
                control2: CGPoint(x: width * 0.4, y: height * 0.9)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.2, y: height * 0.2),
                control1: CGPoint(x: width * 0.1, y: height * 0.6),
                control2: CGPoint(x: width * 0.1, y: height * 0.4)
            )
        
        case 1: // Green glow - follows a diagonal path
            path.move(to: CGPoint(x: width * 0.1, y: height * 0.1))
            path.addCurve(
                to: CGPoint(x: width * 0.9, y: height * 0.9),
                control1: CGPoint(x: width * 0.3, y: height * 0.5),
                control2: CGPoint(x: width * 0.7, y: height * 0.5)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.1, y: height * 0.9),
                control1: CGPoint(x: width * 0.7, y: height * 0.7),
                control2: CGPoint(x: width * 0.3, y: height * 0.7)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.9, y: height * 0.1),
                control1: CGPoint(x: width * 0.3, y: height * 0.3),
                control2: CGPoint(x: width * 0.7, y: height * 0.3)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.1, y: height * 0.1),
                control1: CGPoint(x: width * 0.5, y: width * 0.2),
                control2: CGPoint(x: width * 0.3, y: width * 0.1)
            )
        
        case 2: // Grey glow - follows an oval path
            path.move(to: CGPoint(x: width * 0.5, y: height * 0.2))
            path.addCurve(
                to: CGPoint(x: width * 0.8, y: height * 0.5),
                control1: CGPoint(x: width * 0.7, y: height * 0.2),
                control2: CGPoint(x: width * 0.8, y: height * 0.3)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.5, y: height * 0.8),
                control1: CGPoint(x: width * 0.8, y: height * 0.7),
                control2: CGPoint(x: width * 0.7, y: height * 0.8)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.2, y: height * 0.5),
                control1: CGPoint(x: width * 0.3, y: height * 0.8),
                control2: CGPoint(x: width * 0.2, y: height * 0.7)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.5, y: height * 0.2),
                control1: CGPoint(x: width * 0.2, y: height * 0.3),
                control2: CGPoint(x: width * 0.3, y: height * 0.2)
            )
        default:
            break
        }
        
        // Configure the animation
        glowPathAnimation.path = path
        glowPathAnimation.duration = 60.0 + Double(pathIndex * 10) // Stagger durations
        glowPathAnimation.calculationMode = .paced
        glowPathAnimation.rotationMode = .rotateAuto
        glowPathAnimation.repeatCount = Float.infinity
        glowPathAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(glowPathAnimation, forKey: "positionAnimation")
        
        // Add a subtle scale animation
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.9
        scaleAnimation.toValue = 1.1
        scaleAnimation.duration = 15.0 + Double(pathIndex * 5)
        scaleAnimation.autoreverses = true
        scaleAnimation.repeatCount = Float.infinity
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(scaleAnimation, forKey: "scaleAnimation")
        
        // Add a subtle opacity animation
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.7
        opacityAnimation.toValue = 1.0
        opacityAnimation.duration = 12.0 + Double(pathIndex * 3)
        opacityAnimation.autoreverses = true
        opacityAnimation.repeatCount = Float.infinity
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(opacityAnimation, forKey: "opacityAnimation")
    }
    
    private func addLightBeam(to layer: CALayer) {
        guard let bounds = visualEffectView?.bounds else { return }
        
        // Create a light beam with more visibility
        let beamLayer = CALayer()
        let width = CGFloat.random(in: 70...200)
        let height = bounds.height * 2
        beamLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        
        // Rotate the beam
        let angle = CGFloat.random(in: -20...20) * CGFloat.pi / 180
        beamLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        beamLayer.position = CGPoint(x: CGFloat.random(in: 0...bounds.width), y: 0)
        beamLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        
        // Choose colors randomly for variety
        let colorChoice = Int.random(in: 0...3)
        let beamColor: NSColor
        
        switch colorChoice {
        case 0:
            beamColor = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1.0) // Blue
        case 1:
            beamColor = NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.2, alpha: 1.0) // Green
        case 2:
            beamColor = NSColor(calibratedRed: 0.4, green: 0.4, blue: 0.5, alpha: 1.0) // Grey
        case 3:
            beamColor = NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.4, alpha: 1.0) // Teal
        default:
            beamColor = NSColor.white
        }
        
        // Create a gradient for the beam - higher opacity for more visibility
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = beamLayer.bounds
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            beamColor.withAlphaComponent(CGFloat.random(in: 0.03...0.07)).cgColor,
            NSColor.clear.cgColor
        ]
        gradientLayer.locations = [0.0, 0.5, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        beamLayer.addSublayer(gradientLayer)
        
        layer.addSublayer(beamLayer)
        
        // Animate the beam - slowly fade in and out
        let fadeAnimation = CABasicAnimation(keyPath: "opacity")
        fadeAnimation.fromValue = 0
        fadeAnimation.toValue = 1
        fadeAnimation.duration = CGFloat.random(in: 3...8)
        fadeAnimation.autoreverses = true
        fadeAnimation.fillMode = .forwards
        fadeAnimation.isRemovedOnCompletion = false
        beamLayer.opacity = 0
        beamLayer.add(fadeAnimation, forKey: "fadeAnimation")
        
        // Remove the beam after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 16.0) {
            beamLayer.removeFromSuperlayer()
        }
    }
    
    private func addParticle(to layer: CALayer) {
        guard let bounds = visualEffectView?.bounds else { return }
        
        // Create slightly larger particles with more color variety
        let size = CGFloat.random(in: 1.5...4.0)
        let particleLayer = CALayer()
        
        // Choose random color for variety
        let colorChoice = Int.random(in: 0...4)
        let particleColor: NSColor
        
        switch colorChoice {
        case 0:
            particleColor = NSColor.white
        case 1:
            particleColor = NSColor(calibratedRed: 0.3, green: 0.6, blue: 0.9, alpha: 1.0) // Light blue
        case 2:
            particleColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 0.3, alpha: 1.0) // Light green
        case 3:
            particleColor = NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.6, alpha: 1.0) // Light grey
        case 4:
            particleColor = NSColor(calibratedRed: 0.7, green: 0.7, blue: 0.3, alpha: 1.0) // Yellowish
        default:
            particleColor = NSColor.white
        }
        
        particleLayer.backgroundColor = particleColor.withAlphaComponent(CGFloat.random(in: 0.05...0.15)).cgColor
        particleLayer.cornerRadius = size / 2
        
        // Random position
        let randomX = CGFloat.random(in: 0...bounds.width)
        let randomY = CGFloat.random(in: 0...bounds.height)
        particleLayer.frame = CGRect(x: randomX, y: randomY, width: size, height: size)
        
        layer.addSublayer(particleLayer)
        
        // Add a subtle movement to particles
        let moveAnimation = CABasicAnimation(keyPath: "position")
        let endX = randomX + CGFloat.random(in: -30...30)
        let endY = randomY + CGFloat.random(in: -30...30)
        moveAnimation.fromValue = NSValue(point: NSPoint(x: randomX, y: randomY))
        moveAnimation.toValue = NSValue(point: NSPoint(x: endX, y: endY))
        moveAnimation.duration = CGFloat.random(in: 8...15)
        moveAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        // Animate opacity with slower, more subtle transitions
        let fadeAnimation = CABasicAnimation(keyPath: "opacity")
        fadeAnimation.fromValue = 0.0
        fadeAnimation.toValue = 1.0
        fadeAnimation.duration = 3.0
        fadeAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        
        let fadeOutAnimation = CABasicAnimation(keyPath: "opacity")
        fadeOutAnimation.fromValue = 1.0
        fadeOutAnimation.toValue = 0.0
        fadeOutAnimation.duration = 3.0
        fadeOutAnimation.beginTime = 6.0
        fadeOutAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [moveAnimation, fadeAnimation, fadeOutAnimation]
        animationGroup.duration = 9.0
        
        particleLayer.add(animationGroup, forKey: "animations")
        
        // Remove the particle after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) {
            particleLayer.removeFromSuperlayer()
        }
    }
    
    // NSTrackingArea delegate methods for button hover effect
    override func mouseEntered(with event: NSEvent) {
        if let userInfo = event.trackingArea?.userInfo as? [String: Any],
           let button = userInfo["button"] as? NSButton {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if let userInfo = event.trackingArea?.userInfo as? [String: Any],
           let button = userInfo["button"] as? NSButton {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
            }
        }
    }
    
    func updateTimeDisplay(_ timeString: String) {
        DispatchQueue.main.async { [weak self] in
            self?.timeLabel?.stringValue = timeString
            // Remove the pulse animation - keep the timer still
        }
    }
    
    @objc private func skipButtonClicked() {
        skipCallback?()
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        
        // Update the label with the message passed from AppDelegate
        // Ensure the message label reflects the currentMessage set externally
        if let msgLabel = self.messageLabel {
             DispatchQueue.main.async {
                msgLabel.stringValue = self.currentMessage
             }
        }
        
        // Add an appearance animation
        if let window = self.window, let contentView = window.contentView {
            contentView.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                contentView.animator().alphaValue = 1.0
            }
        }
    }
    
    override func close() {
        // Animate closing
        if let window = self.window, let contentView = window.contentView {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                contentView.animator().alphaValue = 0
            }, completionHandler: {
                super.close()
            })
        } else {
            super.close()
        }
        
        // Clean up timers
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    deinit {
        // Clean up timers
        animationTimer?.invalidate()
        animationTimer = nil
    }
} 