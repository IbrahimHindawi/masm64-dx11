;---------------------------------------------------------------------------------------------------
; 1.1 Hello window
;---------------------------------------------------------------------------------------------------
; A window, a D3D11 device, and a colour every frame: what GLFW and a GL context give LearnOpenGL,
; done by hand because on Windows it is only a page.
;
;   1. register a window class, naming the procedure that receives the window's events, and
;      create the window
;   2. create the device (which makes resources), its immediate context (which records drawing)
;      and a swap chain (the images that take turns being shown and drawn into)
;   3. a render target view of the swap chain's back buffer, so it can be cleared and drawn into
;   4. loop: hand window events to window_proc, clear, present
;
; Everything is in this one file, which is the whole program: ml64 assembles it, and the includes
; are pulled in as text. From here on the conventions are:
;
;   * Win64 calling: arguments in rcx, rdx, r8, r9, then the stack; results in rax (or xmm0).
;     rbx, rsi, rdi, r12-r15 and xmm6-xmm15 survive calls, everything else may not.
;   * `invoke Function, args` makes such a call; masm64's prologue gives every proc a stack frame
;     with room for the arguments of the calls it makes.
;   * `vcall object, Interface_Method, args` calls a COM method (macros.asm). D3D11 is all COM.
;   * names that MASM reserves get an underscore: a struct's `Width` is `_Width`.
include rt.inc
include d3d11.inc
include macros.asm
include cstr.asm
include print.asm

externdef __imp_SetProcessDPIAware:PPROC
SetProcessDPIAware equ <__imp_SetProcessDPIAware>

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; settings
scr_width dword 1280
scr_height dword 720

align 8
window qword 0
swap_chain qword 0              ; IDXGISwapChain
device qword 0                  ; ID3D11Device
context qword 0                 ; ID3D11DeviceContext
backbuffer qword 0              ; ID3D11Texture2D
backbuffer_rtv qword 0          ; ID3D11RenderTargetView

window_class_name byte "LearnD3D11", 0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; win32: every event for the window (keys, mouse, closing) arrives here
; ---------------------------------------------------------------------
align 16
window_proc proc hwnd:qword, msg:qword, wparam:qword, lparam:qword
    cmp dword ptr msg, WM_DESTROY
    jne default
        invoke PostQuitMessage, 0
        xor eax, eax
        ret
    default:
    invoke DefWindowProcA, hwnd, msg, wparam, lparam
    ret
window_proc endp

; process all input: ask Windows whether relevant keys are down this frame and react accordingly
; ----------------------------------------------------------------------------------------------
; The top bit of GetAsyncKeyState is set while a key is held, which makes the SHORT negative.
align 16
process_input proc
    invoke GetAsyncKeyState, VK_ESCAPE
    test ax, ax
    jns done
        invoke DestroyWindow, window
    done:
    ret
process_input endp

align 16
main proc
    local wc:WNDCLASSEX, rect:RECT, style:dword
    local swap_desc:DXGI_SWAP_CHAIN_DESC, feature_level:dword, msg:MSG, running:dword

    ; win32: register a window class and create the window
    ; ----------------------------------------------------
    call SetProcessDPIAware
    invoke mem_zero, ADDR wc, sizeof WNDCLASSEX
    mov wc.cbSize, sizeof WNDCLASSEX
    lea rax, window_proc
    mov wc.lpfnWndProc, rax
    invoke GetModuleHandleA, 0
    mov wc.hInstance, rax
    invoke LoadCursorA, 0, IDC_ARROW
    mov wc.hCursor, rax
    lea rax, window_class_name
    mov wc.lpszClassName, rax
    invoke RegisterClassExA, ADDR wc
    ; A fixed size: the swap chain and every render target keep the size they were created with,
    ; so nothing needs rebuilding on resize. The size asked for is the inside of the window, and
    ; AdjustWindowRect adds the borders.
    mov style, WS_OVERLAPPEDWINDOW and not (WS_THICKFRAME or WS_MAXIMIZEBOX)
    mov rect.left, 0
    mov rect.top, 0
    mov eax, scr_width
    mov rect.right, eax
    mov eax, scr_height
    mov rect.bottom, eax
    invoke AdjustWindowRect, ADDR rect, style, 0
    or style, WS_VISIBLE
    mov eax, rect.right
    sub eax, rect.left
    mov r10d, rect.bottom
    sub r10d, rect.top
    invoke CreateWindowExA, 0, ADDR window_class_name, "LearnD3D11", style, CW_USEDEFAULT, CW_USEDEFAULT, rax, r10, 0, 0, wc.hInstance, 0
    test rax, rax
    jnz window_created
        print "Failed to create the window\n"
        invoke ExitProcess, 1
    window_created:
    mov window, rax

    ; d3d11: create the device, its immediate context and a swap chain
    ; ----------------------------------------------------------------
    invoke mem_zero, ADDR swap_desc, sizeof DXGI_SWAP_CHAIN_DESC
    mov eax, scr_width
    mov swap_desc.BufferDesc._Width, eax
    mov eax, scr_height
    mov swap_desc.BufferDesc.Height, eax
    mov swap_desc.BufferDesc.Format, DXGI_FORMAT_R8G8B8A8_UNORM
    mov swap_desc.SampleDesc.Count, 1
    mov swap_desc.BufferUsage, DXGI_USAGE_RENDER_TARGET_OUTPUT
    mov swap_desc.BufferCount, 2
    mov rax, window
    mov swap_desc.OutputWindow, rax
    mov swap_desc.Windowed, 1
    mov swap_desc.SwapEffect, DXGI_SWAP_EFFECT_FLIP_DISCARD
    mov feature_level, D3D_FEATURE_LEVEL_11_0
    invoke D3D11CreateDeviceAndSwapChain, 0, D3D_DRIVER_TYPE_HARDWARE, 0, 0, ADDR feature_level, 1, D3D11_SDK_VERSION, \
                                          ADDR swap_desc, ADDR swap_chain, ADDR device, 0, ADDR context
    test eax, eax
    jns device_created
        print "Failed to create the D3D11 device\n"
        invoke ExitProcess, 1
    device_created:
    vcall swap_chain, IDXGISwapChain_GetBuffer, 0, ADDR IID_ID3D11Texture2D, ADDR backbuffer
    vcall device, ID3D11Device_CreateRenderTargetView, backbuffer, 0, ADDR backbuffer_rtv

    ; render loop
    ; -----------
    mov running, 1
    render_loop:
        pump:
            invoke PeekMessageA, ADDR msg, 0, 0, 0, PM_REMOVE
            test eax, eax
            jz pumped
            cmp dword ptr msg.message, WM_QUIT
            jne not_quit
                mov running, 0
            not_quit:
            invoke TranslateMessage, ADDR msg
            invoke DispatchMessageA, ADDR msg
            jmp pump
        pumped:
        cmp running, 0
        je render_loop_done

        ; input
        ; -----
        call process_input

        ; render
        ; ------
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, floats(0.2, 0.3, 0.3, 1.0)

        ; dxgi: show the image just drawn, waiting for the next vertical blank
        ; --------------------------------------------------------------------
        vcall swap_chain, IDXGISwapChain_Present, 1, 0
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
