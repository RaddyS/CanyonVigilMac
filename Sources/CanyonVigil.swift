import AppKit
import SwiftUI
import ApplicationServices

struct Slot: Codable, Equatable { var dpi: Int; var color: Int }
struct Profile: Codable, Equatable {
    var vendor: Int; var product: Int; var activeSlot: Int; var speed: Int
    var mode: Int; var action: Int; var rate: Int; var slots: [Slot]; var raw: [Int]
    static let initial = Profile(vendor: 2362, product: 9523, activeSlot: 1, speed: 128,
        mode: 4, action: 232, rate: 500,
        slots: [Slot(dpi: 800, color: 0), Slot(dpi: 1200, color: 8), Slot(dpi: 2400, color: 4), Slot(dpi: 3200, color: 10)], raw: [])
    var valid: Bool {
        vendor == 2362 && product == 9523 && slots.count == 4 && (1...4).contains(activeSlot)
        && (0...255).contains(speed) && [0,2,4,6,8,10,14].contains(mode)
        && [125,250,500,1000].contains(rate) && actions.contains(where: { $0.1 == action })
        && slots.allSatisfy { (200...3200).contains($0.dpi) && $0.dpi % 200 == 0 && (0...15).contains($0.color) }
    }
    var arguments: [String] {
        var result = ["apply"]
        for slot in slots { result.append(String(slot.dpi)); result.append(String(slot.color)) }
        for value in [activeSlot, mode, speed, rate, action] { result.append(String(value)) }
        result.append("verified")
        return result
    }
}
let modes: [(String, Int)] = [("Always on",0),("Breathing",2),("Breathing + segments",4),
    ("6-color cycle",6),("12-color cycle",8),("768-color cycle",10),("Off",14)]
let actions: [(String, Int)] = [("Cycle DPI",232),("Sniper",230),("Switch lighting",231),
    ("Back",224),("Forward",225),("Double click",229),("Play / pause",236),("Mute",237),
    ("Next track",238),("Previous track",239),("Stop playback",240),("Volume up",242),("Volume down",243)]

final class MouseModel: ObservableObject {
    @Published var profile = Profile.initial
    @Published var loaded = false
    @Published var busy = false
    @Published var status = "Connect your mouse and click Read mouse."
    @Published var failed = false
    private let queue = DispatchQueue(label: "vigil.usb")
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CanyonVigilMac", isDirectory: true)

    static func run(_ args: [String]) throws -> Profile {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "vigilctl") else {
            throw NSError(domain: "Vigil", code: 1, userInfo: [NSLocalizedDescriptionKey: "USB helper is missing from the app. Rebuild with build.sh."])
        }
        let task = Process(), output = Pipe(), errors = Pipe()
        task.executableURL = url; task.arguments = args
        task.standardOutput = output; task.standardError = errors
        try task.run()
        // Helper output is bounded to one small JSON object or one error message.
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        let errorBytes = errors.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "Vigil", code: Int(task.terminationStatus), userInfo:
                [NSLocalizedDescriptionKey: String(data: errorBytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "USB operation failed."])
        }
        let p = try JSONDecoder().decode(Profile.self, from: bytes)
        guard p.valid else { throw NSError(domain: "Vigil", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mouse returned settings this version cannot edit. No profile changes were applied."]) }
        return p
    }
    func perform(_ message: String, operation: @escaping () throws -> Profile) {
        guard !busy else { return }
        busy = true; failed = false; status = message
        queue.async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let p):
                    self.profile = p; self.loaded = true; self.failed = false
                    self.status = message.hasPrefix("Applying") ? "Applied and verified by reading the mouse back." : "Mouse connected · current settings loaded."
                case .failure(let error):
                    self.loaded = false; self.failed = true; self.status = error.localizedDescription
                }
            }
        }
    }
    func read() { perform("Reading mouse…") { try Self.run(["read"]) } }
    func apply() {
        guard loaded, profile.valid else { return }
        let wanted = profile, backupFolder = folder
        perform("Applying settings…") {
            let before = try Self.run(["read"])
            try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(before)
            try data.write(to: backupFolder.appendingPathComponent("before-last-apply.json"), options: .atomic)
            let original = backupFolder.appendingPathComponent("first-connected-profile.json")
            if !FileManager.default.fileExists(atPath: original.path) { try data.write(to: original, options: .atomic) }
            return try Self.run(wanted.arguments)
        }
    }
    func restore() {
        do {
            let p = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: folder.appendingPathComponent("before-last-apply.json")))
            guard p.valid else { throw CocoaError(.fileReadCorruptFile) }
            profile = p; status = "Previous profile loaded. Click Apply to restore it to the mouse."
        } catch { failed = true; status = "No previous profile backup is available yet." }
    }
    func exportProfile() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Canyon-profile.json"
        if panel.runModal() == .OK, let url = panel.url {
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(profile).write(to: url, options: .atomic) }
            catch { failed = true; status = error.localizedDescription }
        }
    }
    func importProfile() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let p = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url))
                guard p.valid else { throw CocoaError(.fileReadCorruptFile) }
                profile = p; failed = false; status = "Profile loaded. Click Apply to send it to the mouse."
            } catch { failed = true; status = "Cannot import this profile: \(error.localizedDescription)" }
        }
    }
}

