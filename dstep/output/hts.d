/// @file htslib/hts.h
/// Format-neutral I/O, indexing, and iterator API functions.
/*
    Copyright (C) 2012-2020 Genome Research Ltd.
    Copyright (C) 2010, 2012 Broad Institute.
    Portions copyright (C) 2003-2006, 2008-2010 by Heng Li <lh3@live.co.uk>

    Author: Heng Li <lh3@sanger.ac.uk>

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

import core.stdc.config;
import core.stdc.inttypes;
import core.stdc.limits;
import core.stdc.stdint;

extern (C):

// Separator used to split HTS_PATH (for plugins); REF_PATH (cram references)

enum HTS_PATH_SEPARATOR_CHAR = ':';
enum HTS_PATH_SEPARATOR_STR = ":";

struct BGZF;

struct cram_fd;
struct hFILE;
struct hts_tpool;
struct sam_hdr_t;

/**
 * @hideinitializer
 * Deprecated macro to expand a dynamic array of a given type
 *
 * @param         type_t The type of the array elements
 * @param[in]     n      Requested number of elements of type type_t
 * @param[in,out] m      Size of memory allocated
 * @param[in,out] ptr    Pointer to the array
 *
 * @discussion
 * Do not use this macro.  Use hts_resize() instead as allows allocation
 * failures to be handled more gracefully.
 *
 * The array *ptr will be expanded if necessary so that it can hold @p n
 * or more elements.  If the array is expanded then the new size will be
 * written to @p m and the value in @p ptr may change.
 *
 * It must be possible to take the address of @p ptr and @p m must be usable
 * as an lvalue.
 *
 * @bug
 * If the memory allocation fails, this will call exit(1).  This is
 * not ideal behaviour in a library.
 */

/**
 * @hideinitializer
 * Macro to expand a dynamic array, zeroing any newly-allocated memory
 *
 * @param         type_t The type of the array elements
 * @param[in]     n      Requested number of elements of type type_t
 * @param[in,out] m      Size of memory allocated
 * @param[in,out] ptr    Pointer to the array
 *
 * @discussion
 * Do not use this macro.  Use hts_resize() instead as allows allocation
 * failures to be handled more gracefully.
 *
 * As for hts_expand(), except the bytes that make up the array elements
 * between the old and new values of @p m are set to zero using memset().
 *
 * @bug
 * If the memory allocation fails, this will call exit(1).  This is
 * not ideal behaviour in a library.
 */

// For internal use (by hts_resize()) only
int hts_resize_array_(size_t, size_t, size_t, void*, void**, int, const(char)*);

enum HTS_RESIZE_CLEAR = 1;

/**
 * @hideinitializer
 * Macro to expand a dynamic array of a given type
 *
 * @param         type_t    The type of the array elements
 * @param[in]     num       Requested number of elements of type type_t
 * @param[in,out] size_ptr  Pointer to where the size (in elements) of the
                            array is stored.
 * @param[in,out] ptr       Location of the pointer to the array
 * @param[in]     flags     Option flags
 *
 * @return        0 for success, or negative if an error occurred.
 *
 * @discussion
 * The array *ptr will be expanded if necessary so that it can hold @p num
 * or more elements.  If the array is expanded then the new size will be
 * written to @p *size_ptr and the value in @p *ptr may change.
 *
 * If ( @p flags & HTS_RESIZE_CLEAR ) is set, any newly allocated memory will
 * be cleared.
 */

/// Release resources when dlclosing a dynamically loaded HTSlib
/** @discussion
 *  Normally HTSlib cleans up automatically when your program exits,
 *  whether that is via exit(3) or returning from main(). However if you
 *  have dlopen(3)ed HTSlib and wish to close it before your main program
 *  exits, you must call hts_lib_shutdown() before dlclose(3).
*/
void hts_lib_shutdown();

/**
 * Wrapper function for free(). Enables memory deallocation across DLL
 * boundary. Should be used by all applications, which are compiled
 * with a different standard library than htslib and call htslib
 * methods that return dynamically allocated data.
 */
void hts_free(void* ptr);

/************
 * File I/O *
 ************/

// Add new entries only at the end (but before the *_maximum entry)
// of these enums, as their numbering is part of the htslib ABI.

enum htsFormatCategory
{
    unknown_category = 0,
    sequence_data = 1, // Sequence data -- SAM, BAM, CRAM, etc
    variant_data = 2, // Variant calling data -- VCF, BCF, etc
    index_file = 3, // Index file associated with some data file
    region_list = 4, // Coordinate intervals or regions -- BED, etc
    category_maximum = 32767
}

enum htsExactFormat
{
    unknown_format = 0,
    binary_format = 1,
    text_format = 2,
    sam = 3,
    bam = 4,
    bai = 5,
    cram = 6,
    crai = 7,
    vcf = 8,
    bcf = 9,
    csi = 10,
    gzi = 11,
    tbi = 12,
    bed = 13,
    htsget = 14,
    json = 14,
    empty_format = 15, // File is empty (or empty after decompression)
    fasta_format = 16,
    fastq_format = 17,
    fai_format = 18,
    fqi_format = 19,
    hts_crypt4gh_format = 20,
    format_maximum = 32767
}

enum htsCompression
{
    no_compression = 0,
    gzip = 1,
    bgzf = 2,
    custom = 3,
    bzip2_compression = 4,
    razf_compression = 5,
    compression_maximum = 32767
}

struct htsFormat
{
    htsFormatCategory category;
    htsExactFormat format;

    struct _Anonymous_0
    {
        short major;
        short minor;
    }

    _Anonymous_0 version_;
    htsCompression compression;
    short compression_level; // currently unused
    void* specific; // format specific options; see struct hts_opt.
}

struct hts_idx_t;
struct hts_filter_t;

/**
 * @brief File handle returned by hts_open() etc.
 * This structure should be considered opaque by end users. There should be
 * no need to access most fields directly in user code, and in cases where
 * it is desirable accessor functions such as hts_get_format() are provided.
 */
