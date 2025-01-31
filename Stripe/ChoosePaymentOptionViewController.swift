//
//  ChoosePaymentOptionViewController.swift
//  StripeiOS
//
//  Created by Yuki Tokuhiro on 11/4/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

import Foundation
import UIKit
@_spi(STP) import StripeCore
@_spi(STP) import StripeUICore

protocol ChoosePaymentOptionViewControllerDelegate: AnyObject {
    func choosePaymentOptionViewControllerShouldClose(
        _ choosePaymentOptionViewController: ChoosePaymentOptionViewController)
    func choosePaymentOptionViewControllerDidSelectApplePay(
        _ choosePaymentOptionViewController: ChoosePaymentOptionViewController)
    func choosePaymentOptionViewControllerDidSelectPayWithLink(
        _ choosePaymentOptionViewController: ChoosePaymentOptionViewController,
        linkAccount: PaymentSheetLinkAccount?)
    func choosePaymentOptionViewControllerDidUpdateSelection(
        _ choosePaymentOptionViewController: ChoosePaymentOptionViewController)
}

/// For internal SDK use only
@objc(STP_Internal_ChoosePaymentOptionViewController)
class ChoosePaymentOptionViewController: UIViewController {
    // MARK: - Internal Properties
    let intent: Intent
    let configuration: PaymentSheet.Configuration
    var savedPaymentMethods: [STPPaymentMethod] {
        return savedPaymentOptionsViewController.savedPaymentMethods
    }
    var selectedPaymentOption: PaymentOption? {
        switch mode {
        case .addingNew:
            if let paymentOption = addPaymentMethodViewController.paymentOption {
                return paymentOption
            } else if isApplePayEnabled {
                return .applePay
            }
            return nil
        case .selectingSaved:
            if let selectedPaymentOption = savedPaymentOptionsViewController.selectedPaymentOption {
                return selectedPaymentOption
            } else if isApplePayEnabled && shouldShowWalletHeader {
                // in this case, savedPaymentOptionsViewController doesn't
                // offer apple pay, so default to it
                return .applePay
            } else {
                return nil
            }
        }
    }
    var selectedPaymentMethodType: STPPaymentMethodType {
        return addPaymentMethodViewController.selectedPaymentMethodType
    }
    weak var delegate: ChoosePaymentOptionViewControllerDelegate?
    lazy var navigationBar: SheetNavigationBar = {
        let navBar = SheetNavigationBar(isTestMode: configuration.apiClient.isTestmode,
                                        appearance: configuration.appearance)
        navBar.delegate = self
        return navBar
    }()
    private(set) var error: Error?
    private(set) var isDismissable: Bool = true

    // MARK: - Private Properties
    enum Mode {
        case selectingSaved
        case addingNew
    }
    private var mode: Mode
    private var isSavingInProgress: Bool = false
    private var isVerificationInProgress: Bool = false
    private let isApplePayEnabled: Bool
    var linkAccount: PaymentSheetLinkAccount? {
        didSet {
            walletHeader.linkAccount = linkAccount
            addPaymentMethodViewController.linkAccount = linkAccount
        }
    }

    private var isLinkEnabled: Bool {
        return intent.supportsLink
    }

    private var isWalletEnabled: Bool {
        return isApplePayEnabled || isLinkEnabled
    }

    private var shouldShowWalletHeader: Bool {
        switch mode {
        case .addingNew:
            return isWalletEnabled
        case .selectingSaved:
           // When selecting saved we only add the wallet header for Link -- ApplePay by itself is inlined
            return isLinkEnabled
        }
    }

    // MARK: - Views
    private lazy var addPaymentMethodViewController: AddPaymentMethodViewController = {
        return AddPaymentMethodViewController(
            intent: intent,
            configuration: configuration,
            delegate: self)
    }()
    private let savedPaymentOptionsViewController: SavedPaymentOptionsViewController
    private lazy var headerLabel: UILabel = {
        return PaymentSheetUI.makeHeaderLabel(appearance: configuration.appearance)
    }()
    private lazy var paymentContainerView: DynamicHeightContainerView = {
        return DynamicHeightContainerView()
    }()
    private lazy var errorLabel: UILabel = {
        return ElementsUI.makeErrorLabel()
    }()
    private lazy var confirmButton: ConfirmButton = {        
        let button = ConfirmButton(
            style: .stripe,
            callToAction: .add(paymentMethodType: selectedPaymentMethodType),
            appearance: configuration.appearance,
            backgroundColor: configuration.primaryButtonColor,
            didTap: { [weak self] in
                self?.didTapAddButton()
            }
        )
        return button
    }()
    private lazy var walletHeader: PaymentSheetViewController.WalletHeaderView = {
        var walletOptions: PaymentSheetViewController.WalletHeaderView.WalletOptions = []

        if isApplePayEnabled {
            walletOptions.insert(.applePay)
        }

        if isLinkEnabled {
            walletOptions.insert(.link)
        }

        let header = PaymentSheetViewController.WalletHeaderView(options: walletOptions, appearance: configuration.appearance, delegate: self)
        header.linkAccount = linkAccount
        return header
    }()