enum Mapping: String, CaseIterable, Identifiable {
    case unchanged = "Unchanged", back = "Browser back", forward = "Browser forward"
    case copy = "Copy (⌘C)", paste = "Paste (⌘V)", undo = "Undo (⌘Z)"
    case mission = "Mission Control", desktop = "Show desktop", disabled = "Disabled"
    var id: String { rawValue }
    var shortcut: (CGKeyCode, CGEventFlags)? {
        switch self {
        case .back: return (33, .maskCommand)
        case .forward: return (30, .maskCommand)
        case .copy: return (8, .maskCommand)
        case .paste: return (9, .maskCommand)
        case .undo: return (6, .maskCommand)
        case .mission: return (126, .maskControl)
        case .desktop: return (103, []) // F11; behavior depends on macOS shortcuts.
        default: return nil
        }
    }
}
final class Remapper: ObservableObject {
    @Published var enabled = false
    @Published var message = "Enable to use Mac shortcuts with the middle and side buttons."
    @Published var middle = Mapping.unchanged { didSet { save() } }
    @Published var side1 = Mapping.back { didSet { save() } }
    @Published var side2 = Mapping.forward { didSet { save() } }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held: [Int: Mapping] = [:]
    init() {
        let defaults = UserDefaults.standard
        middle = Mapping(rawValue: defaults.string(forKey: "middle") ?? "") ?? .unchanged
        side1 = Mapping(rawValue: defaults.string(forKey: "side1") ?? "") ?? .back
        side2 = Mapping(rawValue: defaults.string(forKey: "side2") ?? "") ?? .forward
    }
    func save() {
        UserDefaults.standard.set(middle.rawValue, forKey: "middle")
        UserDefaults.standard.set(side1.rawValue, forKey: "side1")
        UserDefaults.standard.set(side2.rawValue, forKey: "side2")
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; held.removeAll(); enabled = false
        message = "Mac button shortcuts are off."
    }
    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            message = "Allow Canyon Vigil in System Settings → Privacy & Security → Accessibility, then enable again."
            return
        }
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<Remapper>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            message = "macOS could not enable button shortcuts. Check Accessibility permission and restart the app."
            return
        }
        tap = port; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true); enabled = true
        message = "Mac shortcuts active while this app is running."
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let chosen: Mapping = button == 2 ? middle : button == 3 ? side1 : button == 4 ? side2 : .unchanged
        let mapping: Mapping
        if type == .otherMouseDown { held[button] = chosen; mapping = chosen }
        else if type == .otherMouseUp { mapping = held.removeValue(forKey: button) ?? .unchanged }
        else { mapping = held[button] ?? .unchanged }
        guard mapping != .unchanged else { return Unmanaged.passUnretained(event) }
        if type == .otherMouseDown, let (key, flags) = mapping.shortcut,
            let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) {
            down.flags = flags; up.flags = flags
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
        return nil
    }
}

