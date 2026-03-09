import SwiftUI
import WidgetKit

// MARK: - Formatting Utilities

private func formatNum(_ value: Double, decimals: Int = 2) -> String {
    let s = String(format: "%.\(decimals)f", value)
    guard s.contains(".") else { return s }
    var r = s
    while r.hasSuffix("0") { r.removeLast() }
    if r.hasSuffix(".") { r.removeLast() }
    return r
}

/// Seconds → "H:MM:SS"
private func secondsToTimeString(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "" }
    let total = Int(s.rounded())
    return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
}

/// "H:MM:SS" or "M:SS" → seconds
private func timeStringToSeconds(_ str: String) -> Double? {
    let parts = str.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    switch parts.count {
    case 3:
        guard let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    case 2:
        guard let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        return m * 60 + s
    default:
        return Double(str)
    }
}

/// Seconds-per-unit → "M:SS"
private func secondsToPaceString(_ secsPerUnit: Double) -> String {
    guard secsPerUnit.isFinite, secsPerUnit > 0 else { return "" }
    let total = Int(secsPerUnit.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// "M:SS" → seconds, or plain number → minutes * 60
private func paceStringToSeconds(_ str: String) -> Double? {
    let parts = str.split(separator: ":").map(String.init)
    if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
        return m * 60 + s
    }
    return Double(str).map { $0 * 60 }
}

// MARK: - Widget Data Model

struct WidgetField: Codable {
    let label: String   // e.g. "PACE", "SPEED", "DIST", "TIME"
    let value: String   // e.g. "8:30 /mi"
}

struct WidgetPreset: Codable {
    let name: String
    let fields: [WidgetField]
}

private let appGroupID  = "group.com.zimalogistics.splitr"
private let widgetKey   = "splitr.widgetData"

// MARK: - Model

enum ValueGroup { case speed, distance, time }

enum InputField: String, CaseIterable, Hashable, Codable {
    case mph, kph, pacePerMile, pacePerKm, distMiles, distKm, time

    var group: ValueGroup {
        switch self {
        case .mph, .kph, .pacePerMile, .pacePerKm: return .speed
        case .distMiles, .distKm: return .distance
        case .time: return .time
        }
    }

    var label: String {
        switch self {
        case .mph:         return "mph"
        case .kph:         return "km/h"
        case .pacePerMile: return "min / mile"
        case .pacePerKm:   return "min / km"
        case .distMiles:   return "miles"
        case .distKm:      return "km"
        case .time:        return "HH:MM:SS"
        }
    }

    // Compact label for saved entry display
    var shortLabel: String {
        switch self {
        case .mph:         return "mph"
        case .kph:         return "km/h"
        case .pacePerMile: return "/mi"
        case .pacePerKm:   return "/km"
        case .distMiles:   return "mi"
        case .distKm:      return "km"
        case .time:        return ""
        }
    }

    var placeholder: String {
        switch self {
        case .time:                    return "0:00:00"
        case .pacePerMile, .pacePerKm: return "0:00"
        default:                       return "0"
        }
    }

    var keyboardType: UIKeyboardType {
        switch self {
        case .time, .pacePerMile, .pacePerKm: return .numbersAndPunctuation
        default: return .decimalPad
        }
    }
}

// MARK: - Saved Entry

struct SavedEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    var name: String
    let texts: [InputField: String]
    let userEnteredFields: [InputField]

    init(id: UUID, date: Date, name: String, texts: [InputField: String], userEnteredFields: [InputField]) {
        self.id = id; self.date = date; self.name = name
        self.texts = texts; self.userEnteredFields = userEnteredFields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id   = try c.decode(UUID.self,              forKey: .id)
        date = try c.decode(Date.self,              forKey: .date)
        name = (try? c.decode(String.self,          forKey: .name)) ?? ""
        texts             = try c.decode([InputField: String].self, forKey: .texts)
        userEnteredFields = try c.decode([InputField].self,         forKey: .userEnteredFields)
    }

    // Line 1: the fields the user typed in
    var line1: String {
        userEnteredFields
            .compactMap { f -> String? in
                guard let t = texts[f], !t.isEmpty else { return nil }
                let suffix = f.shortLabel.isEmpty ? "" : " \(f.shortLabel)"
                return "\(t)\(suffix)"
            }
            .joined(separator: "  ·  ")
    }

    // Line 2: the derived fields
    var line2: String {
        InputField.allCases
            .filter { !userEnteredFields.contains($0) }
            .compactMap { f -> String? in
                guard let t = texts[f], !t.isEmpty else { return nil }
                let suffix = f.shortLabel.isEmpty ? "" : " \(f.shortLabel)"
                return "\(t)\(suffix)"
            }
            .joined(separator: "  ·  ")
    }
}

