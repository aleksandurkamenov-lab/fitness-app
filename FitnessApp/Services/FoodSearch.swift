import Foundation

/// Храна от публичната база Open Food Facts (стойности на 100 г).
struct OnlineFood: Identifiable {
    let id = UUID()
    let name: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

enum FoodSearch {
    /// Търсене по име в Open Food Facts (нужен е интернет).
    static func search(_ query: String) async throws -> [OnlineFood] {
        guard var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: "product_name,brands,nutriments"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("FitnessApp/1.0 (personal use)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw FoodSearchError.invalidResponse
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = root["products"] as? [[String: Any]] else { return [] }
        return products.compactMap { product in
            let name = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty, let nutriments = product["nutriments"] as? [String: Any] else { return nil }
            func value(_ key: String) -> Double? {
                if let number = nutriments[key] as? Double { return number }
                if let text = nutriments[key] as? String { return Double(text) }
                return nil
            }
            guard let kcal = value("energy-kcal_100g") else { return nil }
            let brand = (product["brands"] as? String)?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return OnlineFood(name: brand.isEmpty ? name : "\(name) (\(brand))",
                              kcal: kcal,
                              protein: value("proteins_100g") ?? 0,
                              carbs: value("carbohydrates_100g") ?? 0,
                              fat: value("fat_100g") ?? 0)
        }
    }
}

private enum FoodSearchError: LocalizedError {
    case invalidResponse

    var errorDescription: String? { "Open Food Facts върна неуспешен отговор." }
}