// Maintainers note htsFile cannot be an incomplete struct because some of its
// fields are part of libhts.so's ABI (hence these fields must not be moved):
//  - fp is used in the public sam_itr_next()/etc macros
//  - is_bin is used directly in samtools <= 1.1 and bcftools <= 1.1
//  - is_write and is_cram are used directly in samtools <= 1.1
//  - fp is used directly in samtools (up to and including current develop)
//  - line is used directly in bcftools (up to and including current develop)
//  - is_bgzf and is_cram flags indicate which fp union member to use.
//    Note is_bgzf being set does not indicate the flag is BGZF compressed,
//    nor even whether it is compressed at all (eg on naked BAMs).
struct htsFile
{
    import std.bitmanip : bitfields;

    mixin(bitfields!(
        uint, "is_bin", 1,
        uint, "is_write", 1,
        uint, "is_be", 1,
        uint, "is_cram", 1,
        uint, "is_bgzf", 1,
        uint, "dummy", 27));

    long lineno;
    kstring_t line;
    char* fn;
    char* fn_aux;

    union _Anonymous_1
    {
        BGZF* bgzf;
        cram_fd* cram;
        hFILE* hfile;
    }

    _Anonymous_1 fp;
    void* state; // format specific state information
    htsFormat format;
    hts_idx_t* idx;
    const(char)* fnidx;
    sam_hdr_t* bam_header;
    hts_filter_t* filter;
}

// A combined thread pool and queue allocation size.
// The pool should already be defined, but qsize may be zero to
// indicate an appropriate queue size is taken from the pool.
//
// Reasons for explicitly setting it could be where many more file
// descriptors are in use than threads, so keeping memory low is
// important.
struct htsThreadPool
{
    hts_tpool* pool; // The shared thread pool itself
    int qsize; // Size of I/O queue to use for this fp
}

// REQUIRED_FIELDS
enum sam_fields
{
    SAM_QNAME = 0x00000001,
    SAM_FLAG = 0x00000002,
    SAM_RNAME = 0x00000004,
    SAM_POS = 0x00000008,
    SAM_MAPQ = 0x00000010,
    SAM_CIGAR = 0x00000020,
    SAM_RNEXT = 0x00000040,
    SAM_PNEXT = 0x00000080,
    SAM_TLEN = 0x00000100,
    SAM_SEQ = 0x00000200,
    SAM_QUAL = 0x00000400,
    SAM_AUX = 0x00000800,
    SAM_RGAUX = 0x00001000
}

// Mostly CRAM only, but this could also include other format options
enum hts_fmt_option
{
    // CRAM specific
    CRAM_OPT_DECODE_MD = 0,
    CRAM_OPT_PREFIX = 1,
    CRAM_OPT_VERBOSITY = 2, // obsolete, use hts_set_log_level() instead
    CRAM_OPT_SEQS_PER_SLICE = 3,
    CRAM_OPT_SLICES_PER_CONTAINER = 4,
    CRAM_OPT_RANGE = 5,
    CRAM_OPT_VERSION = 6, // rename to cram_version?
    CRAM_OPT_EMBED_REF = 7,
    CRAM_OPT_IGNORE_MD5 = 8,
    CRAM_OPT_REFERENCE = 9, // make general
    CRAM_OPT_MULTI_SEQ_PER_SLICE = 10,
    CRAM_OPT_NO_REF = 11,
    CRAM_OPT_USE_BZIP2 = 12,
    CRAM_OPT_SHARED_REF = 13,
    CRAM_OPT_NTHREADS = 14, // deprecated, use HTS_OPT_NTHREADS
    CRAM_OPT_THREAD_POOL = 15, // make general
    CRAM_OPT_USE_LZMA = 16,
    CRAM_OPT_USE_RANS = 17,
    CRAM_OPT_REQUIRED_FIELDS = 18,
    CRAM_OPT_LOSSY_NAMES = 19,
    CRAM_OPT_BASES_PER_SLICE = 20,
    CRAM_OPT_STORE_MD = 21,
    CRAM_OPT_STORE_NM = 22,
    CRAM_OPT_RANGE_NOSEEK = 23, // CRAM_OPT_RANGE minus the seek
    CRAM_OPT_USE_TOK = 24,
    CRAM_OPT_USE_FQZ = 25,
    CRAM_OPT_USE_ARITH = 26,
    CRAM_OPT_POS_DELTA = 27, // force delta for AP, even on non-pos sorted data

    // General purpose
    HTS_OPT_COMPRESSION_LEVEL = 100,
    HTS_OPT_NTHREADS = 101,
    HTS_OPT_THREAD_POOL = 102,
    HTS_OPT_CACHE_SIZE = 103,
    HTS_OPT_BLOCK_SIZE = 104,
    HTS_OPT_FILTER = 105,
    HTS_OPT_PROFILE = 106
}

// Profile options for encoding; primarily used at present in CRAM
// but also usable in BAM as a synonym for deflate compression levels.
enum hts_profile_option
{
    HTS_PROFILE_FAST = 0,
    HTS_PROFILE_NORMAL = 1,
    HTS_PROFILE_SMALL = 2,
    HTS_PROFILE_ARCHIVE = 3
}

// For backwards compatibility
alias cram_option = hts_fmt_option;

struct hts_opt
{
    char* arg; // string form, strdup()ed
    hts_fmt_option opt; // tokenised key
    // ... and value
    union _Anonymous_2
    {
        int i;
        char* s;
    }

    _Anonymous_2 val;
    hts_opt* next;
}

/*
 * Explicit index file name delimiter, see below
 */
enum HTS_IDX_DELIM = "##idx##";

/**********************
 * Exported functions *
 **********************/

/*
 * Parses arg and appends it to the option list.
 *
 * Returns 0 on success;
 *        -1 on failure.
 */
int hts_opt_add(hts_opt** opts, const(char)* c_arg);

/*
 * Applies an hts_opt option list to a given htsFile.
 *
 * Returns 0 on success
 *        -1 on failure
 */
int hts_opt_apply(htsFile* fp, hts_opt* opts);

/*
 * Frees an hts_opt list.
 */
void hts_opt_free(hts_opt* opts);

/*
 * Accepts a string file format (sam, bam, cram, vcf, bam) optionally
 * followed by a comma separated list of key=value options and splits
 * these up into the fields of htsFormat struct.
 *
 * Returns 0 on success
 *        -1 on failure.
 */
int hts_parse_format(htsFormat* opt, const(char)* str);

