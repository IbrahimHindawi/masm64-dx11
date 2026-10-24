;---------------------------------------------------------------------------------------------------
; 9. SSAO
;---------------------------------------------------------------------------------------------------
; Ambient light is a constant, so creases, corners and the gap under an object get just as much of
; it as an open floor. Ambient occlusion darkens the places the sky cannot reach; screen-space
; ambient occlusion estimates that from the G-buffer alone, after the geometry is drawn:
;
;   1. geometry pass  positions and normals in view space
;   2. SSAO pass      for each pixel, 64 random points in a small hemisphere around its normal.
;                     Each point is projected to the screen and compared with the depth stored
;                     there: if the G-buffer has something in front of it, that point is buried,
;                     and the pixel is a little occluded
;   3. blur           the kernel is rotated per pixel by a tiled 4x4 noise texture, which trades
;                     banding for noise; a 4x4 average removes the noise
;   4. lighting       as 8.1, with the ambient term scaled by the result
;
;   Tab   lit with SSAO / SSAO alone / lit without
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
include learn\model.asm
include learn\srgb.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
kernel_size equ 64

; Mirror the cbuffers of ssao.hlsl, ssao_lighting.hlsl and ssao_geometry.hlsl.
ssao_constants struct
    kernel vec4 kernel_size dup(<>)     ; points in a hemisphere around +z, in tangent space
ssao_constants ends

lighting_constants struct
    light_position vec3 <>              ; view space
    mode dword ?
lighting_constants ends

surface_constants struct
    flip_normals real4 ?
    pad real4 3 dup(?)
surface_constants ends

align 4
camera_start vec3 <0.0, 2.0, 5.0>
room_center vec3 <0.0, 7.0, 0.0>
room_size vec3 <15.0, 15.0, 15.0>
x_axis vec3 <1.0, 0.0, 0.0>

align 16
t transforms <>
kernel ssao_constants <>
lit lighting_constants <>
surface surface_constants <>
noise_pixels vec4 16 dup(<>)
world_light vec4 <2.0, 4.0, -2.0, 1.0>
view_light vec4 <>
room mat4 <>
lying mat4 <>
scratch mat4 <>
geometry_shader shader <>
ssao_shader shader <>
blur_shader shader <>
lighting_shader shader <>
cam camera <>
backpack model <>
positions render_target <>
normals render_target <>
occlusion render_target <>
smoothed render_target <>
align 8
g_targets qword 2 dup(0)
g_views qword 3 dup(0)
l_views qword 3 dup(0)
g_depth qword 0
noise qword 0
cube_vb qword 0
transforms_buffer qword 0
ssao_buffer qword 0
lighting_buffer qword 0
surface_buffer qword 0
sampler qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; -> xmm0: (rand() % 10000) / 10000, in 0..1
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

; -> xmm0: random01() * 2 - 1, in -1..1
align 16
random_signed proc
    call random01
    addss xmm0, xmm0
    subss xmm0, math_one
    ret
random_signed endp

; Fills the kernel and the noise. The rin original draws v3(random(), random(), random()), whose
; arguments its compiler (clang-cl, like MSVC) evaluates right to left, so z comes first; the same
; order here gives the same points.
align 16
make_samples proc
    local p:vec3, k:real4
    USING rbx, rsi
    SaveRegs
    ; generate sample kernel: more points close to the centre, where occlusion matters
    ; --------------------------------------------------------------------------------
    invoke srand, 3
    lea rsi, kernel.kernel
    xor ebx, ebx
    points:
        call random01
        movss p.z, xmm0
        call random_signed
        movss p.y, xmm0
        call random_signed
        movss p.x, xmm0
        lea rcx, p
        mov rdx, rcx
        call v3_normalize
        ; scale = i / 64, then p *= random01() * lerp(0.1, 1, scale^2)
        cvtsi2ss xmm0, ebx
        movf xmm1, 64.0
        divss xmm0, xmm1
        mulss xmm0, xmm0
        movf xmm1, 0.9
        mulss xmm0, xmm1
        movf xmm1, 0.1
        addss xmm0, xmm1
        movss k, xmm0
        call random01
        mulss xmm0, k
        movaps xmm2, xmm0
        mov rcx, rsi
        lea rdx, p
        call v3_scale
        mov dword ptr [rsi + 12], 0
        add rsi, sizeof vec4
        inc ebx
        cmp ebx, kernel_size
        jb points

    ; generate noise texture: sixteen random rotations about z, tiled over the screen
    ; -------------------------------------------------------------------------------
    lea rsi, noise_pixels
    xor ebx, ebx
    rotations:
        call random_signed
        movss [rsi].vec4.y, xmm0
        call random_signed
        movss [rsi].vec4.x, xmm0
        mov dword ptr [rsi].vec4.z, 0
        mov dword ptr [rsi].vec4.w, 0
        add rsi, sizeof vec4
        inc ebx
        cmp ebx, 16
        jb rotations
    RestoreRegs
    ret
make_samples endp

