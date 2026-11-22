#!/usr/bin/env python3
# asar-file.py — GoboRefined 0.10.8: read a program's name, version and icon out of an Electron
# app.asar WITHOUT running anything (used by gobo-install-app for plain program archives such as
# Antigravity, whose icon and version live only inside resources/app.asar). Run with "python3 -I".
#
#   asar-file.py ASAR --package        prints "productName<TAB>version" from the top package.json
#   asar-file.py ASAR --icon OUT       writes the best icon (PNG) to OUT (must not exist yet);
#                                      prints the inner path; exit 1 when there is none
#
# asar layout: uint32 4, uint32 header size, uint32, uint32 JSON length, JSON (file tree with
# "offset" and "size"), then the file data starting at 8 + header size. Limits: header 64 MB,
# a file read here 16 MB; files marked "unpacked" are skipped.
import json
import os
import struct
import sys

MAX_HEADER = 64 * 1024 * 1024
MAX_FILE = 16 * 1024 * 1024


def load(path):
    f = open(path, "rb")
    head = f.read(16)
    if len(head) != 16:
        raise ValueError("too short")
    one, header_size, _, json_len = struct.unpack("<4I", head)
    if one != 4 or header_size > MAX_HEADER or json_len > header_size:
        raise ValueError("not an asar archive")
    tree = json.loads(f.read(json_len).decode("utf-8"))
    return f, tree, 8 + header_size


def entry(tree, inner):
    node = tree
    for part in inner.strip("/").split("/"):
        files = node.get("files") if isinstance(node, dict) else None
        if not isinstance(files, dict) or part not in files:
            return None
        node = files[part]
    return node if isinstance(node, dict) and "files" not in node else None


def read(f, base, node):
    if node.get("unpacked"):
        return None
    size = int(node.get("size", 0))
    offset = int(node.get("offset", "0"))
    if size <= 0 or size > MAX_FILE or offset < 0:
        return None
    f.seek(base + offset)
    data = f.read(size)
    return data if len(data) == size else None


def walk(node, prefix="", depth=0):
    files = node.get("files") if isinstance(node, dict) else None
    if not isinstance(files, dict) or depth > 4:
        return
    for name, child in files.items():
        path = prefix + "/" + name
        if isinstance(child, dict) and "files" in child:
            if name not in ("node_modules",):
                yield from walk(child, path, depth + 1)
        elif isinstance(child, dict):
            yield path, child


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: asar-file.py ASAR --package | --icon OUT\n")
        return 2
    try:
        f, tree, base = load(sys.argv[1])
    except (OSError, ValueError, UnicodeDecodeError) as e:
        sys.stderr.write("asar-file.py: %s\n" % e)
        return 1
    if sys.argv[2] == "--package":
        node = entry(tree, "package.json")
        data = read(f, base, node) if node else None
        if not data:
            return 1
        try:
            pkg = json.loads(data.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return 1
        name = str(pkg.get("productName") or pkg.get("name") or "")
        version = str(pkg.get("version") or "")
        print("%s\t%s" % (name.replace("\t", " ").replace("\n", " "), version.replace("\t", " ").replace("\n", " ")))
        return 0
    if sys.argv[2] == "--icon" and len(sys.argv) == 4:
        out = sys.argv[3]
        best, best_score = None, -1
        for path, node in walk(tree):
            low = path.lower()
            if not low.endswith(".png") or "tray" in low or "template" in low:
                continue
            score = int(node.get("size", 0)) // 1024
            base_name = low.rsplit("/", 1)[-1]
            if base_name.startswith("icon") or base_name.startswith("logo") or base_name.startswith("app"):
                score += 100000
            score -= path.count("/") * 1000
            if score > best_score:
                best, best_score = (path, node), score
        if not best:
            return 1
        data = read(f, base, best[1])
        if not data or not data.startswith(b"\x89PNG"):
            return 1
        fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        with os.fdopen(fd, "wb") as o:
            o.write(data)
        print(best[0])
        return 0
    sys.stderr.write("usage: asar-file.py ASAR --package | --icon OUT\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