    // MARK: - Init

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(
        intent: Intent,
        savedPaymentMethods: [STPPaymentMethod],
        configuration: PaymentSheet.Configuration,
        isApplePayEnabled: Bool,
        linkAccount: PaymentSheetLinkAccount?,
        delegate: ChoosePaymentOptionViewControllerDelegate
    ) {
        self.intent = intent
        self.isApplePayEnabled = isApplePayEnabled
        self.linkAccount = linkAccount
        
        self.configuration = configuration
        self.delegate = delegate

        let mode: Mode = {
            if savedPaymentMethods.count > 0 || (isApplePayEnabled && !intent.supportsLink) {
                return .selectingSaved
            } else {
                return .addingNew
            }
        }()
        self.mode = mode
        
        // The logic here is copied from the vars so we can use them before init
        let isWalletEnabled = isApplePayEnabled || intent.supportsLink
        let shouldShowWalletheader: Bool = {
            switch mode {
            case .addingNew:
                return isWalletEnabled
            case .selectingSaved:
               // When selecting saved we only add the wallet header for Link -- ApplePay by itself is inlined
                return intent.supportsLink
            }
        }()
        let showApplePay = !shouldShowWalletheader && isApplePayEnabled
        
        self.savedPaymentOptionsViewController = SavedPaymentOptionsViewController(
            savedPaymentMethods: savedPaymentMethods,
            configuration: .init(
                customerID: configuration.customer?.id,
                showApplePay: showApplePay,
                autoSelectDefaultBehavior: intent.supportsLink ? .onlyIfMatched : .defaultFirst
            ),
            appearance: configuration.appearance,
            delegate: nil
        )
        
        
        super.init(nibName: nil, bundle: nil)
        self.savedPaymentOptionsViewController.delegate = self
    }

    // MARK: - UIViewController Methods

