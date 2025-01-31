//
//  Token.swift
//  StripeiOS
//
//  Created by David Estes on 7/14/21.
//  Copyright © 2021 Stripe, Inc. All rights reserved.
//

import Foundation
import PassKit
@_spi(STP) import StripeCore

extension StripeAPI {
    struct Token: StripeDecodable {
        var _allResponseFieldsStorage: NonEncodableParameters?
        
        /// The value of the token. You can store this value on your server and use it to make charges and customers.
        /// - seealso: https://stripe.com/docs/payments/charges-api
        let id: String
        /// Whether or not this token was created in livemode. Will be YES if you used your Live Publishable Key, and NO if you used your Test Publishable Key.
        var livemode: Bool
        /// The type of this token.
        var type: TokenType
        
        /// Possible Token types
        enum TokenType: String, Decodable {
            /// Account token type
            case account
            /// Bank account token type
            case bankAccount = "bank_account"
            /// Card token type
            case card
            /// PII token type
            case PII = "pii"
            /// CVC update token type
            case cvcUpdate = "cvc_update"
        }
        
        /// The credit card details that were used to create the token. Will only be set if the token was created via a credit card or Apple Pay, otherwise it will be
        /// nil.
        @IncludeUnknownFields
        var card: Card?
        // /// The bank account details that were used to create the token. Will only be set if the token was created with a bank account, otherwise it will be nil.
        // Not yet implemented.
        //    var bankAccount: BankAccount?
        /// When the token was created.
        var created: Date?
        
        struct Card: StripeDecodable {
            var _allResponseFieldsStorage: NonEncodableParameters?

            /// The last 4 digits of the card.
            var last4: String
            /// For cards made with Apple Pay, this refers to the last 4 digits of the
            /// "Device Account Number" for the tokenized card. For regular cards, it will
            /// be nil.
            var dynamicLast4: String?
            /// Whether or not the card originated from Apple Pay.
            var isApplePayCard: Bool {
                return (allResponseFields["tokenization_method"] as? String) == "apple_pay"
            }
            /// The card's expiration month. 1-indexed (i.e. 1 == January)
            var expMonth: Int
            /// The card's expiration year.
            var expYear: Int
            /// The cardholder's name.
            var name: String?

            /// City/District/Suburb/Town/Village.
            var addressCity: String?

            /// Billing address country, if provided when creating card.
            var addressCountry: String?

            /// Address line 1 (Street address/PO Box/Company name).
            var addressLine1: String?

            /// If address_line1 was provided, results of the check.
            var addressLine1Check: AddressCheck?
            
            /// Results of an address check.
            enum AddressCheck: String, Decodable {
                case pass
                case fail
                case unavailable
                case unchecked
            }

            /// Address line 2 (Apartment/Suite/Unit/Building).
            var addressLine2: String?

            /// State/County/Province/Region.
            var addressState: String?
            
            /// ZIP or postal code.
            var addressZip: String?

            /// If address_zip was provided, results of the check.
            var addressZipCheck: AddressCheck?
            
            /// The issuer of the card.
            var brand: Brand = .unknown
            
            /// The various card brands to which a payment card can belong.
            enum Brand: String, Decodable {
                /// Visa card
                case visa = "Visa"
                /// American Express card
                case amex = "American Express"
                /// Mastercard card
                case mastercard = "MasterCard"
                /// Discover card
                case discover = "Discover"
                /// JCB card
                case JCB = "JCB"
                /// Diners Club card
                case dinersClub = "Diners Club"
                /// UnionPay card
                case unionPay = "UnionPay"
                /// An unknown card brand type
                case unknown = "Unknown"
            }
            
            /// The funding source for the card (credit, debit, prepaid, or other)
            var funding: FundingType = .other
            
            /// The various funding sources for a payment card.
            enum FundingType: String, Decodable {
                /// Debit card funding
                case debit
                /// Credit card funding
                case credit
                /// Prepaid card funding
                case prepaid
                /// An other or unknown type of funding source.
                case other
            }

            /// Two-letter ISO code representing the issuing country of the card.
            var country: String?
            /// This is only applicable when tokenizing debit cards to issue payouts to managed
            /// accounts. You should not set it otherwise. The card can then be used as a
            /// transfer destination for funds in this currency.
            var currency: String?
        }
    }
}
