;---------------------------------------------------------------------------------------------------
; 1. Advanced lighting: Blinn-Phong
;---------------------------------------------------------------------------------------------------
; Phong's highlight compares the eye direction with the light's reflection. When they are more
; than 90 degrees apart the dot product goes negative, is clamped to zero, and the highlight is cut
; off with a hard edge. That shows most on rough surfaces, whose highlights are wide: here a wooden
; floor, seen low, from the light's own height.
;
; Blinn's fix compares the normal with the halfway vector, the direction between "to the light"
; and "to the eye". The angle between those never passes 90 degrees for a visible surface, so the
; highlight fades out smoothly. It needs a higher exponent for the same size of highlight.
;
;   Tab   Blinn-Phong / Phong
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
; A wide wooden floor at y = -0.5, the texture repeated ten times across.
align 4
plane_vertices label byte
    real4 -10.0, -0.5,  10.0,   0.0, 1.0, 0.0,    0.0, 10.0
    real4  10.0, -0.5,  10.0,   0.0, 1.0, 0.0,   10.0, 10.0
    real4  10.0, -0.5, -10.0,   0.0, 1.0, 0.0,   10.0,  0.0
    real4 -10.0, -0.5,  10.0,   0.0, 1.0, 0.0,    0.0, 10.0
    real4  10.0, -0.5, -10.0,   0.0, 1.0, 0.0,   10.0,  0.0
    real4 -10.0, -0.5, -10.0,   0.0, 1.0, 0.0,    0.0,  0.0
plane_vertices_size equ 6 * 32

; Mirrors `cbuffer light` in advanced_lighting.hlsl.
light_constants struct
    position vec3 <>
    blinn dword ?
light_constants ends

align 4
camera_start vec3 <0.0, 0.0, 3.0>

align 16
t transforms <>
light light_constants <<0.0, 0.0, 0.0>, 1>
lamp_color vec4 <1.0, 1.0, 1.0, 1.0>
model mat4 <>
s shader <>
lamp_shader shader <>
cam camera <>
align 8
cube_vb qword 0
plane_vb qword 0
transforms_buffer qword 0
light_buffer qword 0
lamp_buffer qword 0
wood qword 0
sampler qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11  (Tab: blinn-phong / phong)"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/5.advanced_lighting/1.advanced_lighting/advanced_lighting.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/5.advanced_lighting/1.advanced_lighting/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof light_constants
    mov light_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax
    invoke filesystem_path, "resources/textures/wood.png"
    invoke load_texture, rax, 0
    mov wood, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, 0.0
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
        ; mode 0 is Blinn-Phong, mode 1 plain Phong
        invoke window_mode, 2
        mov ecx, 1
        sub ecx, eax
        mov light.blinn, ecx

        invoke window_begin, floats(0.0, 0.0, 0.0, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; the floor, lit from the origin
        invoke update_buffer, light_buffer, ADDR light, sizeof light_constants
        invoke shader_use, ADDR s
        invoke bind_constants, 1, light_buffer
        invoke bind_texture, 0, wood
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model

        ; the lamp, a tiny cube where the light is
        invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rcx, model
        lea rdx, light.position
        movf xmm2, 0.1
        call m4_translate_scale
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
