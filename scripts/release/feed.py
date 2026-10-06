"""Validate release feeds before handing staged artifacts to the website operator."""
import base64
from pathlib import Path
import re
import urllib.parse
import xml.etree.ElementTree as ET

NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
FEED_URL = "https://getdaydreaming.com/appcast.xml"
DOWNLOAD_PREFIX = "https://getdaydreaming.com/releases/"


def parse_feed(path: Path):
    data = path.read_bytes()
    if b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise ValueError("Appcast may not contain DTD or entity declarations")
    root = ET.fromstring(data)
    if root.tag != "rss" or root.get("version") != "2.0" or len(root.findall("channel")) != 1:
        raise ValueError("Expected a single RSS 2.0 channel")
    return root


def build_numbers(path: Path) -> list[int]:
    numbers = []
    for item in parse_feed(path).findall("channel/item"):
        value = item.findtext(NS + "version")
        if not value or not re.fullmatch(r"[1-9][0-9]*", value):
            raise ValueError("Every appcast build must be a positive integer")
        numbers.append(int(value))
    if len(numbers) != len(set(numbers)):
        raise ValueError("Duplicate appcast build")
    return numbers


def require_next_build(path: Path, build: int):
    if build <= 0 or build <= max(build_numbers(path), default=0):
        raise ValueError("Release build must increase monotonically")


def validate(path: Path, artifact: Path, version: str, build: int):
    root = parse_feed(path)
    build_numbers(path)
    items = [item for item in root.findall("channel/item") if item.findtext(NS + "version") == str(build)]
    if len(items) != 1:
        raise ValueError("Expected exactly one entry for the prepared build")
    item = items[0]
    if item.findtext(NS + "shortVersionString") != version:
        raise ValueError("Marketing version mismatch")
    if item.findtext(NS + "minimumSystemVersion") not in ("26.0", "26.0.0"):
        raise ValueError("Minimum macOS must match the app target")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Missing update archive")
    expected = DOWNLOAD_PREFIX + urllib.parse.quote(artifact.name)
    if enclosure.get("url") != expected:
        raise ValueError("Archive must use the canonical HTTPS release URL")
    if enclosure.get("length") != str(artifact.stat().st_size):
        raise ValueError("Archive length mismatch")
    try:
        signature = base64.b64decode(enclosure.get(NS + "edSignature", ""), validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError("Malformed EdDSA signature") from error
    if len(signature) != 64:
        raise ValueError("Missing EdDSA signature")
    # This checks structure; prepare.py also performs official cryptographic verification.
    return enclosure.get(NS + "edSignature")
