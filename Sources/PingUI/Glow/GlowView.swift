//
//  GlowView.swift
//  PingUI
//
//  Created by Tanner on 9/17/25.
//
//  The animation state machine, kept close to verbatim. What changed: the
//  four constants that used to be hardcoded here are `[glow.pulse]` now, and preview is no
//  longer a mode the view knows about — a preview simply arrives as a different set of
//  glows, because the resolver substituted a preview snapshot upstream.
//

import Cocoa
import PingConfig
import QuartzCore

class GlowView: NSView, @preconcurrency CAAnimationDelegate {
  private var glowLayer: CAGradientLayer!
  let edge: Edge

  private var rotator = Rotator<ResolvedGlow>()
  private var displayed: ResolvedGlow?
  private var pulse = PulseSettings()

  private enum AnimationPhase {
    case idle
    case fadeIn
    case fadeOut
    case crossfade
  }

  private var phase: AnimationPhase = .idle

  private var opacityMultiplier: Float = 1.0
  private var minOpacity: Float { Float(pulse.minOpacity) * opacityMultiplier }
  private var maxOpacity: Float { Float(pulse.maxOpacity) * opacityMultiplier }
  private var fadeDuration: CFTimeInterval { Double(pulse.durationMS) / 1000 }
  private var crossfadeDuration: CFTimeInterval { Double(pulse.crossfadeMS) / 1000 }

  init(frame frameRect: NSRect, edge: Edge) {
    self.edge = edge
    super.init(frame: frameRect)
    setupGlowEffect()
    updateAvailable([])
  }

  required init?(coder: NSCoder) {
    self.edge = .bottom
    super.init(coder: coder)
    setupGlowEffect()
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    MainActor.assumeIsolated {
      setupGlowEffect()
    }
  }

  // MARK: - Public API

  /// Takes effect on the next animation, so a config reload never cuts one short.
  func setPulse(_ pulse: PulseSettings) {
    self.pulse = pulse
  }

  /// Update the set of glows to cycle through without interrupting the current animation.
  /// New glows are prioritized (shown next), existing ones maintain LRU order.
  func updateAvailable(_ glows: [ResolvedGlow]) {
    let wasEmpty = rotator.isEmpty
    rotator.setAvailable(glows)

    if rotator.isEmpty {
      // All glows removed — fade out or go idle
      if phase != .idle {
        displayed = nil
        phase = .idle
        glowLayer?.removeAllAnimations()
      }
      return
    }

    if wasEmpty || phase == .idle {
      // Start fresh
      displayed = rotator.current
      if let glow = displayed {
        apply(glow)
        startFadeIn(entering: true)
      }
      return
    }

    // If what is on screen was removed from the set, accelerate fade-out
    if let displayed, let current = rotator.current, displayed != current {
      accelerateTransitionAway()
    }
  }

  // MARK: - Gradient

  private func gradientColors(for color: NSColor) -> [CGColor] {
    [
      color.cgColor,
      color.withAlphaComponent(0.15).cgColor,
      color.withAlphaComponent(0.0).cgColor,
    ]
  }

  private func gradientPoints(for edge: Edge, size: Double) -> (CGPoint, CGPoint) {
    let s = CGFloat(size)
    switch edge {
    case .bottom:
      return (CGPoint(x: 0.5, y: -0.4), CGPoint(x: 0.8 + s / 5, y: 0.5 + s / 2))
    case .top:
      return (CGPoint(x: 0.5, y: 1.4), CGPoint(x: 0.8 + s / 5, y: 0.5 - s / 2))
    case .left:
      return (CGPoint(x: -0.4, y: 0.5), CGPoint(x: 0.5 + s / 2, y: 0.8 + s / 5))
    case .right:
      return (CGPoint(x: 1.4, y: 0.5), CGPoint(x: 0.5 - s / 2, y: 0.8 + s / 5))
    }
  }

  private func apply(_ glow: ResolvedGlow) {
    opacityMultiplier = Float(glow.opacity)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    glowLayer.colors = gradientColors(for: glow.color.nsColor)
    glowLayer.locations = [0.0, 0.85, 1.0]
    let (start, end) = gradientPoints(for: edge, size: glow.size)
    glowLayer.startPoint = start
    glowLayer.endPoint = end
    CATransaction.commit()
  }

