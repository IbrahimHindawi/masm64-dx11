# Generates includes/d3d11.inc: what the lessons need from the Windows SDK's
# D3D11, DXGI, D3DCompiler and WIC headers, in MASM.
#
#   structs      laid out exactly as the C compiler lays them out: every member
#                at the offset clang reports, with explicit padding, so MASM's
#                own alignment rules never come into it
#   constants    every enum value, and every #define that is an integer
#   vtables      `IFoo_Method equ N`: the byte offset of each COM method in
#                IFoo's vtable, for the `vcall` macro
#   GUIDs        IIDs, CLSIDs and WIC pixel formats, as GUID data
#   imports      the few plain functions (D3D11CreateDeviceAndSwapChain, D3DCompile)
#
# Needs the libclang Python package (`pip install libclang`) and the Windows
# SDK. Run from the repository root:
#
#     python tools/gen_d3d11.py

import os
import re
import sys
import glob

import clang.cindex as ci

SDK_VERSION = "10.0.26100.0"
SDK_INCLUDE = rf"C:\Program Files (x86)\Windows Kits\10\Include\{SDK_VERSION}"
OUT = os.path.join(os.path.dirname(__file__), "..", "includes", "d3d11.inc")
MASM64_HOME = os.environ.get("MASM64_HOME", r"C:\masm64")
WIN64_INC = os.path.join(MASM64_HOME, "include64", "win64.inc")

HEADERS = ["d3d11.h", "d3dcommon.h", "dxgi.h", "dxgiformat.h", "dxgitype.h", "dxgicommon.h",
           "d3dcompiler.h", "wincodec.h", "d3d11sdklayers.h"]

MACRO_PREFIXES = ("D3D11_", "D3D10_", "D3D_", "DXGI_", "D3DCOMPILE_", "WINCODEC_", "WIC")

# Words MASM reserves (it ignores case for them). A member with one of these
# names gets a leading underscore: `desc._Width`.
RESERVED = set("""
width mask size sizeof type offset length lengthof this ptr short near far align even org addr high
low highword lowword mod and or not xor shl shr eq ne lt le gt ge str proc label end segment option
record struct union typedef proto local public extern extrn comm include if else endif ifdef ifndef
while repeat for forc macro endm exitm goto purge code enter leave loop wait lock rep div mul add sub
inc dec cmp test call ret jmp push pop in out pause emms monitor mwait name
""".split())

WRAPPER = r"""
#define WIN32_LEAN_AND_MEAN
#define CINTERFACE
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <d3d11sdklayers.h>
#include <d3dcompiler.h>
#include <wincodec.h>
"""


def clang_args():
    msvc = sorted(glob.glob(r"C:\Program Files\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\include"))
    args = ["-x", "c", "--target=x86_64-pc-windows-msvc", "-fms-extensions", "-fms-compatibility",
            "-D_WIN64", "-D_AMD64_", "-Wno-everything"]
    for sub in ("um", "shared", "ucrt"):
        args.append("-I" + os.path.join(SDK_INCLUDE, sub))
    if msvc:
        args.append("-I" + msvc[-1])
    return args


def parse(source, name="wrapper.c"):
    index = ci.Index.create()
    options = ci.TranslationUnit.PARSE_DETAILED_PROCESSING_RECORD | ci.TranslationUnit.PARSE_SKIP_FUNCTION_BODIES
    return index.parse(name, args=clang_args(), unsaved_files=[(name, source)], options=options)


def from_headers(cursor):
    loc = cursor.location
    return loc.file is not None and os.path.basename(loc.file.name).lower() in HEADERS


def function_like(macro):
    tokens = list(macro.get_tokens())
    return (len(tokens) > 1 and tokens[1].spelling == "("
            and tokens[1].extent.start.offset == tokens[0].extent.end.offset)


def float_like(macro):
    for t in list(macro.get_tokens())[1:]:
        if t.kind == ci.TokenKind.LITERAL and re.match(r"^[0-9.]+([eE][-+]?[0-9]+)?[fF]?$", t.spelling) and ("." in t.spelling or "e" in t.spelling.lower()):
            return True
        if t.kind == ci.TokenKind.LITERAL and t.spelling.startswith(('"', "L\"", "'")):
            return True
    return False


