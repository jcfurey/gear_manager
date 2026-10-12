//
//  String+Extensions.swift
//  ShutterManager
//
//  
//  String utility extensions for enhanced text processing and validation.
//  Provides common string operations for form validation, display formatting,
//  and text processing throughout the application.
//  
//  Key Features:
//  - Whitespace and empty string validation helpers
//  - Optional string processing with nil-safe operations
//  - Text capitalization utilities for proper display formatting
//  - Consistent fallback values for empty/nil strings in UI
//  
//  Architecture:
//  - Extension-based approach for seamless String integration
//  - Computed properties for natural Swift API patterns
//  - Optional<String> extensions for nil-safe string operations
//

import Foundation

/// String utility extensions for enhanced text processing and validation.
extension String {
    
    /// Returns true if the string is empty or contains only whitespace characters.
    /// Useful for form validation and input sanitization.
    var isBlankOrEmpty: Bool {
        return self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Returns the string only if it contains meaningful content, otherwise nil.
    /// Converts empty/whitespace strings to nil for cleaner optional handling.
    var nonEmptyOrNil: String? {
        return isBlankOrEmpty ? nil : self
    }
    
    /// Returns a string with only the first character capitalized.
    /// More conservative than `capitalized` which capitalizes every word.
    var capitalizedFirstLetter: String {
        guard !isEmpty else { return self }
        return prefix(1).uppercased() + dropFirst()
    }
}

/// Optional<String> extensions for nil-safe string operations and display.
extension Optional where Wrapped == String {
    
    /// Returns true if the optional string is nil, empty, or contains only whitespace.
    var isNilOrBlank: Bool {
        return self?.isBlankOrEmpty ?? true
    }
    
    /// Returns a user-friendly display string with consistent fallback for empty values.
    /// Shows "Not specified" for nil/empty strings to improve UI consistency.
    var displayValue: String {
        return isNilOrBlank ? "Not specified" : (self ?? "Not specified")
    }
}
