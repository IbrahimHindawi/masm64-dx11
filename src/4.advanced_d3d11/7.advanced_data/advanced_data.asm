;---------------------------------------------------------------------------------------------------
; 7. Advanced data
;---------------------------------------------------------------------------------------------------
; Two things about vertex buffers that the earlier lessons did not need:
;
;   * a buffer the CPU rewrites. The water's heights are computed here every frame and copied into
;     a DYNAMIC buffer with Map(WRITE_DISCARD): the driver hands back fresh memory, so the GPU can
;     still be reading last frame's copy while this one is written. (GL: glBufferSubData, or
;     glMapBuffer.)
;   * attributes in separate buffers. Positions change every frame and colours never do, so they
;     live apart: slot 0 is rewritten, slot 1 uploaded once. The input layout says which slot each
;     attribute reads.
;
; The index buffer, which says how the grid's points form triangles, never changes either.
; LearnOpenGL's chapter on this has no program; this is one.
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm
include learn\camera.asm

grid equ 96             ; points along each side

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
grid_size real4 8.0     ; world units along each side

; Positions from slot 0, colours from slot 1.
semantic_position byte "POSITION", 0
semantic_color byte "COLOR", 0
align 8
water_layout D3D11_INPUT_ELEMENT_DESC <offset semantic_position, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>
             D3D11_INPUT_ELEMENT_DESC <offset semantic_color, 0, DXGI_FORMAT_R32G32B32_FLOAT, 1, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>

; Mirrors `cbuffer transforms` in advanced_data.hlsl: this lesson's has only the camera.
water_transforms struct
    view mat4 <>
    projection mat4 <>
water_transforms ends

align 4
camera_start vec3 <0.0, 3.0, 7.0>

align 16
t water_transforms <>
s shader <>
cam camera <>
align 8
positions qword 0               ; grid * grid vec3, rewritten every frame
colors qword 0                  ; grid * grid vec3
indices qword 0                 ; (grid - 1)^2 quads, six indices each
index_count qword 0
position_buffer qword 0
color_buffer qword 0
index_buffer qword 0
transforms_buffer qword 0
wire_state qword 0
water_buffers qword 2 dup(0)
water_strides dword 12, 12
water_offsets dword 0, 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; xmm0: x, xmm1: z, xmm2: time -> xmm0: the water's height there, three waves summed
;
;   0.25 sin(1.3 x + 1.7 t) + 0.15 sin(2.1 z - 1.1 t) + 0.08 sin(3.7 (x + z) + 2.3 t)
align 16
wave_height proc
    local x:real4, z:real4, time:real4, sum:real4
    movss x, xmm0
    movss z, xmm1
    movss time, xmm2
    movf xmm1, 1.3
    mulss xmm0, xmm1
    movss xmm1, time
    movf xmm2, 1.7
    mulss xmm1, xmm2
    addss xmm0, xmm1
    call sinf
    movf xmm1, 0.25
    mulss xmm0, xmm1
    movss sum, xmm0
    movss xmm0, z
    movf xmm1, 2.1
    mulss xmm0, xmm1
    movss xmm1, time
    movf xmm2, 1.1
    mulss xmm1, xmm2
    subss xmm0, xmm1
    call sinf
    movf xmm1, 0.15
    mulss xmm0, xmm1
    addss xmm0, sum
    movss sum, xmm0
    movss xmm0, x
    addss xmm0, z
    movf xmm1, 3.7
    mulss xmm0, xmm1
    movss xmm1, time
    movf xmm2, 2.3
    mulss xmm1, xmm2
    addss xmm0, xmm1
    call sinf
    movf xmm1, 0.08
    mulss xmm0, xmm1
    addss xmm0, sum
    ret
wave_height endp

; xmm0: i (0 .. grid - 1) -> xmm0: (i / (grid - 1) - 0.5) * grid_size, the world coordinate
align 16
grid_coordinate proc
    movf xmm1, 95.0                             ; grid - 1
    divss xmm0, xmm1
    subss xmm0, math_half
    mulss xmm0, grid_size
    ret
grid_coordinate endp

