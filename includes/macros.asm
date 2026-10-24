;---------------------------------------------------------------------------------------------------
; macros
;---------------------------------------------------------------------------------------------------
; The small vocabulary every lesson shares: asserts, COM calls, float constants and printing.
ifndef macros_asm
macros_asm = 0

true equ 1
false equ 0

; COM, missing from win64.inc
COINIT_MULTITHREADED equ 0

;---------------------------------------------------------------------------------------------------
; asserts: stop in the debugger when a check fails
;---------------------------------------------------------------------------------------------------
AssertNotEq macro reg:req, flag:req
    LOCAL ok
    cmp reg, flag
    jne ok
    int 3
    ok:
endm

AssertEq macro reg:req, flag:req
    LOCAL ok
    cmp reg, flag
    je ok
    int 3
    ok:
endm

; An HRESULT is a failure when its top bit is set.
AssertHr macro
    LOCAL ok
    test eax, eax
    jns ok
    int 3
    ok:
endm

;---------------------------------------------------------------------------------------------------
; vcall: call a COM method
;---------------------------------------------------------------------------------------------------
; A COM object is a pointer to a pointer to its vtable, an array of function pointers. Method N is
; at byte offset 8 * N, and d3d11.inc names every offset: ID3D11Device_CreateBuffer is 24. The
; object itself is always the hidden first argument, `this`, in rcx.
;
;     vcall device, ID3D11Device_CreateBuffer, ADDR desc, ADDR init, ADDR buffer
;
; r10 and r11 hold the object and its vtable, because invoke itself only uses rax (for stack
; arguments) and the four argument registers. Two things invoke cannot see coming:
;
;   * arguments must not name rcx, rdx, r8 or r9: invoke fills those in order, so a later argument
;     would read a register an earlier one already replaced
;   * a fifth or later argument must not be rax when an earlier stack argument is memory or ADDR:
;     those pass through rax on their way to the stack
vcall macro object:req, method:req, args:VARARG
    ;; No IF around invoke: masm64's argument macros leave IF blocks with GOTO, which upsets an
    ;; enclosing IF/ELSE. With no args the list ends in an empty argument, which invoke skips.
    mov r11, object
    mov r10, [r11]
    invoke qword ptr [r10 + method], r11, args
endm

; Every COM interface starts with IUnknown: QueryInterface, AddRef, Release.
IUnknown_Release equ 16

release macro object:req
    vcall object, IUnknown_Release
endm

;---------------------------------------------------------------------------------------------------
; float constants
;---------------------------------------------------------------------------------------------------
; MASM only converts a float literal into bits when it is data, so each of these puts the
; constant in .const and reads it from there.

; xmm register = constant
movf macro reg:req, value:req
    LOCAL c
    .const
    align 4
    c real4 value
    .code
    movss reg, c
endm

; real4 in memory = constant (through eax)
storef macro dest:req, value:req
    LOCAL c
    .const
    align 4
    c real4 value
    .code
    mov eax, dword ptr c
    mov dword ptr dest, eax
endm

; The address of a constant array of floats, for arguments such as a clear colour:
;
;     vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, floats(0.2, 0.3, 0.3, 1.0)
floats macro values:VARARG
    LOCAL c
    .const
    align 16
    c real4 values
    .code
    exitm <ADDR c>
endm

;---------------------------------------------------------------------------------------------------
; printing
;---------------------------------------------------------------------------------------------------
; printf-style output to the console and the debugger, through user32's wsprintfA. It knows %d,
; %u, %x, %s and %c, but not %f.
;
;     print "Texture failed to load at path: %s\n", rsi
;
; \n in the format becomes a line break.
print macro format:req, args:VARARG
    LOCAL f
    .const
    f byte format, 0
    .code
    invoke print_format, ADDR f, args
endm

endif
