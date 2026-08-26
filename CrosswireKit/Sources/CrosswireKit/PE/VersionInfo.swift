//
//  VersionInfo.swift
//  CrosswireKit
//
//  This file is part of Crosswire.
//
//  Crosswire is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Crosswire is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Crosswire.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

extension PEFile {
    /// A human-readable name pulled from the PE's VS_VERSIONINFO resource.
    ///
    /// Walks the .rsrc tree to RT_VERSION (type 16), parses the
    /// VS_VERSIONINFO -> StringFileInfo -> StringTable -> String hierarchy and
    /// returns the first usable value among, in priority order:
    ///   1. ProductName
    ///   2. FileDescription
    ///   3. InternalName
    ///
    /// Returns `nil` when:
    /// - the file has no .rsrc section
    /// - no RT_VERSION resource is present
    /// - the resource is malformed or contains only blank / path-like values
    ///
    /// VS_VERSIONINFO format reference:
    /// https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo
    ///
    /// All parsing is defensive: every length / offset is bounds-checked
    /// against the resource blob, every walk is capped, and any failure short-
    /// circuits to `nil` instead of throwing. Malformed PE files are common
    /// in the wild (NSIS installers especially), so this method must never
    /// crash the identity-detection flow.
    public func displayName() -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let rsrc = rsrcVersionInfo(handle: handle) else { return nil }
        let entries = rsrc.allEntries
        for entry in entries {
            guard let fileOffset = entry.resolveRVA(sections: sections) else { continue }
            do {
                try handle.seek(toOffset: UInt64(fileOffset))
            } catch { continue }
            guard let blob = try? handle.read(upToCount: Int(entry.size)), !blob.isEmpty else { continue }
            if let name = VersionInfoParser.displayName(from: blob) {
                return name
            }
        }
        return nil
    }

    /// Same shape as `rsrc(handle:types:)` in PortableExecutable.swift, but
    /// scoped to RT_VERSION so the walk skips icons / strings / etc.
    private func rsrcVersionInfo(handle: FileHandle) -> ResourceDirectoryTable? {
        guard let resourceSection = sections.first(where: { $0.name == ".rsrc" }) else { return nil }
        return ResourceDirectoryTable(
            handle: handle,
            pointerToRawData: UInt64(resourceSection.pointerToRawData),
            types: [.versionInfo]
        )
    }
}

/// Pure-bytes parser for the VS_VERSIONINFO blob inside a PE RT_VERSION
/// resource. Kept file-private to VersionInfo.swift; the only public surface
/// is `PEFile.displayName()` above.
///
/// VS_VERSIONINFO is a tree of variable-length records. Every record starts
/// with the same three-field header:
///
///   wLength      UInt16  total record length including children, in bytes
///   wValueLength UInt16  length of Value field (chars for text, bytes for binary)
///   wType        UInt16  0 = binary, 1 = text (UTF-16LE)
///
/// Then a null-terminated UTF-16LE `szKey`, then padding to a DWORD boundary,
/// optionally a `Value`, more padding, then `Children`. Children are nested
/// records that follow exactly the same layout, packed back-to-back until
/// the parent's wLength is consumed.
///
/// We don't need every record — we walk down to StringFileInfo -> StringTable
/// -> String and read the szKey / Value pairs.
private enum VersionInfoParser {
    /// Maximum bytes we will walk inside a single VS_VERSIONINFO blob.
    /// Sane RT_VERSION resources are under 8 KiB; anything larger is almost
    /// certainly malformed and we'd rather bail than spin.
    private static let maxBlobBytes = 64 * 1024

    /// Keys we look for inside StringFileInfo / StringTable, highest priority first.
    private static let preferredKeys = ["ProductName", "FileDescription", "InternalName"]

    static func displayName(from data: Data) -> String? {
        let bytes = data.prefix(maxBlobBytes)
        // Parent header: VS_VERSIONINFO. szKey is always "VS_VERSION_INFO".
        guard let root = parseRecordHeader(bytes, at: 0) else { return nil }
        guard root.key == "VS_VERSION_INFO" else { return nil }

        // Skip the VS_FIXEDFILEINFO value (binary, length given by wValueLength).
        var childOffset = align4(root.headerEnd + Int(root.valueLength))
        let rootEnd = min(Int(root.length), bytes.count)

        // Collect candidate (key -> value) pairs from every StringTable we hit.
        var collected: [String: String] = [:]

        // Walk top-level children of VS_VERSIONINFO. We expect StringFileInfo
        // and VarFileInfo; we only care about StringFileInfo.
        var safety = 0
        while childOffset + 6 <= rootEnd && safety < 64 {
            safety += 1
            guard let child = parseRecordHeader(bytes, at: childOffset) else { break }
            let childEnd = min(childOffset + Int(child.length), rootEnd)
            if child.key == "StringFileInfo" {
                walkStringFileInfo(bytes, start: child.headerEnd, end: childEnd, into: &collected)
            }
            // Advance to next sibling, aligned to DWORD.
            let next = align4(childOffset + Int(child.length))
            if next <= childOffset { break } // malformed: zero-length record
            childOffset = next
        }

        for key in preferredKeys {
            if let value = collected[key], let cleaned = sanitize(value) {
                return cleaned
            }
        }
        return nil
    }

