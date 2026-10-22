//
//  CustomAppIDAlertViewController.swift
//  SideStore
//
//  Created by Magesh K on 28/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign

class AppendTeamIDCheckboxView: UIView, UITextFieldDelegate {
    let checkboxButton = UIButton(type: .system)
    let label = UILabel()
    weak var textField: UITextField?
    var teamID: String = ""
    
    var suffix: String {
        teamID.isEmpty ? "" : ".\(teamID)"
    }
    
    var isChecked: Bool = true {
        didSet {
            updateButtonImage()
            updateTextFieldSuffix()
            onToggle?(isChecked)
        }
    }
    
    var onToggle: ((Bool) -> Void)?
    
    init(isChecked: Bool = true, teamID: String = "", textField: UITextField? = nil) {
        self.isChecked = isChecked
        self.teamID = teamID
        self.textField = textField
        super.init(frame: .zero)
        setup()
        if let tf = textField {
            attach(to: tf, teamID: teamID)
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    func attach(to textField: UITextField, teamID: String) {
        verboseLog("[AppendTeamIDCheckboxView] attach: teamID='\(teamID)', initial textField.text='\(textField.text ?? "")'")
        self.textField = textField
        self.teamID = teamID
        textField.delegate = self
        updateTextFieldSuffix()
        verboseLog("[AppendTeamIDCheckboxView] attach finished: textField.text='\(textField.text ?? "")', suffix='\(suffix)'")
    }

    private func updateTextFieldSuffix() {
        guard let tf = textField, !suffix.isEmpty else {
            verboseLog("[AppendTeamIDCheckboxView] updateTextFieldSuffix skipped: hasTextField=\(textField != nil), suffix='\(suffix)'")
            return
        }
        let current = tf.text ?? ""
        verboseLog("[AppendTeamIDCheckboxView] updateTextFieldSuffix: isChecked=\(isChecked), current='\(current)', suffix='\(suffix)'")
        if isChecked {
            let base = current.hasSuffix(suffix) ? String(current.dropLast(suffix.count)) : current
            let clean = InfoPlistParser.sanitizeBundleID(base)
            tf.text = clean + suffix
        } else {
            if current.hasSuffix(suffix) {
                tf.text = String(current.dropLast(suffix.count))
            }
        }
        verboseLog("[AppendTeamIDCheckboxView] updateTextFieldSuffix result: tf.text='\(tf.text ?? "")'")
    }
    
    func cleanBaseID() -> String {
        guard let text = textField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return "" }
        let rawBase: String
        if isChecked && !suffix.isEmpty && text.hasSuffix(suffix) {
            rawBase = String(text.dropLast(suffix.count))
        } else {
            rawBase = text
        }
        let clean = InfoPlistParser.sanitizeBundleID(rawBase)
        verboseLog("[AppendTeamIDCheckboxView] cleanBaseID: text='\(text)', rawBase='\(rawBase)', clean='\(clean)'")
        return clean
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        verboseLog("[AppendTeamIDCheckboxView] shouldChange: range=\(range), string='\(string)', current='\(textField.text ?? "")'")
        let allowed = SuffixEnforcedTextField.shouldChangeBundleID(
            in: textField,
            range: range,
            replacementString: string,
            suffix: suffix,
            isSuffixEnforced: isChecked
        )
        verboseLog("[AppendTeamIDCheckboxView] shouldChange allowed=\(allowed), resultingText='\(textField.text ?? "")'")
        return allowed
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        guard isChecked && !suffix.isEmpty else { return true }
        textField.text = suffix
        return false
    }
    
    private func updateButtonImage() {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let imageName = isChecked ? "checkmark.circle.fill" : "circle"
        let image = UIImage(systemName: imageName, withConfiguration: configuration)
        checkboxButton.setImage(image, for: .normal)
    }
    
    private func setup() {
        checkboxButton.tintColor = .systemBlue
        checkboxButton.imageView?.contentMode = .scaleAspectFit
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
        checkboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        checkboxButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkboxButton.widthAnchor.constraint(equalToConstant: 22),
            checkboxButton.heightAnchor.constraint(equalToConstant: 22)
        ])
        checkboxButton.addTarget(self, action: #selector(toggleCheckbox), for: .touchUpInside)
        
        label.text = NSLocalizedString("Append Team ID", comment: "")
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .label
        label.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleCheckbox))
        label.addGestureRecognizer(tap)
        
        let stack = UIStackView(arrangedSubviews: [checkboxButton, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        updateButtonImage()
    }
    
    @objc func toggleCheckbox() {
        isChecked.toggle()
    }
}
