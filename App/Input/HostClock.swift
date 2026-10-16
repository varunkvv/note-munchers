import Darwin

/// The one clock every NoteCore call uses: mach host time in seconds.
///
/// `MIDITimeStamp` is mach host time too, so MIDI events, the debug keyboard and the
/// session's timers all line up. See context/notecore-api.md ("one clock").
enum HostClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func seconds(hostTime: UInt64) -> Double {
        Double(hostTime) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }

    static var now: Double { seconds(hostTime: mach_absolute_time()) }

    /// The other way: seconds on this clock as mach host time (for scheduling audio).
    static func hostTime(seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1e9 * Double(timebase.denom) / Double(timebase.numer))
    }
}
