/*  hts_defs.h -- Miscellaneous definitions.

    Copyright (C) 2013-2015,2017, 2019-2020 Genome Research Ltd.

    Author: John Marshall <jm18@sanger.ac.uk>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.  */

extern (C):

// For __MINGW_PRINTF_FORMAT macro

alias HTS_COMPILER_HAS = __has_attribute;

extern (D) int HTS_GCC_AT_LEAST(T0, T1)(auto ref T0 major, auto ref T1 minor)
{
    return 0;
}

// GCC introduced warn_unused_result in 3.4 but added -Wno-unused-result later

// On mingw the "printf" format type doesn't work.  It needs "gnu_printf"
// in order to check %lld and %z, otherwise it defaults to checking against
// the Microsoft library printf format options despite linking against the
// GNU posix implementation of printf.  The __MINGW_PRINTF_FORMAT macro
// expands to printf or gnu_printf as required, but obviously may not
// exist

enum HTS_PRINTF_FMT = printf;

