;---------------------------------------------------------------------------------------------------
; rt.inc: masm64rt.inc without its hard-coded C:\masm64 paths
;---------------------------------------------------------------------------------------------------
; The masm64 SDK's own masm64rt.inc includes and links everything from \masm64\. This takes only
; the include files the lessons use, found through the /I paths build.bat passes, and leaves the
; import libraries to the Windows SDK on the link line.
ifndef rt_inc
rt_inc = 0

    OPTION DOTNAME
    option casemap:none

    include win64.inc
    include vasily.inc
    include macros64.inc

    STACKFRAME

    include kernel32.inc
    include user32.inc
    include gdi32.inc
    include ole32.inc

endif