def masm_name(name):
    return "_" + name if name.lower() in RESERVED else name


# -- What win64.inc already has ------------------------------------------------

def win64_names():
    structs, symbols = set(), set()
    with open(WIN64_INC, encoding="latin-1") as f:
        for line in f:
            m = re.match(r"\s*(\w+)\s+(STRUCT|UNION)\b", line, re.I)
            if m:
                structs.add(m.group(1))
                continue
            m = re.match(r"\s*(\w+)\s+(equ|=|TYPEDEF|textequ)\b", line, re.I)
            if m:
                symbols.add(m.group(1).lower())
    return structs, symbols


# -- Records -------------------------------------------------------------------

class Emitter:
    def __init__(self, win64_structs):
        self.win64_structs = win64_structs
        self.names = {}          # record decl hash -> MASM struct name
        self.done = set()
        self.out = []
        self.checks = []

    def record_name(self, decl):
        key = decl.hash
        if key in self.names:
            return self.names[key]
        return decl.spelling or None

    def scalar(self, t):
        t = t.get_canonical()
        k = t.kind
        size = t.get_size()
        if k == ci.TypeKind.FLOAT:
            return "real4"
        if k in (ci.TypeKind.DOUBLE, ci.TypeKind.LONGDOUBLE):
            return "real8"
        return {1: "byte", 2: "word", 4: "dword", 8: "qword"}.get(size)

    def member(self, name, t):
        """One member declaration, emitting the types it depends on first."""
        t = t.get_canonical()
        if t.kind == ci.TypeKind.CONSTANTARRAY:
            elem = t.get_array_element_type().get_canonical()
            count = t.get_array_size()
            if elem.kind == ci.TypeKind.RECORD:
                rname = self.require(elem.get_declaration())
                return f"{name} {rname} {count} dup(<>)"
            scalar = self.scalar(elem)
            if scalar is None:
                return f"{name} byte {t.get_size()} dup(?)"
            return f"{name} {scalar} {count} dup(?)"
        if t.kind == ci.TypeKind.RECORD:
            rname = self.require(t.get_declaration())
            return f"{name} {rname} <>"
        scalar = self.scalar(t)
        if scalar is None:
            return f"{name} byte {t.get_size()} dup(?)"
        return f"{name} {scalar} ?"

    def body(self, decl, indent):
        """The members of `decl`, padded to clang's offsets. Anonymous nested
        records are written inline, as MASM's nested STRUCT/UNION."""
        lines = []
        is_union = decl.kind == ci.CursorKind.UNION_DECL
        at = 0
        pad = 0
        rtype = decl.type
        fields = list(rtype.get_fields())
        i = 0
        while i < len(fields):
            f = fields[i]
            off = f.get_field_offsetof() // 8 if not is_union else 0
            if f.is_bitfield():
                # A run of bitfields becomes the bytes it occupies.
                start = f.get_field_offsetof()
                end = start
                while i < len(fields) and fields[i].is_bitfield():
                    end = fields[i].get_field_offsetof() + fields[i].get_bitfield_width()
                    i += 1
                first, last = start // 8, (end + 7) // 8
                if first > at:
                    lines.append(f"{indent}_pad{pad} byte {first - at} dup(?)")
                    pad += 1
                    at = first
                lines.append(f"{indent}_bits{pad} byte {last - first} dup(?)   ; bitfields")
                pad += 1
                at = last
                continue
            if not is_union and off > at:
                lines.append(f"{indent}_pad{pad} byte {off - at} dup(?)")
                pad += 1
                at = off
            ft = f.type.get_canonical()
            fdecl = ft.get_declaration() if ft.kind == ci.TypeKind.RECORD else None
            if fdecl is not None and (f.spelling == "" or "(anonymous" in f.spelling or "(unnamed" in f.spelling):
                # An anonymous struct or union: its members belong to this record.
                kw = "UNION" if fdecl.kind == ci.CursorKind.UNION_DECL else "STRUCT"
                lines.append(f"{indent}{kw}")
                lines += self.body(fdecl, indent + "    ")
                lines.append(f"{indent}ENDS")
            elif fdecl is not None and (not fdecl.spelling or "(unnamed" in fdecl.spelling or "(anonymous" in fdecl.spelling):
                # A named member of an unnamed type: the type gets a name of its own.
                rname = self.require(fdecl, f"{self.record_name(decl)}_{f.spelling}")
                lines.append(f"{indent}{masm_name(f.spelling)} {rname} <>")
            else:
                lines.append(indent + self.member(masm_name(f.spelling), f.type))
            if not is_union:
                at = off + ft.get_size()
            i += 1
        total = rtype.get_size()
        if not is_union and total > at:
            lines.append(f"{indent}_pad{pad} byte {total - at} dup(?)")
        return lines

    def require(self, decl, fallback=None):
        decl = decl.get_definition() or decl
        name = self.record_name(decl)
        if not name or "unnamed" in name or "anonymous" in name:
            name = fallback or f"_anon_{decl.hash & 0xffffff:06x}"
            self.names[decl.hash] = name
        if name in self.done:
            return name
        self.done.add(name)
        size = decl.type.get_size()
        if name in self.win64_structs:
            self.checks.append(f".erre sizeof {name} eq {size}, <win64.inc's {name} is not {size} bytes>")
            return name
        body = self.body(decl, "    ")
        kw = "UNION" if decl.kind == ci.CursorKind.UNION_DECL else "STRUCT"
        self.out.append(f"{name} {kw} 1")
        self.out += body
        self.out.append(f"{name} ENDS")
        self.out.append(f".erre sizeof {name} eq {size}, <{name} is not {size} bytes>")
        self.out.append("")
        return name


