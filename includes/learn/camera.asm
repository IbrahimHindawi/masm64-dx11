;---------------------------------------------------------------------------------------------------
; camera: a fly camera from yaw and pitch, LearnOpenGL's Camera class
;---------------------------------------------------------------------------------------------------
; Lessons feed it keyboard, mouse and wheel input and ask it for a view matrix:
;
;     lea rcx, cam                      ; once
;     lea rdx, start_position
;     movf xmm2, -90.0                  ; yaw: -90 looks down -z
;     movf xmm3, 0.0                    ; pitch
;     call camera_create
;     ...
;     invoke camera_process_input, ADDR cam, delta_time      ; every frame (delta_time: a real4)
;     invoke camera_view, ADDR view, ADDR cam
;
;   W A S D, Space, Shift   move
;   right mouse + drag      look
;   wheel                   zoom
ifndef camera_asm
camera_asm = 0

include macros.asm
include math.asm
include learn\window.asm

CAMERA_FORWARD equ 0
CAMERA_BACKWARD equ 1
CAMERA_RIGHT equ 2
CAMERA_LEFT equ 3
CAMERA_UP equ 4
CAMERA_DOWN equ 5

camera struct
    position vec3 <>
    front vec3 <>
    up vec3 <>
    right vec3 <>
    world_up vec3 <>
    yaw real4 ?            ; degrees; -90 looks down -z
    pitch real4 ?          ; degrees
    speed real4 ?          ; units per second
    sensitivity real4 ?    ; degrees per pixel of mouse movement
    zoom real4 ?           ; vertical field of view, degrees
camera ends

.code
; rcx: &camera. front, right and up from yaw and pitch.
align 16
camera_update_vectors proc cam:qword
    local yaw:real4, pitch:real4, cos_pitch:real4
    USING rbx
    SaveRegs
    mov rbx, cam
    movss xmm0, [rbx].camera.yaw
    call radians
    movss yaw, xmm0
    movss xmm0, [rbx].camera.pitch
    call radians
    movss pitch, xmm0
    call cosf
    movss cos_pitch, xmm0
    ; front = normalize(cos(yaw) cos(pitch), sin(pitch), sin(yaw) cos(pitch))
    movss xmm0, yaw
    call cosf
    mulss xmm0, cos_pitch
    movss [rbx].camera.front.x, xmm0
    movss xmm0, pitch
    call sinf
    movss [rbx].camera.front.y, xmm0
    movss xmm0, yaw
    call sinf
    mulss xmm0, cos_pitch
    movss [rbx].camera.front.z, xmm0
    lea rcx, [rbx].camera.front
    mov rdx, rcx
    call v3_normalize
    ; right = normalize(cross(front, world_up)), up = normalize(cross(right, front))
    lea rcx, [rbx].camera.right
    lea rdx, [rbx].camera.front
    lea r8, [rbx].camera.world_up
    call v3_cross
    lea rcx, [rbx].camera.right
    mov rdx, rcx
    call v3_normalize
    lea rcx, [rbx].camera.up
    lea rdx, [rbx].camera.right
    lea r8, [rbx].camera.front
    call v3_cross
    lea rcx, [rbx].camera.up
    mov rdx, rcx
    call v3_normalize
    RestoreRegs
    ret
camera_update_vectors endp

; rcx: &camera, rdx: position (vec3), xmm2: yaw, xmm3: pitch (degrees)
align 16
camera_create proc cam:qword, position:qword, yaw:qword, pitch:qword
    mov rcx, cam
    mov rdx, position
    mov eax, [rdx].vec3.x
    mov [rcx].camera.position.x, eax
    mov eax, [rdx].vec3.y
    mov [rcx].camera.position.y, eax
    mov eax, [rdx].vec3.z
    mov [rcx].camera.position.z, eax
    mov dword ptr [rcx].camera.world_up.x, 0
    mov dword ptr [rcx].camera.world_up.y, 3F800000h    ; 1.0
    mov dword ptr [rcx].camera.world_up.z, 0
    movss [rcx].camera.yaw, xmm2
    movss [rcx].camera.pitch, xmm3
    storef [rcx].camera.speed, 2.5
    storef [rcx].camera.sensitivity, 0.1
    storef [rcx].camera.zoom, 45.0
    invoke camera_update_vectors, cam
    ret
camera_create endp

; rcx: out mat4, rdx: &camera
align 16
camera_view proc out_ref:qword, cam:qword
    local target:vec3
    mov rdx, cam
    lea rcx, target
    lea r8, [rdx].camera.front
    lea rdx, [rdx].camera.position
    call v3_add
    mov rax, cam
    lea rdx, [rax].camera.position
    lea r8, target
    lea r9, [rax].camera.up
    invoke m4_look_at, out_ref, rdx, r8, r9
    ret