    /// Walks StringFileInfo, which contains one or more StringTable children
    /// (one per language/codepage). Each StringTable contains String children
    /// of (key, value) pairs.
    private static func walkStringFileInfo(
        _ bytes: Data,
        start: Int,
        end: Int,
        into collected: inout [String: String]
    ) {
        var offset = align4(start)
        var safety = 0
        while offset + 6 <= end && safety < 64 {
            safety += 1
            guard let table = parseRecordHeader(bytes, at: offset) else { return }
            let tableEnd = min(offset + Int(table.length), end)
            // StringTable's szKey is an 8-char hex string (lang+codepage).
            // We don't filter by language — we just take the first usable
            // value seen for each preferred key.
            walkStringTable(bytes, start: table.headerEnd, end: tableEnd, into: &collected)
            let next = align4(offset + Int(table.length))
            if next <= offset { return }
            offset = next
        }
    }

    /// Walks String children inside a StringTable. Each String record has a
    /// szKey (the metadata field name) and a Value (a null-terminated
    /// UTF-16LE string). wValueLength here is in WORDs, not bytes, when wType
    /// is text — but in practice many writers (including Microsoft tools) put
    /// the byte count there, so we ignore wValueLength and read up to the
    /// record boundary instead.
    private static func walkStringTable(
        _ bytes: Data,
        start: Int,
        end: Int,
        into collected: inout [String: String]
    ) {
        var offset = align4(start)
        var safety = 0
        while offset + 6 <= end && safety < 512 {
            safety += 1
            guard let entry = parseRecordHeader(bytes, at: offset) else { return }
            let entryEnd = min(offset + Int(entry.length), end)
            let valueStart = align4(entry.headerEnd)
            if valueStart < entryEnd {
                if let value = readUTF16String(bytes, start: valueStart, end: entryEnd) {
                    // First writer wins per key — preferred-key priority is
                    // applied after the whole walk.
                    if collected[entry.key] == nil {
                        collected[entry.key] = value
                    }
                }
            }
            let next = align4(offset + Int(entry.length))
            if next <= offset { return }
            offset = next
        }
    }

    /// A parsed VS_VERSIONINFO-style record header: the three UInt16 fields
    /// plus the szKey string and the file offset of the first byte after
    /// szKey's terminator (callers still need to DWORD-align before reading
    /// Value / Children).
    private struct RecordHeader {
        let length: UInt16
        let valueLength: UInt16
        let type: UInt16
        let key: String
        /// Offset of the first byte after the szKey null terminator (NOT yet
        /// aligned to DWORD).
        let headerEnd: Int
    }

    private static func parseRecordHeader(_ bytes: Data, at offset: Int) -> RecordHeader? {
        guard offset + 6 <= bytes.count else { return nil }
        let length = readUInt16(bytes, at: offset)
        let valueLength = readUInt16(bytes, at: offset + 2)
        let type = readUInt16(bytes, at: offset + 4)
        guard length >= 6 else { return nil }
        let keyStart = offset + 6
        guard keyStart <= bytes.count else { return nil }
        // szKey ends at the first UTF-16LE null (two zero bytes on an even
        // boundary). Cap search at the record's declared length.
        let recordEnd = min(offset + Int(length), bytes.count)
        var cursor = keyStart
        while cursor + 1 < recordEnd {
            if bytes[bytes.startIndex + cursor] == 0 && bytes[bytes.startIndex + cursor + 1] == 0 {
                break
            }
            cursor += 2
        }
        guard cursor + 1 < recordEnd else { return nil }
        let keyData = bytes.subdata(in: (bytes.startIndex + keyStart)..<(bytes.startIndex + cursor))
        let key = String(data: keyData, encoding: .utf16LittleEndian) ?? ""
        return RecordHeader(
            length: length,
            valueLength: valueLength,
            type: type,
            key: key,
            headerEnd: cursor + 2
        )
    }

    /// Read a null-terminated UTF-16LE string inside [start, end). Returns
    /// nil if the slice contains no content.
    private static func readUTF16String(_ bytes: Data, start: Int, end: Int) -> String? {
        guard start < end else { return nil }
        var cursor = start
        while cursor + 1 < end {
            if bytes[bytes.startIndex + cursor] == 0 && bytes[bytes.startIndex + cursor + 1] == 0 {
                break
            }
            cursor += 2
        }
        guard cursor > start else { return nil }
        let slice = bytes.subdata(in: (bytes.startIndex + start)..<(bytes.startIndex + cursor))
        return String(data: slice, encoding: .utf16LittleEndian)
    }

    private static func readUInt16(_ bytes: Data, at offset: Int) -> UInt16 {
        let base = bytes.startIndex + offset
        let low = UInt16(bytes[base])
        let high = UInt16(bytes[base + 1])
        return (high << 8) | low
    }

    private static func align4(_ value: Int) -> Int {
        (value + 3) & ~3
    }

    /// Trim whitespace, drop empty strings, and reject values that look like
    /// filesystem paths. Some installers stash junk like `C:\\Build\\out\\app`
    /// or POSIX paths in InternalName; those make terrible display names.
    private static func sanitize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{0000}"))
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("\\") { return nil }
        if trimmed.hasPrefix("/") { return nil }
        // Drive-letter style "C:" even without a backslash.
        if trimmed.count >= 2 {
            let chars = Array(trimmed)
            if chars[1] == ":" && chars[0].isLetter {
                return nil
            }
        }
        return trimmed
    }
}