    override func viewDidLoad() {
        super.viewDidLoad()

        // One stack view contains all our subviews
        let stackView = UIStackView(arrangedSubviews: [
            headerLabel, walletHeader, paymentContainerView, errorLabel, confirmButton,
        ])
        stackView.bringSubviewToFront(headerLabel)
        stackView.directionalLayoutMargins = PaymentSheetUI.defaultMargins
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.spacing = PaymentSheetUI.defaultPadding
        stackView.axis = .vertical
        [stackView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        // Get our margins in order
        view.directionalLayoutMargins = PaymentSheetUI.defaultSheetMargins
        // Hack: Payment container needs to extend to the edges, so we'll 'cancel out' the layout margins with negative padding
        paymentContainerView.directionalLayoutMargins = .insets(
            leading: -PaymentSheetUI.defaultSheetMargins.leading,
            trailing: -PaymentSheetUI.defaultSheetMargins.trailing
        )

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor, constant: -PaymentSheetUI.defaultSheetMargins.bottom),
        ])

        updateUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        STPAnalyticsClient.sharedClient.logPaymentSheetShow(
            isCustom: true,
            paymentMethod: mode.analyticsValue,
            linkEnabled: intent.supportsLink,
            activeLinkSession: linkAccount?.sessionState == .verified
        )
    }

    // MARK: - Private Methods

    private func configureNavBar() {
        navigationBar.setStyle(
            {
                switch mode {
                case .selectingSaved:
                    if self.savedPaymentOptionsViewController.hasRemovablePaymentMethods {
                        self.configureEditSavedPaymentMethodsButton()
                        return .close(showAdditionalButton: true)
                    } else {
                        self.navigationBar.additionalButton.removeTarget(
                            self, action: #selector(didSelectEditSavedPaymentMethodsButton),
                            for: .touchUpInside)
                        return .close(showAdditionalButton: false)
                    }
                case .addingNew:
                    self.navigationBar.additionalButton.removeTarget(
                        self, action: #selector(didSelectEditSavedPaymentMethodsButton),
                        for: .touchUpInside)
                    return savedPaymentOptionsViewController.hasPaymentOptions
                        ? .back : .close(showAdditionalButton: false)
                }
            }())
    }

    // state -> view
    private func updateUI() {
        // Disable interaction if necessary
        let shouldEnableUserInteraction = !isSavingInProgress && !isVerificationInProgress
        if shouldEnableUserInteraction != view.isUserInteractionEnabled {
            sendEventToSubviews(
                shouldEnableUserInteraction ?
                    .shouldEnableUserInteraction : .shouldDisableUserInteraction,
                from: view
            )
        }
        view.isUserInteractionEnabled = shouldEnableUserInteraction
        isDismissable = !isSavingInProgress && !isVerificationInProgress

        configureNavBar()
        
        // Content header
        walletHeader.isHidden = !shouldShowWalletHeader
        walletHeader.showsCardPaymentMessage = (
            addPaymentMethodViewController.paymentMethodTypes == [.card]
        )

        
        switch mode {
        case .selectingSaved:
            headerLabel.isHidden = false
            headerLabel.text = STPLocalizedString(
                "Select your payment method",
                "Title shown above a carousel containing the customer's payment methods")
        case .addingNew:
            headerLabel.isHidden = isWalletEnabled
            if addPaymentMethodViewController.paymentMethodTypes == [.card] {
                headerLabel.text = STPLocalizedString("Add a card", "Title shown above a card entry form")
            } else {
                headerLabel.text = STPLocalizedString("Choose a payment method", "TODO")
            }
        }

        // Content
        let targetViewController: UIViewController = {
            switch mode {
            case .selectingSaved:
                return savedPaymentOptionsViewController
            case .addingNew:
                return addPaymentMethodViewController
            }
        }()
        switchContentIfNecessary(
            to: targetViewController,
            containerView: paymentContainerView
        )

        // Error
        switch mode {
        case .addingNew:
            if addPaymentMethodViewController.setErrorIfNecessary(for: error) == false {
                errorLabel.text = error?.localizedDescription
            }
        case .selectingSaved:
            errorLabel.text = error?.localizedDescription
        }
        UIView.animate(withDuration: PaymentSheetUI.defaultAnimationDuration) {
            self.errorLabel.setHiddenIfNecessary(self.error == nil)
        }

        // Buy button
        switch mode {
        case .selectingSaved:
            UIView.animate(withDuration: PaymentSheetUI.defaultAnimationDuration) {
                // We're selecting a saved PM, there's no 'Add' button
                self.confirmButton.alpha = 0
                self.confirmButton.isHidden = true
            }
        case .addingNew:
            // Configure add button
            if confirmButton.isHidden {
                confirmButton.alpha = 0
                UIView.animate(withDuration: PaymentSheetUI.defaultAnimationDuration) {
                    self.confirmButton.alpha = 1
                    self.confirmButton.isHidden = false
                }
            }
            let confirmButtonState: ConfirmButton.Status = {
                if isSavingInProgress || isVerificationInProgress {
                    // We're in the middle of adding the PM
                    return .processing
                } else if addPaymentMethodViewController.paymentOption == nil {
                    // We don't have valid payment method params yet
                    return .disabled
                } else {
                    return .enabled
                }
            }()
            confirmButton.update(
                state: confirmButtonState,
                callToAction: .add(paymentMethodType: selectedPaymentMethodType),
                animated: true
            )
        }
    }

    @objc
    private func didTapAddButton() {
        self.delegate?.choosePaymentOptionViewControllerShouldClose(self)
    }

    func didDismiss() {
        // If the customer was adding a new payment method and it's incomplete/invalid, return to the saved PM screen
        delegate?.choosePaymentOptionViewControllerShouldClose(self)
        if savedPaymentOptionsViewController.isRemovingPaymentMethods {
            savedPaymentOptionsViewController.isRemovingPaymentMethods = false
            configureEditSavedPaymentMethodsButton()
        }
    }
}

// MARK: - BottomSheetContentViewController
/// :nodoc:
extension ChoosePaymentOptionViewController: BottomSheetContentViewController {
    var allowsDragToDismiss: Bool {
        return isDismissable
    }

    func didTapOrSwipeToDismiss() {
        if isDismissable {
            didDismiss()
        }
    }

    var requiresFullScreen: Bool {
        return false
    }
}

//MARK: - SavedPaymentOptionsViewControllerDelegate
/// :nodoc:
extension ChoosePaymentOptionViewController: SavedPaymentOptionsViewControllerDelegate {
    func didUpdateSelection(
        viewController: SavedPaymentOptionsViewController,
        paymentMethodSelection: SavedPaymentOptionsViewController.Selection
    ) {
        STPAnalyticsClient.sharedClient.logPaymentSheetPaymentOptionSelect(isCustom: true, paymentMethod: paymentMethodSelection.analyticsValue)
        guard case Mode.selectingSaved = mode else {
            assertionFailure()
            return
        }
        switch paymentMethodSelection {
        case .add:
            mode = .addingNew
            error = nil // Clear any errors
            updateUI()
        case .applePay, .saved:
            delegate?.choosePaymentOptionViewControllerDidUpdateSelection(self)
            updateUI()
            if isDismissable {
                delegate?.choosePaymentOptionViewControllerShouldClose(self)
            }
        }

        
    }

