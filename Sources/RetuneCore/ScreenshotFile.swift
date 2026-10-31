import Foundation

/// Naming and pixel layout for player screenshots.
public enum ScreenshotFile {
    /// Built from the time alone, because channel and movie titles are untrusted and can contain path characters.
    public static func url(in folder: URL, date: Date = .now, timeZone: TimeZone = .current) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        return folder.appendingPathComponent("Retune \(formatter.string(from: date)).png")
    }

    /// OpenGL returns rows from bottom to top, while images store them from top to bottom.
    public static func flippedRows(_ pixels: [UInt8], bytesPerRow: Int) -> [UInt8] {
        guard bytesPerRow > 0 else { return [] }
        let rows = pixels.count / bytesPerRow
        var flipped: [UInt8] = []
        flipped.reserveCapacity(rows * bytesPerRow)
        for row in (0..<rows).reversed() {
            flipped.append(contentsOf: pixels[(row * bytesPerRow)..<((row + 1) * bytesPerRow)])
        }
        return flipped
    }
}