/*
 * Tokenise options as (key(=value)?,)*(key(=value)?)?
 * NB: No provision for ',' appearing in the value!
 * Add backslashing rules?
 *
 * This could be used as part of a general command line option parser or
 * as a string concatenated onto the file open mode.
 *
 * Returns 0 on success
 *        -1 on failure.
 */
int hts_parse_opt_list(htsFormat* opt, const(char)* str);

/*! @abstract Table for converting a nucleotide character to 4-bit encoding.
The input character may be either an IUPAC ambiguity code, '=' for 0, or
'0'/'1'/'2'/'3' for a result of 1/2/4/8.  The result is encoded as 1/2/4/8
for A/C/G/T or combinations of these bits for ambiguous bases.
*/
extern __gshared const(ubyte)[256] seq_nt16_table;

/*! @abstract Table for converting a 4-bit encoded nucleotide to an IUPAC
ambiguity code letter (or '=' when given 0).
*/
extern __gshared const(char)[] seq_nt16_str;

/*! @abstract Table for converting a 4-bit encoded nucleotide to about 2 bits.
Returns 0/1/2/3 for 1/2/4/8 (i.e., A/C/G/T), or 4 otherwise (0 or ambiguous).
*/
extern __gshared const(int)[] seq_nt16_int;

/*!
  @abstract  Get the htslib version number
  @return    For released versions, a string like "N.N[.N]"; or git describe
  output if using a library built within a Git repository.
*/
const(char)* hts_version();

/*!
  @abstract  Compile-time HTSlib version number, for use in #if checks
  @return    For released versions X.Y[.Z], an integer of the form XYYYZZ;
  useful for preprocessor conditionals such as
      #if HTS_VERSION >= 101000  // Check for v1.10 or later
*/
// Maintainers: Bump this in the final stage of preparing a new release.
// Immediately after release, bump ZZ to 90 to distinguish in-development
// Git repository builds from the release; you may wish to increment this
// further when significant features are merged.
enum HTS_VERSION = 101200;

/*! @abstract Introspection on the features enabled in htslib
 *
 * @return a bitfield of HTS_FEATURE_* macros.
 */
uint hts_features();

const(char)* hts_test_feature(uint id);

/*! @abstract Introspection on the features enabled in htslib, string form
 *
 * @return a string describing htslib build features
 */
const(char)* hts_feature_string();

// Whether ./configure was used or vanilla Makefile
enum HTS_FEATURE_CONFIGURE = 1;

// Whether --enable-plugins was used
enum HTS_FEATURE_PLUGINS = 2;

// Transport specific
enum HTS_FEATURE_LIBCURL = 1u << 10;
enum HTS_FEATURE_S3 = 1u << 11;
enum HTS_FEATURE_GCS = 1u << 12;

// Compression options
enum HTS_FEATURE_LIBDEFLATE = 1u << 20;
enum HTS_FEATURE_LZMA = 1u << 21;
enum HTS_FEATURE_BZIP2 = 1u << 22;
enum HTS_FEATURE_HTSCODECS = 1u << 23; // htscodecs library version

// Build params
enum HTS_FEATURE_CC = 1u << 27;
enum HTS_FEATURE_CFLAGS = 1u << 28;
enum HTS_FEATURE_CPPFLAGS = 1u << 29;
enum HTS_FEATURE_LDFLAGS = 1u << 30;

/*!
  @abstract    Determine format by peeking at the start of a file
  @param fp    File opened for reading, positioned at the beginning
  @param fmt   Format structure that will be filled out on return
  @return      0 for success, or negative if an error occurred.
*/
int hts_detect_format(hFILE* fp, htsFormat* fmt);

/*!
  @abstract    Get a human-readable description of the file format
  @param fmt   Format structure holding type, version, compression, etc.
  @return      Description string, to be freed by the caller after use.
*/
char* hts_format_description(const(htsFormat)* format);

/*!
  @abstract       Open a sequence data (SAM/BAM/CRAM) or variant data (VCF/BCF)
                  or possibly-compressed textual line-orientated file
  @param fn       The file name or "-" for stdin/stdout. For indexed files
                  with a non-standard naming, the file name can include the
                  name of the index file delimited with HTS_IDX_DELIM
  @param mode     Mode matching / [rwa][bceguxz0-9]* /
  @discussion
      With 'r' opens for reading; any further format mode letters are ignored
      as the format is detected by checking the first few bytes or BGZF blocks
      of the file.  With 'w' or 'a' opens for writing or appending, with format
      specifier letters:
        b  binary format (BAM, BCF, etc) rather than text (SAM, VCF, etc)
        c  CRAM format
        g  gzip compressed
        u  uncompressed
        z  bgzf compressed
        [0-9]  zlib compression level
      and with non-format option letters (for any of 'r'/'w'/'a'):
        e  close the file on exec(2) (opens with O_CLOEXEC, where supported)
        x  create the file exclusively (opens with O_EXCL, where supported)
      Note that there is a distinction between 'u' and '0': the first yields
      plain uncompressed output whereas the latter outputs uncompressed data
      wrapped in the zlib format.
  @example
      [rw]b  .. compressed BCF, BAM, FAI
      [rw]bu .. uncompressed BCF
      [rw]z  .. compressed VCF
      [rw]   .. uncompressed VCF
*/
htsFile* hts_open(const(char)* fn, const(char)* mode);

/*!
  @abstract       Open a SAM/BAM/CRAM/VCF/BCF/etc file
  @param fn       The file name or "-" for stdin/stdout
  @param mode     Open mode, as per hts_open()
  @param fmt      Optional format specific parameters
  @discussion
      See hts_open() for description of fn and mode.
      // TODO Update documentation for s/opts/fmt/
      Opts contains a format string (sam, bam, cram, vcf, bcf) which will,
      if defined, override mode.  Opts also contains a linked list of hts_opt
      structures to apply to the open file handle.  These can contain things
      like pointers to the reference or information on compression levels,
      block sizes, etc.
*/
htsFile* hts_open_format(
    const(char)* fn,
    const(char)* mode,
    const(htsFormat)* fmt);

/*!
  @abstract       Open an existing stream as a SAM/BAM/CRAM/VCF/BCF/etc file
  @param fn       The already-open file handle
  @param mode     Open mode, as per hts_open()
*/
htsFile* hts_hopen(hFILE* fp, const(char)* fn, const(char)* mode);

