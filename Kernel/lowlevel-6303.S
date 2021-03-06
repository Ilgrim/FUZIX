
	.export _di
	.export _ei
	.export _irqrestore
	.export _swab
	.export _doexec
	.export _sys_cpu
	.export _sys_stubs
	.export _sys_cpu_feat
	.export _set_cpu_type
	.export unix_syscall_entry
	.export interrupt_handler
	.export nmi_handler
	.export trap_handler

	.export outnewline
	.export outcharhex
	.export outstring
	.export outx
	.export outd

	.setcpu 6303

#include "platform/kernel.def"
#include "kernel-6303.def"

	.code

_di:
	tpa		; return cc codes in D
	sei
	rts

_ei:
	cli
	rts

_irqrestore:
	tsx
	ldd	2,x 
			; D holds the return from di where A is the cc
	tap		; we trash overflow and carry but they are assumed
	rts		; clobbered anyway

_swab:
	tsx
	ldab	3,x
	ldaa	4,x
	rts

	.common

outnewline:
	ldab #0x0d
	bsr outchar_call
	ldab #0x0a
	bra outchar_call


outcharhex:
	pshb
	lsrb
	lsrb
	lsrb
	lsrb
	bsr outnibble
	pulb
	pshb
	bsr outnibble
	pulb
	rts

outnibble:
	andb #0x0F
	cmpb #0x0A
	ble outh2
	addb #0x07
outh2:	addb #0x30
outchar_call:
	jmp outchar

outstring:
	ldab ,x
	beq outsdone
	bsr outchar_call
	inx
	bra outstring

outx:
	xgdx
	pshx		; actually the old D
	bsr outcharhex
	tab
	bsr outcharhex
	pulx
	xgdx
outsdone:
	rts

outd:
	psha
	pshb
	bsr outcharhex
	tab
	bsr outcharhex
	pulb
	pula
	rts


deliver_signals:
	ldaa _udata+U_DATA__U_CURSIG
	bne deliver_signals_2
signal_raced:
	rts
deliver_signals_2:
	tab
	ldx #_udata+U_DATA__U_SIGVEC
	abx
	abx
	ldx 0,x
	beq signal_raced
	clrb
	pshb
	psha
	ldd #signal_return
	psha
	pshb
	jmp ,x
signal_return:
	sei
	sts _udata+U_DATA__U_SYSCALL_SP
	lds #kstack_top
	jsr map_kernel_di
	jsr _chksigs
	jsr map_process_always_di
	lds _udata+U_DATA__U_SYSCALL_SP
	bra deliver_signals
	

;
;	We are called from SWI. The stack holds 7 bytes of return
;	information, B holds the syscall number on entry
;
unix_syscall_entry:
	tsx
	stab _udata+U_DATA__U_CALLNO
	ldd 11,x
	std _udata+U_DATA__U_ARGN
	ldd 13,x
	std _udata+U_DATA__U_ARGN+2
	ldd 15,x
	std _udata+U_DATA__U_ARGN+4
	ldd 17,x
	std _udata+U_DATA__U_ARGN+6
	ldaa #1
	staa _udata+U_DATA__U_INSYS	; we may want to use udata-> tricks ?
	stx _udata+U_DATA__U_SYSCALL_SP
	lds #kstack_top
	jsr map_kernel_di		; no-op in pure banked
	cli
	jsr _unix_syscall
	sei
	clr _udata+U_DATA__U_INSYS
	jsr map_process_always	; no-op in pure banked
	lds _udata+U_DATA__U_SYSCALL_SP
	; Now the fun bit - the CPU saves X and D so we have to patch them
	; into the return frame
	ldd _udata+U_DATA__U_RETVAL
	tsx
	std 2,x			; return in D
	ldd _udata+U_DATA__U_ERROR
	std 4,x			; error in X
	tst _udata+U_DATA__U_CURSIG
	bne via_signal
	rti
via_signal:
	jsr deliver_signals_2
	rti

_doexec:
	tsx
	ldx 3,x
	sei
	jsr map_process_always
	lds _udata+U_DATA__U_ISP
	clr _udata+U_DATA__U_INSYS
	cli
	ldd PROGLOAD
	jmp 0,x

trap_handler:
	tst _udata + U_DATA__U_INSYS
	bne trap_illegal
	tst _inint
	bne trap_illegal
	; We should fix the trap address of the stack and see if it is > 31
	; if so then it was an illegal instruction on 6303 TODO
	ldx #9
	pshx
	ldx _udata+U_DATA__U_PTAB
	ldx P_TAB__P_PID_OFFSET,x
	pshx
	ldaa #39
	swi		; Will never return

trap_illegal:
	ldx #illegalmsg
trapx:
	jsr outstring
	jsr _platform_monitor

nmi_handler:
	jsr map_kernel_di
	ldx #nmimsg
	bra trapx

illegalmsg:
	.ascii '[illegal]'
	.byte 0
nmimsg:
	.ascii '[NMI]'
	.byte 0
;
;	The trap saved our entire register state for us
;
interrupt_handler:
	sts istack_switched_sp
	lds #istack_top
	des
	jsr map_save_kernel

	ldaa #1
	staa _udata+U_DATA__U_ININTERRUPT
	staa _inint
	; Save the C direct page values so we can re-enter
	; If we turn on register variables we will need to save them too
	ldx @tmp
	pshx
	ldx @tmp1
	pshx
	ldx @sreg
	pshx
	ldx @fp
	pshx
	jsr _platform_interrupt
	; Restore the C direct page
	pulx
	stx @fp
	pulx
	stx @sreg
	pulx
	stx @tmp1
	pulx
	stx @tmp
	clr _inint
	tst _need_resched
	bne preemption
	jsr map_restore
	lds istack_switched_sp
	clr _udata+U_DATA__U_ININTERRUPT
	tst _udata+U_DATA__U_INSYS
	bne no_signals
	jsr deliver_signals
no_signals:
	rti	

preemption:
	clr _need_resched
	; Save the stack pointer across
	ldd istack_switched_sp
	std _udata+U_DATA__U_SYSCALL_SP
	lds #kstack_top
	ldab #1
	stab _udata+U_DATA__U_INSYS
	jsr _chksigs
	ldx _udata+U_DATA__U_PTAB
	ldab P_TAB__P_STATUS_OFFSET,x
	cmpb #P_RUNNING
	bne not_running
	ldab #P_READY
	stab P_TAB__P_STATUS_OFFSET,x
	oim #PFL_BATCH, P_TAB__P_FLAGS_OFFSET,x
not_running:
	jsr _platform_switchout
	clr _udata+U_DATA__U_ININTERRUPT
	clr _udata+U_DATA__U_INSYS
	jsr map_process_always
	lds _udata+U_DATA__U_SYSCALL_SP
	ldaa _udata+U_DATA__U_CURSIG
	beq no_signals
	jmp deliver_signals_2

	.code

;
;	FIXME: eventually test 6803 v 6303 and for 6303
;	set features to 3 (xgdx as well as 6803) 
;
_set_cpu_type:
	rts

	.data
_sys_cpu:
	.byte 2		; 6800 class CPU
_sys_cpu_feat:
	.byte 1		; 6800 with 6801/3 features
_sys_stubs:
	swi
	rts
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