# -- Main ----------------------------------------------------------------------

def main():
    tu = parse(WRAPPER)
    errors = [d for d in tu.diagnostics if d.severity >= ci.Diagnostic.Error]
    for d in errors[:10]:
        print("clang:", d, file=sys.stderr)
    if errors:
        sys.exit(1)

    win64_structs, win64_symbols = win64_names()
    em = Emitter(win64_structs)

    typedefs = []        # (typedef name, record decl)
    enums = []           # (name, value)
    macros = []          # names of object-like macros to evaluate
    vtables = []         # (interface, [methods])
    functions = []

    # Records are named after their typedef wherever it was declared, so
    # `LARGE_INTEGER` is found in win64.inc rather than written out again as
    # `_LARGE_INTEGER`.
    for c in tu.cursor.get_children():
        if c.kind == ci.CursorKind.TYPEDEF_DECL:
            under = c.underlying_typedef_type.get_canonical()
            if under.kind == ci.TypeKind.RECORD:
                decl = under.get_declaration()
                if decl.hash not in em.names or em.names[decl.hash] not in win64_structs:
                    em.names.setdefault(decl.hash, c.spelling)
                    if c.spelling in win64_structs:
                        em.names[decl.hash] = c.spelling

    for c in tu.cursor.get_children():
        if not from_headers(c):
            continue
        if c.kind == ci.CursorKind.TYPEDEF_DECL:
            under = c.underlying_typedef_type.get_canonical()
            if under.kind == ci.TypeKind.RECORD:
                decl = under.get_declaration()
                if decl.hash not in em.names:
                    em.names[decl.hash] = c.spelling
                typedefs.append((c.spelling, decl))
        elif c.kind == ci.CursorKind.ENUM_DECL:
            for e in c.get_children():
                if e.kind == ci.CursorKind.ENUM_CONSTANT_DECL:
                    enums.append((e.spelling, e.enum_value))
        elif c.kind == ci.CursorKind.MACRO_DEFINITION:
            if c.spelling.startswith(MACRO_PREFIXES) and not function_like(c) and not float_like(c):
                macros.append(c.spelling)
        elif c.kind == ci.CursorKind.FUNCTION_DECL:
            if c.spelling.startswith(("D3D11Create", "D3DCompile", "D3DReadFileToBlob", "CreateDXGIFactory", "D3DReflect")):
                functions.append(c.spelling)

    # Integer #defines: evaluated by clang, as enum values in a second unit.
    seen = {n for n, _ in enums}
    probe = WRAPPER + "\n".join(f"enum __e_{m} {{ __v_{m} = ({m}) }};" for m in macros if m not in seen)
    tu2 = parse(probe, "probe.c")
    for c in tu2.cursor.get_children():
        if c.kind == ci.CursorKind.ENUM_DECL and c.spelling.startswith("__e_"):
            for e in c.get_children():
                if e.kind == ci.CursorKind.ENUM_CONSTANT_DECL:
                    ok = not any(d.location.line == e.location.line and d.location.file and d.location.file.name == "probe.c"
                                 for d in tu2.diagnostics if d.severity >= ci.Diagnostic.Error)
                    if ok:
                        enums.append((e.spelling[4:], e.enum_value))

    # Structs, and vtables from the C interface's `IFooVtbl` structs.
    for name, decl in typedefs:
        if name.endswith("Vtbl"):
            iface = name[:-4]
            methods = [f.spelling for f in decl.type.get_fields()]
            vtables.append((iface, methods))
            continue
        fields = list(decl.type.get_fields())
        if len(fields) == 1 and fields[0].spelling == "lpVtbl":
            continue   # the interface itself: only its vtable matters
        if decl.type.get_size() <= 0:
            continue
        em.require(decl)

    # GUIDs, straight from the header text.
    guids = {}
    for header in HEADERS:
        path = None
        for sub in ("um", "shared"):
            p = os.path.join(SDK_INCLUDE, sub, header)
            if os.path.exists(p):
                path = p
        text = open(path, encoding="latin-1").read()
        for m in re.finditer(r'MIDL_INTERFACE\("([0-9a-fA-F-]+)"\)\s*\n\s*(\w+)\s*:', text):
            guids["IID_" + m.group(2)] = m.group(1)
        for m in re.finditer(r'class\s+DECLSPEC_UUID\("([0-9a-fA-F-]+)"\)\s*\n?\s*(\w+)\s*;', text):
            guids["CLSID_" + m.group(2)] = m.group(1)
        for m in re.finditer(r"DEFINE_GUID\(\s*(\w+)\s*,\s*([^)]*)\)", text):
            parts = [p.strip() for p in m.group(2).split(",")]
            if len(parts) == 11:
                guids[m.group(1)] = parts

    w = []
    w.append(";" + "-" * 99)
    w.append("; d3d11.inc: generated by tools/gen_d3d11.py from the Windows SDK " + SDK_VERSION + ". Do not edit.")
    w.append(";" + "-" * 99)
    w.append("ifndef d3d11_inc")
    w.append("d3d11_inc = 0")
    w.append("")
    w.append("; -- constants " + "-" * 86)
    emitted = set()
    for name, value in enums:
        if name.lower() in win64_symbols or name in emitted:
            continue
        emitted.add(name)
        w.append(f"{name} equ {value}")
    w.append("")
    w.append("; -- structs " + "-" * 88)
    w += em.checks
    w.append("")
    w += em.out
    w.append("; -- vtables: byte offsets of each method " + "-" * 58)
    for iface, methods in vtables:
        for i, m in enumerate(methods):
            w.append(f"{iface}_{m} equ {i * 8}")
        w.append("")
    w.append("; -- imports " + "-" * 88)
    for f in sorted(set(functions)):
        w.append(f"externdef __imp_{f}:PPROC")
        w.append(f"{f} equ <__imp_{f}>")
    w.append("")
    w.append("; -- GUIDs " + "-" * 90)
    w.append(".const")
    w.append("align 4")
    for name, value in sorted(guids.items()):
        if name.lower() in win64_symbols:
            continue
        if isinstance(value, str):
            a, b, c, d, e = value.split("-")
            tail = [d[0:2], d[2:4]] + [e[i:i + 2] for i in range(0, 12, 2)]
            w.append(f"{name} GUID <0{a}h, 0{b}h, 0{c}h, {{{', '.join('0' + x + 'h' for x in tail)}}}>")
        else:
            nums = ["0" + p[2:].rstrip("uUlL") + "h" if p.lower().startswith("0x") else p for p in value]
            w.append(f"{name} GUID <{nums[0]}, {nums[1]}, {nums[2]}, {{{', '.join(nums[3:])}}}>")
    w.append(".code")
    w.append("")
    w.append("endif")

    with open(OUT, "w", newline="\r\n") as f:
        f.write("\n".join(w) + "\n")
    print(f"{OUT}: {len(emitted)} constants, {len(em.done)} structs, {len(vtables)} vtables, {len(guids)} GUIDs")


if __name__ == "__main__":
    main()
