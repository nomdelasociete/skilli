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

    /// CPU time used so far (user and system), in milliseconds, and the
    /// times the process woke the CPU: what an idle cost is measured by.
    static func cpu() -> (milliseconds: Double, wakeups: UInt64)? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else { return nil }
        // Mach absolute time units on Apple silicon, nanoseconds once scaled.
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(usage.ri_user_time + usage.ri_system_time)
        return (ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000, usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups)
    }
}
