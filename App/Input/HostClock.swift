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
}
