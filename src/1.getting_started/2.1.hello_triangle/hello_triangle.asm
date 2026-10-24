;---------------------------------------------------------------------------------------------------
; 2.1 Hello triangle
;---------------------------------------------------------------------------------------------------
; Getting three points on screen, with every step written out:
;
;   1. compile a vertex shader and a pixel shader from HLSL
;   2. put the vertices in a GPU buffer, and describe one vertex's layout
;   3. each frame: bind it all, and draw
;
; The vertex shader runs once per vertex and says where it lands in clip space; the pixel shader
; runs once per covered pixel and says its colour. GL needs a VBO and a VAO; D3D needs the buffer
; and an input layout, which is checked against the vertex shader when it is created.
;
; The left shape is three vertices drawn in order. The right is four vertices and six indices: two
; triangles sharing a diagonal, with no vertex stored twice (LearnOpenGL's 2.2
; hello_triangle_indexed). Tab toggles wireframe, which shows the diagonal.
include rt.inc
include d3d11.inc
include macros.asm
include cstr.asm
include print.asm
include saha.asm
include learn\filesystem.asm

externdef __imp_SetProcessDPIAware:PPROC
SetProcessDPIAware equ <__imp_SetProcessDPIAware>

D3D_COMPILE_STANDARD_FILE_INCLUDE equ 1

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; settings
scr_width dword 1280
scr_height dword 720

; Positions straight in clip space: x and y from -1 to 1, the centre is 0.
; Counter-clockwise, which these lessons treat as the front.
align 4
triangle_vertices real4 -0.9, -0.5, 0.0
                  real4 -0.1, -0.5, 0.0
                  real4 -0.5,  0.5, 0.0
triangle_vertices_size equ $ - triangle_vertices

rectangle_vertices real4 0.1, -0.5, 0.0     ; bottom left
                   real4 0.9, -0.5, 0.0     ; bottom right
                   real4 0.9,  0.5, 0.0     ; top right
                   real4 0.1,  0.5, 0.0     ; top left
rectangle_vertices_size equ $ - rectangle_vertices

rectangle_indices dword 0, 1, 2, 0, 2, 3
rectangle_indices_size equ $ - rectangle_indices

; One attribute: three floats, read as POSITION by the vertex shader.
semantic_position byte "POSITION", 0
align 8
vertex_layout D3D11_INPUT_ELEMENT_DESC <offset semantic_position, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>

; keys pressed since they were last read, for toggles
keys_pressed byte 256 dup(0)

align 8
window qword 0
swap_chain qword 0
device qword 0
context qword 0
backbuffer qword 0
backbuffer_rtv qword 0
raster_state qword 0
wire_state qword 0
vertex_shader qword 0
pixel_shader qword 0
input_layout qword 0
triangle_vb qword 0
rectangle_vb qword 0
rectangle_ib qword 0
stride dword 12
offset_ dword 0
wireframe dword 0

window_class_name byte "LearnD3D11", 0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; win32: every event for the window (keys, mouse, closing) arrives here
; ---------------------------------------------------------------------
align 16
window_proc proc hwnd:qword, msg:qword, wparam:qword, lparam:qword
    mov eax, dword ptr msg
    cmp eax, WM_DESTROY
    jne not_destroy
        invoke PostQuitMessage, 0
        xor eax, eax
        ret
    not_destroy:
    ; Bit 30 of lparam is set when the key was already down: a repeat.
    cmp eax, WM_KEYDOWN
    jne default
    mov rax, lparam
    bt rax, 30
    jc default
    mov rax, wparam
    cmp rax, 256
    jae default
        lea rcx, keys_pressed
        mov byte ptr [rcx + rax], 1
        xor eax, eax
        ret
    default:
    invoke DefWindowProcA, hwnd, msg, wparam, lparam
    ret
window_proc endp

; rcx: key -> rax: 1 if it was pressed since the last call
align 16
key_pressed proc
    and ecx, 0FFh
    lea rdx, keys_pressed
    movzx eax, byte ptr [rdx + rcx]
    mov byte ptr [rdx + rcx], 0
    ret
key_pressed endp

; process all input: ask Windows whether relevant keys are down this frame and react accordingly
; ----------------------------------------------------------------------------------------------
align 16
process_input proc
    invoke GetAsyncKeyState, VK_ESCAPE
    test ax, ax
    jns done
        invoke DestroyWindow, window
    done:
    ret
process_input endp

; rcx: path, rdx: source, r8: size, r9: entry point, [rsp+32]: target -> rax: the compiled code
align 16
compile_shader proc path:qword, source:qword, source_size:qword, entry:qword, target:qword
    local bytecode:qword, errors:qword
    mov bytecode, 0
    mov errors, 0
    invoke D3DCompile, source, source_size, path, 0, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry, target, 0, 0, ADDR bytecode, ADDR errors
    test eax, eax
    jns compiled
        vcall errors, ID3D10Blob_GetBufferPointer
        print "ERROR::SHADER::COMPILATION_FAILED\n%s\n", rax
        invoke ExitProcess, 1
    compiled:
    mov rax, bytecode
    ret