    func didSelectRemove(
        viewController: SavedPaymentOptionsViewController,
        paymentMethodSelection: SavedPaymentOptionsViewController.Selection
    ) {
        guard case .saved(let paymentMethod) = paymentMethodSelection,
            let ephemeralKey = configuration.customer?.ephemeralKeySecret
        else {
            return
        }
        configuration.apiClient.detachPaymentMethod(
            paymentMethod.stripeId, fromCustomerUsing: ephemeralKey
        ) { (_) in
            // no-op
        }

        if !savedPaymentOptionsViewController.hasRemovablePaymentMethods {
            savedPaymentOptionsViewController.isRemovingPaymentMethods = false
            // calling updateUI() at this point causes an issue with the height of the add card vc
            // if you do a subsequent presentation. Since bottom sheet height stuff is complicated,
            // just update the nav bar which is all we need to do anyway
            configureNavBar()
        }
    }

    // MARK: Helpers
    func configureEditSavedPaymentMethodsButton() {
        if savedPaymentOptionsViewController.isRemovingPaymentMethods {
            navigationBar.additionalButton.setTitle(UIButton.doneButtonTitle, for: .normal)
        } else {
            navigationBar.additionalButton.setTitle(UIButton.editButtonTitle, for: .normal)
        }
        navigationBar.additionalButton.accessibilityIdentifier = "edit_saved_button"
        navigationBar.additionalButton.titleLabel?.font = configuration.appearance.font.base.medium
        navigationBar.additionalButton.titleLabel?.adjustsFontForContentSizeCategory = true
        navigationBar.additionalButton.addTarget(
            self, action: #selector(didSelectEditSavedPaymentMethodsButton), for: .touchUpInside)
    }

    @objc
    func didSelectEditSavedPaymentMethodsButton() {
        savedPaymentOptionsViewController.isRemovingPaymentMethods.toggle()
        configureEditSavedPaymentMethodsButton()
    }
}

//MARK: - AddPaymentMethodViewControllerDelegate
/// :nodoc:
extension ChoosePaymentOptionViewController: AddPaymentMethodViewControllerDelegate {
    func didUpdate(_ viewController: AddPaymentMethodViewController) {
        error = nil  // clear error
        if case .link(let linkAccount, _) = selectedPaymentOption,
           linkAccount.sessionState == .requiresVerification {
            isVerificationInProgress = true
            updateUI()
            linkAccount.startVerification { result in
                switch result {
                case .success(let collectOTP):
                    if collectOTP {
                        let twoFAViewController = Link2FAViewController(mode: .inlineLogin, linkAccount: linkAccount) { _ in
                            self.dismiss(animated: true, completion: nil)
                            self.isVerificationInProgress = false
                            self.updateUI()
                        }
                        self.present(twoFAViewController, animated: true)
                    } else {
                        self.isVerificationInProgress = false
                        self.updateUI()
                    }
                case .failure(_):
                    // TODO(ramont): error handling
                    self.isVerificationInProgress = false
                    self.updateUI()
                }
            }
        } else {
            updateUI()
        }
    }

    func shouldOfferLinkSignup(_ viewController: AddPaymentMethodViewController) -> Bool {
        guard let linkAccount = linkAccount else {
            return true
        }

        return !linkAccount.isRegistered
    }
    func updateErrorLabel(for error: Error?) {
        // no-op: No current use case for this
    }
}
//MARK: - SheetNavigationBarDelegate
/// :nodoc:
extension ChoosePaymentOptionViewController: SheetNavigationBarDelegate {
    func sheetNavigationBarDidClose(_ sheetNavigationBar: SheetNavigationBar) {
        didDismiss()
    }

    func sheetNavigationBarDidBack(_ sheetNavigationBar: SheetNavigationBar) {
        // This is quite hardcoded. Could make some generic "previous mode" or "previous VC" that we always go back to
        switch mode {
        case .addingNew:
            error = nil
            mode = .selectingSaved
            updateUI()
        default:
            assertionFailure()
        }
    }
}

//MARK: - WalletHeaderViewDelegate
/// :nodoc:
extension ChoosePaymentOptionViewController: WalletHeaderViewDelegate {
    func walletHeaderViewApplePayButtonTapped(_ header: PaymentSheetViewController.WalletHeaderView) {
        savedPaymentOptionsViewController.unselectPaymentMethod()
        delegate?.choosePaymentOptionViewControllerDidSelectApplePay(self)
    }

    func walletHeaderViewPayWithLinkTapped(_ header: PaymentSheetViewController.WalletHeaderView) {
        savedPaymentOptionsViewController.unselectPaymentMethod()
        delegate?.choosePaymentOptionViewControllerDidSelectPayWithLink(self, linkAccount: linkAccount)
    
    }

}