align 16
main proc
    local desc:D3D11_BUFFER_DESC, raster_desc:D3D11_RASTERIZER_DESC, wx:real4
    USING rbx, rsi, rdi, r12, r13
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth

    ; the same rasterizer state as window.asm's, drawing only the edges
    invoke mem_zero, ADDR raster_desc, sizeof D3D11_RASTERIZER_DESC
    mov raster_desc.FillMode, D3D11_FILL_WIREFRAME
    mov raster_desc.CullMode, D3D11_CULL_NONE
    mov raster_desc.FrontCounterClockwise, 1
    mov raster_desc.DepthClipEnable, 1
    vcall device, ID3D11Device_CreateRasterizerState, ADDR raster_desc, ADDR wire_state

    invoke shader_create, ADDR s, "src/4.advanced_d3d11/7.advanced_data/advanced_data.hlsl", ADDR water_layout, 2

    ; the grid: colours by depth, and two triangles to each square of four points
    invoke arenaPush, ADDR arena, grid * grid * sizeof vec3, 16
    mov positions, rax
    invoke arenaPush, ADDR arena, grid * grid * sizeof vec3, 16
    mov colors, rax
    invoke arenaPush, ADDR arena, (grid - 1) * (grid - 1) * 6 * 4, 16
    mov indices, rax
    mov rsi, colors
    mov rdi, indices
    xor r12d, r12d                              ; z
    rows:
        ; colour = (0.1, 0.35 + 0.4 fz, 0.6 + 0.3 fz), fz = z / (grid - 1)
        cvtsi2ss xmm0, r12d
        movf xmm1, 95.0
        divss xmm0, xmm1
        movf xmm1, 0.4
        mulss xmm1, xmm0
        movf xmm2, 0.35
        addss xmm1, xmm2
        movf xmm2, 0.3
        mulss xmm2, xmm0
        movf xmm3, 0.6
        addss xmm2, xmm3
        xor r13d, r13d                          ; x
        columns:
            storef [rsi].vec3.x, 0.1
            movss [rsi].vec3.y, xmm1
            movss [rsi].vec3.z, xmm2
            add rsi, sizeof vec3
            cmp r13d, grid - 1
            jae no_quad
            cmp r12d, grid - 1
            jae no_quad
                ; a = z * grid + x, b = a + grid: (a, b, b + 1), (a, b + 1, a + 1)
                imul eax, r12d, grid
                add eax, r13d
                lea edx, [eax + grid]
                mov [rdi + 0], eax
                mov [rdi + 4], edx
                lea ecx, [edx + 1]
                mov [rdi + 8], ecx
                mov [rdi + 12], eax
                mov [rdi + 16], ecx
                lea ecx, [eax + 1]
                mov [rdi + 20], ecx
                add rdi, 24
            no_quad:
            inc r13d
            cmp r13d, grid
            jb columns
        inc r12d
        cmp r12d, grid
        jb rows
    mov rax, rdi
    sub rax, indices
    shr rax, 2
    mov index_count, rax

    ; Positions: DYNAMIC, so the CPU may write them; nothing to start with.
    invoke mem_zero, ADDR desc, sizeof D3D11_BUFFER_DESC
    mov desc.ByteWidth, grid * grid * sizeof vec3
    mov desc.Usage, D3D11_USAGE_DYNAMIC
    mov desc.BindFlags, D3D11_BIND_VERTEX_BUFFER
    mov desc.CPUAccessFlags, D3D11_CPU_ACCESS_WRITE
    vcall device, ID3D11Device_CreateBuffer, ADDR desc, 0, ADDR position_buffer
    ; colours and indices: immutable
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, colors, grid * grid * sizeof vec3
    mov color_buffer, rax
    mov rax, index_count
    shl rax, 2
    invoke create_buffer, D3D11_BIND_INDEX_BUFFER, indices, rax
    mov index_buffer, rax
    invoke create_constant_buffer, sizeof water_transforms
    mov transforms_buffer, rax
    mov rax, position_buffer
    mov water_buffers[0], rax
    mov rax, color_buffer
    mov water_buffers[8], rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, -25.0
    call camera_create

    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        call get_time
        movss current_frame, xmm0
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        invoke camera_process_input, ADDR cam, ADDR delta_time

        ; this frame's water: every point's height, then the whole buffer rewritten
        mov rsi, positions
        xor r12d, r12d                          ; z
        heights_rows:
            xor r13d, r13d                      ; x
            heights_columns:
                cvtsi2ss xmm0, r13d
                call grid_coordinate
                movss wx, xmm0
                movss [rsi].vec3.x, xmm0
                cvtsi2ss xmm0, r12d
                call grid_coordinate
                movss [rsi].vec3.z, xmm0
                movaps xmm1, xmm0
                movss xmm0, wx
                movss xmm2, current_frame
                call wave_height
                movss [rsi].vec3.y, xmm0
                add rsi, sizeof vec3
                inc r13d
                cmp r13d, grid
                jb heights_columns
            inc r12d
            cmp r12d, grid
            jb heights_rows
        invoke update_buffer, position_buffer, positions, grid * grid * sizeof vec3

        invoke window_begin, floats(0.05, 0.05, 0.08, 1.0)
        invoke camera_view, ADDR t.view, ADDR cam
        invoke camera_projection, ADDR t.projection, ADDR cam
        invoke update_buffer, transforms_buffer, ADDR t, sizeof water_transforms
        invoke shader_use, ADDR s
        invoke bind_constants, 0, transforms_buffer

        ; positions from slot 0, colours from slot 1
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 2, ADDR water_buffers, ADDR water_strides, ADDR water_offsets
        vcall context, ID3D11DeviceContext_IASetIndexBuffer, index_buffer, DXGI_FORMAT_R32_UINT, 0
        vcall context, ID3D11DeviceContext_RSSetState, wire_state
        vcall context, ID3D11DeviceContext_DrawIndexed, index_count, 0, 0
        vcall context, ID3D11DeviceContext_RSSetState, raster_state

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