/*!
  @abstract  Close a file handle, flushing buffered data for output streams
  @param fp  The file handle to be closed
  @return    0 for success, or negative if an error occurred.
*/
int hts_close(htsFile* fp);

/*!
  @abstract  Returns the file's format information
  @param fp  The file handle
  @return    Read-only pointer to the file's htsFormat.
*/
const(htsFormat)* hts_get_format(htsFile* fp);

/*!
  @ abstract      Returns a string containing the file format extension.
  @ param format  Format structure containing the file type.
  @ return        A string ("sam", "bam", etc) or "?" for unknown formats.
 */
const(char)* hts_format_file_extension(const(htsFormat)* format);

/*!
  @abstract  Sets a specified CRAM option on the open file handle.
  @param fp  The file handle open the open file.
  @param opt The CRAM_OPT_* option.
  @param ... Optional arguments, dependent on the option used.
  @return    0 for success, or negative if an error occurred.
*/
int hts_set_opt(htsFile* fp, hts_fmt_option opt, ...);

/*!
  @abstract         Read a line (and its \n or \r\n terminator) from a file
  @param fp         The file handle
  @param delimiter  Unused, but must be '\n' (or KS_SEP_LINE)
  @param str        The line (not including the terminator) is written here
  @return           Length of the string read;
                    -1 on end-of-file; <= -2 on error
*/
int hts_getline(htsFile* fp, int delimiter, kstring_t* str);

char** hts_readlines(const(char)* fn, int* _n);
/*!
    @abstract       Parse comma-separated list or read list from a file
    @param list     File name or comma-separated list
    @param is_file
    @param _n       Size of the output array (number of items read)
    @return         NULL on failure or pointer to newly allocated array of
                    strings
*/
char** hts_readlist(const(char)* fn, int is_file, int* _n);

/*!
  @abstract  Create extra threads to aid compress/decompression for this file
  @param fp  The file handle
  @param n   The number of worker threads to create
  @return    0 for success, or negative if an error occurred.
  @notes     This function creates non-shared threads for use solely by fp.
             The hts_set_thread_pool function is the recommended alternative.
*/
int hts_set_threads(htsFile* fp, int n);

/*!
  @abstract  Create extra threads to aid compress/decompression for this file
  @param fp  The file handle
  @param p   A pool of worker threads, previously allocated by hts_create_threads().
  @return    0 for success, or negative if an error occurred.
*/
int hts_set_thread_pool(htsFile* fp, htsThreadPool* p);

/*!
  @abstract  Adds a cache of decompressed blocks, potentially speeding up seeks.
             This may not work for all file types (currently it is bgzf only).
  @param fp  The file handle
  @param n   The size of cache, in bytes
*/
void hts_set_cache_size(htsFile* fp, int n);

/*!
  @abstract  Set .fai filename for a file opened for reading
  @return    0 for success, negative on failure
  @discussion
      Called before *_hdr_read(), this provides the name of a .fai file
      used to provide a reference list if the htsFile contains no @SQ headers.
*/
int hts_set_fai_filename(htsFile* fp, const(char)* fn_aux);

/*!
  @abstract  Sets a filter expression
  @return    0 for success, negative on failure
  @discussion
      To clear an existing filter, specifying expr as NULL.
*/
int hts_set_filter_expression(htsFile* fp, const(char)* expr);

/*!
  @abstract  Determine whether a given htsFile contains a valid EOF block
  @return    3 for a non-EOF checkable filetype;
             2 for an unseekable file type where EOF cannot be checked;
             1 for a valid EOF block;
             0 for if the EOF marker is absent when it should be present;
            -1 (with errno set) on failure
  @discussion
      Check if the BGZF end-of-file (EOF) marker is present
*/
int hts_check_EOF(htsFile* fp);

/************
 * Indexing *
 ************/

/*!
These HTS_IDX_* macros are used as special tid values for hts_itr_query()/etc,
producing iterators operating as follows:
 - HTS_IDX_NOCOOR iterates over unmapped reads sorted at the end of the file
 - HTS_IDX_START  iterates over the entire file
 - HTS_IDX_REST   iterates from the current position to the end of the file
 - HTS_IDX_NONE   always returns "no more alignment records"
When one of these special tid values is used, beg and end are ignored.
When REST or NONE is used, idx is also ignored and may be NULL.
*/
enum HTS_IDX_NOCOOR = -2;
enum HTS_IDX_START = -3;
enum HTS_IDX_REST = -4;
enum HTS_IDX_NONE = -5;

enum HTS_FMT_CSI = 0;
enum HTS_FMT_BAI = 1;
enum HTS_FMT_TBI = 2;
enum HTS_FMT_CRAI = 3;
enum HTS_FMT_FAI = 4;

// Almost INT64_MAX, but when cast into a 32-bit int it's
// also INT_MAX instead of -1.  This avoids bugs with old code
// using the new hts_pos_t data type.
enum HTS_POS_MAX = ((cast(long) INT_MAX) << 32) | INT_MAX;
enum HTS_POS_MIN = INT64_MIN;
enum PRIhts_pos = PRId64;
alias hts_pos_t = c_long;

// For comparison with previous release:
//
// #define HTS_POS_MAX INT_MAX
// #define HTS_POS_MIN INT_MIN
// #define PRIhts_pos PRId32
// typedef int32_t hts_pos_t;

struct hts_pair_pos_t
{
    hts_pos_t beg;
    hts_pos_t end;
}

alias hts_pair32_t = hts_pair_pos_t; // For backwards compatibility

struct hts_pair64_t
{
    ulong u;
    ulong v;
}

struct hts_pair64_max_t
{
    ulong u;
    ulong v;
    ulong max;
}

struct hts_reglist_t
{
    const(char)* reg;
    hts_pair_pos_t* intervals;
    int tid;
    uint count;
    hts_pos_t min_beg;
    hts_pos_t max_end;
}

alias hts_readrec_func = int function(BGZF* fp, void* data, void* r, int* tid, hts_pos_t* beg, hts_pos_t* end);
alias hts_seek_func = int function(void* fp, long offset, int where);
alias hts_tell_func = c_long function(void* fp);

