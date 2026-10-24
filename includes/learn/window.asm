;---------------------------------------------------------------------------------------------------
; window: what GLFW is to LearnOpenGL
;---------------------------------------------------------------------------------------------------
; A window, a D3D11 device and its swap chain, keyboard and mouse input, and a clock. Lessons 1.1
; and 1.2 do all of this by hand; from 1.3 on it lives here, and lessons start with
;
;     invoke window_create, "LearnD3D11"
;     render_loop:
;         call window_poll            ; rax = 0 once the window is closed
;         ...
;         call window_present
;
; Globals the lessons use: `window`, `device`, `context`, `swap_chain`, `backbuffer_rtv`,
; `raster_state`, `viewport`, `scr_width` and `scr_height`, and once window_create_depth has made
; them, `depth_texture` and `depth_dsv`.
;
; For checking a lesson without a person at the keyboard:
;
;     lesson.exe --shot out.png [--time t] [--mode n]
;
; renders a few frames with the clock stopped at t seconds (1 by default), in mode n, saves the
; backbuffer as a PNG and exits. The window stays hidden.
ifndef window_asm
window_asm = 0

include macros.asm
include cstr.asm
include print.asm

externdef __imp_SetProcessDPIAware:PPROC
SetProcessDPIAware equ <__imp_SetProcessDPIAware>

WHEEL_DELTA equ 120

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; settings: a fixed size, so the swap chain and every render target keep the size they were created
; with and nothing needs rebuilding on resize
scr_width dword 1280
scr_height dword 720

align 8
window qword 0
device qword 0                  ; ID3D11Device: makes resources
context qword 0                 ; ID3D11DeviceContext: records drawing
swap_chain qword 0              ; IDXGISwapChain: the images shown in turn
backbuffer qword 0              ; ID3D11Texture2D
backbuffer_rtv qword 0          ; ID3D11RenderTargetView of it
raster_state qword 0            ; ID3D11RasterizerState with GL's conventions
depth_texture qword 0           ; ID3D11Texture2D, from window_create_depth
depth_dsv qword 0               ; ID3D11DepthStencilView of it
align 4
viewport D3D11_VIEWPORT <>      ; the whole window

; input
window_keys_pressed byte 256 dup(0)     ; keys pressed since they were last read, for toggles
align 4
window_scroll real4 0.0                 ; wheel notches since the last frame
window_mouse_dx real4 0.0               ; cursor movement over the last frame, in pixels
window_mouse_dy real4 0.0               ; (up is positive)
window_last_cursor POINT <>
window_mode_value dword 0
window_mode_given dword 0               ; did --mode pick it?

; clock
align 8
window_perf_frequency qword 0
window_perf_start qword 0

; --shot
window_frame dword 0
window_shot_time real4 1.0
window_shot_path byte 260 dup(0)

window_class_name byte "LearnD3D11Masm64", 0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; win32: every event for the window (keys, mouse, closing) arrives here
align 16
window_proc proc hwnd:qword, msg:qword, wparam:qword, lparam:qword
    mov eax, dword ptr msg
    cmp eax, WM_DESTROY
    je on_destroy
    cmp eax, WM_KEYDOWN
    je on_key
    cmp eax, WM_MOUSEWHEEL
    je on_wheel
    jmp default

    on_destroy:
        invoke PostQuitMessage, 0
        xor eax, eax
        ret
    on_key:
        ; Bit 30 of lparam is set when the key was already down: a repeat.
        mov rax, lparam
        bt rax, 30
        jc default
        mov rax, wparam
        cmp rax, 256
        jae default
        lea rcx, window_keys_pressed
        mov byte ptr [rcx + rax], 1
        xor eax, eax
        ret
    on_wheel:
        ; The high word of wparam is the distance turned, 120 per notch.
        mov rax, wparam
        shr eax, 16
        movsx eax, ax
        cvtsi2ss xmm0, eax
        movf xmm1, 120.0
        divss xmm0, xmm1
        addss xmm0, window_scroll
        movss window_scroll, xmm0
        xor eax, eax
        ret
    default:
    invoke DefWindowProcA, hwnd, msg, wparam, lparam
    ret
window_proc endp

