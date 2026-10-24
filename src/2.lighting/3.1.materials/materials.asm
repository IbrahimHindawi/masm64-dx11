;---------------------------------------------------------------------------------------------------
; 3.1 Materials
;---------------------------------------------------------------------------------------------------
; The three Phong terms get their own colours, on both sides:
;
;   material   how much ambient, diffuse and specular light the surface reflects, and how tight
;              its highlight is (shininess)
;   light      how much of each the light gives out
;
; Each term is light * material. The light's colour drifts over time, which shows the split: the
; highlight takes the light's colour, the body takes the product of the two.
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
; Mirror `cbuffer material` and `cbuffer light` in materials.hlsl.
material_constants struct
    ambient vec3 <>
    pad0 real4 ?
    diffuse vec3 <>
    pad1 real4 ?
    specular vec3 <>
    shininess real4 ?
material_constants ends

light_constants struct
    position vec3 <>
    pad0 real4 ?
    ambient vec3 <>
    pad1 real4 ?
    diffuse vec3 <>
    pad2 real4 ?
    specular vec3 <>
    pad3 real4 ?
light_constants ends

align 4
camera_start vec3 <-1.0, 1.0, 4.0>

align 16
t transforms <>
material material_constants <<1.0, 0.5, 0.31>, 0.0, <1.0, 0.5, 0.31>, 0.0, <0.5, 0.5, 0.5>, 32.0>
light light_constants <<1.2, 1.0, 2.0>, 0.0, <>, 0.0, <>, 0.0, <1.0, 1.0, 1.0>, 0.0>
lamp_color vec4 <0.0, 0.0, 0.0, 1.0>
model mat4 <>
lighting_shader shader <>
lamp_shader shader <>
cam camera <>
align 8
cube_vb qword 0
transforms_buffer qword 0
material_buffer qword 0
light_buffer qword 0
lamp_buffer qword 0
stride dword cube_stride
offset_ dword 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; xmm0: time, xmm1: rate -> xmm0: sin(time * rate) / 2 + 0.5, a colour channel drifting in 0..1
align 16
drift proc
    mulss xmm0, xmm1
    call sinf
    mulss xmm0, math_half
    addss xmm0, math_half
    ret
drift endp

align 16
main proc
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke shader_create, ADDR lighting_shader, "src/2.lighting/3.1.materials/materials.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/2.lighting/3.1.materials/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof material_constants
    mov material_buffer, rax
    invoke create_constant_buffer, sizeof light_constants
    mov light_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax
    ; the material never changes
    invoke update_buffer, material_buffer, ADDR material, sizeof material_constants

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -75.0
    movf xmm3, -10.0
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

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR cube_vb, ADDR stride, ADDR offset_
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; the light's colour: each channel drifts at its own rate
        movss xmm0, current_frame
        movf xmm1, 2.0
        call drift
        movss lamp_color.x, xmm0
        movss xmm0, current_frame
        movf xmm1, 0.7
        call drift
        movss lamp_color.y, xmm0
        movss xmm0, current_frame
        movf xmm1, 1.3
        call drift
        movss lamp_color.z, xmm0
        ; diffuse = colour / 2, ambient = diffuse / 5
        lea rcx, light.diffuse
        lea rdx, lamp_color
        movss xmm2, math_half
        call v3_scale
        lea rcx, light.ambient
        lea rdx, light.diffuse
        movf xmm2, 0.2
        call v3_scale
        invoke update_buffer, light_buffer, ADDR light, sizeof light_constants

        invoke shader_use, ADDR lighting_shader
        invoke bind_constants, 1, material_buffer
        invoke bind_constants, 2, light_buffer
        invoke m4_identity, ADDR model
        invoke draw_cube, transforms_buffer, ADDR t, ADDR model

        invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rcx, model
        lea rdx, light.position
        movf xmm2, 0.2
        call m4_translate_scale
        invoke draw_cube, transforms_buffer, ADDR t, ADDR model

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