/**
 * @brief File iterator that can handle multiple target regions.
 * This structure should be considered opaque by end users.
 * It does both the stepping inside the file and the filtering of alignments.
 * It can operate in single or multi-region mode, and depending on this,
 * it uses different fields.
 *
 * read_rest (1) - read everything from the current offset, without filtering
 * finished  (1) - no more iterations
 * is_cram   (1) - current file has CRAM format
 * nocoor    (1) - read all unmapped reads
 *
 * multi     (1) - multi-region moode
 * reg_list  - List of target regions
 * n_reg     - Size of the above list
 * curr_reg  - List index of the current region of search
 * curr_intv - Interval index inside the current region; points to a (beg, end)
 * end       - Used for CRAM files, to preserve the max end coordinate
 *
 * multi     (0) - single-region mode
 * tid       - Reference id of the target region
 * beg       - Start position of the target region
 * end       - End position of the target region
 *
 * Common fields:
 * off        - List of file offsets computed from the index
 * n_off      - Size of the above list
 * i          - List index of the current file offset
 * curr_off   - File offset for the next file read
 * curr_tid   - Reference id of the current alignment
 * curr_beg   - Start position of the current alignment
 * curr_end   - End position of the current alignment
 * nocoor_off - File offset where the unmapped reads start
 *
 * readrec    - File specific function that reads an alignment
 * seek       - File specific function for changing the file offset
 * tell       - File specific function for indicating the file offset
 */

struct hts_itr_t
{
    import std.bitmanip : bitfields;

    mixin(bitfields!(
        uint, "read_rest", 1,
        uint, "finished", 1,
        uint, "is_cram", 1,
        uint, "nocoor", 1,
        uint, "multi", 1,
        uint, "dummy", 27));

    int tid;
    int n_off;
    int i;
    int n_reg;
    hts_pos_t beg;
    hts_pos_t end;
    hts_reglist_t* reg_list;
    int curr_tid;
    int curr_reg;
    int curr_intv;
    hts_pos_t curr_beg;
    hts_pos_t curr_end;
    ulong curr_off;
    ulong nocoor_off;
    hts_pair64_max_t* off;
    int function() readrec;
    int function() seek;
    long function() tell;

    struct _Anonymous_3
    {
        int n;
        int m;
        int* a;
    }

    _Anonymous_3 bins;
}

alias hts_itr_multi_t = hts_itr_t;

extern (D) auto hts_bin_first(T)(auto ref T l)
{
    return ((1 << ((l << 1) + l)) - 1) / 7;
}

extern (D) auto hts_bin_parent(T)(auto ref T l)
{
    return (l - 1) >> 3;
}

///////////////////////////////////////////////////////////
// Low-level API for building indexes.

/// Create a BAI/CSI/TBI type index structure
/** @param n          Initial number of targets
    @param fmt        Format, one of HTS_FMT_CSI, HTS_FMT_BAI or HTS_FMT_TBI
    @param offset0    Initial file offset
    @param min_shift  Number of bits for the minimal interval
    @param n_lvls     Number of levels in the binning index
    @return An initialised hts_idx_t struct on success; NULL on failure

The struct returned by a successful call should be freed via hts_idx_destroy()
when it is no longer needed.
*/
hts_idx_t* hts_idx_init(
    int n,
    int fmt,
    ulong offset0,
    int min_shift,
    int n_lvls);

/// Free a BAI/CSI/TBI type index
/** @param idx   Index structure to free
 */
void hts_idx_destroy(hts_idx_t* idx);

/// Push an index entry
/** @param idx        Index
    @param tid        Target id
    @param beg        Range start (zero-based)
    @param end        Range end (zero-based, half-open)
    @param offset     File offset
    @param is_mapped  Range corresponds to a mapped read
    @return 0 on success; -1 on failure

The @p is_mapped parameter is used to update the n_mapped / n_unmapped counts
stored in the meta-data bin.
 */
int hts_idx_push(
    hts_idx_t* idx,
    int tid,
    hts_pos_t beg,
    hts_pos_t end,
    ulong offset,
    int is_mapped);

/// Finish building an index
/** @param idx          Index
    @param final_offset Last file offset
    @return 0 on success; non-zero on failure.
*/
int hts_idx_finish(hts_idx_t* idx, ulong final_offset);

/// Returns index format
/** @param idx   Index
    @return One of HTS_FMT_CSI, HTS_FMT_BAI or HTS_FMT_TBI
*/
int hts_idx_fmt(hts_idx_t* idx);

/// Add name to TBI index meta-data
/** @param idx   Index
    @param tid   Target identifier
    @param name  Target name
    @return Index number of name in names list on success; -1 on failure.
*/
int hts_idx_tbi_name(hts_idx_t* idx, int tid, const(char)* name);

// Index loading and saving

/// Save an index to a file
/** @param idx  Index to be written
    @param fn   Input BAM/BCF/etc filename, to which .bai/.csi/etc will be added
    @param fmt  One of the HTS_FMT_* index formats
    @return  0 if successful, or negative if an error occurred.
*/
int hts_idx_save(const(hts_idx_t)* idx, const(char)* fn, int fmt);

/// Save an index to a specific file
/** @param idx    Index to be written
    @param fn     Input BAM/BCF/etc filename
    @param fnidx  Output filename, or NULL to add .bai/.csi/etc to @a fn
    @param fmt    One of the HTS_FMT_* index formats
    @return  0 if successful, or negative if an error occurred.
*/
int hts_idx_save_as(
    const(hts_idx_t)* idx,
    const(char)* fn,
    const(char)* fnidx,
    int fmt);

/// Load an index file
/** @param fn   BAM/BCF/etc filename, to which .bai/.csi/etc will be added or
                the extension substituted, to search for an existing index file.
                In case of a non-standard naming, the file name can include the
                name of the index file delimited with HTS_IDX_DELIM.
    @param fmt  One of the HTS_FMT_* index formats
    @return  The index, or NULL if an error occurred.

If @p fn contains the string "##idx##" (HTS_IDX_DELIM), the part before
the delimiter will be used as the name of the data file and the part after
it will be used as the name of the index.

Otherwise, this function tries to work out the index name as follows:

  It will try appending ".csi" to @p fn
  It will try substituting an existing suffix (e.g. .bam, .vcf) with ".csi"
  Then, if @p fmt is HTS_FMT_BAI:
    It will try appending ".bai" to @p fn
    To will substituting the existing suffix (e.g. .bam) with ".bai"
  else if @p fmt is HTS_FMT_TBI:
    It will try appending ".tbi" to @p fn
    To will substituting the existing suffix (e.g. .vcf) with ".tbi"

If the index file is remote (served over a protocol like https), first a check
is made to see is a locally cached copy is available.  This is done for all
of the possible names listed above.  If a cached copy is not available then
the index will be downloaded and stored in the current working directory,
with the same name as the remote index.

    Equivalent to hts_idx_load3(fn, NULL, fmt, HTS_IDX_SAVE_REMOTE);
*/
hts_idx_t* hts_idx_load(const(char)* fn, int fmt);

