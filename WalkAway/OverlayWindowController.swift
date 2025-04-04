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
    var currentMessage: String = "Take a break!"
    var skipCallback: (() -> Void)?
    private var timeLabel: NSTextField?
    private var visualEffectView: NSVisualEffectView?
    private var animationTimer: Timer?
    
    convenience init() {
        // Get the main screen
        guard let screen = NSScreen.main else {
            fatalError("Could not find main screen")
        }
        
        // Create a window filling the entire screen
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
    
    private func setupContentView() {
        guard let window = self.window else { return }
        
        // Create a visual effect view for the background blur
        let visualEffectView = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        visualEffectView.material = .ultraDark // Using the darkest material for depth
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        self.visualEffectView = visualEffectView
        
        // Create a gradient background layer
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = visualEffectView.bounds
        
        // Create a rich navy blue gradient with subtle color variation
        let darkNavy = NSColor(calibratedRed: 0.0, green: 0.05, blue: 0.2, alpha: 0.9)
        let mediumNavy = NSColor(calibratedRed: 0.0, green: 0.1, blue: 0.3, alpha: 0.85)
        let lightNavy = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.4, alpha: 0.8)
        
        gradientLayer.colors = [
            darkNavy.cgColor,
            mediumNavy.cgColor,
            lightNavy.cgColor,
            mediumNavy.cgColor
        ]
        
        // Create a diagonal gradient
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        
        // Adding gradient to the view
        visualEffectView.layer?.addSublayer(gradientLayer)
        
        // Add subtle particle effect (small dots that fade in and out)
        let particleLayer = CALayer()
        particleLayer.frame = visualEffectView.bounds
        visualEffectView.layer?.addSublayer(particleLayer)
        
        // Container for content
        let containerView = NSView(frame: visualEffectView.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = .clear
        
        // Add a subtle curved shape layer
        let shapeLayer = CAShapeLayer()
        let path = NSBezierPath()
        let height = visualEffectView.bounds.height
        let width = visualEffectView.bounds.width
        
        // Create a gentle wave across the screen
        path.move(to: NSPoint(x: 0, y: height * 0.4))
        path.curve(to: NSPoint(x: width, y: height * 0.6),
                  controlPoint1: NSPoint(x: width * 0.3, y: height * 0.5),
                  controlPoint2: NSPoint(x: width * 0.7, y: height * 0.3))
        
        // Convert NSBezierPath to CGPath using the extension
        shapeLayer.path = path.cgPath
        shapeLayer.lineWidth = 2.0
        shapeLayer.strokeColor = NSColor.white.withAlphaComponent(0.1).cgColor
        shapeLayer.fillColor = nil
        containerView.layer?.addSublayer(shapeLayer)
        
        // Motivational message with shadow and styling
        let messageLabel = createStyledLabel(text: currentMessage, fontSize: 36, weight: .medium)
        messageLabel.shadow = NSShadow()
        messageLabel.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.5)
        messageLabel.shadow?.shadowOffset = NSSize(width: 0, height: 2)
        messageLabel.shadow?.shadowBlurRadius = 4
        
        // Timer text with glowing effect
        let timerLabel = createStyledLabel(text: "00:00", fontSize: 80, weight: .bold)
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 80, weight: .bold)
        self.timeLabel = timerLabel
        
        // Create a subtle glow behind the timer
        let glowView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        glowView.wantsLayer = true
        glowView.layer?.backgroundColor = NSColor.blue.withAlphaComponent(0.2).cgColor
        glowView.layer?.cornerRadius = 50
        glowView.layer?.masksToBounds = false
        glowView.layer?.shadowColor = NSColor.blue.withAlphaComponent(0.4).cgColor
        glowView.layer?.shadowOffset = .zero
        glowView.layer?.shadowRadius = 25
        glowView.layer?.shadowOpacity = 0.8
        
        // Stylish skip button with hover effect
        let skipButton = NSButton(title: "Skip Break", target: self, action: #selector(skipButtonClicked))
        skipButton.bezelStyle = .rounded
        skipButton.wantsLayer = true
        skipButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        skipButton.layer?.cornerRadius = 20
        skipButton.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        skipButton.contentTintColor = NSColor.white
        
        // Add hover effect to the button
        skipButton.trackingAreas.forEach { skipButton.removeTrackingArea($0) }
        let trackingArea = NSTrackingArea(
            rect: skipButton.bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: ["button": skipButton]
        )
        skipButton.addTrackingArea(trackingArea)
        
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
        
        // Start subtle animations
        startBackgroundAnimations(gradientLayer: gradientLayer, particleLayer: particleLayer)
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
    
    private func startBackgroundAnimations(gradientLayer: CAGradientLayer, particleLayer: CALayer) {
        // Animate gradient positions
        let gradientAnimation = CABasicAnimation(keyPath: "colors")
        let darkNavy = NSColor(calibratedRed: 0.0, green: 0.05, blue: 0.2, alpha: 0.9)
        let mediumNavy = NSColor(calibratedRed: 0.0, green: 0.1, blue: 0.3, alpha: 0.85)
        let lightNavy = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.4, alpha: 0.8)
        let accentNavy = NSColor(calibratedRed: 0.05, green: 0.15, blue: 0.35, alpha: 0.85)
        
        gradientAnimation.fromValue = [
            darkNavy.cgColor,
            mediumNavy.cgColor,
            lightNavy.cgColor,
            mediumNavy.cgColor
        ]
        
        gradientAnimation.toValue = [
            mediumNavy.cgColor,
            lightNavy.cgColor,
            accentNavy.cgColor,
            darkNavy.cgColor
        ]
        
        gradientAnimation.duration = 15.0
        gradientAnimation.autoreverses = true
        gradientAnimation.repeatCount = Float.infinity
        gradientLayer.add(gradientAnimation, forKey: "colorChange")
        
        // Create subtle particle animation with timer
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak particleLayer] _ in
            guard let particleLayer = particleLayer else { return }
            self?.addParticle(to: particleLayer)
        }
        
        // Add the timer to common run loop mode
        if let timer = animationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func addParticle(to layer: CALayer) {
        let size = CGFloat.random(in: 2...5)
        let particleLayer = CALayer()
        particleLayer.backgroundColor = NSColor.white.withAlphaComponent(CGFloat.random(in: 0.1...0.3)).cgColor
        particleLayer.cornerRadius = size / 2
        
        // Random position
        let maxX = layer.bounds.width
        let maxY = layer.bounds.height
        let randomX = CGFloat.random(in: 0...maxX)
        let randomY = CGFloat.random(in: 0...maxY)
        particleLayer.frame = CGRect(x: randomX, y: randomY, width: size, height: size)
        
        layer.addSublayer(particleLayer)
        
        // Animate opacity
        let fadeAnimation = CABasicAnimation(keyPath: "opacity")
        fadeAnimation.fromValue = 0.0
        fadeAnimation.toValue = 1.0
        fadeAnimation.duration = 1.0
        
        let fadeOutAnimation = CABasicAnimation(keyPath: "opacity")
        fadeOutAnimation.fromValue = 1.0
        fadeOutAnimation.toValue = 0.0
        fadeOutAnimation.duration = 1.0
        fadeOutAnimation.beginTime = 3.0 // Start after fade in completes + delay
        
        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [fadeAnimation, fadeOutAnimation]
        animationGroup.duration = 4.0
        
        particleLayer.add(animationGroup, forKey: "fadeInOut")
        
        // Remove the particle after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
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
            
            // Add a subtle pulse animation to the timer when it updates
            if let timeLabel = self?.timeLabel {
                let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
                pulseAnimation.fromValue = 1.0
                pulseAnimation.toValue = 1.05
                pulseAnimation.duration = 0.15
                pulseAnimation.autoreverses = true
                timeLabel.layer?.add(pulseAnimation, forKey: "pulse")
            }
        }
    }
    
    @objc private func skipButtonClicked() {
        skipCallback?()
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        
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
    }
    
    deinit {
        // Clean up animation timer
        animationTimer?.invalidate()
        animationTimer = nil
    }
} 