// MARK: - ViewModel

@MainActor
final class ConverterViewModel: ObservableObject {
    @Published private(set) var fieldTexts: [InputField: String] =
        Dictionary(uniqueKeysWithValues: InputField.allCases.map { ($0, "") })

    @Published private(set) var userEnteredFields: Set<InputField> = []
    @Published private(set) var savedEntries: [SavedEntry] = []
    @Published private(set) var activeShortcutKm: String? = nil

    // Base values (SI: m/s, metres, seconds)
    private var speedMps: Double? = nil
    private var distanceM: Double? = nil
    private var timeSec: Double? = nil
    private var anchoredGroups: Set<ValueGroup> = []

    private var isUpdating = false
    private let savedKey       = "splitr.savedEntries"
    private let kvStore        = NSUbiquitousKeyValueStore.default
    private let sharedDefaults = UserDefaults(suiteName: appGroupID)
    private var iCloudObserver: NSObjectProtocol?

    init() {
        loadSaved()
        setupiCloudSync()
    }

    deinit {
        if let obs = iCloudObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: Custom Binding

    func binding(for field: InputField) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.fieldTexts[field] ?? "" },
            set: { [weak self] newValue in
                guard let self, !self.isUpdating else { return }
                self.handleEdit(field: field, text: newValue)
            }
        )
    }

    // MARK: Actions

    func clearAll() {
        speedMps = nil; distanceM = nil; timeSec = nil
        anchoredGroups = []; userEnteredFields = []; activeShortcutKm = nil
        isUpdating = true
        for f in InputField.allCases { fieldTexts[f] = "" }
        isUpdating = false
    }

    func save(name: String = "") {
        guard !userEnteredFields.isEmpty else { return }
        let texts = fieldTexts.filter { !(($1).isEmpty) }
        let entry = SavedEntry(
            id: UUID(),
            date: Date(),
            name: name.trimmingCharacters(in: .whitespaces),
            texts: texts,
            userEnteredFields: Array(userEnteredFields)
        )
        savedEntries.insert(entry, at: 0)
        persistSaved()
    }

    func restore(_ entry: SavedEntry) {
        clearAll()
        for field in entry.userEnteredFields {
            if let text = entry.texts[field], !text.isEmpty {
                handleEdit(field: field, text: text)
            }
        }
    }

    func delete(_ entry: SavedEntry) {
        savedEntries.removeAll { $0.id == entry.id }
        persistSaved()
    }

    func rename(_ entry: SavedEntry, to name: String) {
        guard let idx = savedEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        savedEntries[idx].name = name
        persistSaved()
    }

    func moveEntry(from sourceIdx: Int, to targetIdx: Int) {
        savedEntries.move(fromOffsets: IndexSet(integer: sourceIdx),
                          toOffset: targetIdx > sourceIdx ? targetIdx + 1 : targetIdx)
        persistSaved()
    }

    func clearField(_ field: InputField) {
        handleEdit(field: field, text: "")
    }

    func reformatTimeIfNeeded() {
        guard userEnteredFields.contains(.time), let secs = timeSec else { return }
        fieldTexts[.time] = secondsToTimeString(secs)
    }

    func setDistanceKm(_ text: String, shortcutKm: String? = nil) {
        handleEdit(field: .distKm, text: text)
        activeShortcutKm = shortcutKm  // set after handleEdit (which clears it)
    }

    var shareText: String {
        ConverterViewModel.buildShareText(lookup: { fieldTexts[$0] })
    }

    static func shareText(for entry: SavedEntry) -> String {
        buildShareText(lookup: { entry.texts[$0] })
    }

    private static func buildShareText(lookup: (InputField) -> String?) -> String {
        var lines = ["Splitr", ""]
        let sections: [(String, [InputField])] = [
            ("Speed",    [.mph, .kph]),
            ("Pace",     [.pacePerMile, .pacePerKm]),
            ("Distance", [.distMiles, .distKm]),
            ("Time",     [.time])
        ]
        for (title, fields) in sections {
            let parts = fields.compactMap { f -> String? in
                guard let t = lookup(f), !t.isEmpty else { return nil }
                return "\(t) \(f.label)"
            }
            guard !parts.isEmpty else { continue }
            lines.append(title + ":")
            lines.append(contentsOf: parts)
            lines.append("")
        }
        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    // MARK: Persistence

    private func loadSaved() {
        let data = kvStore.data(forKey: savedKey)
                ?? sharedDefaults?.data(forKey: savedKey)
                ?? UserDefaults.standard.data(forKey: savedKey)
        guard let data,
              let entries = try? JSONDecoder().decode([SavedEntry].self, from: data)
        else { return }
        savedEntries = entries
    }

    private func persistSaved() {
        guard let data = try? JSONEncoder().encode(savedEntries) else { return }
        UserDefaults.standard.set(data, forKey: savedKey)
        sharedDefaults?.set(data, forKey: savedKey)
        kvStore.set(data, forKey: savedKey)
        kvStore.synchronize()
        updateWidgetData()
    }

    private func updateWidgetData() {
        let swapSpeed    = UserDefaults.standard.bool(forKey: "splitr.swap.speed")
        let swapPace     = UserDefaults.standard.bool(forKey: "splitr.swap.pace")
        let swapDistance = UserDefaults.standard.bool(forKey: "splitr.swap.distance")

        // One field per category, left-side preferred
        let widgetSlots: [(InputField, String)] = [
            (swapSpeed    ? .kph       : .mph,          "SPEED"),
            (swapPace     ? .pacePerKm : .pacePerMile,  "PACE"),
            (swapDistance ? .distKm    : .distMiles,     "DIST"),
            (.time,                                      "TIME"),
        ]

        let presets = savedEntries.prefix(5).map { entry -> WidgetPreset in
            let fields = widgetSlots.compactMap { (field, label) -> WidgetField? in
                guard let value = entry.texts[field], !value.isEmpty else { return nil }
                let suffix = field.shortLabel.isEmpty ? "" : " \(field.shortLabel)"
                return WidgetField(label: label, value: "\(value)\(suffix)")
            }
            return WidgetPreset(name: entry.name, fields: fields)
        }
        if let data = try? JSONEncoder().encode(Array(presets)) {
            sharedDefaults?.set(data, forKey: widgetKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func setupiCloudSync() {
        kvStore.synchronize()
        iCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let data = self.kvStore.data(forKey: self.savedKey),
                      let entries = try? JSONDecoder().decode([SavedEntry].self, from: data)
                else { return }
                self.savedEntries = entries
                UserDefaults.standard.set(data, forKey: self.savedKey)
                self.sharedDefaults?.set(data, forKey: self.savedKey)
                self.updateWidgetData()
            }
        }
    }

    // MARK: Private

    private func handleEdit(field: InputField, text: String) {
        if field == .distKm || field == .distMiles { activeShortcutKm = nil }
        fieldTexts[field] = text

        if text.isEmpty {
            // Only remove anchor if no other field in the group is user-entered
            let others = userEnteredFields.filter { $0.group == field.group && $0 != field }
            if others.isEmpty {
                anchoredGroups.remove(field.group)
                setBase(field.group, value: nil)
            }
            userEnteredFields.remove(field)
        } else if let base = parseToBase(field: field, text: text) {
            setBase(field.group, value: base)
            anchoredGroups.insert(field.group)
            // Within a group, only the most-recently-edited field is "user entered"
            InputField.allCases.filter { $0.group == field.group }.forEach { userEnteredFields.remove($0) }
            userEnteredFields.insert(field)
        }

        recalculate(skip: field)
    }

    private func setBase(_ group: ValueGroup, value: Double?) {
        switch group {
        case .speed:    speedMps = value
        case .distance: distanceM = value
        case .time:     timeSec = value
        }
    }

    private func parseToBase(field: InputField, text: String) -> Double? {
        switch field {
        case .mph:
            return Double(text).map { $0 * 0.44704 }
        case .kph:
            return Double(text).map { $0 / 3.6 }
        case .pacePerMile:
            guard let secs = paceStringToSeconds(text), secs > 0 else { return nil }
            return 1609.344 / secs
        case .pacePerKm:
            guard let secs = paceStringToSeconds(text), secs > 0 else { return nil }
            return 1000.0 / secs
        case .distMiles:
            return Double(text).map { $0 * 1609.344 }
        case .distKm:
            return Double(text).map { $0 * 1000 }
        case .time:
            return timeStringToSeconds(text)
        }
    }

    private func recalculate(skip: InputField) {
        // Start with anchored (user-provided) values
        var speed = anchoredGroups.contains(.speed)    ? speedMps    : nil
        var dist  = anchoredGroups.contains(.distance) ? distanceM   : nil
        var time  = anchoredGroups.contains(.time)     ? timeSec     : nil

        // Derive each missing group from the other two
        if time  == nil, let s = speed, let d = dist, s > 0 { time  = d / s }
        if dist  == nil, let s = speed, let t = time         { dist  = s * t }
        if speed == nil, let d = dist,  let t = time, t > 0  { speed = d / t }

        // Persist derived values for potential chained lookups
        if !anchoredGroups.contains(.speed)    { speedMps = speed }
        if !anchoredGroups.contains(.distance) { distanceM = dist }
        if !anchoredGroups.contains(.time)     { timeSec = time }

        if anchoredGroups.count >= 2 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        isUpdating = true
        defer { isUpdating = false }

        updateSpeedFields(mps: speed, skip: skip)
        updateDistanceFields(meters: dist, skip: skip)
        updateTimeField(seconds: time, skip: skip)
    }

    private func updateSpeedFields(mps: Double?, skip: InputField) {
        if let s = mps {
            let mph = s * 2.23694
            let kph = s * 3.6
            if skip != .mph         { fieldTexts[.mph]         = formatNum(mph) }
            if skip != .kph         { fieldTexts[.kph]         = formatNum(kph) }
            if skip != .pacePerMile { fieldTexts[.pacePerMile] = s > 0 ? secondsToPaceString(1609.344 / s) : "" }
            if skip != .pacePerKm   { fieldTexts[.pacePerKm]   = s > 0 ? secondsToPaceString(1000.0  / s) : "" }
        } else {
            for f in [InputField.mph, .kph, .pacePerMile, .pacePerKm] where f != skip && !userEnteredFields.contains(f) {
                fieldTexts[f] = ""
            }
        }
    }

    private func updateDistanceFields(meters: Double?, skip: InputField) {
        if let d = meters {
            if skip != .distMiles  { fieldTexts[.distMiles]  = formatNum(d / 1609.344, decimals: 3) }
            if skip != .distKm { fieldTexts[.distKm] = formatNum(d / 1000, decimals: 3) }
        } else {
            for f in [InputField.distMiles, .distKm] where f != skip && !userEnteredFields.contains(f) {
                fieldTexts[f] = ""
            }
        }
    }

    private func updateTimeField(seconds: Double?, skip: InputField) {
        if let t = seconds {
            if skip != .time { fieldTexts[.time] = secondsToTimeString(t) }
        } else if skip != .time && !userEnteredFields.contains(.time) {
            fieldTexts[.time] = ""
        }
    }
}

// MARK: - Design Tokens

enum Splitr {
    // Backgrounds
    static let bgBase    = Color(red: 0.05, green: 0.07, blue: 0.13)
    static let bgCard    = Color(red: 0.10, green: 0.13, blue: 0.21)
    static let bgActive  = Color(red: 0.08, green: 0.18, blue: 0.32)
    static let bgCalc    = Color(red: 0.09, green: 0.14, blue: 0.23)

    // Accent — electric blue
    static let accent       = Color(red: 0.25, green: 0.65, blue: 1.00)
    static let accentSubtle = Color(red: 0.25, green: 0.65, blue: 1.00).opacity(0.18)
    static let accentDim    = Color(red: 0.25, green: 0.65, blue: 1.00).opacity(0.35)

    // Text
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.55)
    static let textDim       = Color(white: 0.28)

    // Borders
    static let borderActive  = Color(red: 0.25, green: 0.65, blue: 1.00).opacity(0.55)
    static let borderCalc    = Color(red: 0.25, green: 0.65, blue: 1.00).opacity(0.20)
    static let borderIdle    = Color(white: 0.18)
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm = ConverterViewModel()
    @FocusState private var focusedField: InputField?
    @State private var showSaveAlert = false
    @State private var saveName = ""
    @AppStorage("splitr.hasSeenHint")    private var hasSeenHint    = false
    @AppStorage("splitr.swap.speed")    private var swapSpeed      = false
    @AppStorage("splitr.swap.pace")     private var swapPace       = false
    @AppStorage("splitr.swap.distance") private var swapDistance   = false
    @State private var showHint = false
    @State private var savedReorderMode = false
    @State private var showTipJar = false

    var body: some View {
        NavigationStack {
            ZStack {
                Splitr.bgBase.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        ConverterSection(title: "Speed") {
                            SwappablePair(.mph, .kph, vm: vm, focus: $focusedField, isSwapped: $swapSpeed, isReorderMode: $savedReorderMode)
                        }

                        ConverterSection(title: "Pace") {
                            SwappablePair(.pacePerMile, .pacePerKm, vm: vm, focus: $focusedField, isSwapped: $swapPace, isReorderMode: $savedReorderMode)
                        }

                        ConverterSection(title: "Distance") {
                            SwappablePair(.distMiles, .distKm, vm: vm, focus: $focusedField, isSwapped: $swapDistance, isReorderMode: $savedReorderMode)
                            DistanceShortcutsRow(vm: vm, focus: $focusedField)
                        }

                        ConverterSection(title: "Time") {
                            FieldCard(.time, vm: vm, focus: $focusedField)
                        }

                        HStack(spacing: 12) {
                            if !vm.userEnteredFields.isEmpty {
                                Button {
                                    vm.reformatTimeIfNeeded()
                                    saveName = ""
                                    showSaveAlert = true
                                } label: {
                                    Label("Save", systemImage: "bookmark.fill")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Splitr.accent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Splitr.accentSubtle)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Splitr.accentDim, lineWidth: 1)
                                        )
                                }
                            }
                            Button {
                                vm.clearAll()
                                focusedField = nil
                            } label: {
                                Label("Clear All", systemImage: "xmark.circle.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Splitr.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Splitr.bgCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Splitr.borderIdle, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.top, 4)

                        if !vm.savedEntries.isEmpty {
                            SavedSection(vm: vm, isReorderMode: $savedReorderMode)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if savedReorderMode { savedReorderMode = false }
                    }
                }
            }
            .navigationTitle("Splitr")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Splitr.bgBase, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if savedReorderMode {
                        Button("Done") {
                            savedReorderMode = false
                        }
                        .foregroundStyle(Splitr.accent)
                        .fontWeight(.semibold)
                    }
                    if !vm.userEnteredFields.isEmpty && !savedReorderMode {
                        ShareLink(item: vm.shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Splitr.accent)
                                .offset(y: -1)
                        }
                    }
                    if !savedReorderMode {
                        Button {
                            showTipJar = true
                        } label: {
                            Text("☕")
                                .font(.system(size: 18))
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .foregroundStyle(Splitr.accent)
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: focusedField) { old, _ in
            if old == .time { vm.reformatTimeIfNeeded() }
        }
        .onAppear {
            if !hasSeenHint { showHint = true }
        }
        .sheet(isPresented: $showTipJar) {
            TipJarSheet()
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHint) {
            HintSheet {
                hasSeenHint = true
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSaveAlert, onDismiss: { focusedField = nil }) {
            NamePresetSheet(saveName: $saveName) { name in
                vm.save(name: name)
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Name Preset Sheet

struct NamePresetSheet: View {
    var title: String = "Name this preset"
    @Binding var saveName: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    let onSave: (String) -> Void

    var body: some View {
        ZStack {
            Splitr.bgBase.ignoresSafeArea()
            VStack(spacing: 20) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Splitr.textPrimary)

                TextField("e.g. Marathon pace", text: $saveName)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Splitr.textPrimary)
                    .tint(Splitr.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Splitr.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Splitr.borderActive, lineWidth: 1))
                    .focused($focused)

                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Splitr.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Splitr.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Splitr.borderIdle, lineWidth: 1))
                    }

                    Button {
                        onSave(saveName.trimmingCharacters(in: .whitespaces))
                        saveName = ""
                        dismiss()
                    } label: {
                        Text(saveName.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Save")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Splitr.bgBase)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Splitr.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(24)
        }
        .onAppear { focused = true }
    }
}

// MARK: - Section

struct ConverterSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Splitr.textSecondary)
                .padding(.horizontal, 4)
            content
        }
    }
}

