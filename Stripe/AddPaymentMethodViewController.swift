//
//  AddPaymentMethodViewController.swift
//  StripeiOS
//
//  Created by Yuki Tokuhiro on 10/13/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

import Foundation
import UIKit
@_spi(STP) import StripeUICore
@_spi(STP) import StripeCore
protocol AddPaymentMethodViewControllerDelegate: AnyObject {
    func didUpdate(_ viewController: AddPaymentMethodViewController)
    func shouldOfferLinkSignup(_ viewController: AddPaymentMethodViewController) -> Bool
    func updateErrorLabel(for: Error?)
}


enum OverrideableBuyButtonBehavior {
    case LinkUSBankAccount
}

/// This displays:
/// - A carousel of Payment Method types
/// - Input fields for the selected Payment Method type
/// For internal SDK use only
@objc(STP_Internal_AddPaymentMethodViewController)
class AddPaymentMethodViewController: UIViewController {
    // MARK: - Read-only Properties
    weak var delegate: AddPaymentMethodViewControllerDelegate?
    lazy var paymentMethodTypes: [STPPaymentMethodType] = {
        var recommendedPaymentMethodTypes = intent.recommendedPaymentMethodTypes
        if configuration.linkPaymentMethodsOnly {
            // If we're in the Link modal, manually add instant debit
            // as an option and let the support calls decide if it's allowed
            recommendedPaymentMethodTypes.append(.linkInstantDebit)
        }
        if ConnectionsSDKAvailability.connections() == nil {
            if let index = recommendedPaymentMethodTypes.firstIndex(of: .USBankAccount) {
                recommendedPaymentMethodTypes.remove(at: index)
            }
        }
        return recommendedPaymentMethodTypes.filter {
            PaymentSheet.supportsAdding(
                paymentMethod: $0,
                configuration: configuration,
                intent: intent,
                supportedPaymentMethods: configuration.linkPaymentMethodsOnly ?
                    PaymentSheet.supportedLinkPaymentMethods : PaymentSheet.supportedPaymentMethods
            )
        }
    }()
    var selectedPaymentMethodType: STPPaymentMethodType {
        return paymentMethodTypesView.selected
    }
    var paymentOption: PaymentOption? {
        if let linkEnabledElement = paymentMethodFormElement as? LinkEnabledPaymentMethodElement {
            return linkEnabledElement.makePaymentOption()
        }

        if let params = paymentMethodFormElement.updateParams(
            params: IntentConfirmParams(type: selectedPaymentMethodType)
        ) {
            return .new(confirmParams: params)
        }
        return nil
    }

    var linkAccount: PaymentSheetLinkAccount? {
        didSet {
            updateFormElement()
        }
    }

    var overrideCallToAction: ConfirmButton.CallToActionType? {
        return overrideBuyButtonBehavior != nil
        ? ConfirmButton.CallToActionType.customWithLock(
            title: STPLocalizedString("Begin linking account",
                                      "Title for confirm button to start linking account"))
        : nil
    }

    var overrideBuyButtonBehavior: OverrideableBuyButtonBehavior? {
        if selectedPaymentMethodType == .USBankAccount {
            if let paymentOption = paymentOption,
               case .new(let confirmParams) = paymentOption {
                if confirmParams.paymentMethodParams.usBankAccount?.linkAccountSessionID == nil {
                    return .LinkUSBankAccount
                }
            } else {
                return .LinkUSBankAccount
            }
        }
        return nil
    }

    private let intent: Intent
    private let configuration: PaymentSheet.Configuration
    private lazy var paymentMethodFormElement: PaymentMethodElement = {
        return makeElement(for: selectedPaymentMethodType)
    }()

    // MARK: - Views
    private lazy var paymentMethodDetailsView: UIView = {
        return paymentMethodFormElement.view
    }()
    private lazy var paymentMethodTypesView: PaymentMethodTypeCollectionView = {
        let view = PaymentMethodTypeCollectionView(
            paymentMethodTypes: paymentMethodTypes, appearance: configuration.appearance, delegate: self)
        return view
    }()
    private lazy var paymentMethodDetailsContainerView: DynamicHeightContainerView = {
        // when displaying link, we aren't in the bottom/payment sheet so pin to top for height changes
        let view = DynamicHeightContainerView(pinnedDirection: configuration.linkPaymentMethodsOnly ? .top : .bottom)
        view.directionalLayoutMargins = PaymentSheetUI.defaultMargins
        view.addPinnedSubview(paymentMethodDetailsView)
        view.updateHeight()
        return view
    }()

    // MARK: - Inits
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(
        intent: Intent,
        configuration: PaymentSheet.Configuration,
        delegate: AddPaymentMethodViewControllerDelegate,
        linkAccount: PaymentSheetLinkAccount? = nil
    ) {
        self.configuration = configuration
        self.intent = intent
        self.delegate = delegate
        self.linkAccount = linkAccount
        super.init(nibName: nil, bundle: nil)
        self.view.backgroundColor = configuration.appearance.colors.background
    }

