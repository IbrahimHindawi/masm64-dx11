;---------------------------------------------------------------------------------------------------
; 10.1 Instancing
;---------------------------------------------------------------------------------------------------
; Drawing the same mesh many times, each copy placed differently, in one draw call. Twenty
; thousand rocks orbit a planet here; drawn one by one that would be twenty thousand draws, each
; with its own constant buffer update.
;
; Instead every rock's model matrix goes into one more vertex buffer, marked PER_INSTANCE_DATA in
; the input layout. The rock's own vertices are read per vertex as usual; the matrix advances once
; per copy. DrawInstanced says how many copies to make.
;
; A mat4 does not fit one input element (at most four floats), so it is sent as four:
; INSTANCE0..3, one row each, put back together in the shader.
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm
include learn\camera.asm
include learn\transforms.asm
include learn\model.asm

amount equ 20000

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
semantic_instance byte "INSTANCE", 0
align 8
instance_layout D3D11_INPUT_ELEMENT_DESC <offset model_semantic_position, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>
                D3D11_INPUT_ELEMENT_DESC <offset model_semantic_normal, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0>
                D3D11_INPUT_ELEMENT_DESC <offset model_semantic_texcoord, 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D11_INPUT_PER_VERTEX_DATA, 0>
                D3D11_INPUT_ELEMENT_DESC <offset semantic_instance, 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 0, D3D11_INPUT_PER_INSTANCE_DATA, 1>
                D3D11_INPUT_ELEMENT_DESC <offset semantic_instance, 1, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 16, D3D11_INPUT_PER_INSTANCE_DATA, 1>
                D3D11_INPUT_ELEMENT_DESC <offset semantic_instance, 2, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 32, D3D11_INPUT_PER_INSTANCE_DATA, 1>
                D3D11_INPUT_ELEMENT_DESC <offset semantic_instance, 3, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 48, D3D11_INPUT_PER_INSTANCE_DATA, 1>

align 4
camera_start vec3 <0.0, 12.0, 70.0>
y_axis vec3 <0.0, 1.0, 0.0>
spin_axis vec3 <0.4, 0.6, 0.8>
planet_scale vec3 <4.0, 4.0, 4.0>

align 16
t transforms <>
spin mat4 <>
scale_ mat4 <>
place vec3 <>
planet_shader shader <>
rock_shader shader <>
cam camera <>
planet model <>
rock model <>
align 8
matrices qword 0                ; amount mat4, one per rock
instance_buffer qword 0
transforms_buffer qword 0
sampler qword 0
rock_buffers qword 2 dup(0)
rock_strides dword sizeof model_vertex, sizeof mat4
rock_offsets dword 0, 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; -> xmm0: a random number in 0..1, in steps of 1 / 10000
align 16
random01 proc
    call rand
    xor edx, edx
    mov ecx, 10000
    div ecx
    cvtsi2ss xmm0, edx
    movf xmm1, 10000.0
    divss xmm0, xmm1
    ret
random01 endp

; -> xmm0: a random number in -1..1
align 16
random_signed proc
    call random01
    addss xmm0, xmm0
    subss xmm0, math_one
    ret
random_signed endp

