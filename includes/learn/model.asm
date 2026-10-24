;---------------------------------------------------------------------------------------------------
; model: loading models from Wavefront .obj files
;---------------------------------------------------------------------------------------------------
; What Assimp and LearnOpenGL's Model and Mesh classes are to LearnOpenGL. Only the part of the
; format the lessons' models use:
;
;   v  x y z        a position
;   vt u v          a texture coordinate
;   vn x y z        a normal
;   f  a/b/c ...    a face: position/uv/normal indices, counted from 1
;   mtllib x.mtl    the material file, which names the textures
;
; Faces with more than three corners are split into a fan. Every corner becomes its own vertex, so
; nothing is shared between triangles; that costs memory, not correctness.
;
; OBJ's v normally runs up the image and D3D's runs down, so v usually needs flipping. Whether it
; does depends on how the model's textures were saved: the backpack's already suit top-down v.
; Hence `flip_v`, chosen per model.
;
;     invoke model_load, ADDR backpack, "resources/objects/backpack/", "backpack.obj", 0
;     ...
;     invoke model_draw, ADDR backpack
;
; model_draw binds the textures to fixed slots: diffuse t0, specular t1, normal t2.
ifndef model_asm
model_asm = 0

include macros.asm
include math.asm
include cstr.asm
include print.asm
include saha.asm
include learn\window.asm
include learn\filesystem.asm
include learn\gpu.asm

model_vertex struct
    position vec3 <>
    normal vec3 <>
    uv vec2 <>
model_vertex ends

model struct
    vertices qword ?        ; ID3D11Buffer of model_vertex
    vertex_count dword ?
    pad dword ?
    diffuse qword ?         ; ID3D11ShaderResourceView: map_Kd
    specular qword ?        ; map_Ks
    normal qword ?          ; map_Bump
model ends

; One `a/b/c` corner of a face. Missing parts (`a//c`, `a/b`, `a`) are 0.
obj_corner struct
    position dword ?
    uv dword ?
    normal dword ?
obj_corner ends

.data
model_semantic_position byte "POSITION", 0
model_semantic_normal byte "NORMAL", 0
model_semantic_texcoord byte "TEXCOORD", 0
align 8
model_layout D3D11_INPUT_ELEMENT_DESC <offset model_semantic_position, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>
             D3D11_INPUT_ELEMENT_DESC <offset model_semantic_normal, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0>
             D3D11_INPUT_ELEMENT_DESC <offset model_semantic_texcoord, 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D11_INPUT_PER_VERTEX_DATA, 0>
model_layout_count equ 3

.code
;---------------------------------------------------------------------------------------------------
; reading text: rcx is the cursor going in, rax the cursor coming out
;---------------------------------------------------------------------------------------------------
; past spaces and tabs (touching only rax and r9: callers keep pointers in rdx)
align 16
obj_skip_spaces proc
    mov rax, rcx
    skip:
        mov r9b, [rax]
        cmp r9b, ' '
        je next
        cmp r9b, 9
        jne done
        next:
        inc rax
        jmp skip
    done:
    ret
obj_skip_spaces endp

; to the start of the next line
align 16
obj_next_line proc
    mov rax, rcx
    scan:
        mov r9b, [rax]
        test r9b, r9b
        jz done
        inc rax
        cmp r9b, 10
        jne scan
    done:
    ret
obj_next_line endp

; rcx: cursor, rdx: keyword -> rax: 1 when the line starts with the keyword and a space or tab
align 16
obj_starts proc
    compare:
        mov al, [rdx]
        test al, al
        jz word_ended
        cmp al, [rcx]
        jne no
        inc rcx
        inc rdx
        jmp compare
    word_ended:
    mov al, [rcx]
    cmp al, ' '
    je yes
    cmp al, 9
    je yes
    no:
    xor eax, eax
    ret
    yes:
    mov eax, 1
    ret
obj_starts endp

; rcx: cursor, rdx: where to write the word (128 bytes at most) -> rax: cursor after it
align 16
obj_word proc
    call obj_skip_spaces
    mov r8d, 127
    copy:
        mov cl, [rax]
        test cl, cl
        jz done
        cmp cl, 10
        je done
        cmp cl, 13
        je done
        cmp cl, ' '
        je done
        cmp cl, 9
        je done
        mov [rdx], cl
        inc rax
        inc rdx
        dec r8d
        jnz copy
    done:
    mov byte ptr [rdx], 0
    ret
