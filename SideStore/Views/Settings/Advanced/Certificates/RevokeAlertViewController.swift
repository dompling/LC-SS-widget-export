//
//  RevokeAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 8/1/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

class RevokeAlertViewController: UIViewController {
    let keepLocalCheckboxButton = UIButton(type: .system)
    
    var isKeepLocalChecked: Bool = false {
        didSet {
            updateButtonImage(keepLocalCheckboxButton, isChecked: isKeepLocalChecked)
        }
    }
    
    private func updateButtonImage(_ button: UIButton, isChecked: Bool) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let imageName = isChecked ? "checkmark.circle.fill" : "circle"
        let image = UIImage(systemName: imageName, withConfiguration: configuration)
        button.setImage(image, for: .normal)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        updateButtonImage(keepLocalCheckboxButton, isChecked: isKeepLocalChecked)
        
        keepLocalCheckboxButton.tintColor = .systemBlue
        keepLocalCheckboxButton.imageView?.contentMode = .scaleAspectFit
        keepLocalCheckboxButton.setContentHuggingPriority(.required, for: .horizontal)
        keepLocalCheckboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            keepLocalCheckboxButton.widthAnchor.constraint(equalToConstant: 24),
            keepLocalCheckboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        keepLocalCheckboxButton.addTarget(self, action: #selector(toggleKeepLocalCheckbox), for: .touchUpInside)
        
        let label = UILabel()
        label.text = NSLocalizedString("Keep Local Certificate", comment: "")
        label.font = .systemFont(ofSize: 14)
        label.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleKeepLocalCheckbox))
        label.addGestureRecognizer(tap)
        
        let stack = UIStackView(arrangedSubviews: [keepLocalCheckboxButton, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        self.preferredContentSize = CGSize(width: 270, height: 32)
    }
    
    @objc func toggleKeepLocalCheckbox() {
        isKeepLocalChecked.toggle()
    }
}