compile_shader endp

; rcx: bind flags, rdx: data, r8: size -> rax: the buffer
;
; An immutable buffer: filled once at creation, never written by the CPU again.
align 16
create_buffer proc bind:qword, data:qword, data_size:qword
    local desc:D3D11_BUFFER_DESC, init:D3D11_SUBRESOURCE_DATA, buffer:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_BUFFER_DESC
    mov eax, dword ptr data_size
    mov desc.ByteWidth, eax
    mov desc.Usage, D3D11_USAGE_IMMUTABLE
    mov eax, dword ptr bind
    mov desc.BindFlags, eax
    invoke mem_zero, ADDR init, sizeof D3D11_SUBRESOURCE_DATA
    mov rax, data
    mov init.pSysMem, rax
    vcall device, ID3D11Device_CreateBuffer, ADDR desc, ADDR init, ADDR buffer
    mov rax, buffer
    ret
create_buffer endp

align 16
main proc
    local wc:WNDCLASSEX, rect:RECT, style:dword
    local swap_desc:DXGI_SWAP_CHAIN_DESC, feature_level:dword, msg:MSG, running:dword
    local raster_desc:D3D11_RASTERIZER_DESC, viewport:D3D11_VIEWPORT
    local path:qword, source:qword, source_size:qword, vs_code:qword, ps_code:qword
    USING rbx, rsi
    SaveRegs

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
    ; so nothing needs rebuilding on resize.
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
    invoke mem_zero, ADDR viewport, sizeof D3D11_VIEWPORT
    cvtsi2ss xmm0, scr_width
    movss viewport._Width, xmm0
    cvtsi2ss xmm0, scr_height
    movss viewport.Height, xmm0
    storef viewport.MaxDepth, 1.0

    ; build and compile our shader program
    ; ------------------------------------
    invoke filesystem_path, "src/1.getting_started/2.1.hello_triangle/hello_triangle.hlsl"
    mov path, rax
    invoke filesystem_read, path, ADDR source_size
    mov source, rax
    invoke compile_shader, path, source, source_size, "vs_main", "vs_5_0"
    mov vs_code, rax
    invoke compile_shader, path, source, source_size, "ps_main", "ps_5_0"
    mov ps_code, rax
    vcall vs_code, ID3D10Blob_GetBufferPointer
    mov rbx, rax
    vcall vs_code, ID3D10Blob_GetBufferSize
    mov rsi, rax
    vcall device, ID3D11Device_CreateVertexShader, rbx, rsi, 0, ADDR vertex_shader
    ; The layout is created against the compiled vertex shader, which is the one place D3D checks
    ; that the two agree.
    vcall device, ID3D11Device_CreateInputLayout, ADDR vertex_layout, 1, rbx, rsi, ADDR input_layout
    vcall ps_code, ID3D10Blob_GetBufferPointer
    mov rbx, rax
    vcall ps_code, ID3D10Blob_GetBufferSize
    vcall device, ID3D11Device_CreatePixelShader, rbx, rax, 0, ADDR pixel_shader

    ; set up vertex data (and buffer(s))
    ; ----------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR triangle_vertices, triangle_vertices_size
    mov triangle_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR rectangle_vertices, rectangle_vertices_size
    mov rectangle_vb, rax
    invoke create_buffer, D3D11_BIND_INDEX_BUFFER, ADDR rectangle_indices, rectangle_indices_size
    mov rectangle_ib, rax

    mov raster_desc.FillMode, D3D11_FILL_WIREFRAME
    vcall device, ID3D11Device_CreateRasterizerState, ADDR raster_desc, ADDR wire_state

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
        invoke key_pressed, VK_TAB
        xor wireframe, eax

        ; render
        ; ------
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, 0
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, floats(0.2, 0.3, 0.3, 1.0)

        mov rax, raster_state
        cmp wireframe, 0
        je solid
            mov rax, wire_state
        solid:
        vcall context, ID3D11DeviceContext_RSSetState, rax
        vcall context, ID3D11DeviceContext_IASetInputLayout, input_layout
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_VSSetShader, vertex_shader, 0, 0
        vcall context, ID3D11DeviceContext_PSSetShader, pixel_shader, 0, 0

        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR triangle_vb, ADDR stride, ADDR offset_
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR rectangle_vb, ADDR stride, ADDR offset_
        vcall context, ID3D11DeviceContext_IASetIndexBuffer, rectangle_ib, DXGI_FORMAT_R32_UINT, 0
        vcall context, ID3D11DeviceContext_DrawIndexed, 6, 0, 0

        ; dxgi: show the image just drawn, waiting for the next vertical blank
        ; --------------------------------------------------------------------
        vcall swap_chain, IDXGISwapChain_Present, 1, 0
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