; Each rock: somewhere on a ring of radius 45, scattered by up to 6 across and 1.8 up and down,
; scaled 0.05..0.25 and turned at random.
align 16
place_rocks proc
    local angle:real4, rock_scale:real4
    USING rbx, rsi
    SaveRegs
    invoke srand, 7
    mov rsi, matrices
    xor ebx, ebx
    rocks:
        ; angle = i / amount * 2 * pi
        cvtsi2ss xmm0, ebx
        movf xmm1, 20000.0
        divss xmm0, xmm1
        addss xmm0, xmm0
        mulss xmm0, math_pi
        movss angle, xmm0
        ; x = sin(angle) * 45 + (random * 2 - 1) * 6
        call sinf
        movf xmm1, 45.0
        mulss xmm0, xmm1
        movss place.x, xmm0
        call random_signed
        movf xmm1, 6.0
        mulss xmm0, xmm1
        addss xmm0, place.x
        movss place.x, xmm0
        ; y = (random * 2 - 1) * 6 * 0.3
        call random_signed
        movf xmm1, 6.0
        mulss xmm0, xmm1
        movf xmm1, 0.3
        mulss xmm0, xmm1
        movss place.y, xmm0
        ; z = cos(angle) * 45 + (random * 2 - 1) * 6
        movss xmm0, angle
        call cosf
        movf xmm1, 45.0
        mulss xmm0, xmm1
        movss place.z, xmm0
        call random_signed
        movf xmm1, 6.0
        mulss xmm0, xmm1
        addss xmm0, place.z
        movss place.z, xmm0
        ; scale = 0.05 + random * 0.2
        call random01
        movf xmm1, 0.2
        mulss xmm0, xmm1
        movf xmm1, 0.05
        addss xmm0, xmm1
        movss rock_scale, xmm0
        ; spin = rotate(random * 2 * pi, (0.4, 0.6, 0.8))
        call random01
        addss xmm0, xmm0
        mulss xmm0, math_pi
        movaps xmm1, xmm0
        lea rcx, spin
        lea r8, spin_axis
        call m4_rotate
        ; matrices[i] = translate(x, y, z) * spin * scale
        invoke m4_identity, ADDR scale_
        movss xmm0, rock_scale
        movss scale_.m[0], xmm0
        movss scale_.m[20], xmm0
        movss scale_.m[40], xmm0
        invoke m4_mul, ADDR spin, ADDR spin, ADDR scale_
        invoke m4_translate, rsi, ADDR place
        invoke m4_mul, rsi, rsi, ADDR spin
        add rsi, sizeof mat4
        inc ebx
        cmp ebx, amount
        jb rocks
    RestoreRegs
    ret
place_rocks endp

align 16
main proc
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    invoke shader_create, ADDR planet_shader, "src/4.advanced_d3d11/10.1.instancing/planet.hlsl", ADDR model_layout, model_layout_count
    invoke shader_create, ADDR rock_shader, "src/4.advanced_d3d11/10.1.instancing/asteroids.hlsl", ADDR instance_layout, 7
    ; these two .obj files expect v up the image, so v is flipped
    invoke model_load, ADDR planet, "resources/objects/planet/", "planet.obj", 1
    invoke model_load, ADDR rock, "resources/objects/rock/", "rock.obj", 1
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, -10.0
    call camera_create
    storef cam.speed, 15.0
    storef cam.zoom, 50.0

    ; every rock's matrix, in one vertex buffer read once per instance
    invoke arenaPush, ADDR arena, amount * sizeof mat4, 16
    mov matrices, rax
    call place_rocks
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, matrices, amount * sizeof mat4
    mov instance_buffer, rax
    mov rax, rock.vertices
    mov rock_buffers[0], rax
    mov rax, instance_buffer
    mov rock_buffers[8], rax

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

        invoke window_begin, floats(0.02, 0.02, 0.03, 1.0)
        ; the ring is large: depth out to 500
        invoke camera_view, ADDR t.view, ADDR cam
        movf xmm0, 500.0
        movss real4 ptr [rsp + 32], xmm0
        movss xmm0, cam.zoom
        call radians
        movaps xmm1, xmm0
        cvtsi2ss xmm2, scr_width
        cvtsi2ss xmm0, scr_height
        divss xmm2, xmm0
        movf xmm3, 0.1
        lea rcx, t.projection
        call m4_perspective
        v3load xmm0, cam.position
        v3store t.view_position, xmm0
        invoke bind_constants, 0, transforms_buffer

        ; the planet: turning slowly, four times its size
        movss xmm1, current_frame
        movf xmm0, 0.1
        mulss xmm1, xmm0
        lea rcx, spin
        lea r8, y_axis
        call m4_rotate
        invoke m4_scale, ADDR scale_, ADDR planet_scale
        invoke m4_mul, ADDR t.model, ADDR spin, ADDR scale_
        invoke m4_normal_matrix, ADDR t.normal_matrix, ADDR t.model
        invoke update_buffer, transforms_buffer, ADDR t, sizeof transforms
        invoke shader_use, ADDR planet_shader
        invoke model_draw, ADDR planet

        ; the rocks: one draw, the whole ring turning slower still
        movss xmm1, current_frame
        movf xmm0, 0.02
        mulss xmm1, xmm0
        lea rcx, t.model
        lea r8, y_axis
        call m4_rotate
        invoke update_buffer, transforms_buffer, ADDR t, sizeof transforms
        invoke shader_use, ADDR rock_shader
        ; rock.mtl names its only texture as map_Bump, so that is the one to show
        invoke bind_texture, 0, rock.normal
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 2, ADDR rock_buffers, ADDR rock_strides, ADDR rock_offsets
        vcall context, ID3D11DeviceContext_DrawInstanced, rock.vertex_count, amount, 0, 0

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
