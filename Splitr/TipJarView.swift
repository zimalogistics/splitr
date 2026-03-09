import SwiftUI
import StoreKit

// MARK: - Product IDs
// These must match exactly what you create in App Store Connect
// App Store Connect → Your App → In-App Purchases → Create New
// Type: Consumable, IDs as below

enum TipProduct: String, CaseIterable {
    case small  = "com.zimalogistics.splitr.tip.small"   // $0.99
    case medium = "com.zimalogistics.splitr.tip.medium"  // $2.99
    case large  = "com.zimalogistics.splitr.tip.large"   // $4.99
}

// MARK: - Store

@MainActor
final class TipStore: ObservableObject {
    @Published var products: [Product] = []
    @Published var isPurchasing = false
    @Published var didPurchase  = false

    init() {
        Task { await loadProducts() }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: TipProduct.allCases.map(\.rawValue))
                .sorted { $0.price < $1.price }
        } catch {
            // tip jar is non-essential — fail silently
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if case .success = result {
                didPurchase = true
            }
        } catch {
            // ignore cancellations / errors
        }
    }
}

// MARK: - Sheet

struct TipJarSheet: View {
    @StateObject private var store = TipStore()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Splitr.bgBase.ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("☕")
                        .font(.system(size: 48))
                    Text("Buy the Dev a Coffee")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Splitr is free and always will be.\nIf it's saved you time, a tip means a lot.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Splitr.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                if store.didPurchase {
                    thankYouView
                } else if store.products.isEmpty {
                    loadingView
                } else {
                    tipButtons
                }

                Button("Maybe later") {
                    dismiss()
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Splitr.textSecondary)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
    }

    private var tipButtons: some View {
        VStack(spacing: 12) {
            ForEach(store.products, id: \.id) { product in
                Button {
                    Task { await store.purchase(product) }
                } label: {
                    HStack {
                        Text(label(for: product))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(product.displayPrice)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Splitr.accent)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Splitr.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Splitr.borderIdle, lineWidth: 1)
                    )
                }
                .disabled(store.isPurchasing)
            }
        }
    }

    private var thankYouView: some View {
        VStack(spacing: 12) {
            Text("🎉")
                .font(.system(size: 44))
            Text("Thank you!")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("You're the reason this app stays free.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Splitr.textSecondary)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Splitr.accent)
                .padding(.top, 4)
        }
    }

    private var loadingView: some View {
        ProgressView()
            .tint(Splitr.accent)
            .padding()
    }

    private func label(for product: Product) -> String {
        switch product.id {
        case TipProduct.small.rawValue:  return "Small coffee ☕"
        case TipProduct.medium.rawValue: return "Large coffee ☕☕"
        case TipProduct.large.rawValue:  return "You're a legend 🏆"
        default: return product.displayName
        }
    }
}
