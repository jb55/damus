//
//  TranslationService.swift
//  damus
//
//  Created by Terry Yiu on 2/3/23.
//

import Foundation

enum TranslationService: String, CaseIterable, Identifiable, StringCodable {
    init?(from string: String) {
        guard let ts = TranslationService(rawValue: string) else {
            return nil
        }
        
        self = ts
    }
    
    func to_string() -> String {
        return self.rawValue
    }
    
    var id: String { self.rawValue }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var tag: String
        var displayName: String
    }

    case none
    case purple
    case libretranslate
    case deepl
    case nokyctranslate
    case winetranslate

    var model: Model {
        switch self {
        case .none:
            let displayName: String
            if TranslationService.isAppleTranslationPopoverSupported {
                displayName = NSLocalizedString("apple_translation_service", value: "Apple", comment: "Dropdown option for selecting Apple as a translation service.")
            } else {
                displayName = NSLocalizedString("none_translation_service", value: "None", comment: "Dropdown option for selecting no translation service.")
            }
            return .init(tag: self.rawValue, displayName: displayName)
        case .purple:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("Damus Purple", comment: "Dropdown option for selecting Damus Purple as a translation service."))
        case .libretranslate:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("LibreTranslate (Open Source)", comment: "Dropdown option for selecting LibreTranslate as the translation service."))
        case .deepl:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("DeepL (Proprietary, Higher Accuracy)", comment: "Dropdown option for selecting DeepL as the translation service."))
        case .nokyctranslate:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("NoKYCTranslate.com (Prepay with BTC)", comment: "Dropdown option for selecting NoKYCTranslate.com as the translation service."))
         case .winetranslate:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("translate.nostr.wine (DeepL, Pay with BTC)", comment: "Dropdown option for selecting translate.nostr.wine as the translation service."))
        }
    }

    static var isAppleTranslationPopoverSupported: Bool {
        if #available(iOS 17.4, macOS 14.4, *) {
            return true
        } else {
            return false
        }
    }
}
