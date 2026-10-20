import Darwin

enum Metrics {
    /// Physical footprint — the number Activity Monitor shows as "Memory".
    static func memoryFootprintBytes() -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }

    static func memoryFootprintMB() -> Double? {
        memoryFootprintBytes().map { Double($0) / 1_048_576 }
    }
}