; The words of the command line: --shot <path>, --time <seconds>, --mode <n>.
align 16
window_parse_args proc
    USING rsi, rdi
    SaveRegs
    call GetCommandLineA
    mov rsi, rax
    next_word:
        ; skip spaces, then look at the word
        cmp byte ptr [rsi], ' '
        jne look
        inc rsi
        jmp next_word
    look:
        cmp byte ptr [rsi], 0
        je done
        invoke cstr_starts_with, rsi, "--shot "
        test eax, eax
        jz not_shot
            add rsi, 7
            lea rdi, window_shot_path
            ; up to the next space, or between quotes when it is quoted
            mov dl, ' '
            cmp byte ptr [rsi], '"'
            jne copy_path
                mov dl, '"'
                inc rsi
            copy_path:
                mov al, [rsi]
                test al, al
                jz path_done
                inc rsi
                cmp al, dl
                je path_done
                mov [rdi], al
                inc rdi
                jmp copy_path
            path_done:
            mov byte ptr [rdi], 0
            jmp next_word
        not_shot:
        invoke cstr_starts_with, rsi, "--time "
        test eax, eax
        jz not_time
            lea rcx, [rsi + 7]
            call parse_float
            movss window_shot_time, xmm0
            mov rsi, rax
            jmp next_word
        not_time:
        invoke cstr_starts_with, rsi, "--mode "
        test eax, eax
        jz not_mode
            lea rcx, [rsi + 7]
            call parse_int
            mov window_mode_value, eax
            mov window_mode_given, 1
            mov rsi, rdx
            jmp next_word
        not_mode:
        ; any other word: skip it, quotes and all
        xor edi, edi                ; inside quotes?
        skip:
            mov al, [rsi]
            test al, al
            jz done
            cmp al, '"'
            jne not_quote
                xor edi, 1
            not_quote:
            cmp al, ' '
            jne skip_on
                test edi, edi
                jz next_word
            skip_on:
            inc rsi
            jmp skip
    done:
    RestoreRegs
    ret
window_parse_args endp

; rcx: caption -> rax: the window. Creates the window, the device, its immediate context, the swap
; chain and a render target view of its back buffer.
align 16
window_create proc caption:qword
    local wc:WNDCLASSEX, rect:RECT, swap_desc:DXGI_SWAP_CHAIN_DESC, feature_level:dword, style:dword
    local raster_desc:D3D11_RASTERIZER_DESC

    call window_parse_args

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

    ; The size asked for is the inside of the window; AdjustWindowRect adds the borders.
    mov style, WS_OVERLAPPEDWINDOW and not (WS_THICKFRAME or WS_MAXIMIZEBOX)
    mov rect.left, 0
    mov rect.top, 0
    mov eax, scr_width
    mov rect.right, eax
    mov eax, scr_height
    mov rect.bottom, eax
    invoke AdjustWindowRect, ADDR rect, style, 0
    ; Shown unless taking a --shot.
    cmp window_shot_path, 0
    jne hidden
        or style, WS_VISIBLE
    hidden:
    mov eax, rect.right
    sub eax, rect.left
    mov r10d, rect.bottom
    sub r10d, rect.top
    invoke CreateWindowExA, 0, ADDR window_class_name, caption, style, CW_USEDEFAULT, CW_USEDEFAULT, rax, r10, 0, 0, wc.hInstance, 0
    test rax, rax
    jnz created
        print "Failed to create the window\n"
        invoke ExitProcess, 1
    created:
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

    ; configure global d3d11 state
    ; ----------------------------
    ; GL's conventions rather than D3D's: counter-clockwise triangles face the viewer, and nothing
    ; is culled.
    invoke mem_zero, ADDR raster_desc, sizeof D3D11_RASTERIZER_DESC
    mov raster_desc.FillMode, D3D11_FILL_SOLID
    mov raster_desc.CullMode, D3D11_CULL_NONE
    mov raster_desc.FrontCounterClockwise, 1
    mov raster_desc.DepthClipEnable, 1
    vcall device, ID3D11Device_CreateRasterizerState, ADDR raster_desc, ADDR raster_state
    vcall context, ID3D11DeviceContext_RSSetState, raster_state
    cvtsi2ss xmm0, scr_width
    movss viewport._Width, xmm0
    cvtsi2ss xmm0, scr_height
    movss viewport.Height, xmm0
    storef viewport.MaxDepth, 1.0

    ; the clock starts now
    invoke QueryPerformanceFrequency, ADDR window_perf_frequency
    invoke QueryPerformanceCounter, ADDR window_perf_start
    invoke GetCursorPos, ADDR window_last_cursor

    mov rax, window
    ret
window_create endp

; A depth buffer the size of the window: 24 bits of depth, 8 of stencil.
align 16
window_create_depth proc
    local desc:D3D11_TEXTURE2D_DESC
    invoke mem_zero, ADDR desc, sizeof D3D11_TEXTURE2D_DESC
    mov eax, scr_width
    mov desc._Width, eax
    mov eax, scr_height
    mov desc.Height, eax
    mov desc.MipLevels, 1
    mov desc.ArraySize, 1
    mov desc.Format, DXGI_FORMAT_D24_UNORM_S8_UINT
    mov desc.SampleDesc.Count, 1
    mov desc.BindFlags, D3D11_BIND_DEPTH_STENCIL
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, 0, ADDR depth_texture
    vcall device, ID3D11Device_CreateDepthStencilView, depth_texture, 0, ADDR depth_dsv
    ret
