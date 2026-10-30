import AppKit
import GameController
import SwiftUI

@MainActor final class InputRouter: ObservableObject {
    enum Action { case previous, next, launch, info, library, back, favorite, search }
    @Published var controllerName: String?
    @Published var usingController = false
    @Published var playGlyph = "a.circle"
    @Published var infoGlyph = "y.circle"
    @Published var libraryGlyph = "x.circle"
    @Published var backGlyph = "b.circle"
    var perform: ((Action) -> Void)?
    var searchIsPresented: (() -> Bool)?
    var navigateSearch: ((Int) -> Void)?
    var acceptsInput: (() -> Bool)?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var repeatTask: Task<Void, Never>?
    private var menuTracking = false
    private var shiftDown = false
    private var direction = 0
    private var lastScroll = Date.distantPast
    private var controllers: [GCController] = []
    private var pressedButtons = Set<ObjectIdentifier>()
    func start() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .scrollWheel, .mouseMoved, .leftMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            return self.keyboard(event)
        }) { monitors.append(monitor) }
        for notification in [NSNotification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.configureControllers() } })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRepeat(); self?.pressedButtons.removeAll(); self?.shiftDown = false }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = true; self?.stopRepeat() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = false }
        })
        GCController.shouldMonitorBackgroundEvents = false
        configureControllers()
    }
    func stop() {
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        repeatTask?.cancel(); repeatTask = nil; direction = 0
        for controller in controllers { controller.extendedGamepad?.valueChangedHandler = nil }
        controllers.removeAll()
    }
    private var textEntry: Bool { NSApp.keyWindow?.firstResponder is NSTextView }
    private var canAct: Bool {
        !menuTracking && NSApp.mainMenu?.highlightedItem == nil && NSApp.isActive && NSApp.keyWindow?.title == "Joynite" && NSApp.keyWindow?.attachedSheet == nil && (acceptsInput?() ?? true)
    }
    private func keyboard(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseDown || event.type == .mouseMoved { usingController = false; return event }
        if event.type == .flagsChanged {
            let down = event.modifierFlags.contains(.shift)
            defer { shiftDown = down }
            guard canAct, searchIsPresented?() != true, !textEntry, down, !shiftDown,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            usingController = false; perform?(.info); return event
        }
        if canAct, event.type == .keyDown, event.keyCode == 48 { return nil }
        if canAct, searchIsPresented?() == true, event.type == .keyDown,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty, [125,126].contains(event.keyCode) {
            navigateSearch?(event.keyCode == 125 ? 1 : -1); return nil
        }
        guard canAct, !textEntry else { return event }
        if event.type == .scrollWheel {
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), abs(event.scrollingDeltaX) > 3 else { return event }
            if Date().timeIntervalSince(lastScroll) > 0.2 { lastScroll = Date(); usingController = false; perform?(event.scrollingDeltaX < 0 ? .next : .previous) }
            return nil
        }
        guard event.type == .keyDown, event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
        let action: Action?
        switch event.keyCode {
        case 49: action = event.isARepeat ? nil : .search
        case 123, 0: action = .previous
        case 124, 2: action = .next
        case 36, 76: action = event.isARepeat ? nil : .launch
        case 53: action = .back
        case 37: action = event.isARepeat ? nil : .library
        case 3: action = event.isARepeat ? nil : .favorite
        default: return event
        }
        usingController = false
        if let action { perform?(action) }
        return nil
    }
    private func configureControllers() {
        for controller in controllers { controller.extendedGamepad?.valueChangedHandler = nil }
        repeatTask?.cancel(); direction = 0; pressedButtons.removeAll()
        controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        controllerName = controllers.first?.vendorName ?? (controllers.isEmpty ? nil : "Controller")
        if controllers.isEmpty { usingController = false }
        for controller in controllers {
            guard let pad = controller.extendedGamepad else { continue }
            controller.handlerQueue = .main
            pad.valueChangedHandler = { [weak self, weak controller] gamepad, element in
                MainActor.assumeIsolated { self?.controllerEvent(gamepad, element: element, controller: controller) }
            }
        }
    }
    private func controllerEvent(_ pad: GCExtendedGamepad, element: GCControllerElement, controller: GCController?) {
        guard canAct, !textEntry else { stopRepeat(); pressedButtons.removeAll(); return }
        usingController = true
        controllerName = controller?.vendorName ?? "Controller"
        playGlyph = pad.buttonA.sfSymbolsName ?? "a.circle"
        infoGlyph = pad.buttonY.sfSymbolsName ?? "y.circle"
        libraryGlyph = pad.buttonX.sfSymbolsName ?? "x.circle"
        backGlyph = pad.buttonB.sfSymbolsName ?? "b.circle"
        let face = element === pad.buttonA || element === pad.buttonB || element === pad.buttonX || element === pad.buttonY || element === pad.rightShoulder || element === pad.leftShoulder || element === pad.rightThumbstickButton
        if face, let button = element as? GCControllerButtonInput {
            let id = ObjectIdentifier(button)
            if !button.isPressed { pressedButtons.remove(id); return }
            guard pressedButtons.insert(id).inserted else { return }
        }
        if element === pad.dpad || element === pad.leftThumbstick || element === pad.dpad.left || element === pad.dpad.right || element === pad.dpad.xAxis || element === pad.leftThumbstick.xAxis {
            let x = abs(pad.dpad.xAxis.value) > 0.5 ? pad.dpad.xAxis.value : pad.leftThumbstick.xAxis.value
            let next = x < -0.55 ? -1 : x > 0.55 ? 1 : 0
            if next != direction { stopRepeat(); direction = next; if next != 0 { step(next); beginRepeat(next) } }
        } else if element === pad.buttonA, pad.buttonA.isPressed { perform?(.launch) }
        else if element === pad.buttonY, pad.buttonY.isPressed { perform?(.info) }
        else if element === pad.buttonX, pad.buttonX.isPressed { perform?(.library) }
        else if element === pad.buttonB, pad.buttonB.isPressed { perform?(.back) }
        else if element === pad.rightShoulder, pad.rightShoulder.isPressed { perform?(.next) }
        else if element === pad.leftShoulder, pad.leftShoulder.isPressed { perform?(.previous) }
        else if element === pad.rightThumbstickButton, pad.rightThumbstickButton?.isPressed == true { perform?(.favorite) }
    }
    private func step(_ value: Int) { perform?(value < 0 ? .previous : .next) }
    private func stopRepeat() { repeatTask?.cancel(); repeatTask = nil; direction = 0 }
    private func beginRepeat(_ value: Int) {
        repeatTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
                while !Task.isCancelled {
                    guard let self, self.canAct, self.direction == value, !self.textEntry else { return }
                    self.step(value); try await Task.sleep(nanoseconds: 170_000_000)
                }
            } catch { return }
        }
    }
}
