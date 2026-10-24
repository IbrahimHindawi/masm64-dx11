;---------------------------------------------------------------------------------------------------
; 2.1 Basic lighting
;---------------------------------------------------------------------------------------------------
; The Phong model: light reflected by a surface, as the sum of three parts.
;
;   ambient   a little light from everywhere, so nothing is pitch black
;   diffuse   brightest where the surface faces the light: dot(normal, to_light)
;   specular  a highlight where the light bounces straight at the eye
;
; All three need the surface's normal and position in one space; here that is world space. Normals
; are moved there by the normal matrix, the inverse transpose of the model matrix, so a stretched
; object does not get bent normals. HLSL has no inverse(), so draw_cube computes it on the CPU and
; sends it with every draw. The light circles the cube.
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
; Mirrors `cbuffer light` in basic_lighting.hlsl.
light_constants struct
    object_color vec3 <>
    pad0 real4 ?
    light_color vec3 <>
    pad1 real4 ?
    light_position vec3 <>
    pad2 real4 ?
light_constants ends

align 4
camera_start vec3 <-1.0, 1.0, 4.0>

align 16
t transforms <>
light light_constants <<1.0, 0.5, 0.31>, 0.0, <1.0, 1.0, 1.0>, 0.0, <>, 0.0>
lamp_color vec4 <1.0, 1.0, 1.0, 1.0>
model mat4 <>
lighting_shader shader <>
lamp_shader shader <>
cam camera <>
align 8
cube_vb qword 0
transforms_buffer qword 0
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
align 16
main proc
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke shader_create, ADDR lighting_shader, "src/2.lighting/2.1.basic_lighting/basic_lighting.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/2.lighting/2.1.basic_lighting/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof light_constants
    mov light_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -75.0
    movf xmm3, -10.0
    call camera_create

    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        ; per-frame time logic
        call get_time
        movss current_frame, xmm0
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        invoke camera_process_input, ADDR cam, ADDR delta_time

        ; render
        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR cube_vb, ADDR stride, ADDR offset_
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; the light circles the cube: (2 cos t, 1, 2 sin t)
        movss xmm0, current_frame
        call cosf
        addss xmm0, xmm0
        movss light.light_position.x, xmm0
        storef light.light_position.y, 1.0
        movss xmm0, current_frame
        call sinf
        addss xmm0, xmm0
        movss light.light_position.z, xmm0
        invoke update_buffer, light_buffer, ADDR light, sizeof light_constants
        invoke shader_use, ADDR lighting_shader
        invoke bind_constants, 1, light_buffer
        invoke m4_identity, ADDR model
        invoke draw_cube, transforms_buffer, ADDR t, ADDR model

        invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rcx, model
        lea rdx, light.light_position
        movf xmm2, 0.2
        call m4_translate_scale
        invoke draw_cube, transforms_buffer, ADDR t, ADDR model

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
