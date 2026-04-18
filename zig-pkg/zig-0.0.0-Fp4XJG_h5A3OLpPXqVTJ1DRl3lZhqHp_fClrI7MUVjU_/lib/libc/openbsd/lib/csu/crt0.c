/*	$OpenBSD: crt0.c,v 1.19 2025/05/24 06:32:12 deraadt Exp $	*/

/*
 * Copyright (c) 1995 Christopher G. Demetriou
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *      This product includes software developed by Christopher G. Demetriou
 *	for the NetBSD Project.
 * 4. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/syscall.h>
#include <stdlib.h>
#include <limits.h>

#include "md_init.h"
/* zig patch: no static crt support */
#include "extern.h"

#define STR(x) __STRING(x)	/* shorter macro name for MD_RCRT0_START */

/* some defaults */
#ifndef	MD_START_ARGS
#define	MD_START_ARGS	\
	int argc, char **argv, char **envp, void (*cleanup)(void)
#endif
static void		___start(MD_START_ARGS) __used;
#ifndef	MD_EPROL_LABEL
#define	MD_EPROL_LABEL	__asm("  .text\n_eprol:")
#endif

char	***_csu_finish(char **_argv, char **_envp, void (*_cleanup)(void));

/* zig patch: no profiling support */

#ifdef MD_CRT0_START
MD_CRT0_START;
#endif

/* zig patch: no legacy leanup abi support */

static void
___start(MD_START_ARGS)
{
	size_t size, i;
	char ***environp;
#ifdef MD_START_SETUP
	MD_START_SETUP
#endif

	environp = _csu_finish(argv, envp, cleanup);

	exit(main(argc, argv, *environp));
}