    // MARK: - UIViewController
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CompatibleColor.systemBackground

        let stackView = UIStackView(arrangedSubviews: [
            paymentMethodTypesView, paymentMethodDetailsContainerView,
        ])
        stackView.bringSubviewToFront(paymentMethodTypesView)
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        if paymentMethodTypes == [.card] {
            paymentMethodTypesView.isHidden = true
        } else {
            paymentMethodTypesView.isHidden = false
        }
        updateUI()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if let cardDetailsView = paymentMethodDetailsView as? CardDetailsEditView {
            cardDetailsView.deviceOrientation = UIDevice.current.orientation
        }
    }

    // MARK: - Internal
    
    /// Returns true iff we could map the error to one of the displayed fields
    func setErrorIfNecessary(for error: Error?) -> Bool {
        // TODO
        return false
    }

    // MARK: - Private

    private func updateUI() {
        // Swap out the input view if necessary
        if paymentMethodFormElement.view !== paymentMethodDetailsView {
            let oldView = paymentMethodDetailsView
            let newView = paymentMethodFormElement.view
            self.paymentMethodDetailsView = newView

            // Add the new one and lay it out so it doesn't animate from a zero size
            paymentMethodDetailsContainerView.addPinnedSubview(newView)
            paymentMethodDetailsContainerView.layoutIfNeeded()
            newView.alpha = 0

            UISelectionFeedbackGenerator().selectionChanged()
            // Fade the new one in and the old one out
            animateHeightChange {
                self.paymentMethodDetailsContainerView.updateHeight()
                oldView.alpha = 0
                newView.alpha = 1
            } completion: { _ in
                // Remove the old one
                oldView.removeFromSuperview()
            }
        }
    }

    private func makeElement(for type: STPPaymentMethodType) -> PaymentMethodElement {
        let offerSaveToLinkWhenSupported = delegate?.shouldOfferLinkSignup(self) ?? false

        let formElement = PaymentSheetFormFactory(
            intent: intent,
            configuration: configuration,
            paymentMethod: type,
            offerSaveToLinkWhenSupported: offerSaveToLinkWhenSupported,
            linkAccount: linkAccount
        ).make()
        formElement.delegate = self
        return formElement
    }

    private func updateFormElement() {
        paymentMethodFormElement = makeElement(for: selectedPaymentMethodType)
        updateUI()
    }

    func didTapBuyButton(behavior: OverrideableBuyButtonBehavior, from viewController: UIViewController) {
        switch(behavior) {
        case .LinkUSBankAccount:
            handleCollectBankAccount(from: viewController)
        }
    }

    func handleCollectBankAccount(from viewController: UIViewController) {
        guard case .new(let confirmParams) = paymentOption,
              let usBankAccountPaymentMethodElement = self.paymentMethodFormElement as? USBankAccountPaymentMethodElement else {
            assertionFailure()
            return
        }

        if let name = confirmParams.paymentMethodParams.nonnil_billingDetails.name {
            let params = STPCollectBankAccountParams.collectUSBankAccountParams(
                with: name,
                email: confirmParams.paymentMethodParams.nonnil_billingDetails.email)
            let client = STPBankAccountCollector()
            switch(intent) {
            case .paymentIntent:
                client.collectBankAccountForPayment(clientSecret: intent.clientSecret,
                                                    params: params,
                                                    from: viewController) { connectionsResult, linkAccountSession, error in
                    let errorText = STPLocalizedString("Something went wrong when linking your account.\nPlease try again later.",
                                                       "Error message when an error case happens when linking your account")
                    let genericError = PaymentSheetError.unknown(debugDescription: errorText)

                    if let _ = error {
                        self.delegate?.updateErrorLabel(for: genericError)
                        return
                    }
                    guard let connectionsResult = connectionsResult else {
                        self.delegate?.updateErrorLabel(for: genericError)
                        return
                    }

                    switch(connectionsResult) {
                    case .cancelled:
                        self.delegate?.updateErrorLabel(for: genericError)
                        break
                    case .completed(let linkedBank):
                        usBankAccountPaymentMethodElement.setLinkedBank(linkedBank)
                    case .failed:
                        self.delegate?.updateErrorLabel(for: genericError)
                    }
                }
            case .setupIntent:
                assertionFailure("When dependent code is done, find a way to unify both payment intent and setup intent code")
            }
        }
    }
}

// MARK: - PaymentMethodTypeCollectionViewDelegate

extension AddPaymentMethodViewController: PaymentMethodTypeCollectionViewDelegate {
    func didUpdateSelection(_ paymentMethodTypeCollectionView: PaymentMethodTypeCollectionView) {
        updateFormElement()
        delegate?.didUpdate(self)
    }
}

// MARK: - ElementDelegate

extension AddPaymentMethodViewController: ElementDelegate {
    func continueToNextField(element: Element) {
        delegate?.didUpdate(self)
    }
    
    func didUpdate(element: Element) {
        delegate?.didUpdate(self)
        animateHeightChange()
    }
}
