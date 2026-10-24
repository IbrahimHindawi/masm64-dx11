;---------------------------------------------------------------------------------------------------
; 4. Face culling
;---------------------------------------------------------------------------------------------------
; A closed object's back faces can never be seen: something in front always covers them. So the
; rasterizer can skip them before any pixel is shaded, roughly halving the work for a cube.
;
; Which side is the front comes from the winding, the order the corners appear in on screen. Every
; vertex array here is counter-clockwise from outside, and the rasterizer is told so
; (FrontCounterClockwise); a triangle seen from behind then comes out clockwise, and is culled.
;
; Culling front faces leaves the insides of the cubes: you see through the near walls to the far
; ones.
;
;   Tab   none / cull back faces / cull front faces
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm
include learn\cube.asm
include learn\camera.asm
include learn\transforms.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
align 4
plane_vertices real4 -5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   0.0, 2.0
               real4  5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   2.0, 2.0
               real4  5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   2.0, 0.0
               real4 -5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   0.0, 2.0
               real4  5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   2.0, 0.0
               real4 -5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   0.0, 0.0
plane_vertices_size equ 6 * 32

camera_start vec3 <-1.0, 1.0, 4.0>
cube_a vec3 <-1.0, 0.0, -1.0>
cube_b vec3 <2.0, 0.0, 0.0>
cull_modes dword D3D11_CULL_NONE, D3D11_CULL_BACK, D3D11_CULL_FRONT

align 16
t transforms <>
model mat4 <>
s shader <>
cam camera <>
align 8
cull_states qword 3 dup(0)      ; ID3D11RasterizerState for each of cull_modes
cube_vb qword 0
plane_vb qword 0
transforms_buffer qword 0
cube_texture qword 0
floor_texture qword 0
sampler qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    local raster_desc:D3D11_RASTERIZER_DESC
    USING rbx, rsi, rdi
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth
    invoke window_mode_default, 2

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; window.asm's rasterizer state, with each of the three cull modes
    invoke mem_zero, ADDR raster_desc, sizeof D3D11_RASTERIZER_DESC
    mov raster_desc.FillMode, D3D11_FILL_SOLID
    mov raster_desc.FrontCounterClockwise, 1
    mov raster_desc.DepthClipEnable, 1
    lea rsi, cull_modes
    lea rdi, cull_states
    xor ebx, ebx
    states:
        mov eax, [rsi + rbx * 4]
        mov raster_desc.CullMode, eax
        lea rax, [rdi + rbx * 8]
        vcall device, ID3D11Device_CreateRasterizerState, ADDR raster_desc, rax
        inc ebx
        cmp ebx, 3
        jb states

    invoke shader_create, ADDR s, "src/4.advanced_d3d11/4.face_culling/face_culling.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke filesystem_path, "resources/textures/marble.jpg"
    invoke load_texture, rax, 0
    mov cube_texture, rax
    invoke filesystem_path, "resources/textures/metal.png"
    invoke load_texture, rax, 0
    mov floor_texture, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -75.0
    movf xmm3, -15.0
    call camera_create

    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        call get_time
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        invoke camera_process_input, ADDR cam, ADDR delta_time
        invoke window_mode, 3
        mov ebx, eax

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR s

        invoke bind_texture, 0, floor_texture
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model

        ; the cubes with this mode's culling
        lea rax, cull_states
        mov rax, [rax + rbx * 8]
        vcall context, ID3D11DeviceContext_RSSetState, rax
        invoke bind_texture, 0, cube_texture
        invoke m4_translate, ADDR model, ADDR cube_a
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
        invoke m4_translate, ADDR model, ADDR cube_b
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
        vcall context, ID3D11DeviceContext_RSSetState, raster_state

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
