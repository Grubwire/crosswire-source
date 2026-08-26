#!/usr/bin/env python3
"""
Insert a new release item into appcast.xml.

Usage:
  update-appcast.py --appcast appcast.xml \
                    --version 1.1.0 \
                    --build 51 \
                    --url https://download.grubwire.io/app/Crosswire-v1.1.0.dmg \
                    --length 12345678 \
                    --signature "abc123==" \
                    --min-system 14.0 \
                    --release-notes-url https://github.com/grubwire/Crosswire/releases/tag/v1.1.0

The script is idempotent for a given version: if an <item> with the same
sparkle:shortVersionString already exists, it is replaced rather than duplicated.
"""

import argparse
import sys
from email.utils import formatdate
from xml.etree import ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"

ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--appcast", required=True)
    p.add_argument("--version", required=True, help="short version, e.g. 1.1.0")
    p.add_argument("--build", required=True, help="build number, e.g. 51")
    p.add_argument("--url", required=True)
    p.add_argument("--length", required=True)
    p.add_argument("--signature", required=True, help="EdDSA signature from sign_update")
    p.add_argument("--min-system", default="14.0")
    p.add_argument("--release-notes-url", default="")
    args = p.parse_args()

    tree = ET.parse(args.appcast)
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        print("appcast.xml has no <channel>", file=sys.stderr)
        return 1

    # Remove any existing item for this version (idempotent re-runs).
    for existing in list(channel.findall("item")):
        short = existing.find(f"{{{SPARKLE_NS}}}shortVersionString")
        if short is not None and short.text == args.version:
            channel.remove(existing)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    ET.SubElement(item, "pubDate").text = formatdate(localtime=False, usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = args.build
    ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = args.version
    ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion").text = args.min_system
    if args.release_notes_url:
        ET.SubElement(item, f"{{{SPARKLE_NS}}}releaseNotesLink").text = args.release_notes_url
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        f"{{{SPARKLE_NS}}}edSignature": args.signature,
        "length": args.length,
        "type": "application/octet-stream",
    })

    # Newest first.
    insert_at = 0
    for idx, child in enumerate(list(channel)):
        if child.tag in ("title", "link", "description", "language"):
            insert_at = idx + 1
    channel.insert(insert_at, item)

    ET.indent(tree, space="    ", level=0)
    tree.write(args.appcast, xml_declaration=True, encoding="utf-8")
    print(f"appcast.xml updated with version {args.version} (build {args.build})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