align 16
main proc
    local noise_desc:D3D11_TEXTURE2D_DESC, noise_init:D3D11_SUBRESOURCE_DATA, noise_texture:qword
    invoke window_create, "LearnD3D11  (Tab: lit with ssao / ssao / lit without)"
    ; The back buffer is viewed as sRGB: what the shaders write is linear, and the view
    ; gamma-encodes it on the way in (5.2).
    call window_use_srgb
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR geometry_shader, "src/5.advanced_lighting/9.ssao/ssao_geometry.hlsl", ADDR model_layout, model_layout_count
    invoke shader_create, ADDR ssao_shader, "src/5.advanced_lighting/9.ssao/ssao.hlsl", 0, 0
    invoke shader_create, ADDR blur_shader, "src/5.advanced_lighting/9.ssao/ssao_blur.hlsl", 0, 0
    invoke shader_create, ADDR lighting_shader, "src/5.advanced_lighting/9.ssao/ssao_lighting.hlsl", 0, 0

    ; load models
    ; -----------
    invoke model_load, ADDR backpack, "resources/objects/backpack/", "backpack.obj", 0
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof ssao_constants
    mov ssao_buffer, rax
    invoke create_constant_buffer, sizeof lighting_constants
    mov lighting_buffer, rax
    invoke create_constant_buffer, sizeof surface_constants
    mov surface_buffer, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, -15.0
    call camera_create

    ; configure g-buffer and ssao framebuffers
    ; ----------------------------------------
    invoke create_render_target, ADDR positions, scr_width, scr_height, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    invoke create_render_target, ADDR normals, scr_width, scr_height, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    invoke create_render_target, ADDR occlusion, scr_width, scr_height, DXGI_FORMAT_R16_FLOAT, 1
    invoke create_render_target, ADDR smoothed, scr_width, scr_height, DXGI_FORMAT_R16_FLOAT, 1
    invoke create_depth_buffer, scr_width, scr_height, 1
    mov g_depth, rax

    call make_samples
    invoke update_buffer, ssao_buffer, ADDR kernel, sizeof ssao_constants
    ; the noise as a 4x4 float texture
    invoke mem_zero, ADDR noise_desc, sizeof D3D11_TEXTURE2D_DESC
    mov noise_desc._Width, 4
    mov noise_desc.Height, 4
    mov noise_desc.MipLevels, 1
    mov noise_desc.ArraySize, 1
    mov noise_desc.Format, DXGI_FORMAT_R32G32B32A32_FLOAT
    mov noise_desc.SampleDesc.Count, 1
    mov noise_desc.BindFlags, D3D11_BIND_SHADER_RESOURCE
    invoke mem_zero, ADDR noise_init, sizeof D3D11_SUBRESOURCE_DATA
    lea rax, noise_pixels
    mov noise_init.pSysMem, rax
    mov noise_init.SysMemPitch, 4 * sizeof vec4
    vcall device, ID3D11Device_CreateTexture2D, ADDR noise_desc, ADDR noise_init, ADDR noise_texture
    AssertHr
    vcall device, ID3D11Device_CreateShaderResourceView, noise_texture, 0, ADDR noise

    ; the views each pass binds
    mov rax, positions.rtv
    mov g_targets[0], rax
    mov rax, normals.rtv
    mov g_targets[8], rax
    mov rax, positions.srv
    mov g_views[0], rax
    mov l_views[0], rax
    mov rax, normals.srv
    mov g_views[8], rax
    mov l_views[8], rax
    mov rax, noise
    mov g_views[16], rax
    mov rax, smoothed.srv
    mov l_views[16], rax

    ; the room: a big cube seen from inside; the backpack: lying on its back
    invoke m4_translate, ADDR room, ADDR room_center
    invoke m4_scale, ADDR scratch, ADDR room_size
    invoke m4_mul, ADDR room, ADDR room, ADDR scratch
    movf xmm0, -90.0
    call radians
    movaps xmm1, xmm0
    lea rcx, lying
    lea r8, x_axis
    call m4_rotate

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
        mov lit.mode, eax

        ; 1. geometry pass: render scene's geometry/colour data into the g-buffer
        ; -----------------------------------------------------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 2, ADDR g_targets, g_depth
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, positions.rtv, floats(0.0, 0.0, 0.0, 0.0)
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, normals.rtv, floats(0.0, 0.0, 0.0, 0.0)
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, g_depth, D3D11_CLEAR_DEPTH, 0, 0
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR geometry_shader
        invoke bind_constants, 1, surface_buffer
        storef surface.flip_normals, -1.0
        invoke update_buffer, surface_buffer, ADDR surface, sizeof surface_constants
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR room
        storef surface.flip_normals, 1.0
        invoke update_buffer, surface_buffer, ADDR surface, sizeof surface_constants
        invoke mem_copy, ADDR t.model, ADDR lying, sizeof mat4
        invoke m4_normal_matrix, ADDR t.normal_matrix, ADDR lying
        invoke update_buffer, transforms_buffer, ADDR t, sizeof transforms
        invoke model_draw, ADDR backpack

        ; 2. generate SSAO texture
        ; ------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR occlusion.rtv, 0
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, occlusion.rtv, floats(1.0, 1.0, 1.0, 1.0)
        invoke shader_use, ADDR ssao_shader
        invoke bind_constants, 1, ssao_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 3, ADDR g_views
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        ; 3. blur SSAO texture to remove noise
        ; ------------------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR smoothed.rtv, 0
        invoke shader_use, ADDR blur_shader
        invoke bind_texture, 0, occlusion.srv
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        ; 4. lighting pass: Blinn-Phong in view space, ambient scaled by the occlusion
        ; ----------------------------------------------------------------------------
        call unbind_textures
        invoke window_begin, floats(0.0, 0.0, 0.0, 1.0)
        invoke m4_mul_v4, ADDR view_light, ADDR t.view, ADDR world_light
        v3load xmm0, view_light
        v3store lit.light_position, xmm0
        invoke update_buffer, lighting_buffer, ADDR lit, sizeof lighting_constants
        invoke shader_use, ADDR lighting_shader
        invoke bind_constants, 1, lighting_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 3, ADDR l_views
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
