# From C to MASM64

The lessons are written the way the C or rin versions are, one call at a
time, so they can be read side by side with LearnOpenGL. What assembly adds
is a handful of conventions, and a few traps that each cost an afternoon
once. They are all here.

## One file, one program

Each lesson is a single `.asm` that `include`s what it uses, from
`includes/`: a unity build. `ml64` assembles that one file and `link` makes
the program; there is nothing else to compile. Every include starts with a
guard (`ifndef math_asm` / `math_asm = 0`), so including one twice is
harmless, and includes include what they need themselves.

`rt.inc` stands in for the MASM64 SDK's `masm64rt.inc`: the SDK's structures
and constants (`win64.inc`), its macros, and the `kernel32`, `user32`, `gdi32`
and `ole32` imports. `d3d11.inc` adds everything Direct3D.

## Calling convention

Everything follows Win64:

- the first four arguments go in `rcx`, `rdx`, `r8`, `r9`, the rest on the
  stack above 32 bytes of *shadow space*
- a float argument goes in the `xmm` register of its *position*: the second
  argument in `xmm1` whatever the first one was
- results come back in `rax`, or `xmm0` for a float
- `rbx`, `rsi`, `rdi`, `rbp`, `r12`-`r15` and `xmm6`-`xmm15` survive a call;
  everything else may not

The SDK's `STACKFRAME` prologue gives every `proc` a frame with room for the
arguments of the calls it makes, up to twelve, so a proc never adjusts `rsp`
around a call. That is also why registers are saved with
`USING rbx, rsi` / `SaveRegs` / `RestoreRegs`, which keep them in locals: a
`push` inside the frame would sit exactly where the next call's stack
arguments go.

## invoke

`invoke Function, a, b, c` loads the arguments and calls. It is a macro, and
three things it cannot see coming:

- **Arguments are loaded in order.** `invoke f, rdx, rcx` puts `rdx` in `rcx`
  first, and then the second argument reads `rcx`, which no longer holds what
  it did. Never pass `rcx`, `rdx`, `r8` or `r9` as an argument after the one
  that overwrites it; 4.8's pixel shaders hit this.
- **Stack arguments travel through `rax`.** A fifth or later argument that is
  memory or `ADDR something` is loaded into `rax` and stored; a later
  argument that *is* `rax` then reads the wrong value.
- **Struct fields through a register** need a size: `qword ptr [rbx].model.vertices`,
  not `[rbx].model.vertices`.

Float arguments are not `invoke`'s business at all. They are set in their
`xmm` register before the call, and a placeholder stands in the argument list:

```asm
movf xmm3, 1.0      ; ClearDepthStencilView(this, dsv, flags, depth, stencil): depth is the 4th
vcall context, ID3D11DeviceContext_ClearDepthStencilView, depth_dsv, D3D11_CLEAR_DEPTH, 0, 0
```

## COM

Direct3D is COM: an object is a pointer to a pointer to a table of functions,
and a method is a call through that table with the object as the first
argument. `vcall` does it:

```asm
vcall device, ID3D11Device_CreateBuffer, ADDR desc, ADDR init, ADDR buffer
```

`ID3D11Device_CreateBuffer` is the method's byte offset in the table, from
`d3d11.inc`. `release object` calls `IUnknown::Release`.

## Floats

MASM only turns `1.5` into bits when it is data, so constants go into `.const`
on the way: `movf xmm0, 1.5` loads one, `storef desc.MaxDepth, 1.0` stores
one, and `floats(0.2, 0.3, 0.3, 1.0)` is the address of four, for a clear
colour. `math.asm` works in SSE, four floats to a register: `v3load` and
`v3store` move a `vec3`, and a matrix row is one `movups`.

## Structures and names

`d3d11.inc` is generated from the Windows SDK's headers by
`tools/gen_d3d11.py`, with each member at the offset the C compiler gives it
and each structure's size checked when it is assembled. Members that MASM
reserves get an underscore: `desc._Width`, `swap_desc._Flags`.

MASM reserves more than it seems to. Names that cannot be variables or
members include `size`, `type`, `length`, `offset`, `name`, `title`, `code`,
`frame`, `dt`, `width`, `mask`, every instruction mnemonic and every register
(`gs`). And code labels inside a procedure share their namespace with the
lesson's globals: a global called `plain` breaks a `plain:` label in
`print.asm`. Lesson globals get distinctive names.

## Globals

A global is addressed relative to the instruction (`rip`), which works
wherever the program is loaded. A global indexed by a register is not:
`table[rbx * 4]` is a 32-bit absolute address, and the linker refuses it in a
64-bit program. Load the address first:

```asm
lea rdi, table
mov eax, [rdi + rbx * 4]
```

Locals are fine either way: they are addressed from `rbp`.

## Memory

There is no `malloc`. `saha.asm` is an arena: one large reservation of address
space, committed a page at a time as it is used. Files, images and models are
pushed onto it and kept for the life of the program; temporary work can be
undone with `arenaGetPos` / `arenaSetPos`.

## When something is wrong

`AssertHr` after a call that returns an `HRESULT` stops in the debugger
(`int 3`) when it failed; `AssertEq` and `AssertNotEq` check anything else.
`print "x = %d\n", eax` writes to the console and the debugger's output, with
`wsprintfA`'s formats (no `%f`). Building puts a `.pdb` beside each program, so
Visual Studio or WinDbg can step through the source.