/// Load a specific index file
/** @param fn     Input BAM/BCF/etc filename
    @param fnidx  The input index filename
    @return  The index, or NULL if an error occurred.

    Equivalent to hts_idx_load3(fn, fnidx, 0, 0);

    This function will not attempt to save index files locally.
*/
hts_idx_t* hts_idx_load2(const(char)* fn, const(char)* fnidx);

/// Load a specific index file
/** @param fn     Input BAM/BCF/etc filename
    @param fnidx  The input index filename
    @param fmt    One of the HTS_FMT_* index formats
    @param flags  Flags to alter behaviour (see description)
    @return  The index, or NULL if an error occurred.

    If @p fnidx is NULL, the index name will be derived from @p fn in the
    same way as hts_idx_load().

    If @p fnidx is not NULL, @p fmt is ignored.

    The @p flags parameter can be set to a combination of the following
    values:

        HTS_IDX_SAVE_REMOTE   Save a local copy of any remote indexes
        HTS_IDX_SILENT_FAIL   Fail silently if the index is not present

    The index struct returned by a successful call should be freed
    via hts_idx_destroy() when it is no longer needed.
*/
hts_idx_t* hts_idx_load3(
    const(char)* fn,
    const(char)* fnidx,
    int fmt,
    int flags);

/// Flags for hts_idx_load3() ( and also sam_idx_load3(), tbx_idx_load3() )
enum HTS_IDX_SAVE_REMOTE = 1;
enum HTS_IDX_SILENT_FAIL = 2;

///////////////////////////////////////////////////////////
// Functions for accessing meta-data stored in indexes

/// Get extra index meta-data
/** @param idx    The index
    @param l_meta Pointer to where the length of the extra data is stored
    @return Pointer to the extra data if present; NULL otherwise

    Indexes (both .tbi and .csi) made by tabix include extra data about
    the indexed file.  The returns a pointer to this data.  Note that the
    data is stored exactly as it is in the index.  Callers need to interpret
    the results themselves, including knowing what sort of data to expect;
    byte swapping etc.
*/
ubyte* hts_idx_get_meta(hts_idx_t* idx, uint* l_meta);

/// Set extra index meta-data
/** @param idx     The index
    @param l_meta  Length of data
    @param meta    Pointer to the extra data
    @param is_copy If not zero, a copy of the data is taken
    @return 0 on success; -1 on failure (out of memory).

    Sets the data that is returned by hts_idx_get_meta().

    If is_copy != 0, a copy of the input data is taken.  If not, ownership of
    the data pointed to by *meta passes to the index.
*/
int hts_idx_set_meta(hts_idx_t* idx, uint l_meta, ubyte* meta, int is_copy);

/// Get number of mapped and unmapped reads from an index
/** @param      idx      Index
    @param      tid      Target ID
    @param[out] mapped   Location to store number of mapped reads
    @param[out] unmapped Location to store number of unmapped reads
    @return 0 on success; -1 on failure (data not available)

    BAI and CSI indexes store information on the number of reads for each
    target that were mapped or unmapped (unmapped reads will generally have
    a paired read that is mapped to the target).  This function returns this
    information if it is available.

    @note Cram CRAI indexes do not include this information.
*/
int hts_idx_get_stat(
    const(hts_idx_t)* idx,
    int tid,
    ulong* mapped,
    ulong* unmapped);

/// Return the number of unplaced reads from an index
/** @param idx    Index
    @return Unplaced reads count

    Unplaced reads are not linked to any reference (e.g. RNAME is '*' in SAM
    files).
*/
ulong hts_idx_get_n_no_coor(const(hts_idx_t)* idx);

///////////////////////////////////////////////////////////
// Region parsing

enum HTS_PARSE_THOUSANDS_SEP = 1; ///< Ignore ',' separators within numbers
enum HTS_PARSE_ONE_COORD = 2; ///< chr:pos means chr:pos-pos and not chr:pos-end
enum HTS_PARSE_LIST = 4; ///< Expect a comma separated list of regions. (Disables HTS_PARSE_THOUSANDS_SEP)

/// Parse a numeric string
/** The number may be expressed in scientific notation, and optionally may
    contain commas in the integer part (before any decimal point or E notation).
    @param str     String to be parsed
    @param strend  If non-NULL, set on return to point to the first character
                   in @a str after those forming the parsed number
    @param flags   Or'ed-together combination of HTS_PARSE_* flags
    @return  Converted value of the parsed number.

    When @a strend is NULL, a warning will be printed (if hts_verbose is HTS_LOG_WARNING
    or more) if there are any trailing characters after the number.
*/
long hts_parse_decimal(const(char)* str, char** strend, int flags);

alias hts_name2id_f = int function(void*, const(char)*);
alias hts_id2name_f = const(char)* function(void*, int);

/// Parse a "CHR:START-END"-style region string
/** @param str  String to be parsed
    @param beg  Set on return to the 0-based start of the region
    @param end  Set on return to the 1-based end of the region
    @return  Pointer to the colon or '\0' after the reference sequence name,
             or NULL if @a str could not be parsed.

    NOTE: For compatibility with hts_parse_reg only.
    Please use hts_parse_region instead.
*/
const(char)* hts_parse_reg64(const(char)* str, hts_pos_t* beg, hts_pos_t* end);

/// Parse a "CHR:START-END"-style region string
/** @param str  String to be parsed
    @param beg  Set on return to the 0-based start of the region
    @param end  Set on return to the 1-based end of the region
    @return  Pointer to the colon or '\0' after the reference sequence name,
             or NULL if @a str could not be parsed.
*/
const(char)* hts_parse_reg(const(char)* str, int* beg, int* end);

