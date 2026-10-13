import Foundation
import CoreBluetooth
import ErgoCore

final class BluetoothProbe: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "Bluetooth observation is stopped"
    @Published var running = false
    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var identifiers: [UUID] = []
    private var timeout: Timer?
    private let log: CaptureLog
    private let service = CBUUID(string: ErgoTarget.service)
    private let notify = CBUUID(string: ErgoTarget.notify)

    init(log: CaptureLog) { self.log = log }

    func start(identifiers: [UUID]) {
        guard !running else { return }
        guard !identifiers.isEmpty else {
            status = "Cannot identify PT Ergo's Bluetooth endpoint; reconnect the keyboard and retry"
            return
        }
        do { try log.begin() } catch { status = error.localizedDescription; return }
        self.identifiers = identifiers
        running = true
        status = "Checking Bluetooth access…"
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
        timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.log.record("ble_timeout")
            self.stop()
            self.status = "Bluetooth discovery timed out; reconnect PT Ergo and retry"
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.record("ble_state", ["state": central.state.rawValue])
        guard running else { return }
        guard central.state == .poweredOn else {
            status = "Bluetooth is unavailable (state \(central.state.rawValue))"
            return
        }
        let candidates = central.retrievePeripherals(withIdentifiers: identifiers)
        guard let device = candidates.first else {
            status = "The keyboard's paired Bluetooth endpoint could not be retrieved"
            stop()
            return
        }
        // Only the identifier obtained from VID/PID/transport-matched HID is eligible.
        guard identifiers.contains(device.identifier) else { return }
        target = device
        device.delegate = self
        status = "Connecting to PT Ergo's configuration service…"
        central.connect(device, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard running, peripheral == target else { return }
        log.record("ble_connected")
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.record("ble_connect_failed", ["error": error?.localizedDescription ?? "unknown"])
        stop()
        status = "Could not connect to PT Ergo's configuration service"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard running else { return }
        log.record("ble_disconnected", ["error": error?.localizedDescription ?? "none"])
        stop()
        status = "Bluetooth configuration connection ended"
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard running, peripheral == target else { return }
        if let error { fail("Service discovery", error); return }
        let services = peripheral.services ?? []
        log.record("ble_services", ["uuids": services.map { $0.uuid.uuidString }])
        guard let found = services.first(where: { $0.uuid == service }) else {
            stop(); status = "PT Ergo did not expose the expected configuration service"; return
        }
        peripheral.discoverCharacteristics([notify], for: found)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard running, peripheral == target else { return }
        if let error { fail("Characteristic discovery", error); return }
        for characteristic in service.characteristics ?? [] {
            log.record("ble_characteristic", ["uuid": characteristic.uuid.uuidString,
                                             "properties": characteristic.properties.rawValue])
            guard characteristic.uuid == notify,
                  characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else { continue }
            // This enables notifications (CCCD), but sends no Razer configuration command.
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard running, peripheral == target else { return }
        if let error { fail("Notification subscription", error); return }
        log.record("ble_subscription", ["uuid": characteristic.uuid.uuidString, "enabled": characteristic.isNotifying])
        if characteristic.isNotifying {
            timeout?.invalidate(); timeout = nil
            status = "Observing PT Ergo Bluetooth notifications — no configuration commands sent"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard running, peripheral == target else { return }
        if let error { log.record("ble_value_error", ["error": error.localizedDescription]); return }
        guard let bytes = characteristic.value else { return }
        log.record("ble_notification", ["uuid": characteristic.uuid.uuidString,
            "hex": bytes.map { String(format: "%02x", $0) }.joined()])
    }

    private func fail(_ action: String, _ error: Error) {
        log.record("ble_error", ["action": action, "error": error.localizedDescription])
        stop(); status = "\(action) failed: \(error.localizedDescription)"
    }

    func stop() {
        running = false
        timeout?.invalidate(); timeout = nil
        if let target {
            target.delegate = nil
            central?.cancelPeripheralConnection(target)
        }
        target = nil
        central?.delegate = nil
        central = nil
        status = "Bluetooth observation stopped"
    }
}
