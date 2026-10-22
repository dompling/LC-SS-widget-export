//
//  ExportAccountAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 8/3/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

class PaddedSecureTextField: UITextField {
    var padding = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }
}

class ExportAccountAlertViewController: UIViewController {
    let passwordTextField = PaddedSecureTextField()
    let includePasswordButton = UIButton(type: .system)
    
    var isIncludePasswordChecked: Bool = false {
        didSet {
            updateButtonImage()
        }
    }
    
    private func updateButtonImage() {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let imageName = isIncludePasswordChecked ? "checkmark.circle.fill" : "circle"
        let image = UIImage(systemName: imageName, withConfiguration: configuration)
        includePasswordButton.setImage(image, for: .normal)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        passwordTextField.isSecureTextEntry = true
        passwordTextField.placeholder = NSLocalizedString("File Password", comment: "")
        passwordTextField.borderStyle = .none
        #if !os(tvOS)
        passwordTextField.backgroundColor = .tertiarySystemFill
        #else
        passwordTextField.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        #endif
        passwordTextField.layer.cornerRadius = 14
        passwordTextField.layer.masksToBounds = true
        passwordTextField.font = .systemFont(ofSize: 16)
        passwordTextField.autocapitalizationType = .none
        passwordTextField.autocorrectionType = .no
        
        NSLayoutConstraint.activate([
            passwordTextField.heightAnchor.constraint(equalToConstant: 44),
            passwordTextField.widthAnchor.constraint(equalToConstant: 240)
        ])
        
        includePasswordButton.tintColor = .systemBlue
        includePasswordButton.imageView?.contentMode = .scaleAspectFit
        includePasswordButton.setContentHuggingPriority(.required, for: .horizontal)
        includePasswordButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            includePasswordButton.widthAnchor.constraint(equalToConstant: 24),
            includePasswordButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        includePasswordButton.addTarget(self, action: #selector(toggleIncludePassword), for: .touchUpInside)
        updateButtonImage()
        
        let label = UILabel()
        label.text = NSLocalizedString("Include Account Password", comment: "")
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleIncludePassword))
        label.addGestureRecognizer(tap)
        
        let checkboxStack = UIStackView(arrangedSubviews: [includePasswordButton, label])
        checkboxStack.axis = .horizontal
        checkboxStack.spacing = 8
        checkboxStack.alignment = .center
        
        let mainStack = UIStackView(arrangedSubviews: [passwordTextField, checkboxStack])
        mainStack.axis = .vertical
        mainStack.spacing = 14
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            mainStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8)
        ])
        
        self.preferredContentSize = CGSize(width: 270, height: 96)
    }
    
    @objc func toggleIncludePassword() {
        isIncludePasswordChecked.toggle()
    }
}