obj_word endp

; rcx: cursor -> rax: 1 if a face corner (a number) comes next, rdx: the cursor at it
align 16
obj_at_corner proc
    call obj_skip_spaces
    mov rdx, rax
    movzx ecx, byte ptr [rax]
    xor eax, eax
    cmp ecx, '-'
    je yes
    sub ecx, '0'
    cmp ecx, 9
    ja no
    yes:
    mov eax, 1
    no:
    ret
obj_at_corner endp

; rcx: cursor at a corner, rdx: &obj_corner -> rax: cursor after it
align 16
obj_read_corner proc cursor:qword, corner:qword
    mov rdx, corner
    mov qword ptr [rdx], 0
    mov dword ptr [rdx + 8], 0
    mov rcx, cursor
    call parse_int
    mov rcx, corner
    mov [rcx].obj_corner.position, eax
    cmp byte ptr [rdx], '/'
    jne done
    inc rdx
    cmp byte ptr [rdx], '/'
    je no_uv
        mov rcx, rdx
        call parse_int
        mov rcx, corner
        mov [rcx].obj_corner.uv, eax
    no_uv:
    cmp byte ptr [rdx], '/'
    jne done
    inc rdx
    mov rcx, rdx
    call parse_int
    mov rcx, corner
    mov [rcx].obj_corner.normal, eax
    done:
    mov rax, rdx
    ret
obj_read_corner endp

; rcx: cursor -> xmm0: the float after any spaces, rax: cursor after it
align 16
obj_float proc
    call obj_skip_spaces
    mov rcx, rax
    call parse_float
    ret
obj_float endp

;---------------------------------------------------------------------------------------------------
; materials
;---------------------------------------------------------------------------------------------------
; rcx: the model's directory (full path, ending in a slash), rdx: the .mtl's name, r8: &model.
; Reads the .mtl and loads the textures it names.
align 16
obj_load_material proc dir:qword, mtl_name:qword, out_ref:qword
    local path[260]:byte, word_[128]:byte, kind:dword
    USING rsi
    SaveRegs
    invoke cstr_copy, ADDR path, dir
    invoke cstr_append, ADDR path, mtl_name
    invoke filesystem_read, ADDR path, 0
    test rax, rax
    jz done
    mov rsi, rax
    lines:
        cmp byte ptr [rsi], 0
        je done
        mov rcx, rsi
        call obj_skip_spaces
        mov rsi, rax
        mov kind, 0
        invoke obj_starts, rsi, "map_Kd"
        test eax, eax
        jz not_diffuse
            mov kind, model.diffuse
        not_diffuse:
        invoke obj_starts, rsi, "map_Ks"
        test eax, eax
        jz not_specular
            mov kind, model.specular
        not_specular:
        invoke obj_starts, rsi, "map_Bump"
        test eax, eax
        jz not_normal
            mov kind, model.normal
        not_normal:
        cmp kind, 0
        je next_line
            ; the keyword, then the file name
            lea rdx, word_
            mov rcx, rsi
            call obj_word
            lea rdx, word_
            mov rcx, rax
            call obj_word
            mov rsi, rax
            invoke cstr_copy, ADDR path, dir
            invoke cstr_append, ADDR path, ADDR word_
            ; Colours are drawn as stored, as LearnOpenGL's model loader does; the normal map is
            ; data either way.
            invoke load_texture, ADDR path, 0
            mov rcx, out_ref
            mov edx, kind
            mov [rcx + rdx], rax
        next_line:
        mov rcx, rsi
        call obj_next_line
        mov rsi, rax
        jmp lines
    done:
    RestoreRegs
    ret
obj_load_material endp

