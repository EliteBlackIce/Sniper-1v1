"""
build_place.py - rebuilds dist/SniperDuel.rbxlx from src/ without Rojo.

    python tools/build_place.py

Writes the same XML place file `rojo build -o dist/SniperDuel.rbxlx` makes
for this project (default.project.json): every .lua file becomes a
ModuleScript, *.server.lua a Script and *.client.lua a LocalScript, and
folders become Folders. Double-click the result to open it in Studio.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The service-level properties from default.project.json, in the form a
# place file stores them.
TOKENS = {
    ("Lighting", "Technology"): {"Future": 4},
    ("StarterPlayer", "GameSettingsAvatar"): {"R6": 0, "R15": 1},
}
FLOATS = {"CameraMaxZoomDistance", "CameraMinZoomDistance"}
# names Rojo treats as their own class when a $path points at them
CONTAINERS = {"StarterCharacterScripts", "StarterPlayerScripts", "ServerScriptService", "ReplicatedStorage", "StarterGui"}


class Builder:
    def __init__(self, src_root):
        self.src_root = src_root
        self.ref = 0
        self.out = []

    def line(self, depth, text):
        self.out.append("  " * depth + text)

    def open_item(self, depth, cls, name, props=()):
        self.line(depth, '<Item class="%s" referent="%d">' % (cls, self.ref))
        self.ref += 1
        self.line(depth + 1, "<Properties>")
        self.line(depth + 2, '<string name="Name">%s</string>' % name)
        for kind, key, value in props:
            self.line(depth + 2, '<%s name="%s">%s</%s>' % (kind, key, value, kind))

    def script(self, depth, path, name):
        if name.endswith(".server.lua"):
            cls, name, extra = "Script", name[:-11], [("token", "RunContext", "0")]
        elif name.endswith(".client.lua"):
            cls, name, extra = "LocalScript", name[:-11], []
        else:
            cls, name, extra = "ModuleScript", name[:-4], []
        with open(path, encoding="utf-8", newline="") as f:
            source = f.read()
        source = source.replace("]]>", "]]]]><![CDATA[>")
        self.line(depth, '<Item class="%s" referent="%d">' % (cls, self.ref))
        self.ref += 1
        self.line(depth + 1, "<Properties>")
        self.line(depth + 2, '<string name="Name">%s</string>' % name)
        for kind, key, value in extra:
            self.line(depth + 2, '<%s name="%s">%s</%s>' % (kind, key, value, kind))
        self.out.append("  " * (depth + 2) + '<string name="Source"><![CDATA[' + source + "]]></string>")
        self.line(depth + 1, "</Properties>")
        self.line(depth, "</Item>")

    def folder(self, depth, path, name):
        self.open_item(depth, "Folder", name)
        self.line(depth + 1, "</Properties>")
        self.children(depth + 1, path)
        self.line(depth, "</Item>")

    def children(self, depth, path):
        for entry in sorted(os.listdir(path)):
            full = os.path.join(path, entry)
            if os.path.isdir(full):
                self.folder(depth, full, entry)
            elif entry.endswith(".lua") or entry.endswith(".luau"):
                self.script(depth, full, entry.replace(".luau", ".lua"))

    def node(self, depth, name, spec, cls=None):
        cls = spec.get("$className", cls or name)
        props = []
        for key, value in sorted(spec.get("$properties", {}).items()):
            if (cls, key) in TOKENS:
                props.append(("token", key, TOKENS[(cls, key)][value]))
            elif isinstance(value, bool):
                props.append(("bool", key, "true" if value else "false"))
            elif key in FLOATS or isinstance(value, (int, float)):
                props.append(("float", key, value))
            else:
                props.append(("string", key, value))
        if "$path" in spec:
            # a folder synced from disk
            cls = spec.get("$className") or (name if name in CONTAINERS else "Folder")
            self.open_item(depth, cls, name, props)
            self.line(depth + 1, "</Properties>")
            self.children(depth + 1, os.path.join(self.src_root, spec["$path"]))
            self.line(depth, "</Item>")
            return
        self.open_item(depth, cls, name, props)
        self.line(depth + 1, "</Properties>")
        for child in sorted(k for k in spec if not k.startswith("$")):
            self.node(depth + 1, child, spec[child])
        self.line(depth, "</Item>")


def build(root=ROOT, out_path=None):
    with open(os.path.join(root, "default.project.json"), encoding="utf-8") as f:
        project = json.load(f)
    b = Builder(root)
    b.out.append('<roblox version="4">')
    for name in sorted(k for k in project["tree"] if not k.startswith("$")):
        b.node(1, name, project["tree"][name])
    b.out.append("</roblox>")
    out_path = out_path or os.path.join(root, "dist", "SniperDuel.rbxlx")
    with open(out_path, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(b.out))
    return out_path


if __name__ == "__main__":
    print("wrote", build(*(sys.argv[1:2] or [ROOT])))
