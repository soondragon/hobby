import Foundation

/// Keeps schema v1 compatible with the deployed server while the domain adopts general forms.
/// Legacy field names are wire aliases; their values describe the individual's species form.
enum CloudSaveWire {
    static func encode(_ command: CloudSaveCommand) throws -> Data {
        guard var body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any],
              var state = body["state"] as? [String: Any] else { throw CloudError.invalidResponse }
        rename(&state, from: "pendingForm", to: "pendingUnownForm", speciesID: state["pendingHatchID"] as? Int)
        rename(&state, from: "representativeForm", to: "representativeUnownForm", speciesID: state["representativeSpeciesID"] as? Int)
        if var active = state["active"] as? [String: Any] {
            rename(&active, from: "form", to: "unownForm", speciesID: active["baseID"] as? Int)
            state["active"] = active
        }
        if let entries = state["dex"] as? [[String: Any]] {
            state["dex"] = entries.map { entry in
                var entry = entry
                rename(&entry, from: "form", to: "unownForm", speciesID: entry["baseID"] as? Int)
                return entry
            }
        }
        body["state"] = state
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private static func rename(_ object: inout [String: Any], from: String, to: String, speciesID: Int?) {
        guard let value = object.removeValue(forKey: from) as? String else { return }
        // Default non-Unown forms were absent in older saves. Keep that identity stable.
        if let speciesID, speciesID != PokemonForm.unownSpeciesID,
           (PokemonForm.forms(speciesID: speciesID).first ?? PokemonForm.lineForms(baseID: speciesID).first)?.rawValue == value { return }
        object[to] = value
    }
}