/// Parse a "CHR:START-END"-style region string
/** @param str   String to be parsed
    @param tid   Set on return (if not NULL) to be reference index (-1 if invalid)
    @param beg   Set on return to the 0-based start of the region
    @param end   Set on return to the 1-based end of the region
    @param getid Function pointer.  Called if not NULL to set tid.
    @param hdr   Caller data passed to getid.
    @param flags Bitwise HTS_PARSE_* flags listed above.
    @return      Pointer to the byte after the end of the entire region
                 specifier (including any trailing comma) on success,
                 or NULL if @a str could not be parsed.

    A variant of hts_parse_reg which is reference-id aware.  It uses
    the iterator name2id callbacks to validate the region tokenisation works.

    This is necessary due to GRCh38 HLA additions which have reference names
    like "HLA-DRB1*12:17".

    To work around ambiguous parsing issues, eg both "chr1" and "chr1:100-200"
    are reference names, quote using curly braces.
    Thus "{chr1}:100-200" and "{chr1:100-200}" disambiguate the above example.

    Flags are used to control how parsing works, and can be one of the below.

    HTS_PARSE_THOUSANDS_SEP:
        Ignore commas in numbers.  For example with this flag 1,234,567
        is interpreted as 1234567.

    HTS_PARSE_LIST:
        If present, the region is assmed to be a comma separated list and
        position parsing will not contain commas (this implicitly
        clears HTS_PARSE_THOUSANDS_SEP in the call to hts_parse_decimal).
        On success the return pointer will be the start of the next region, ie
        the character after the comma.  (If *ret != '\0' then the caller can
        assume another region is present in the list.)

        If not set then positions may contain commas.  In this case the return
        value should point to the end of the string, or NULL on failure.

    HTS_PARSE_ONE_COORD:
        If present, X:100 is treated as the single base pair region X:100-100.
        In this case X:-100 is shorthand for X:1-100 and X:100- is X:100-<end>.
        (This is the standard bcftools region convention.)

        When not set X:100 is considered to be X:100-<end> where <end> is
        the end of chromosome X (set to INT_MAX here).  X:100- and X:-100 are
        invalid.
        (This is the standard samtools region convention.)

    Note the supplied string expects 1 based inclusive coordinates, but the
    returned coordinates start from 0 and are half open, so pos0 is valid
    for use in e.g. "for (pos0 = beg; pos0 < end; pos0++) {...}"

    If NULL is returned, the value in tid mat give additional information
    about the error:

        -2   Failed to parse @p hdr; or out of memory
        -1   The reference in @p str has mismatched braces, or does not
             exist in @p hdr
        >= 0 The specified range in @p str could not be parsed
*/
const(char)* hts_parse_region(
    const(char)* s,
    int* tid,
    hts_pos_t* beg,
    hts_pos_t* end,
    hts_name2id_f getid,
    void* hdr,
    int flags);

///////////////////////////////////////////////////////////
// Generic iterators
//
// These functions provide the low-level infrastructure for iterators.
// Wrappers around these are used to make iterators for specific file types.
// See:
//     htslib/sam.h  for SAM/BAM/CRAM iterators
//     htslib/vcf.h  for VCF/BCF iterators
//     htslib/tbx.h  for files indexed by tabix

/// Create a single-region iterator
/** @param idx      Index
    @param tid      Target ID
    @param beg      Start of region
    @param end      End of region
    @param readrec  Callback to read a record from the input file
    @return An iterator on success; NULL on failure

    The iterator struct returned by a successful call should be freed
    via hts_itr_destroy() when it is no longer needed.
 */
hts_itr_t* hts_itr_query(
    const(hts_idx_t)* idx,
    int tid,
    hts_pos_t beg,
    hts_pos_t end,
    int function() readrec);

/// Free an iterator
/** @param iter   Iterator to free
 */
void hts_itr_destroy(hts_itr_t* iter);

alias hts_itr_query_func = hts_itr_t* function(const(hts_idx_t)* idx, int tid, hts_pos_t beg, hts_pos_t end, int function() readrec);

/// Create a single-region iterator from a text region specification
/** @param idx       Index
    @param reg       Region specifier
    @param getid     Callback function to return the target ID for a name
    @param hdr       Input file header
    @param itr_query Callback function returning an iterator for a numeric tid,
                     start and end position
    @param readrec   Callback to read a record from the input file
    @return An iterator on success; NULL on error

    The iterator struct returned by a successful call should be freed
    via hts_itr_destroy() when it is no longer needed.
 */
hts_itr_t* hts_itr_querys(
    const(hts_idx_t)* idx,
    const(char)* reg,
    hts_name2id_f getid,
    void* hdr,
    hts_itr_t* function() itr_query,
    int function() readrec);

/// Return the next record from an iterator
/** @param fp      Input file handle
    @param iter    Iterator
    @param r       Pointer to record placeholder
    @param data    Data passed to the readrec callback
    @return >= 0 on success, -1 when there is no more data, < -1 on error
 */
int hts_itr_next(BGZF* fp, hts_itr_t* iter, void* r, void* data);

/// Return a list of target names from an index
/** @param      idx    Index
    @param[out] n      Location to store the number of targets
    @param      getid  Callback function to get the name for a target ID
    @param      hdr    Header from indexed file
    @return An array of pointers to the names on success; NULL on failure

    @note The names are pointers into the header data structure.  When cleaning
    up, only the array should be freed, not the names.
 */
const(char*)* hts_idx_seqnames(
    const(hts_idx_t)* idx,
    int* n,
    hts_id2name_f getid,
    void* hdr); // free only the array, not the values

/**********************************
 * Iterator with multiple regions *
 **********************************/

alias hts_itr_multi_query_func = int function(const(hts_idx_t)* idx, hts_itr_t* itr);
int hts_itr_multi_bam(const(hts_idx_t)* idx, hts_itr_t* iter);
int hts_itr_multi_cram(const(hts_idx_t)* idx, hts_itr_t* iter);

