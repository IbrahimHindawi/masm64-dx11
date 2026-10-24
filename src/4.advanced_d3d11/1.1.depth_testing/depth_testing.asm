;---------------------------------------------------------------------------------------------------
; 1.1 Depth testing
;---------------------------------------------------------------------------------------------------
; The depth buffer holds, per pixel, how far away the nearest surface drawn so far is. Each new
; pixel is compared against it (here: keep it if LESS) and either replaces it or is thrown away.
; That is what has quietly been making the cubes hide each other since 1.6.1 coordinate systems;
; D3D has the test on by default.
;
; Tab shows the depth itself. It is not linear: perspective spends most of the 0..1 range just in
; front of the camera, so nearly everything reads as white. Undoing the projection gives the real
; distance, the third view. D3D's depth runs 0..1 where GL's runs -1..1, so the formula differs
; from LearnOpenGL's by that remapping.
;
;   Tab   textured / raw depth / linear depth
;
; From this chapter on, draw_vertices (includes/learn/transforms.asm) draws any vertex buffer of
; position-normal-uv vertices with a model matrix, and bind_texture puts one texture in a register.
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
; A floor: two triangles at y = -0.5, the texture repeated twice across.
align 4
plane_vertices real4 -5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   0.0, 2.0
               real4  5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   2.0, 2.0
               real4  5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   2.0, 0.0
               real4 -5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   0.0, 2.0
               real4  5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   2.0, 0.0
               real4 -5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   0.0, 0.0
plane_vertices_size equ 6 * 32

; Mirrors `cbuffer view_mode` in depth_testing.hlsl.
view_constants struct
    mode dword ?            ; 0 textured, 1 raw depth, 2 linear depth
    near_plane real4 ?
    far_plane real4 ?
    pad real4 ?
view_constants ends

align 4
camera_start vec3 <-1.0, 1.0, 4.0>
cube_a vec3 <-1.0, 0.0, -1.0>
cube_b vec3 <2.0, 0.0, 0.0>

align 16
t transforms <>
v view_constants <0, 0.1, 100.0, 0.0>
model mat4 <>
s shader <>
cam camera <>
align 8
cube_vb qword 0
plane_vb qword 0
transforms_buffer qword 0
view_buffer qword 0
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
    invoke window_create, "LearnD3D11"
    call window_create_depth
    invoke window_mode_default, 2

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    invoke shader_create, ADDR s, "src/4.advanced_d3d11/1.1.depth_testing/depth_testing.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof view_constants
    mov view_buffer, rax
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
        mov v.mode, eax

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke update_buffer, view_buffer, ADDR v, sizeof view_constants
        invoke shader_use, ADDR s
        invoke bind_constants, 1, view_buffer

        ; the floor, then two cubes on it
        invoke bind_texture, 0, floor_texture
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model
        invoke bind_texture, 0, cube_texture
        invoke m4_translate, ADDR model, ADDR cube_a
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
        invoke m4_translate, ADDR model, ADDR cube_b
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
