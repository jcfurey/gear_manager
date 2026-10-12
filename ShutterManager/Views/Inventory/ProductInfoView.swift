//
//  ProductInfoView.swift
//  ShutterManager
//

import SwiftUI

//
//  ProductInfoView.swift
//  ShutterManager
//
//  Sheet that shows a UPC lookup result (image, name, brand, description,
//  category, barcode) with actions to add it, enter manually, or rescan.
//

/// Displays a `ProductInfo` lookup result and lets the user act on it via the
/// `onUseProduct` / `onManualEntry` / `onScanAgain` callbacks.
struct ProductInfoView: View {
    /// Product information from the UPC lookup service.
    let productInfo: ProductInfo

    /// Called when the user adds this product to inventory.
    let onUseProduct: (ProductInfo) -> Void

    /// Called when the user opts for manual entry instead of the lookup data.
    let onManualEntry: () -> Void

    /// Called when the user wants to scan another barcode.
    let onScanAgain: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Success indicator
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                            .accessibilityHidden(true)
                        
                        Text("Product Found!")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Found in \(productInfo.source.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    // Product card
                    VStack(alignment: .leading, spacing: 16) {
                        // Product image
                        if let imageURL = productInfo.imageURL,
                           let url = URL(string: imageURL) {
                            // Phase-based: the `content:placeholder:` form keeps showing the
                            // placeholder when the load FAILS, so a dead link — or any plain-http
                            // retailer image URL, which App Transport Security blocks — spun the
                            // progress indicator forever. A failed image is simply omitted.
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 200)
                                        .cornerRadius(12)
                                        .accessibilityLabel("Photo of \(productInfo.name)")
                                } else if phase.error == nil {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.gray.opacity(0.2))
                                        .frame(height: 200)
                                        .overlay {
                                            ProgressView()
                                        }
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            // Product name
                            Text(productInfo.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Brand
                            if let brand = productInfo.displayBrand {
                                Label(brand, systemImage: "tag.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Description
                            if let description = productInfo.displayDescription {
                                Text(description)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            // Category
                            if let category = productInfo.category {
                                Label(category, systemImage: "folder.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Barcode
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Barcode")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Text(productInfo.barcode)
                                    .font(.monospaced(.body)())
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .background(.gray.opacity(0.05))
                    .cornerRadius(16)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Product Found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Action buttons
                VStack(spacing: 12) {
                    // Primary action - use this product
                    Button(action: {
                        onUseProduct(productInfo)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .accessibilityHidden(true)
                            Text("Add to Inventory")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.blue)
                        .cornerRadius(25)
                    }
                    
                    // Secondary actions
                    HStack(spacing: 16) {
                        Button("Enter Manually") {
                            onManualEntry()
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(20)
                        
                        Button("Scan Again") {
                            onScanAgain()
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.gray.opacity(0.1))
                        .cornerRadius(20)
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
        }
    }
}

#Preview {
    ProductInfoView(
        productInfo: ProductInfo(
            name: "Z6 III Mirrorless Camera",
            brand: "Nikon",
            description: "24.5MP full-frame mirrorless camera body",
            imageURL: nil,
            category: "Cameras & Optics",
            barcode: "1234567890123",
            source: .upcItemDB
        ),
        onUseProduct: { _ in },
        onManualEntry: { },
        onScanAgain: { }
    )
}
