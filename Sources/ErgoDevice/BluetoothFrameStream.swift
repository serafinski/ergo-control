import Foundation
import CoreBluetooth
import ErgoCore

/// Bounded lab-only stream, following the recovered vendor frame path.
/// Every ATT write is acknowledged; command replies are observed separately.
/// This connection never runs reads/configuration or restoration. Disconnect it
/// before reconnecting the ordinary controller for verified restoration.
public final class BluetoothFrameStream: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public private(set) var ready = false
    public private(set) var disconnected = false
    public private(set) var failure: Error?
    public private(set) var successReplies = 0
    public private(set) var transportFrames = 0
    private let identity: UUID
    private let region: UInt8
    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var exchange: Protocol30Exchange?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var issued: Set<UInt8> = []
    private var transactions = TransactionSequence()
    private var stopping = false
    private let service = CBUUID(string: ErgoTarget.service)
    private let write = CBUUID(string: "52401524-F97C-7F90-0E7F-6C6F4E36DB1C")
    private let notify = CBUUID(string: ErgoTarget.notify)

    public init(verifiedIdentity: String, region: UInt8) throws {
        guard let id = UUID(uuidString: verifiedIdentity), region == 5 else { throw LightingLabError.invalidPacket }
        identity = id; self.region = region
        super.init()
    }
    public func connect() {
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !stopping else { return }
        guard central.state == .poweredOn else {
            if central.state != .unknown && central.state != .resetting { fail("Bluetooth is unavailable for the frame test.") }
            return
        }
        guard let device = central.retrievePeripherals(withIdentifiers: [identity]).first else { fail("The verified keyboard is unavailable."); return }
        target = device; device.delegate = self; central.connect(device)
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == target, !stopping else { return }
        peripheral.discoverServices([service])
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        disconnected = true; fail(error?.localizedDescription ?? "Frame test could not connect.")
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == target else { return }
        disconnected = true; ready = false
        if !stopping { fail(error?.localizedDescription ?? "Frame test disconnected.") }
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == target, !stopping else { return }
        guard error == nil, let found = peripheral.services?.first(where: { $0.uuid == service }) else { fail("Frame service discovery failed."); return }
        peripheral.discoverCharacteristics([write, notify], for: found)
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == target, !stopping else { return }
        guard error == nil,
              let output = service.characteristics?.first(where: { $0.uuid == write && $0.properties.contains(.write) }),
              let input = service.characteristics?.first(where: { $0.uuid == notify && $0.properties.contains(.notify) }) else { fail("Frame characteristics are unavailable."); return }
        characteristic = output; peripheral.setNotifyValue(true, for: input)
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == target, !stopping else { return }
        guard error == nil, characteristic.isNotifying else { fail("Frame replies could not be observed."); return }
        ready = true
    }
    public func frame(_ colors: [DialColor], completion: @escaping (Result<Void, Error>) -> Void) {
        guard ready, !stopping, self.completion == nil, let target, let characteristic else {
            completion(.failure(LightingLabError.message("Frame stream is not ready."))); return
        }
        do {
            let request = try BluetoothLightingLabCommand.frame(colors).request(transaction: transactions.next(), region: region)
            exchange = try Protocol30Exchange(request: request, queueWrites: true)
            self.completion = completion; issued.insert(request.transaction)
            while let chunk = exchange?.nextWrite() { target.writeValue(chunk, for: characteristic, type: .withResponse) }
        } catch { completion(.failure(error)); stop() }
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == target, characteristic.uuid == write, !stopping else { return }
        if let error { fail(error.localizedDescription); return }
        do { try exchange?.acknowledgeWrite() }
        catch { fail("Unexpected frame write acknowledgement."); return }
        if exchange?.writesComplete == true {
            transportFrames += 1; exchange = nil
            let done = completion; completion = nil; done?(.success(()))
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == target, characteristic.uuid == notify, !stopping else { return }
        if let error { fail(error.localizedDescription); return }
        guard let data = characteristic.value, data.count == 8 || data.count == 20,
              let transaction = data.first, issued.contains(transaction) else { return }
        let bytes = Array(data), status = bytes[7]
        if status == 1 || status == 3 { return }
        guard status == 2, bytes[1...3].allSatisfy({ $0 == 0 }) else { fail("Keyboard rejected a streamed frame (status \(status))."); return }
        successReplies += 1
    }
    private func fail(_ message: String) {
        if failure == nil { failure = LightingLabError.message(message) }
        let done = completion; completion = nil; done?(.failure(failure!)); stop()
    }
    public func stop() {
        ready = false; stopping = true
        if let target, target.state != .disconnected { central?.cancelPeripheralConnection(target) }
        else { disconnected = true }
    }
}
