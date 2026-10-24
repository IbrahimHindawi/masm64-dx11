;---------------------------------------------------------------------------------------------------
; shadow: depth textures to draw shadows into and read them back from
;---------------------------------------------------------------------------------------------------
; A shadow map is one typeless texture seen two ways: as a depth buffer (D32_FLOAT) while the
; light's view is drawn into it, and as a float texture (R32_FLOAT) while it is read.
;
;   create_shadow_map    a square map for a directional light (5.3.1 shadow mapping)
;   create_depth_cube    six of them as a cube, for a point light (5.3.2 point shadows)
;   cube_face_matrices   the six views of a cube's faces from one point (5.3.2 point shadows)
;   shadow_bias_state    a rasterizer that pushes depth away from the light, against shadow acne
ifndef shadow_asm
shadow_asm = 0

include macros.asm
include math.asm
include learn\window.asm

shadow_map struct
    dsv qword ?         ; ID3D11DepthStencilView, while drawing the light's view
    srv qword ?         ; ID3D11ShaderResourceView, while reading it
shadow_map ends

.code
; rcx: &shadow_map, rdx: size, r8: 1 for a cube of six faces, 0 for one square
align 16
create_shadow_texture proc out_ref:qword, map_size:qword, cube:qword
    local desc:D3D11_TEXTURE2D_DESC, texture:qword
    local dsv:D3D11_DEPTH_STENCIL_VIEW_DESC, srv:D3D11_SHADER_RESOURCE_VIEW_DESC
    USING rbx
    SaveRegs
    mov rbx, out_ref
    invoke mem_zero, ADDR desc, sizeof D3D11_TEXTURE2D_DESC
    mov eax, dword ptr map_size
    mov desc._Width, eax
    mov desc.Height, eax
    mov desc.MipLevels, 1
    mov desc.ArraySize, 1
    mov desc.Format, DXGI_FORMAT_R32_TYPELESS
    mov desc.SampleDesc.Count, 1
    mov desc.BindFlags, D3D11_BIND_DEPTH_STENCIL or D3D11_BIND_SHADER_RESOURCE
    cmp cube, 0
    je flat_texture
        mov desc.ArraySize, 6
        mov desc.MiscFlags, D3D11_RESOURCE_MISC_TEXTURECUBE
    flat_texture:
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, 0, ADDR texture
    AssertHr

    ; drawn into as depth: one view of all six faces for a cube, which the geometry shader picks
    ; between with SV_RenderTargetArrayIndex
    invoke mem_zero, ADDR dsv, sizeof D3D11_DEPTH_STENCIL_VIEW_DESC
    mov dsv.Format, DXGI_FORMAT_D32_FLOAT
    mov dsv.ViewDimension, D3D11_DSV_DIMENSION_TEXTURE2D
    cmp cube, 0
    je flat_dsv
        mov dsv.ViewDimension, D3D11_DSV_DIMENSION_TEXTURE2DARRAY
        mov dsv.Texture2DArray.ArraySize, 6
    flat_dsv:
    lea rax, [rbx].shadow_map.dsv
    vcall device, ID3D11Device_CreateDepthStencilView, texture, ADDR dsv, rax
    AssertHr

    ; read as one float a texel
    invoke mem_zero, ADDR srv, sizeof D3D11_SHADER_RESOURCE_VIEW_DESC
    mov srv.Format, DXGI_FORMAT_R32_FLOAT
    mov srv.ViewDimension, D3D11_SRV_DIMENSION_TEXTURE2D
    mov srv.Texture2D.MipLevels, 1
    cmp cube, 0
    je flat_srv
        mov srv.ViewDimension, D3D11_SRV_DIMENSION_TEXTURECUBE
        mov srv.TextureCube.MipLevels, 1
    flat_srv:
    lea rax, [rbx].shadow_map.srv
    vcall device, ID3D11Device_CreateShaderResourceView, texture, ADDR srv, rax
    AssertHr
    release texture
    RestoreRegs
    ret