  // MARK: - Setup

  private func setupGlowEffect() {
    self.wantsLayer = true

    glowLayer = CAGradientLayer()
    glowLayer.frame = self.bounds
    glowLayer.type = .radial

    let (start, end) = gradientPoints(for: edge, size: 0.5)
    glowLayer.startPoint = start
    glowLayer.endPoint = end

    glowLayer.opacity = minOpacity
    self.layer?.addSublayer(glowLayer)
  }

  // MARK: - Animation

  private func startFadeIn(entering: Bool = false) {
    phase = .fadeIn
    glowLayer?.removeAllAnimations()

    let anim = CABasicAnimation(keyPath: "opacity")
    anim.fromValue = entering ? 0 : minOpacity
    anim.toValue = maxOpacity
    anim.duration = fadeDuration
    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    anim.delegate = self

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    glowLayer.opacity = maxOpacity
    glowLayer?.add(anim, forKey: "glowAnimation")
    CATransaction.commit()
  }

  private func startFadeOut() {
    phase = .fadeOut

    let anim = CABasicAnimation(keyPath: "opacity")
    anim.fromValue = maxOpacity
    anim.toValue = minOpacity
    anim.duration = fadeDuration
    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    anim.delegate = self

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    glowLayer.opacity = minOpacity
    glowLayer?.add(anim, forKey: "glowAnimation")
    CATransaction.commit()
  }

  private func startCrossfade(to glow: ResolvedGlow) {
    phase = .crossfade
    let oldColors = glowLayer.colors
    let oldEndPoint = glowLayer.endPoint
    let oldMinOpacity = minOpacity
    displayed = glow
    let newColors = gradientColors(for: glow.color.nsColor)

    apply(glow)

    let newMinOpacity = minOpacity

    let colorsAnim = CABasicAnimation(keyPath: "colors")
    colorsAnim.fromValue = oldColors
    colorsAnim.toValue = newColors

    let endPointAnim = CABasicAnimation(keyPath: "endPoint")
    endPointAnim.fromValue = oldEndPoint
    endPointAnim.toValue = glowLayer.endPoint

    let opacityAnim = CABasicAnimation(keyPath: "opacity")
    opacityAnim.fromValue = oldMinOpacity
    opacityAnim.toValue = newMinOpacity

    let group = CAAnimationGroup()
    group.animations = [colorsAnim, endPointAnim, opacityAnim]
    group.duration = crossfadeDuration
    group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    group.delegate = self

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    glowLayer.opacity = newMinOpacity
    glowLayer.add(group, forKey: "glowAnimation")
    CATransaction.commit()
  }

  private func accelerateTransitionAway() {
    guard phase != .crossfade else { return }

    let currentOpacity =
      glowLayer.presentation()?.opacity ?? glowLayer.opacity
    glowLayer.removeAllAnimations()

    let duration = max(
      0.15, Double(currentOpacity / maxOpacity) * fadeDuration * 0.5)

    phase = .fadeOut

    let anim = CABasicAnimation(keyPath: "opacity")
    anim.fromValue = currentOpacity
    anim.toValue = minOpacity
    anim.duration = duration
    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    anim.delegate = self

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    glowLayer.opacity = minOpacity
    glowLayer.add(anim, forKey: "glowAnimation")
    CATransaction.commit()
  }

  func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
    guard flag else { return }

    switch phase {
    case .idle:
      break
    case .fadeIn:
      startFadeOut()
    case .fadeOut:
      if rotator.isEmpty {
        phase = .idle
      } else if let next = rotator.next(), let displayed, next != displayed {
        startCrossfade(to: next)
      } else {
        // A single glow, or the same one again — just keep breathing
        displayed = rotator.current
        startFadeIn()
      }
    case .crossfade:
      startFadeIn()
    }
  }

  override func layout() {
    super.layout()
    glowLayer?.frame = self.bounds
  }
}
