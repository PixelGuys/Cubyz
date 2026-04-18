/*	$OpenBSD: crtbegin.c,v 1.26 2019/01/09 16:42:38 visa Exp $	*/
/*	$NetBSD: crtbegin.c,v 1.1 1996/09/12 16:59:03 cgd Exp $	*/

/*
 * Copyright (c) 1993 Paul Kranenburg
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
 *      This product includes software developed by Paul Kranenburg.
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

/*
 * Run-time module for GNU C++ compiled shared libraries.
 *
 * The linker constructs the following arrays of pointers to global
 * constructors and destructors. The first element contains the
 * number of pointers in each.
 * The tables are also null-terminated.
 */
#include <stdlib.h>

#include "md_init.h"
#include "os-note-elf.h"
#include "extern.h"

/* zig patch: no ctors/dtors and init/fini */

/*
 * Include support for the __cxa_atexit/__cxa_finalize C++ abi for
 * gcc > 2.x. __dso_handle is NULL in the main program and a unique
 * value for each C++ shared library. For more info on this API, see:
 *
 *     http://www.codesourcery.com/cxx-abi/abi.html#dso-dtor
 */

void *__dso_handle = NULL;
__asm(".hidden  __dso_handle");

long __guard_local __dso_hidden __attribute__((section(".openbsd.randomdata")));