// MARK: - Swappable Pair

struct SwappablePair: View {
    let field1: InputField
    let field2: InputField
    @ObservedObject var vm: ConverterViewModel
    var focus: FocusState<InputField?>.Binding
    @Binding var isSwapped: Bool
    @Binding var isReorderMode: Bool

    init(_ field1: InputField, _ field2: InputField,
         vm: ConverterViewModel,
         focus: FocusState<InputField?>.Binding,
         isSwapped: Binding<Bool>,
         isReorderMode: Binding<Bool>) {
        self.field1 = field1; self.field2 = field2
        self.vm = vm; self.focus = focus
        self._isSwapped = isSwapped; self._isReorderMode = isReorderMode
    }

    private var left:  InputField { isSwapped ? field2 : field1 }
    private var right: InputField { isSwapped ? field1 : field2 }

    var body: some View {
        VStack(spacing: 6) {
            if isReorderMode {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isSwapped.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("swap")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Splitr.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Splitr.accentSubtle)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Splitr.accentDim, lineWidth: 1))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            HStack(spacing: 12) {
                FieldCard(left,  vm: vm, focus: focus)
                    .allowsHitTesting(!isReorderMode)
                FieldCard(right, vm: vm, focus: focus)
                    .allowsHitTesting(!isReorderMode)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isReorderMode)
    }
}

