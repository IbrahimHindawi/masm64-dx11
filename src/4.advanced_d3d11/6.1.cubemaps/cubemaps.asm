;---------------------------------------------------------------------------------------------------
; 6.1 Cubemaps
;---------------------------------------------------------------------------------------------------
; A cubemap is six images on the inside of a cube, read by direction rather than by uv: give it a
; vector and it returns what you would see looking that way from the cube's centre. Two uses:
;
;   skybox      a cube around the camera, textured with the sky. Drawn without the view's
;               translation, so it turns with the camera but can never be reached. Its depth is
;               forced to the far plane (z = w), so it only fills what nothing else covered
;   reflection  each pixel of an object looks up the sky in the direction the eye ray bounces off
;               it. Refraction bends the ray instead, by the ratio of the two materials' indices
;               (air to glass)
;
; In D3D a cubemap is a texture array of six slices with the TEXTURECUBE flag, faces in the same
; order as GL: +x, -x, +y, -y, +z, -z. load_cubemap (includes/learn/gpu.asm) makes one.
;
;   Tab   reflect / refract
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
; Mirrors `cbuffer env` in cubemaps.hlsl.
env_constants struct
    refract_mode dword ?
    pad dword 3 dup(?)
env_constants ends

align 4
camera_start vec3 <0.0, 0.5, 4.0>
cube_position vec3 <-1.0, 0.0, 0.0>
sphere_position vec3 <1.2, 0.0, 0.0>
y_axis vec3 <0.0, 1.0, 0.0>
; each quad of the sphere: six corners as (x, y) steps, two counter-clockwise triangles
sphere_corners dword 0, 0,  1, 0,  1, 1,  0, 0,  1, 1,  0, 1

face_right byte "resources/textures/skybox/right.jpg", 0
face_left byte "resources/textures/skybox/left.jpg", 0
face_top byte "resources/textures/skybox/top.jpg", 0
face_bottom byte "resources/textures/skybox/bottom.jpg", 0
face_front byte "resources/textures/skybox/front.jpg", 0
face_back byte "resources/textures/skybox/back.jpg", 0
align 8
face_names qword face_right, face_left, face_top, face_bottom, face_front, face_back
faces qword 6 dup(0)            ; the same, as full paths

align 16
t transforms <>
env env_constants <>
model mat4 <>
rotation mat4 <>
s shader <>
skybox_shader shader <>
cam camera <>
align 8
cube_vb qword 0
sphere_vb qword 0
sphere_count qword 0
transforms_buffer qword 0
env_buffer qword 0
skybox qword 0
sampler qword 0
sky_depth qword 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; rcx: segments -> rax: a vertex buffer of a unit sphere, rdx: its vertex count
;
; A grid of segments x segments quads wrapped around: u goes round the equator, v from the north
; pole (v = 0) to the south. Position and normal are the same point on the unit sphere.
align 16
create_sphere proc segments:qword
    local u:real4, v:real4, sin_v:real4, vertex_count:qword, vertices:qword
    USING rbx, rsi, rdi, r12, r13
    SaveRegs
    mov eax, dword ptr segments
    imul eax, eax
    imul eax, 6
    mov vertex_count, rax
    shl rax, 5                                  ; 32 bytes a vertex
    invoke arenaPush, ADDR arena, rax, 16
    mov vertices, rax
    mov rdi, rax                                ; the next vertex
    xor r12d, r12d                              ; y
    stacks:
        xor r13d, r13d                          ; x
        slices:
            lea rsi, sphere_corners
            xor ebx, ebx
            corners:
                ; u = (x + dx) / segments, v = (y + dy) / segments
                mov eax, [rsi + rbx * 8]
                add eax, r13d
                cvtsi2ss xmm0, eax
                cvtsi2ss xmm1, dword ptr segments
                divss xmm0, xmm1
                movss u, xmm0
                mov eax, [rsi + rbx * 8 + 4]
                add eax, r12d
                cvtsi2ss xmm0, eax
                divss xmm0, xmm1
                movss v, xmm0
                ; p = (cos(2 pi u) sin(pi v), cos(pi v), sin(2 pi u) sin(pi v))
                mulss xmm0, math_pi
                call sinf
                movss sin_v, xmm0
                movss xmm0, v
                mulss xmm0, math_pi
                call cosf
                movss real4 ptr [rdi + 4], xmm0
                movss real4 ptr [rdi + 16], xmm0
                movss xmm0, u
                addss xmm0, xmm0
                mulss xmm0, math_pi
                call cosf
                mulss xmm0, sin_v
                movss real4 ptr [rdi + 0], xmm0
                movss real4 ptr [rdi + 12], xmm0
                movss xmm0, u
                addss xmm0, xmm0
                mulss xmm0, math_pi
                call sinf
                mulss xmm0, sin_v
                movss real4 ptr [rdi + 8], xmm0
                movss real4 ptr [rdi + 20], xmm0
                movss xmm0, u
                movss real4 ptr [rdi + 24], xmm0
                movss xmm0, v
                movss real4 ptr [rdi + 28], xmm0
                add rdi, 32
                inc ebx
                cmp ebx, 6
                jb corners
            inc r13d
            cmp r13d, dword ptr segments
            jb slices
        inc r12d
        cmp r12d, dword ptr segments
        jb stacks
    mov rax, vertex_count
    shl rax, 5
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, vertices, rax
    mov rdx, vertex_count
    RestoreRegs
    ret