/// Create a multi-region iterator from a region list
/** @param idx          Index
    @param reglist      Region list
    @param count        Number of items in region list
    @param getid        Callback to convert names to target IDs
    @param hdr          Indexed file header (passed to getid)
    @param itr_specific Filetype-specific callback function
    @param readrec      Callback to read an input file record
    @param seek         Callback to seek in the input file
    @param tell         Callback to return current input file location
    @return An iterator on success; NULL on failure

    The iterator struct returned by a successful call should be freed
    via hts_itr_destroy() when it is no longer needed.
 */
hts_itr_t* hts_itr_regions(
    const(hts_idx_t)* idx,
    hts_reglist_t* reglist,
    int count,
    hts_name2id_f getid,
    void* hdr,
    int function() itr_specific,
    int function() readrec,
    int function() seek,
    long function() tell);

/// Return the next record from an iterator
/** @param fp      Input file handle
    @param iter    Iterator
    @param r       Pointer to record placeholder
    @return >= 0 on success, -1 when there is no more data, < -1 on error
 */
int hts_itr_multi_next(htsFile* fd, hts_itr_t* iter, void* r);

/// Create a region list from a char array
/** @param argv      Char array of target:interval elements, e.g. chr1:2500-3600, chr1:5100, chr2
    @param argc      Number of items in the array
    @param r_count   Pointer to the number of items in the resulting region list
    @param hdr       Header for the sam/bam/cram file
    @param getid     Callback to convert target names to target ids.
    @return  A region list on success, NULL on failure

    The hts_reglist_t struct returned by a successful call should be freed
    via hts_reglist_free() when it is no longer needed.
 */
hts_reglist_t* hts_reglist_create(
    char** argv,
    int argc,
    int* r_count,
    void* hdr,
    hts_name2id_f getid);

/// Free a region list
/** @param reglist    Region list
    @param count      Number of items in the list
 */
void hts_reglist_free(hts_reglist_t* reglist, int count);

/// Free a multi-region iterator
/** @param iter   Iterator to free
 */
alias hts_itr_multi_destroy = hts_itr_destroy;

/**
 * hts_file_type() - Convenience function to determine file type
 * DEPRECATED:  This function has been replaced by hts_detect_format().
 * It and these FT_* macros will be removed in a future HTSlib release.
 */
enum FT_UNKN = 0;
enum FT_GZ = 1;
enum FT_VCF = 2;
enum FT_VCF_GZ = FT_GZ | FT_VCF;
enum FT_BCF = 1 << 2;
enum FT_BCF_GZ = FT_GZ | FT_BCF;
enum FT_STDIN = 1 << 3;
int hts_file_type(const(char)* fname);

/***************************
 * Revised MAQ error model *
 ***************************/

struct errmod_t;

errmod_t* errmod_init(double depcorr);
void errmod_destroy(errmod_t* em);

/*
    n: number of bases
    m: maximum base
    bases[i]: qual:6, strand:1, base:4
    q[i*m+j]: phred-scaled likelihood of (i,j)
 */
int errmod_cal(const(errmod_t)* em, int n, int m, ushort* bases, float* q);

/*****************************************************
 * Probabilistic banded glocal alignment             *
 * See https://doi.org/10.1093/bioinformatics/btr076 *
 *****************************************************/

struct probaln_par_t
{
    float d;
    float e;
    int bw;
}

/// Perform probabilistic banded glocal alignment
/** @param      ref     Reference sequence
    @param      l_ref   Length of reference
    @param      query   Query sequence
    @param      l_query Length of query sequence
    @param      iqual   Query base qualities
    @param      c       Alignment parameters
    @param[out] state   Output alignment
    @param[out] q    Phred scaled posterior probability of state[i] being wrong
    @return     Phred-scaled likelihood score, or INT_MIN on failure.

The reference and query sequences are coded using integers 0,1,2,3,4 for
bases A,C,G,T,N respectively (N here is for any ambiguity code).

On output, state and q are arrays of length l_query. The higher 30
bits give the reference position the query base is matched to and the
lower two bits can be 0 (an alignment match) or 1 (an
insertion). q[i] gives the phred scaled posterior probability of
state[i] being wrong.

On failure, errno will be set to EINVAL if the values of l_ref or l_query
were invalid; or ENOMEM if a memory allocation failed.
*/

int probaln_glocal(
    const(ubyte)* ref_,
    int l_ref,
    const(ubyte)* query,
    int l_query,
    const(ubyte)* iqual,
    const(probaln_par_t)* c,
    int* state,
    ubyte* q);

/**********************
 * MD5 implementation *
 **********************/

struct hts_md5_context;

/*! @abstract   Initialises an MD5 context.
 *  @discussion
 *    The expected use is to allocate an hts_md5_context using
 *    hts_md5_init().  This pointer is then passed into one or more calls
 *    of hts_md5_update() to compute successive internal portions of the
 *    MD5 sum, which can then be externalised as a full 16-byte MD5sum
 *    calculation by calling hts_md5_final().  This can then be turned
 *    into ASCII via hts_md5_hex().
 *
 *    To dealloate any resources created by hts_md5_init() call the
 *    hts_md5_destroy() function.
 *
 *  @return     hts_md5_context pointer on success, NULL otherwise.
 */
hts_md5_context* hts_md5_init();

/*! @abstract Updates the context with the MD5 of the data. */
void hts_md5_update(hts_md5_context* ctx, const(void)* data, c_ulong size);

/*! @abstract Computes the final 128-bit MD5 hash from the given context */
void hts_md5_final(ubyte* digest, hts_md5_context* ctx);

/*! @abstract Resets an md5_context to the initial state, as returned
 *            by hts_md5_init().
 */
void hts_md5_reset(hts_md5_context* ctx);

/*! @abstract Converts a 128-bit MD5 hash into a 33-byte nul-termninated
 *            hex string.
 */
void hts_md5_hex(char* hex, const(ubyte)* digest);

/*! @abstract Deallocates any memory allocated by hts_md5_init. */
void hts_md5_destroy(hts_md5_context* ctx);

int hts_reg2bin(hts_pos_t beg, hts_pos_t end, int min_shift, int n_lvls);

// compute the level of bin
int hts_bin_bot(int bin, int n_lvls);

/**************
 * Endianness *
 **************/

int ed_is_big();
ushort ed_swap_2(ushort v);
void* ed_swap_2p(void* x);
uint ed_swap_4(uint v);
void* ed_swap_4p(void* x);
ulong ed_swap_8(ulong v);
void* ed_swap_8p(void* x);