// MARK: - Field Card

struct FieldCard: View {
    let field: InputField
    @ObservedObject var vm: ConverterViewModel
    var focus: FocusState<InputField?>.Binding

    init(_ field: InputField, vm: ConverterViewModel, focus: FocusState<InputField?>.Binding) {
        self.field = field
        self.vm = vm
        self.focus = focus
    }

    private var isUserEntered: Bool { vm.userEnteredFields.contains(field) }
    private var hasValue: Bool      { !(vm.fieldTexts[field] ?? "").isEmpty }
    private var isCalculated: Bool  { hasValue && !isUserEntered }

    private var cardBackground: Color {
        isUserEntered ? Splitr.bgActive :
        isCalculated  ? Splitr.bgCalc   :
                        Splitr.bgCard
    }

    private var borderColor: Color {
        isUserEntered ? Splitr.borderActive :
        isCalculated  ? Splitr.borderCalc   :
                        Splitr.borderIdle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label row
            HStack(spacing: 6) {
                Text(field.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(isUserEntered ? Splitr.accent : Splitr.textSecondary)
                Spacer()
                if isUserEntered {
                    Button {
                        vm.clearField(field)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Splitr.textDim)
                    }
                    .buttonStyle(.plain)
                } else if isCalculated {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Splitr.accent.opacity(0.7))
                }
            }