create_sphere endp

align 16
main proc
    local depth_desc:D3D11_DEPTH_STENCIL_DESC
    USING rbx, rsi, rdi
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; The sky is drawn where the depth is still the far plane, and must not write depth itself.
    invoke mem_zero, ADDR depth_desc, sizeof D3D11_DEPTH_STENCIL_DESC
    mov depth_desc.DepthEnable, 1
    mov depth_desc.DepthWriteMask, D3D11_DEPTH_WRITE_MASK_ZERO
    mov depth_desc.DepthFunc, D3D11_COMPARISON_LESS_EQUAL
    vcall device, ID3D11Device_CreateDepthStencilState, ADDR depth_desc, ADDR sky_depth

    invoke shader_create, ADDR s, "src/4.advanced_d3d11/6.1.cubemaps/cubemaps.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR skybox_shader, "src/4.advanced_d3d11/6.1.cubemaps/skybox.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_sphere, 64
    mov sphere_vb, rax
    mov sphere_count, rdx
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof env_constants
    mov env_buffer, rax

    ; the six faces, +x, -x, +y, -y, +z, -z
    lea rsi, face_names
    lea rbx, faces
    lea rdi, faces + 6 * 8
    paths:
        invoke filesystem_path, qword ptr [rsi]
        mov [rbx], rax
        add rsi, 8
        add rbx, 8
        cmp rbx, rdi
        jb paths
    invoke load_cubemap, ADDR faces
    mov skybox, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, -5.0
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
        invoke window_mode, 2
        mov env.refract_mode, eax

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; a turning cube and a sphere, both mirrors (or glass) of the sky
        invoke update_buffer, env_buffer, ADDR env, sizeof env_constants
        invoke shader_use, ADDR s
        invoke bind_constants, 1, env_buffer
        invoke bind_texture, 0, skybox
        movss xmm1, current_frame
        mulss xmm1, math_half
        lea rcx, rotation
        lea r8, y_axis
        call m4_rotate
        invoke m4_translate, ADDR model, ADDR cube_position
        invoke m4_mul, ADDR model, ADDR model, ADDR rotation
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
        invoke m4_translate, ADDR model, ADDR sphere_position
        invoke draw_vertices, transforms_buffer, ADDR t, sphere_vb, sphere_count, ADDR model

        ; draw skybox as last, with the translation removed from the view matrix
        invoke m4_without_translation, ADDR t.view, ADDR t.view
        invoke shader_use, ADDR skybox_shader
        vcall context, ID3D11DeviceContext_OMSetDepthStencilState, sky_depth, 0
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
        vcall context, ID3D11DeviceContext_OMSetDepthStencilState, 0, 0

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