create_shadow_texture endp

; rcx: &shadow_map, rdx: size in texels
align 16
create_shadow_map proc out_ref:qword, map_size:qword
    invoke create_shadow_texture, out_ref, map_size, 0
    ret
create_shadow_map endp

; rcx: &shadow_map, rdx: size of each face in texels
align 16
create_depth_cube proc out_ref:qword, map_size:qword
    invoke create_shadow_texture, out_ref, map_size, 1
    ret
create_depth_cube endp

; rcx: out (six mat4), rdx: center (vec3), xmm2: z_near, xmm3: z_far
;
; The view-projection of each cubemap face, seen from `center`, in the order +x, -x, +y, -y, +z, -z.
; A cubemap's faces are laid out left-handed, which a right-handed look-at cannot produce. GL's
; bottom-up framebuffer flips every rendered image and so fixes that for free; D3D's is top-down,
; so the face projection flips y instead. That flip reverses the winding, so culling stays off.
align 16
cube_face_matrices proc out_ref:qword, center:qword, z_near:qword, z_far:qword
    local projection:mat4, flip:mat4, face_view:mat4, target:vec3
    USING rbx, rsi, rdi
    SaveRegs
    movss real4 ptr z_near, xmm2
    movss real4 ptr z_far, xmm3
    ; projection = scale(1, -1, 1) * perspective(90 degrees, 1, near, far)
    movss xmm0, real4 ptr z_far
    movss real4 ptr [rsp + 32], xmm0
    movf xmm0, 90.0
    call radians
    movaps xmm1, xmm0
    movss xmm2, math_one
    movss xmm3, real4 ptr z_near
    lea rcx, projection
    call m4_perspective
    invoke m4_identity, ADDR flip
    mov dword ptr flip.m[20], 0BF800000h        ; -1
    invoke m4_mul, ADDR projection, ADDR flip, ADDR projection

    mov rdi, out_ref
    lea rsi, cube_face_directions
    xor ebx, ebx
    faces:
        ; look from the center along the face's direction, with the face's up
        mov rdx, center
        lea rcx, target
        lea r8, [rsi]
        call v3_add
        lea r9, [rsi + 12]
        invoke m4_look_at, ADDR face_view, center, ADDR target, r9
        invoke m4_mul, rdi, ADDR projection, ADDR face_view
        add rdi, sizeof mat4
        add rsi, 24
        inc ebx
        cmp ebx, 6
        jb faces
    RestoreRegs
    ret
cube_face_matrices endp

.const
; for each face: the direction it looks in, then its up
align 4
cube_face_directions real4  1.0,  0.0,  0.0,    0.0, -1.0,  0.0
                     real4 -1.0,  0.0,  0.0,    0.0, -1.0,  0.0
                     real4  0.0,  1.0,  0.0,    0.0,  0.0,  1.0
                     real4  0.0, -1.0,  0.0,    0.0,  0.0, -1.0
                     real4  0.0,  0.0,  1.0,    0.0, -1.0,  0.0
                     real4  0.0,  0.0, -1.0,    0.0, -1.0,  0.0
.code

; -> rax: ID3D11RasterizerState for shadow passes: GL's conventions, as the window's, with depth
; pushed away from the light, more on slopes seen at a grazing angle.
align 16
shadow_bias_state proc
    local desc:D3D11_RASTERIZER_DESC, state:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_RASTERIZER_DESC
    mov desc.FillMode, D3D11_FILL_SOLID
    mov desc.CullMode, D3D11_CULL_NONE
    mov desc.FrontCounterClockwise, 1
    mov desc.DepthClipEnable, 1
    mov desc.DepthBias, 1000
    storef desc.SlopeScaledDepthBias, 2.0
    vcall device, ID3D11Device_CreateRasterizerState, ADDR desc, ADDR state
    AssertHr
    mov rax, state
    ret
shadow_bias_state endp

endif
