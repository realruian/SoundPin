import Foundation

/// Runs the built-in read-only report off the main thread. No discovery,
/// pairing, device connection or undocumented Bluetooth selectors are used.
struct BluetoothBatteryService: DeviceBatteryProviding {
    func readBatteries() async -> [String: DeviceBattery]? {
        await Task.detached(priority: .utility) {
            guard let data = Self.reportData() else { return nil }
            return DeviceBattery.parseReport(data)
        }.value
    }

    static func reportData(executable: String = "/usr/sbin/system_profiler",
                           arguments: [String] = ["SPBluetoothDataType", "-json", "-timeout", "5"],
                           timeout: TimeInterval = 8) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Also bound the child if system_profiler's own timeout stops working.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { if process.isRunning { process.terminate() } }
        timer.resume()
        defer { timer.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return data
    }
}