            // Value
            TextField(field.placeholder, text: vm.binding(for: field))
                .font(.system(.title2, design: .rounded, weight: isUserEntered ? .bold : .regular))
                .monospacedDigit()
                .keyboardType(field.keyboardType)
                .focused(focus, equals: field)
                .foregroundStyle(
                    isUserEntered ? Splitr.textPrimary   :
                    isCalculated  ? Splitr.accent        :
                                    Splitr.textDim
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: 1)
        )
        // Glow on active card
        .shadow(
            color: isUserEntered ? Splitr.accent.opacity(0.12) : .clear,
            radius: 12, x: 0, y: 4
        )
        .animation(.easeInOut(duration: 0.2), value: isUserEntered)
        .animation(.easeInOut(duration: 0.2), value: isCalculated)
    }
}

// MARK: - Distance Shortcuts

private struct DistanceShortcut {
    let label: String
    let kmText: String
}

private let distanceShortcuts: [DistanceShortcut] = [
    .init(label: "800m",     kmText: "0.8"),
    .init(label: "1500m",    kmText: "1.5"),
    .init(label: "3K",       kmText: "3"),
    .init(label: "5K",       kmText: "5"),
    .init(label: "10K",      kmText: "10"),
    .init(label: "Half",     kmText: "21.1"),
    .init(label: "Marathon", kmText: "42.195"),
]