struct ContentView: View {
    @StateObject private var model = MouseModel()
    @StateObject private var remapper = Remapper()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "computermouse.fill").font(.system(size: 34)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Canyon Vigil").font(.largeTitle.bold())
                    Text("Mouse settings for Mac").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Read mouse") { model.read() }.disabled(model.busy)
            }
            TabView {
                hardware.padding(18).tabItem { Label("Mouse settings", systemImage: "slider.horizontal.3") }
                buttons.padding(18).tabItem { Label("Mac shortcuts", systemImage: "command") }
            }
            HStack(alignment: .top) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).foregroundStyle(model.failed ? .red : .secondary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 40)
            HStack {
                Menu("Profiles") {
                    Button("Import profile…") { model.importProfile() }
                    Button("Export profile…") { model.exportProfile() }.disabled(!model.loaded)
                    Button("Load previous settings") { model.restore() }.disabled(!model.loaded)
                }.fixedSize().disabled(model.busy)
                Spacer()
                Text("Changes are sent when you click Apply.").font(.caption).foregroundStyle(.secondary)
                Button("Apply to mouse") { model.apply() }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(!model.loaded || model.busy || !model.profile.valid)
            }
        }.padding(24).frame(width: 740, height: 690)
        .onAppear { model.read() }
    }
    var hardware: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("DPI profiles").font(.title3.bold())
            Text("Choose sensitivity and a built-in color for each of the four profiles.").foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow { Text("Profile"); Text("Sensitivity"); Text("Color preset"); Text("Active") }.font(.caption).foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { index in
                    GridRow {
                        Text("DPI \(index + 1)").fontWeight(.medium)
                        Picker("Sensitivity", selection: $model.profile.slots[index].dpi) {
                            ForEach(Array(stride(from: 200, through: 3200, by: 200)), id: \.self) { Text("\($0) DPI").tag($0) }
                        }.labelsHidden().frame(width: 150)
                        Picker("Color preset", selection: $model.profile.slots[index].color) {
                            ForEach(0..<16, id: \.self) { Text("Preset \($0 + 1)").tag($0) }
                        }.labelsHidden().frame(width: 140)
                        Button { model.profile.activeSlot = index + 1 } label: {
                            Image(systemName: model.profile.activeSlot == index + 1 ? "largecircle.fill.circle" : "circle")
                        }.buttonStyle(.plain).accessibilityLabel("Activate DPI profile \(index + 1)")
                    }
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lighting").font(.title3.bold())
                    Picker("Mode", selection: $model.profile.mode) {
                        ForEach(modes, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    HStack {
                        Text("Animation speed")
                        Slider(value: Binding(get: { Double(model.profile.speed) }, set: { model.profile.speed = Int($0) }), in: 0...255, step: 1)
                        Text("\(model.profile.speed)").monospacedDigit().frame(width: 30)
                    }
                    Text("Colors use the mouse’s 16 built-in presets; arbitrary RGB is not yet supported.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Performance").font(.title3.bold())
                    Picker("Polling rate", selection: $model.profile.rate) {
                        ForEach([125,250,500,1000], id: \.self) { Text("\($0) Hz").tag($0) }
                    }
                    Picker("Top DPI button", selection: $model.profile.action) {
                        ForEach(actions, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    Text("Hardware changes are read back to verify that the mouse accepted them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }.disabled(!model.loaded || model.busy)
    }
    var buttons: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make the buttons work your way").font(.title3.bold())
            Text("These shortcuts run on your Mac while the app is open. They apply to the middle and side buttons on all connected mice.")
                .foregroundStyle(.secondary)
            mappingPicker("Middle button", selection: $remapper.middle)
            mappingPicker("Side button 1", selection: $remapper.side1)
            mappingPicker("Side button 2", selection: $remapper.side2)
            Text("Left and right clicks keep their normal functions. Browser and desktop shortcuts depend on the active app and your macOS keyboard settings.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button(remapper.enabled ? "Disable Mac shortcuts" : "Enable Mac shortcuts") {
                    if remapper.enabled { remapper.stop() } else { remapper.start() }
                }
                Text(remapper.enabled ? "Enabled" : "Off").foregroundStyle(remapper.enabled ? .green : .secondary)
            }
            Text(remapper.message).font(.callout).textSelection(.enabled)
            Text("macOS asks for Accessibility permission when you enable shortcuts. Hardware DPI and lighting settings do not require that permission.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
    func mappingPicker(_ title: String, selection: Binding<Mapping>) -> some View {
        HStack { Text(title).frame(width: 130, alignment: .leading)
            Picker(title, selection: selection) { ForEach(Mapping.allCases) { Text($0.rawValue).tag($0) } }
                .labelsHidden().frame(width: 260)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct CanyonVigilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup { ContentView() }.windowResizability(.contentSize)
    }
}