;---------------------------------------------------------------------------------------------------
; models
;---------------------------------------------------------------------------------------------------
; One corner of a face, written as the vertex at r15: what its three indices point at. Used inside
; model_load, whose locals p, n and t are the position, normal and uv arrays.
fan_vertex macro c:req
    mov eax, c.position
    lea rax, [rax + rax * 2]
    mov rcx, p
    lea rcx, [rcx + rax * 4]
    v3load xmm0, [rcx]
    v3store [r15].model_vertex.position, xmm0
    mov eax, c.normal
    lea rax, [rax + rax * 2]
    mov rcx, n
    lea rcx, [rcx + rax * 4]
    v3load xmm0, [rcx]
    v3store [r15].model_vertex.normal, xmm0
    mov eax, c.uv
    mov rcx, t
    mov rax, [rcx + rax * 8]
    mov qword ptr [r15].model_vertex.uv, rax
    add r15, sizeof model_vertex
endm

; rcx: &model, rdx: directory relative to the repository root (ending in a slash), r8: the .obj
; inside it, r9: 1 to flip v
align 16
model_load proc out_ref:qword, relative_dir:qword, file:qword, flip_v:qword
    local dir:qword, path[260]:byte, word_[128]:byte
    local positions:qword, uvs:qword, normals:qword, corners:qword
    local p:qword, t:qword, n:qword, vertices:qword
    local first:obj_corner, previous:obj_corner, corner:obj_corner, fan_count:qword
    local desc:D3D11_BUFFER_DESC, init:D3D11_SUBRESOURCE_DATA
    USING rbx, rsi, rdi, r12, r13, r14, r15
    SaveRegs

    invoke mem_zero, out_ref, sizeof model
    invoke filesystem_path, relative_dir
    mov dir, rax
    invoke cstr_copy, ADDR path, dir
    invoke cstr_append, ADDR path, file
    invoke filesystem_read, ADDR path, 0
    test rax, rax
    jnz have_text
        print "model: cannot read %s\n", ADDR path
        invoke ExitProcess, 1
    have_text:
    mov rbx, rax                        ; the text, kept for the second pass

    ; First pass: count, so every array is allocated once at its final size.
    xor r12, r12                        ; positions
    xor r13, r13                        ; uvs
    xor r14, r14                        ; normals
    xor r15, r15                        ; corners
    mov rsi, rbx
    count_lines:
        cmp byte ptr [rsi], 0
        je counted
        invoke obj_starts, rsi, "v"
        add r12, rax
        invoke obj_starts, rsi, "vt"
        add r13, rax
        invoke obj_starts, rsi, "vn"
        add r14, rax
        invoke obj_starts, rsi, "f"
        test eax, eax
        jz count_next
            inc rsi
            xor edi, edi                ; corners on this face
            count_corners:
                mov rcx, rsi
                call obj_at_corner
                mov rsi, rdx
                test eax, eax
                jz corners_counted
                invoke obj_read_corner, rsi, ADDR corner
                mov rsi, rax
                inc edi
                jmp count_corners
            corners_counted:
            cmp edi, 3
            jb count_next
            lea rax, [rdi - 2]
            lea rax, [rax + rax * 2]    ; (n - 2) * 3
            add r15, rax
        count_next:
        mov rcx, rsi
        call obj_next_line
        mov rsi, rax
        jmp count_lines
    counted:
    mov positions, r12
    mov uvs, r13
    mov normals, r14
    mov corners, r15

    ; Index 0 is the "missing" entry, so 1-based indices need no adjusting.
    lea rax, [r12 + 1]
    arenaPushArrayZero ADDR arena, vec3, rax, 16
    mov p, rax
    lea rax, [r13 + 1]
    arenaPushArrayZero ADDR arena, vec2, rax, 16
    mov t, rax
    lea rax, [r14 + 1]
    arenaPushArrayZero ADDR arena, vec3, rax, 16
    mov n, rax
    mov dword ptr [rax].vec3.y, 3F800000h   ; the missing normal is up
    arenaPushArray ADDR arena, model_vertex, r15, 16
    mov vertices, rax

    ; Second pass: fill them in.
    mov r12, p
    add r12, sizeof vec3                ; next position
    mov r13, t
    add r13, sizeof vec2                ; next uv
    mov r14, n
    add r14, sizeof vec3                ; next normal
    mov r15, vertices                   ; next vertex
    mov rsi, rbx
    lines:
        cmp byte ptr [rsi], 0
        je read
        invoke obj_starts, rsi, "v"
        test eax, eax
        jz not_position
            lea rcx, [rsi + 1]
            call obj_float
            movss [r12].vec3.x, xmm0
            mov rcx, rax
            call obj_float
            movss [r12].vec3.y, xmm0
            mov rcx, rax
            call obj_float
            movss [r12].vec3.z, xmm0
            mov rsi, rax
            add r12, sizeof vec3
            jmp next_line
        not_position:
        invoke obj_starts, rsi, "vt"
        test eax, eax
        jz not_uv
            lea rcx, [rsi + 2]
            call obj_float
            movss [r13].vec2.x, xmm0
            mov rcx, rax
            call obj_float
            mov rsi, rax
            cmp flip_v, 0
            je no_flip
                movss xmm1, math_one
                subss xmm1, xmm0
                movss xmm0, xmm1
            no_flip:
            movss [r13].vec2.y, xmm0
            add r13, sizeof vec2
            jmp next_line
        not_uv:
        invoke obj_starts, rsi, "vn"
        test eax, eax
        jz not_normal
            lea rcx, [rsi + 2]
            call obj_float
            movss [r14].vec3.x, xmm0
            mov rcx, rax
            call obj_float
            movss [r14].vec3.y, xmm0
            mov rcx, rax
            call obj_float
            movss [r14].vec3.z, xmm0
            mov rsi, rax
            add r14, sizeof vec3
            jmp next_line
        not_normal:
        invoke obj_starts, rsi, "f"
        test eax, eax
        jz not_face
            inc rsi
            mov fan_count, 0
            face_corners:
                mov rcx, rsi
                call obj_at_corner
                mov rsi, rdx
                test eax, eax
                jz next_line
                invoke obj_read_corner, rsi, ADDR corner
                mov rsi, rax
                cmp fan_count, 0
                jne not_first
                    invoke mem_copy, ADDR first, ADDR corner, sizeof obj_corner
                not_first:
                cmp fan_count, 2
                jb fan_later
                    ; a triangle of the fan: the first corner, the previous one and this one
                    fan_vertex first
                    fan_vertex previous
                    fan_vertex corner
                fan_later:
                invoke mem_copy, ADDR previous, ADDR corner, sizeof obj_corner
                inc fan_count
                jmp face_corners
        not_face:
        invoke obj_starts, rsi, "mtllib"
        test eax, eax
        jz next_line
            lea rdx, word_
            mov rcx, rsi
            call obj_word
            lea rdx, word_
            mov rcx, rax
            call obj_word
            mov rsi, rax
            invoke obj_load_material, dir, ADDR word_, out_ref
        next_line:
        mov rcx, rsi
        call obj_next_line
        mov rsi, rax
        jmp lines

    read:
    ; one immutable vertex buffer
    mov r12, r15
    sub r12, vertices                   ; bytes
    mov rax, r12
    xor edx, edx
    mov ecx, sizeof model_vertex
    div rcx
    mov rbx, out_ref
    mov [rbx].model.vertex_count, eax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, vertices, r12
    mov [rbx].model.vertices, rax

    RestoreRegs
    ret
model_load endp

; rcx: &model, rdx: how many instances
align 16
model_draw_instanced proc m:qword, instances:qword
    local stride:dword, offset_:dword, views[3]:qword
    USING rbx
    SaveRegs
    mov rbx, m
    mov stride, sizeof model_vertex
    mov offset_, 0
    mov rax, [rbx].model.diffuse
    mov views[0], rax
    mov rax, [rbx].model.specular
    mov views[8], rax
    mov rax, [rbx].model.normal
    mov views[16], rax
    vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 3, ADDR views
    vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
    lea rax, [rbx].model.vertices
    vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, rax, ADDR stride, ADDR offset_
    vcall context, ID3D11DeviceContext_DrawInstanced, dword ptr [rbx].model.vertex_count, instances, 0, 0
    RestoreRegs
    ret
model_draw_instanced endp

; rcx: &model
align 16
model_draw proc m:qword
    invoke model_draw_instanced, m, 1
    ret
model_draw endp

endif
