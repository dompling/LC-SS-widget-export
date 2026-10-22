//
//  AppScreenshotCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 10/11/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

extension AppScreenshotCollectionViewCell
{
    private class ImageView: UIImageView
    {
        override func layoutSubviews()
        {
            super.layoutSubviews()
            
            // Explicitly layout cell to ensure rounded corners are accurate.
            self.superview?.superview?.setNeedsLayout()
        }
    }
}

class AppScreenshotCollectionViewCell: UICollectionViewCell
{
    let imageView: UIImageView
    let reloadImageView: UIImageView
    var onRetry: (() -> Void)?
    
    var aspectRatio: CGSize = AppScreenshot.defaultAspectRatio {
        didSet {
            self.updateAspectRatio()
        }
    }
    
    private var isRounded: Bool = false {
        didSet {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
    
    private var aspectRatioConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect)
    {
        self.imageView = ImageView(frame: .zero)
        self.imageView.clipsToBounds = true
        self.imageView.layer.cornerCurve = .continuous
        self.imageView.layer.borderColor = UIColor.tertiaryLabel.cgColor
        
        self.reloadImageView = UIImageView()
        
        super.init(frame: frame)
        
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.imageView)
        
        let widthConstraint = self.imageView.widthAnchor.constraint(equalTo: self.contentView.widthAnchor)
        widthConstraint.priority = .defaultHigh
        
        let heightConstraint = self.imageView.heightAnchor.constraint(equalTo: self.contentView.heightAnchor)
        heightConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            self.imageView.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor),
            self.imageView.heightAnchor.constraint(lessThanOrEqualTo: self.contentView.heightAnchor),
            self.imageView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.imageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor)
        ])
        
        let reloadConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let reloadImage = UIImage(systemName: "arrow.clockwise", withConfiguration: reloadConfig)
        self.reloadImageView.image = reloadImage?.withRenderingMode(.alwaysTemplate)
        self.reloadImageView.tintColor = .label
        self.reloadImageView.contentMode = .scaleAspectFit
        self.reloadImageView.isUserInteractionEnabled = true
        self.reloadImageView.isHidden = true
        self.reloadImageView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.reloadImageView)
        
        NSLayoutConstraint.activate([
            self.reloadImageView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.reloadImageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            self.reloadImageView.widthAnchor.constraint(equalToConstant: 24),
            self.reloadImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(AppScreenshotCollectionViewCell.reloadButtonTapped))
        self.reloadImageView.addGestureRecognizer(tap)
        
        self.updateAspectRatio()
        self.updateTraits()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        
        self.updateTraits()
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        if self.isRounded
        {
            let cornerRadius = self.imageView.bounds.width / 9.0 // Based on iPhone 15
            self.imageView.layer.cornerRadius = cornerRadius
        }
        else
        {
            self.imageView.layer.cornerRadius = 5
        }
    }
}

extension AppScreenshotCollectionViewCell
{
    func setImage(_ image: UIImage?)
    {
        guard var image, let cgImage = image.cgImage else {
            self.imageView.image = image
            return
        }
        
        self.reloadImageView.isHidden = true
                
        if image.size.width > image.size.height && self.aspectRatio.width < self.aspectRatio.height
        {
            // Image is landscape, but cell has portrait aspect ratio, so rotate image to match.
            image = UIImage(cgImage: cgImage, scale: image.scale, orientation: .right)
        }
        
        self.imageView.image = image
    }
    
    @objc private func reloadButtonTapped()
    {
        self.onRetry?()
    }
}

private extension AppScreenshotCollectionViewCell
{
    func updateAspectRatio()
    {
        self.aspectRatioConstraint?.isActive = false
        
        self.aspectRatioConstraint = self.imageView.widthAnchor.constraint(equalTo: self.imageView.heightAnchor, multiplier: self.aspectRatio.width / self.aspectRatio.height)
        self.aspectRatioConstraint?.isActive = true
        
        let aspectRatio: Double
        if self.aspectRatio.width > self.aspectRatio.height
        {
            aspectRatio = self.aspectRatio.height / self.aspectRatio.width
        }
        else
        {
            aspectRatio = self.aspectRatio.width / self.aspectRatio.height
        }
        
        let tolerance = 0.001 as Double
        let modernAspectRatio = AppScreenshot.defaultAspectRatio.width / AppScreenshot.defaultAspectRatio.height
        
        let isRounded = (aspectRatio >= modernAspectRatio - tolerance) && (aspectRatio <= modernAspectRatio + tolerance)
        self.isRounded = isRounded
    }
    
    func updateTraits()
    {
        let displayScale = (self.traitCollection.displayScale == 0.0) ? 1.0 : self.traitCollection.displayScale
        self.imageView.layer.borderWidth = 1.0 / displayScale
    }
}