struct DistanceShortcutsRow: View {
    @ObservedObject var vm: ConverterViewModel
    var focus: FocusState<InputField?>.Binding

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(distanceShortcuts, id: \.label) { shortcut in
                    let isActive = vm.activeShortcutKm == shortcut.kmText
                    Button {
                        focus.wrappedValue = nil
                        vm.setDistanceKm(shortcut.kmText, shortcutKm: shortcut.kmText)
                    } label: {
                        Text(shortcut.label)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(isActive ? Splitr.bgBase : Splitr.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isActive ? Splitr.accent : Splitr.bgCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isActive ? Splitr.accent : Splitr.borderIdle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
                }
            }
        }
    }
}

// MARK: - Saved Section

struct SavedSection: View {
    @ObservedObject var vm: ConverterViewModel
    @Binding var isReorderMode: Bool
    @State private var entryToRename: SavedEntry?
    @State private var renameName = ""

    var body: some View {
        ConverterSection(title: "Saved") {
            VStack(spacing: 8) {
                ForEach(Array(vm.savedEntries.enumerated()), id: \.element.id) { idx, entry in
                    HStack(spacing: 8) {
                        if isReorderMode {
                            VStack(spacing: 10) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        vm.moveEntry(from: idx, to: idx - 1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(idx == 0 ? Splitr.textDim : Splitr.accent)
                                }
                                .disabled(idx == 0)

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        vm.moveEntry(from: idx, to: idx + 1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(idx == vm.savedEntries.count - 1 ? Splitr.textDim : Splitr.accent)
                                }
                                .disabled(idx == vm.savedEntries.count - 1)
                            }
                            .frame(width: 24)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        }

                        SavedEntryRow(entry: entry, vm: vm,
                            onRename: {
                                renameName = entry.name
                                entryToRename = entry
                            },
                            onStartReorder: {
                                isReorderMode = true
                            }
                        )
                    }
                    .animation(.easeInOut(duration: 0.2), value: isReorderMode)
                }
            }
        }
        .sheet(item: $entryToRename) { entry in
            NamePresetSheet(title: "Rename preset", saveName: $renameName) { name in
                vm.rename(entry, to: name)
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }
}

struct SavedEntryRow: View {
    let entry: SavedEntry
    @ObservedObject var vm: ConverterViewModel
    var onRename: () -> Void
    var onStartReorder: () -> Void