window_create_depth endp

; rcx: clear colour (4 floats)
;
; The start of drawing a frame into the window: the backbuffer (and depth buffer, if there is one)
; as the render target, the whole window as the viewport, both cleared. The depth clears to 1, the
; far plane, and the stencil to 0.
align 16
window_begin proc color:qword
    vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, depth_dsv
    vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
    vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, color
    cmp depth_dsv, 0
    je no_depth
        ; The depth is a float: the fourth argument, counting `this`, so it travels in xmm3.
        movf xmm3, 1.0
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, depth_dsv, D3D11_CLEAR_DEPTH or D3D11_CLEAR_STENCIL, 0, 0
    no_depth:
    ret
window_begin endp

; -> rax: 0 once the window has been closed. Hands the window's events to window_proc, and works
; out how far the mouse moved since the last call.
align 16
window_poll proc
    local msg:MSG, cursor:POINT, running:dword
    mov running, 1
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

    ; Screen y grows downwards, so moving the mouse up is a positive dy here: pitch up.
    invoke GetCursorPos, ADDR cursor
    mov eax, cursor.x
    sub eax, window_last_cursor.x
    cvtsi2ss xmm0, eax
    movss window_mouse_dx, xmm0
    mov eax, window_last_cursor.y
    sub eax, cursor.y
    cvtsi2ss xmm0, eax
    movss window_mouse_dy, xmm0
    mov eax, cursor.x
    mov window_last_cursor.x, eax
    mov eax, cursor.y
    mov window_last_cursor.y, eax

    ; GetAsyncKeyState reads the whole keyboard, so keys only count while this window has the
    ; focus; glfwGetKey only ever sees its own window's keys.
    invoke GetForegroundWindow
    cmp rax, window
    je focused
        xor eax, eax
        mov window_mouse_dx, eax
        mov window_mouse_dy, eax
        mov window_scroll, eax
    focused:

    invoke key_down, VK_ESCAPE
    test eax, eax
    jz no_escape
        invoke DestroyWindow, window
    no_escape:

    ; A --shot that ends before its frame is taken is a failure, not a quiet exit.
    cmp running, 0
    jne still_running
    cmp window_shot_path, 0
    je still_running
        print "shot: the window was closed before the picture was taken\n"
        invoke ExitProcess, 2
    still_running:
    mov eax, running
    ret
window_poll endp

; rcx: virtual key -> rax: 1 while it is held. The top bit of GetAsyncKeyState is set while a key
; is down, which makes the SHORT negative.
align 16
key_down proc vkey:qword
    invoke GetForegroundWindow
    cmp rax, window
    jne up
    invoke GetAsyncKeyState, vkey
    test ax, ax
    jns up
    mov eax, 1
    ret
    up:
    xor eax, eax
    ret
key_down endp

; rcx: virtual key -> rax: 1 if it was pressed since the last call
align 16
key_pressed proc
    and ecx, 0FFh
    lea rdx, window_keys_pressed
    movzx eax, byte ptr [rdx + rcx]
    mov byte ptr [rdx + rcx], 0
    ret
key_pressed endp

; rcx: how many modes the lesson has -> rax: the current one. Tab steps through them and 1..9 pick
; one; --mode picks the first.
align 16
window_mode proc count:qword
    local key:dword
    invoke key_pressed, VK_TAB
    test eax, eax
    jz no_tab
        mov eax, window_mode_value
        inc eax
        xor edx, edx
        div dword ptr count
        mov window_mode_value, edx
    no_tab:
    mov key, '1'
    digits:
        invoke key_pressed, key
        test eax, eax
        jz next_digit
            mov eax, key
            sub eax, '1'
            cmp eax, dword ptr count
            jae next_digit
            mov window_mode_value, eax
        next_digit:
        inc key
        cmp key, '9'
        jbe digits
    mov eax, window_mode_value
    ret
window_mode endp

; rcx: the mode a lesson starts in, unless --mode picked another
align 16
window_mode_default proc
    cmp window_mode_given, 0
    jne given
        mov window_mode_value, ecx
    given:
    ret
window_mode_default endp

; -> xmm0: seconds since the window was created: what glfwGetTime is to LearnOpenGL. Stopped at
; --time while taking a --shot.
align 16
get_time proc
    local now:qword
    cmp window_shot_path, 0
    je running
        movss xmm0, window_shot_time
        ret
    running:
    invoke QueryPerformanceCounter, ADDR now
    mov rax, now
    sub rax, window_perf_start
    cvtsi2sd xmm0, rax
    cvtsi2sd xmm1, window_perf_frequency
    divsd xmm0, xmm1
    cvtsd2ss xmm0, xmm0
    ret
get_time endp

