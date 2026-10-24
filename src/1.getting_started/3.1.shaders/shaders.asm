;---------------------------------------------------------------------------------------------------
; 3.1 Shaders
;---------------------------------------------------------------------------------------------------
; Two ways to get data into a shader:
;
;   * per vertex: each vertex carries a colour, and the rasterizer blends the three across the
;     triangle on its way to the pixel shader (right)
;   * per draw: a constant buffer, D3D's uniform. The CPU fills a struct and copies it in whole
;     with Map; every vertex and pixel of the draw reads the same values (left: a tint that pulses
;     over time)
;
; From here on shaders are loaded by includes/learn/shader.asm, which does what 2.1 wrote out:
; compile vs_main and ps_main from one .hlsl file and create the input layout against the vertex
; shader. LearnOpenGL's 3.3 shaders_class introduces its Shader class the same way. The window,
; device and swap chain, written out in 1.1 and 2.1, come from includes/learn/window.asm, which is
; to these lessons what GLFW is to LearnOpenGL's.
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; x, y, z, then r, g, b
align 4
left_triangle real4 -0.9, -0.5, 0.0,   1.0, 1.0, 1.0
              real4 -0.1, -0.5, 0.0,   1.0, 1.0, 1.0
              real4 -0.5,  0.5, 0.0,   1.0, 1.0, 1.0
left_triangle_size equ $ - left_triangle

right_triangle real4 0.1, -0.5, 0.0,   1.0, 0.0, 0.0
               real4 0.9, -0.5, 0.0,   0.0, 1.0, 0.0
               real4 0.5,  0.5, 0.0,   0.0, 0.0, 1.0
right_triangle_size equ $ - right_triangle

semantic_position byte "POSITION", 0
semantic_color byte "COLOR", 0
align 8
vertex_layout D3D11_INPUT_ELEMENT_DESC <offset semantic_position, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>
              D3D11_INPUT_ELEMENT_DESC <offset semantic_color, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0>

; Mirrors `cbuffer frame` in the shader, register for register.
frame_constants struct
    tint vec4 <>
frame_constants ends

align 16
s shader <>
c frame_constants <>
align 8
left_vb qword 0
right_vb qword 0
constants qword 0
stride dword 24
offset_ dword 0

; timing
current_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11"

    ; build and compile our shader program
    ; ------------------------------------
    invoke shader_create, ADDR s, "src/1.getting_started/3.1.shaders/shaders.hlsl", ADDR vertex_layout, 2

    ; set up vertex data
    ; ------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR left_triangle, left_triangle_size
    mov left_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR right_triangle, right_triangle_size
    mov right_vb, rax

    ; A dynamic constant buffer: the CPU may rewrite it. Its size must be a multiple of 16 bytes,
    ; the size of one HLSL register.
    invoke create_constant_buffer, sizeof frame_constants
    mov constants, rax

    ; render loop
    ; -----------
    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        ; per-frame time logic
        ; --------------------
        call get_time
        movss current_frame, xmm0

        ; render
        ; ------
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, 0
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, floats(0.2, 0.3, 0.3, 1.0)

        invoke shader_use, ADDR s
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_PSSetConstantBuffers, 0, 1, ADDR constants

        ; WRITE_DISCARD hands back fresh memory each time, so the GPU never waits on the CPU, and
        ; the previous draw keeps the values it saw.
        ; tint = (0, sin(t) / 2 + 0.5, 0, 1)
        movss xmm0, current_frame
        call sinf
        mulss xmm0, math_half
        addss xmm0, math_half
        storef c.tint.x, 0.0
        movss c.tint.y, xmm0
        storef c.tint.z, 0.0
        storef c.tint.w, 1.0
        invoke update_buffer, constants, ADDR c, sizeof frame_constants
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR left_vb, ADDR stride, ADDR offset_
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        storef c.tint.x, 1.0
        storef c.tint.y, 1.0
        storef c.tint.z, 1.0
        invoke update_buffer, constants, ADDR c, sizeof frame_constants
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR right_vb, ADDR stride, ADDR offset_
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        ; dxgi: show the image just drawn, waiting for the next vertical blank
        ; --------------------------------------------------------------------
        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
