//
//  DeleteAppAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 16/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

class DeleteAppAlertViewController: UIViewController {
    let checkboxButton = UIButton(type: .system)
    
    var isChecked: Bool = true {
        didSet {
            updateButtonImage(checkboxButton, isChecked: isChecked)
            onToggle?(isChecked)
        }
    }
    
    var onToggle: ((Bool) -> Void)?
    
    private func updateButtonImage(_ button: UIButton, isChecked: Bool) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let imageName = isChecked ? "checkmark.circle.fill" : "circle"
        let image = UIImage(systemName: imageName, withConfiguration: configuration)
        button.setImage(image, for: .normal)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        checkboxButton.tintColor = .systemBlue
        checkboxButton.imageView?.contentMode = .scaleAspectFit
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
        checkboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            checkboxButton.widthAnchor.constraint(equalToConstant: 24),
            checkboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        checkboxButton.addTarget(self, action: #selector(toggleCheckbox), for: .touchUpInside)
        
        let label = UILabel()
        label.text = NSLocalizedString("Uninstall from device", comment: "")
        label.font = .systemFont(ofSize: 14)
        label.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleCheckbox))
        label.addGestureRecognizer(tap)
        
        let stack = UIStackView(arrangedSubviews: [checkboxButton, label])
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
        
        updateButtonImage(checkboxButton, isChecked: isChecked)
        self.preferredContentSize = CGSize(width: 270, height: 36)
    }
    
    @objc func toggleCheckbox() {
        isChecked.toggle()
    }
}
