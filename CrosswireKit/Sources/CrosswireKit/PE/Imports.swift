//
//  Imports.swift
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
    /// Lowercased DLL names this PE imports, in declaration order.
    ///
    /// Reads the PE Import Directory Table (data directory index 1) and walks
    /// the IMAGE_IMPORT_DESCRIPTOR array, returning the Name field of each
    /// descriptor. Doesn't enumerate per-function imports — DLL granularity is
    /// enough for the runtime-detector (`msvcr120.dll` → vcrun2013, etc).
    ///
    /// Returns an empty array if:
    /// - the file has no Optional Header (object files, etc.)
    /// - the Import Directory is empty (no imports)
    /// - an RVA can't be resolved (malformed file)
    ///
    /// Delay-loaded imports (data directory index 13) are NOT included.
    /// Self-contained Java launchers (e.g. SWG Legends launcher with bundled
    /// JRE) declare almost nothing here because the JRE is extracted at
    /// runtime — their static imports are just kernel32/user32/etc.
    public var importedDLLs: [String] {
        guard let opt = optionalHeader else { return [] }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        // The Optional Header's data directories follow the
        // numberOfRvaAndSizes field. Layout per Microsoft PE spec:
        //   PE32:     Optional Header is 96 bytes before data directories
        //   PE32+:    Optional Header is 112 bytes before data directories
        //
        // Each data directory entry is 8 bytes: { RVA: UInt32, Size: UInt32 }
        // Import Directory is at index 1.
        let optionalHeaderStart = optionalHeaderFileOffset()
        let dataDirsStart = optionalHeaderStart + (opt.magic == .pe32Plus ? 112 : 96)
        let importDirRVAOffset = dataDirsStart + 1 * 8
        guard let importTableRVA = handle.extract(UInt32.self, offset: importDirRVAOffset),
              importTableRVA != 0 else { return [] }

        guard let importTableFileOffset = resolveRVAtoFileOffset(importTableRVA) else { return [] }

        var dlls: [String] = []
        var descriptorOffset = UInt64(importTableFileOffset)
        // IMAGE_IMPORT_DESCRIPTOR is 20 bytes; layout:
        //   OriginalFirstThunk (UInt32)  — RVA to ILT, or 0
        //   TimeDateStamp      (UInt32)
        //   ForwarderChain     (UInt32)
        //   Name               (UInt32)  — RVA to null-terminated DLL name
        //   FirstThunk         (UInt32)  — RVA to IAT
        // Array terminates with a descriptor that is all zeros.
        let importDescriptorSize: UInt64 = 20
        // Cap the walk so a malformed file can't infinite-loop.
        let maxDescriptors = 4096
        for _ in 0..<maxDescriptors {
            guard let name = handle.extract(UInt32.self, offset: descriptorOffset + 12) else { break }
            let originalFirstThunk = handle.extract(UInt32.self, offset: descriptorOffset) ?? 0
            let firstThunk = handle.extract(UInt32.self, offset: descriptorOffset + 16) ?? 0
            // Sentinel — all-zero descriptor ends the array. (Name == 0 is
            // sufficient on its own; check the thunks too for robustness.)
            if name == 0 && originalFirstThunk == 0 && firstThunk == 0 { break }
            if let dllName = readNullTerminatedString(handle: handle, atRVA: name) {
                dlls.append(dllName.lowercased())
            }
            descriptorOffset += importDescriptorSize
        }
        return dlls
    }

    /// File offset of the start of the Optional Header. PortableExecutable.swift's
    /// init didn't expose this, so reconstruct it from the parsed COFF header.
    private func optionalHeaderFileOffset() -> UInt64 {
        // Re-derive: signature ptr is at file offset 0x3C; PE signature is 4 bytes;
        // COFF header is 20 bytes after the signature. Optional header starts
        // 24 bytes after the PE signature start.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        guard let peOffset = handle.extract(UInt32.self, offset: 0x3C) else { return 0 }
        return UInt64(peOffset) + 24
    }

    /// Map a relative virtual address to a file offset using the section
    /// table. Returns nil if no section contains the RVA.
    private func resolveRVAtoFileOffset(_ rva: UInt32) -> UInt32? {
        for section in sections {
            let start = section.virtualAddress
            let end = start + section.virtualSize
            if rva >= start && rva < end {
                return section.pointerToRawData + (rva - start)
            }
        }
        return nil
    }

    /// Read a null-terminated ASCII string at the file offset that maps from
    /// the given RVA. Caps at 256 bytes to avoid runaway reads on malformed
    /// files; DLL names are short.
    private func readNullTerminatedString(handle: FileHandle, atRVA rva: UInt32) -> String? {
        guard let fileOffset = resolveRVAtoFileOffset(rva) else { return nil }
        do {
            try handle.seek(toOffset: UInt64(fileOffset))
        } catch { return nil }
        guard let data = try? handle.read(upToCount: 256), !data.isEmpty else { return nil }
        var end = data.endIndex
        for (idx, byte) in data.enumerated() where byte == 0 {
            end = idx
            break
        }
        return String(data: data.prefix(end), encoding: .ascii)
    }
}
