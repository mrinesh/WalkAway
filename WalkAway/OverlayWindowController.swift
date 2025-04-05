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
    // Keep track of background animation layers
    private var backgroundLayers: [CALayer] = []
    private var animationTimers: [Timer] = [] // Store all timers for cleanup
    // Remove message timer - AppDelegate handles message selection
    // private var messageTimer: Timer?
    private var skipButton: NSButton?
    var isSkippable: Bool = true // Property to control button visibility
    
    // Updated initializer to accept a specific screen and skippable status
    convenience init(screen: NSScreen, isSkippable: Bool) {
        // 1. Create a basic window without explicit frame or screen initially
        let window = NSWindow(
            contentRect: .zero, // Start with zero rect
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
            // screen: screen // Don't assign screen here initially
        )
        
        // Configure window properties that don't depend on frame
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        
        // 2. Initialize the NSWindowController
        self.init(window: window)
        
        // 3. Set skippable status
        self.isSkippable = isSkippable
        
        // 4. NOW set the frame explicitly using the screen's global coordinates
        window.setFrame(screen.frame, display: true)
        
        // 5. Set up content view (now that the frame should be correctly set)
        setupContentView()
    }
    
    // Default convenience init (update if needed, or remove if only screen-specific init is used)
    convenience init() {
        guard let mainScreen = NSScreen.main else {
            fatalError("Could not find main screen for default init")
        }
        self.init(screen: mainScreen, isSkippable: true) // Default to skippable
    }
    
    // Remove internal random message function
    // private func getRandomMotivationalMessage() -> String { ... }
    
    private func setupContentView() {
        guard let window = self.window else { return }
        
        // Create a visual effect view for the background blur
        visualEffectView = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        guard let visualEffectView = visualEffectView else { return }
        visualEffectView.material = .ultraDark 
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        
        // --- Redesigned Background Elements --- 
        
        // 1. Base Gradient Layer
        let baseGradientLayer = CAGradientLayer()
        baseGradientLayer.frame = visualEffectView.bounds
        baseGradientLayer.name = "baseGradient"
        // Define new color palette (e.g., deep blues, purples, teals)
        let color1 = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)
        let color2 = NSColor(calibratedRed: 0.1, green: 0.08, blue: 0.25, alpha: 1.0) // Purple hint
        let color3 = NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.3, alpha: 1.0) // Teal hint
        let color4 = NSColor(calibratedRed: 0.06, green: 0.1, blue: 0.2, alpha: 1.0)
        baseGradientLayer.colors = [color1.cgColor, color2.cgColor, color3.cgColor, color4.cgColor]
        baseGradientLayer.locations = [0.0, 0.3, 0.7, 1.0]
        baseGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        baseGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        visualEffectView.layer?.addSublayer(baseGradientLayer)
        backgroundLayers.append(baseGradientLayer)

        // 2. Drifting Nebulae Layers (Soft, Large Glows)
        let nebulaColors = [
            NSColor(calibratedRed: 0.2, green: 0.3, blue: 0.6, alpha: 0.1), // Soft Blue
            NSColor(calibratedRed: 0.4, green: 0.2, blue: 0.5, alpha: 0.08), // Soft Magenta
            NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.4, alpha: 0.09)  // Soft Teal
        ]
        for i in 0..<nebulaColors.count {
            let nebulaLayer = createNebulaLayer(color: nebulaColors[i], bounds: visualEffectView.bounds)
            nebulaLayer.name = "nebula_\(i)"
            visualEffectView.layer?.addSublayer(nebulaLayer)
            backgroundLayers.append(nebulaLayer)
        }

        // 3. Particle Layer
        let particleLayer = CALayer()
        particleLayer.frame = visualEffectView.bounds
        particleLayer.name = "particleLayer"
        visualEffectView.layer?.addSublayer(particleLayer)
        backgroundLayers.append(particleLayer)
        
        // 4. Comet Trail Layer
        let cometLayer = CALayer()
        cometLayer.frame = visualEffectView.bounds
        cometLayer.name = "cometLayer"
        visualEffectView.layer?.addSublayer(cometLayer)
        backgroundLayers.append(cometLayer)
        
        // --- End Redesigned Background --- 

        // Container for Foreground Content (Timer, Message, Button)
        let containerView = NSView(frame: visualEffectView.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = .clear // Transparent container
        
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
        
        // --- Conditional Skip Button / Text --- 
        let skipControl: NSView // Use NSView as common type for stack
        if isSkippable {
            let button = createSkipButton()
            self.skipButton = button // Store reference if needed
            skipControl = button
        } else {
            let nonSkippableLabel = createStyledLabel(text: "Non Skippable Break", fontSize: 15, weight: .medium)
            nonSkippableLabel.textColor = NSColor.white.withAlphaComponent(0.6) // Make it less prominent
            skipControl = nonSkippableLabel
        }
        // --- End Conditional --- 
        
        // Create a stack for vertical layout
        let stackView = NSStackView(views: [messageLabel, timerLabel, skipControl])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.distribution = .equalSpacing
        stackView.spacing = 40
        
        // Position the stack in the container
        containerView.addSubview(glowView) // Add glow first so it's behind stack
        containerView.addSubview(stackView)
        
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
        
        // Add the container on top of the background elements
        visualEffectView.addSubview(containerView)
        containerView.frame = visualEffectView.bounds
        containerView.autoresizingMask = [.width, .height]
        
        // Set the visual effect view as the window's content
        window.contentView = visualEffectView
        
        // Start background animations
        startBackgroundAnimations()
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
    
    // Helper to create soft nebula layers
    private func createNebulaLayer(color: NSColor, bounds: CGRect) -> CALayer {
        let nebulaLayer = CALayer()
        let size = max(bounds.width, bounds.height) * CGFloat.random(in: 0.6...1.2) // Large size
        nebulaLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        // Position randomly initially (animation will move it)
        nebulaLayer.position = CGPoint(x: CGFloat.random(in: 0...bounds.width),
                                   y: CGFloat.random(in: 0...bounds.height))
                                   
        nebulaLayer.backgroundColor = color.cgColor
        nebulaLayer.cornerRadius = size / 2
        nebulaLayer.opacity = 0 // Start invisible, fade in
        
        // Use shadow as a heavy blur/glow effect
        nebulaLayer.shadowColor = color.withAlphaComponent(color.alphaComponent * 1.5).cgColor
        nebulaLayer.shadowRadius = size / 3 // Large radius for soft edges
        nebulaLayer.shadowOpacity = 1.0
        nebulaLayer.shadowOffset = .zero
        
        return nebulaLayer
    }
    
    // Start all background animations
    private func startBackgroundAnimations() {
        cleanupTimers() // Ensure previous timers are stopped
        
        guard let layer = visualEffectView?.layer else { return }

        // Find layers by name (safer than assuming order)
        let baseGradientLayer = layer.sublayers?.first { $0.name == "baseGradient" } as? CAGradientLayer
        let nebulaLayers = layer.sublayers?.filter { $0.name?.starts(with: "nebula_") ?? false } ?? []
        let particleLayer = layer.sublayers?.first { $0.name == "particleLayer" }
        let cometLayer = layer.sublayers?.first { $0.name == "cometLayer" }
        
        // 1. Animate Base Gradient
        if let gradientLayer = baseGradientLayer {
            animateBaseGradient(gradientLayer)
        }
        
        // 2. Animate Nebulae
        for (index, nebulaLayer) in nebulaLayers.enumerated() {
            animateNebulaLayer(nebulaLayer, index: index, bounds: layer.bounds)
        }
        
        // 3. Animate Particles
        if let pLayer = particleLayer {
            let particleTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak pLayer] _ in
                guard let strongSelf = self, let targetLayer = pLayer else { return }
                strongSelf.addParticle(to: targetLayer)
            }
            RunLoop.main.add(particleTimer, forMode: .common)
            animationTimers.append(particleTimer)
        }
        
        // 4. Animate Comet Trails
        if let cLayer = cometLayer {
            let cometTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self, weak cLayer] _ in
                 guard let strongSelf = self, let targetLayer = cLayer else { return }
                 strongSelf.addCometTrail(to: targetLayer)
            }
            RunLoop.main.add(cometTimer, forMode: .common)
             animationTimers.append(cometTimer)
        }
    }
    
    // Animation for the base gradient
    private func animateBaseGradient(_ layer: CAGradientLayer) {
        let color1 = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.15, alpha: 1.0).cgColor
        let color2 = NSColor(calibratedRed: 0.1, green: 0.08, blue: 0.25, alpha: 1.0).cgColor
        let color3 = NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.3, alpha: 1.0).cgColor
        let color4 = NSColor(calibratedRed: 0.06, green: 0.1, blue: 0.2, alpha: 1.0).cgColor
        
        let color5 = NSColor(calibratedRed: 0.12, green: 0.06, blue: 0.22, alpha: 1.0).cgColor // More purple
        let color6 = NSColor(calibratedRed: 0.07, green: 0.18, blue: 0.28, alpha: 1.0).cgColor // More teal
        let color7 = NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.18, alpha: 1.0).cgColor // Darker
        let color8 = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.25, alpha: 1.0).cgColor

        let colorAnimation = CABasicAnimation(keyPath: "colors")
        colorAnimation.fromValue = [color1, color2, color3, color4]
        colorAnimation.toValue = [color5, color6, color8, color7]
        colorAnimation.duration = 90.0 // Very slow
        colorAnimation.autoreverses = true
        colorAnimation.repeatCount = .infinity
        colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(colorAnimation, forKey: "baseColorChange")

        let locationAnimation = CABasicAnimation(keyPath: "locations")
        locationAnimation.fromValue = [0.0, 0.3, 0.7, 1.0]
        locationAnimation.toValue = [0.0, 0.4, 0.6, 1.0] // Shift focus
        locationAnimation.duration = 75.0 // Very slow
        locationAnimation.autoreverses = true
        locationAnimation.repeatCount = .infinity
        locationAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(locationAnimation, forKey: "baseLocationChange")
    }
    
    // Animation for the nebula layers
    private func animateNebulaLayer(_ layer: CALayer, index: Int, bounds: CGRect) {
        // Very slow drift animation
        let driftAnimation = CAKeyframeAnimation(keyPath: "position")
        let startPoint = layer.position
        let endPoint = CGPoint(x: startPoint.x + CGFloat.random(in: -100...100),
                             y: startPoint.y + CGFloat.random(in: -100...100))
        // Simple path for slow drift
        let path = CGMutablePath()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        driftAnimation.path = path
        driftAnimation.duration = 120.0 + Double.random(in: -20...20) // Long, varied duration
        driftAnimation.autoreverses = true
        driftAnimation.repeatCount = .infinity
        driftAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(driftAnimation, forKey: "nebulaDrift")

        // Slow fade in/out
        let fadeAnimation = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnimation.values = [0.0, 1.0, 1.0, 0.0] // Fade in, stay, fade out
        fadeAnimation.keyTimes = [0.0, 0.15, 0.85, 1.0] // Control fade timing
        fadeAnimation.duration = 60.0 + Double.random(in: -10...10) // Long fade cycle
        fadeAnimation.repeatCount = .infinity
        // Stagger start times slightly
        fadeAnimation.beginTime = CACurrentMediaTime() + Double(index) * 5.0 
        layer.add(fadeAnimation, forKey: "nebulaFade")
    }
    
    // Add subtle particle with drift
    private func addParticle(to layer: CALayer) {
        let particle = CALayer()
        let size = CGFloat.random(in: 1.0...2.5)
        particle.frame = CGRect(x: CGFloat.random(in: 0...layer.bounds.width),
                                y: CGFloat.random(in: 0...layer.bounds.height),
                                width: size, height: size)
        particle.backgroundColor = NSColor.white.withAlphaComponent(CGFloat.random(in: 0.1...0.4)).cgColor
        particle.cornerRadius = size / 2
        particle.opacity = 0 // Start invisible
        layer.addSublayer(particle)

        // Animations
        let driftX = CGFloat.random(in: 20...50) // Gentle upward-right drift
        let driftY = CGFloat.random(in: -50...(-20))
        let duration = TimeInterval.random(in: 8...15)

        let positionAnimation = CABasicAnimation(keyPath: "position")
        positionAnimation.fromValue = particle.position
        positionAnimation.toValue = CGPoint(x: particle.position.x + driftX, y: particle.position.y + driftY)
        positionAnimation.duration = duration
        positionAnimation.timingFunction = CAMediaTimingFunction(name: .linear)

        let fadeAnimation = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnimation.values = [0.0, 1.0, 1.0, 0.0]
        fadeAnimation.keyTimes = [0.0, 0.1, 0.8, 1.0]
        fadeAnimation.duration = duration
        
        let group = CAAnimationGroup()
        group.animations = [positionAnimation, fadeAnimation]
        group.duration = duration
        
        particle.add(group, forKey: "particleAnimation")

        // Remove layer after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            particle.removeFromSuperlayer()
        }
    }
    
    // Add comet trail effect
    private func addCometTrail(to layer: CALayer) {
        let comet = CAShapeLayer()
        let path = CGMutablePath()
        let startX = CGFloat.random(in: 0...layer.bounds.width)
        let startY = CGFloat.random(in: 0...layer.bounds.height)
        let length = CGFloat.random(in: 50...150)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let endX = startX + length * cos(angle)
        let endY = startY + length * sin(angle)
        
        path.move(to: CGPoint(x: startX, y: startY))
        path.addLine(to: CGPoint(x: endX, y: endY))
        
        comet.path = path
        comet.lineWidth = CGFloat.random(in: 1.0...2.0)
        // Accent color (e.g., soft gold or cyan)
        let accentColor = NSColor(calibratedRed: 0.8, green: 0.7, blue: 0.3, alpha: 0.7) 
        comet.strokeColor = accentColor.cgColor
        comet.opacity = 0 // Start invisible
        
        // Use lineDashPhase animation for trail effect
        comet.lineDashPattern = [NSNumber(value: length), NSNumber(value: length)] // Dash = length, Gap = length
        comet.lineCap = .round
        layer.addSublayer(comet)

        let duration = TimeInterval.random(in: 1.5...3.0)

        let dashAnimation = CABasicAnimation(keyPath: "lineDashPhase")
        dashAnimation.fromValue = -length // Start with the gap showing
        dashAnimation.toValue = length    // End with the dash having moved through
        dashAnimation.duration = duration
        dashAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let fadeOutAnimation = CABasicAnimation(keyPath: "opacity")
        fadeOutAnimation.fromValue = 1.0
        fadeOutAnimation.toValue = 0.0
        fadeOutAnimation.duration = duration * 0.6 // Fade out quicker
        fadeOutAnimation.beginTime = duration * 0.4 // Start fading after head passes
        fadeOutAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fadeOutAnimation.fillMode = .forwards
        fadeOutAnimation.isRemovedOnCompletion = false // Keep final state
        
        let fadeInAnimation = CABasicAnimation(keyPath: "opacity")
        fadeInAnimation.fromValue = 0.0
        fadeInAnimation.toValue = 1.0
        fadeInAnimation.duration = duration * 0.2 // Quick fade in
        fadeInAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [dashAnimation, fadeInAnimation, fadeOutAnimation]
        group.duration = duration
        
        comet.add(group, forKey: "cometAnimation")

        // Remove layer after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            comet.removeFromSuperlayer()
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
        cleanupTimers()
    }
    
    // Cleanup timers and layers
    private func cleanupTimers() {
        for timer in animationTimers {
            timer.invalidate()
        }
        animationTimers.removeAll()
    }
    
    deinit {
        print("OverlayWindowController deinit")
        cleanupTimers()
        // Optionally remove background layers if needed, though window closure handles this
        backgroundLayers.forEach { $0.removeFromSuperlayer() }
        backgroundLayers.removeAll()
    }
} 