camera_view endp

; rcx: out mat4, rdx: &camera -> the projection the lessons use: the camera's zoom as the vertical
; field of view, the window's aspect ratio, and depth from 0.1 to 100 units.
align 16
camera_projection proc out_ref:qword, cam:qword
    movf xmm0, 100.0
    movss real4 ptr [rsp + 32], xmm0        ; z_far, the fifth argument, on the stack
    mov rdx, cam
    movss xmm0, [rdx].camera.zoom
    call radians
    movaps xmm1, xmm0                       ; fovy
    cvtsi2ss xmm2, scr_width
    cvtsi2ss xmm0, scr_height
    divss xmm2, xmm0                        ; aspect
    movf xmm3, 0.1                          ; z_near
    mov rcx, out_ref
    call m4_perspective
    ret
camera_projection endp

; rcx: &camera, rdx: CAMERA_FORWARD ... CAMERA_DOWN, xmm2: seconds since the last frame
align 16
camera_process_keyboard proc cam:qword, direction:qword, seconds:qword
    local step:vec3
    mov rcx, cam
    mulss xmm2, [rcx].camera.speed          ; how far this frame
    mov eax, dword ptr direction
    lea rdx, [rcx].camera.front
    cmp eax, CAMERA_RIGHT
    jb along
    lea rdx, [rcx].camera.right
    cmp eax, CAMERA_UP
    jb along
    lea rdx, [rcx].camera.world_up
    along:
    ; forward, right and up (even) add the step; backward, left and down (odd) subtract it
    test eax, 1
    jz forwards
        xorps xmm2, math_sign_mask
    forwards:
    lea rcx, step
    call v3_scale
    mov rcx, cam
    lea rdx, [rcx].camera.position
    lea r8, step
    mov rcx, rdx
    call v3_add
    ret
camera_process_keyboard endp

; rcx: &camera, xmm1: dx, xmm2: dy (pixels; up is positive)
;
; Pitch stops short of straight up and down, where the view would flip.
align 16
camera_process_mouse proc cam:qword
    mov rcx, cam
    mulss xmm1, [rcx].camera.sensitivity
    addss xmm1, [rcx].camera.yaw
    movss [rcx].camera.yaw, xmm1
    mulss xmm2, [rcx].camera.sensitivity
    movss xmm0, [rcx].camera.pitch
    addss xmm0, xmm2
    movf xmm1, -89.0
    movf xmm2, 89.0
    call clampf
    mov rcx, cam
    movss [rcx].camera.pitch, xmm0
    invoke camera_update_vectors, cam
    ret
camera_process_mouse endp

; rcx: &camera, xmm1: wheel notches. Zooming is narrowing the field of view.
align 16
camera_process_scroll proc cam:qword
    mov rcx, cam
    addss xmm1, xmm1                        ; 2 degrees a notch
    movss xmm0, [rcx].camera.zoom
    subss xmm0, xmm1
    movf xmm1, 1.0
    movf xmm2, 45.0
    call clampf
    mov rcx, cam
    movss [rcx].camera.zoom, xmm0
    ret
camera_process_scroll endp

; rcx: &camera, rdx: address of the frame's duration (a real4)
;
; process all input: ask Windows whether relevant keys are down this frame and react accordingly.
; Movement is scaled by the frame's duration, so the speed is the same at any frame rate.
align 16
camera_process_input proc cam:qword, dt_ref:qword
    USING rbx, rsi
    SaveRegs
    ; Nothing at all while another window has the focus, the zoom's clamp included: a lesson may
    ; start the zoom outside the range the wheel keeps it in.
    invoke GetForegroundWindow
    cmp rax, window
    jne done
    lea rbx, camera_keys
    xor esi, esi
    keys:
        movzx eax, byte ptr [rbx + rsi]
        invoke key_down, rax
        test eax, eax
        jz next_key
            mov rax, dt_ref
            movss xmm2, real4 ptr [rax]
            invoke camera_process_keyboard, cam, rsi
        next_key:
        inc esi
        cmp esi, 6
        jb keys

    ; Hold the right mouse button to look around.
    invoke key_down, VK_RBUTTON
    test eax, eax
    jz no_look
        movss xmm1, window_mouse_dx
        movss xmm2, window_mouse_dy
        invoke camera_process_mouse, cam
    no_look:
    movss xmm1, window_scroll
    invoke camera_process_scroll, cam
    mov dword ptr window_scroll, 0
    done:
    RestoreRegs
    ret
camera_process_input endp

.const
; the key for each CAMERA_ direction, in order
camera_keys byte 'W', 'S', 'D', 'A', VK_SPACE, VK_SHIFT

.code
endif