    var body: some View {
        Button { vm.restore(entry) } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    // Name (if set)
                    if !entry.name.isEmpty {
                        Text(entry.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Splitr.textPrimary)
                            .lineLimit(1)
                    }
                    // Line 1 — user inputs
                    if !entry.line1.isEmpty {
                        Text(entry.line1)
                            .font(.system(size: entry.name.isEmpty ? 13 : 11, weight: entry.name.isEmpty ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(entry.name.isEmpty ? Splitr.accent : Splitr.accent.opacity(0.8))
                            .lineLimit(1)
                    }
                    // Line 2 — derived values
                    if !entry.line2.isEmpty {
                        Text(entry.line2)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Splitr.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                // Share button
                ShareLink(item: ConverterViewModel.shareText(for: entry)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Splitr.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Splitr.bgBase)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                // Delete button
                Button {
                    vm.delete(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Splitr.textDim)
                        .frame(width: 28, height: 28)
                        .background(Splitr.bgBase)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Splitr.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Splitr.borderIdle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onRename() } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button { onStartReorder() } label: {
                Label("Move", systemImage: "arrow.up.and.down")
            }
            Button(role: .destructive) { vm.delete(entry) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Hint Sheet

struct HintSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onDismiss: () -> Void

    private struct HintRow: View {
        let icon: String
        let text: String
        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Splitr.accent)
                    .frame(width: 28)
                Text(text)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Splitr.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        ZStack {
            Splitr.bgBase.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("How it works")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Splitr.textPrimary)

                VStack(alignment: .leading, spacing: 16) {
                    HintRow(icon: "pencil.and.outline",
                            text: "Enter any two values — speed, pace, distance, or time.")
                    HintRow(icon: "bolt.fill",
                            text: "Splitr instantly calculates everything else.")
                    HintRow(icon: "bookmark.fill",
                            text: "Save your favourite combinations and load them later.")
                }

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Got it")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Splitr.bgBase)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Splitr.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(28)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