; dxgi: show the image just drawn, waiting for the next vertical blank. While taking a --shot, the
; third frame is saved instead, and the program ends.
align 16
window_present proc
    cmp window_shot_path, 0
    je show
    cmp window_frame, 3
    jb show
        invoke window_capture, ADDR window_shot_path
        invoke ExitProcess, 0
    show:
    vcall swap_chain, IDXGISwapChain_Present, 1, 0
    inc window_frame
    ret
window_present endp

; rcx: path. Saves the backbuffer as a PNG, through WIC.
;
; The backbuffer cannot be read by the CPU, so it is copied into a staging texture, which can. A
; flip-model swap chain throws the backbuffer away on Present, so this runs before it.
align 16
window_capture proc path:qword
    local desc:D3D11_TEXTURE2D_DESC, staging:qword, mapped:D3D11_MAPPED_SUBRESOURCE
    local wic:qword, stream:qword, encoder:qword, wic_frame:qword, props:qword
    local wide[260]:word, format:GUID, pixels:qword
    USING rbx, rsi, rdi, r12
    SaveRegs

    vcall backbuffer, ID3D11Texture2D_GetDesc, ADDR desc
    mov desc.Usage, D3D11_USAGE_STAGING
    mov desc.BindFlags, 0
    mov desc.CPUAccessFlags, D3D11_CPU_ACCESS_READ
    mov desc.MiscFlags, 0
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, 0, ADDR staging
    AssertHr
    vcall context, ID3D11DeviceContext_CopyResource, staging, backbuffer
    vcall context, ID3D11DeviceContext_Map, staging, 0, D3D11_MAP_READ, 0, ADDR mapped
    AssertHr

    ; RGBA rows, RowPitch bytes apart, become tightly packed BGRA with alpha forced to opaque:
    ; the format every WIC PNG encoder takes.
    mov eax, desc._Width
    mul desc.Height
    shl rax, 2
    invoke VirtualAlloc, 0, rax, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE
    mov pixels, rax
    mov rdi, rax
    mov rsi, mapped.pData
    xor ebx, ebx
    rows:
        xor ecx, ecx
        columns:
            mov eax, [rsi + rcx * 4]    ; A B G R, from the top byte down
            mov edx, eax
            and edx, 00FF00h            ; G stays
            mov r8d, eax
            shr r8d, 16
            and r8d, 0FFh               ; B to the bottom
            or edx, r8d
            and eax, 0FFh
            shl eax, 16                 ; R to the third byte
            or eax, edx
            or eax, 0FF000000h          ; opaque
            mov [rdi], eax
            add rdi, 4
            inc ecx
            cmp ecx, desc._Width
            jb columns
        mov eax, mapped.RowPitch
        add rsi, rax
        inc ebx
        cmp ebx, desc.Height
        jb rows
    vcall context, ID3D11DeviceContext_Unmap, staging, 0
    release staging

    invoke CoInitializeEx, 0, COINIT_MULTITHREADED
    invoke CoCreateInstance, ADDR CLSID_WICImagingFactory, 0, CLSCTX_INPROC_SERVER, ADDR IID_IWICImagingFactory, ADDR wic
    AssertHr
    invoke MultiByteToWideChar, CP_UTF8, 0, path, -1, ADDR wide, 260
    vcall wic, IWICImagingFactory_CreateStream, ADDR stream
    vcall stream, IWICStream_InitializeFromFilename, ADDR wide, GENERIC_WRITE
    test eax, eax
    jns opened
        print "shot: cannot write %s\n", path
        invoke ExitProcess, 1
    opened:
    vcall wic, IWICImagingFactory_CreateEncoder, ADDR GUID_ContainerFormatPng, 0, ADDR encoder
    vcall encoder, IWICBitmapEncoder_Initialize, stream, WICBitmapEncoderNoCache
    vcall encoder, IWICBitmapEncoder_CreateNewFrame, ADDR wic_frame, ADDR props
    vcall wic_frame, IWICBitmapFrameEncode_Initialize, props
    vcall wic_frame, IWICBitmapFrameEncode_SetSize, desc._Width, desc.Height
    lea rdi, format
    lea rsi, GUID_WICPixelFormat32bppBGRA
    mov ecx, sizeof GUID
    rep movsb
    vcall wic_frame, IWICBitmapFrameEncode_SetPixelFormat, ADDR format
    mov eax, desc._Width
    shl eax, 2
    mov r12d, eax                       ; stride
    mul desc.Height
    mov ebx, eax                        ; size
    vcall wic_frame, IWICBitmapFrameEncode_WritePixels, desc.Height, r12, rbx, pixels
    AssertHr
    vcall wic_frame, IWICBitmapFrameEncode_Commit
    vcall encoder, IWICBitmapEncoder_Commit
    AssertHr
    release wic_frame
    release props
    release encoder
    release stream
    release wic

    RestoreRegs
    ret
window_capture endp

endif
