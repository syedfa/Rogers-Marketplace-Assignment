import SwiftUI

struct PriceText: View {
    let price: Decimal
    var font: Font = .headline

    var body: some View {
        Text(price, format: .currency(code: "USD").precision(.fractionLength(0...2)))
            .font(font)
            .fontWeight(.bold)
    }
}
