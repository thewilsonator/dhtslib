/// @file htslib/cram.h
/// CRAM format-specific API functions.
/*
    Copyright (C) 2015, 2016, 2018-2020 Genome Research Ltd.

    Author: James Bonfield <jkb@sanger.ac.uk>

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

/** @file
 * Consider using the higher level hts_*() API for programs that wish to
 * be file format agnostic (see htslib/hts.h).
 *
 * This API should be used for CRAM specific code. The specifics of the
 * public API are implemented in cram_io.h, cram_encode.h and cram_decode.h
 * although these should not be included directly (use this file instead).
 */

module htslib.cram;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.stdarg : va_list;

import htslib.sam;
import htslib.hts;
import htslib.hfile : hFILE;

extern (C):

// see cram/cram_structs.h for an internal more complete copy of this enum

// Htslib 1.11 had these listed without any hts prefix, and included
// some internal values such as RANS1 and GZIP_RLE (which shouldn't have ever
// been public).
//
// We can't find evidence of these being used and the data type occurs
// nowhere in functions or structures meaning using it would be pointless.
// However for safety, if you absolute need the API to not change then
// define HTS_COMPAT to 101100 (XYYYZZ for X.Y[.Z], meaning 1.11).

// Public methods as defined in the CRAM spec.

// CRAM 2.x and 3.0

// NB: the subsequent numbers may change.  They're simply here for
// compatibility with the old API, but may have no bearing on the
// internal way htslib works.  DO NOT USE

//#include <sys/types.h>
alias off_t = size_t;
alias ssize_t = size_t;

enum cram_block_method
{
    BM_ERROR = -1,
    RAW = 0,
    GZIP = 1,
    BZIP2 = 2,
    LZMA = 3,
    RANS = 4, // Generic; either order
    RANS0 = 4,
    RANS1 = 10, // Not externalised; stored as RANS (generic)
    GZIP_RLE = 11 // NB: not externalised in CRAM
}

enum cram_content_type
{
    CT_ERROR = -1,
    FILE_HEADER = 0,
    COMPRESSION_HEADER = 1,
    MAPPED_SLICE = 2,
    UNMAPPED_SLICE = 3, // CRAM V1.0 only
    EXTERNAL = 4,
    CORE = 5
}

// Opaque data types, see cram_structs for the fully fledged versions.
struct cram_file_def;
struct cram_fd;
struct cram_container;
struct cram_block;
struct cram_slice;
struct cram_metrics;
struct cram_block_slice_hdr;
struct cram_block_compression_hdr;
struct refs_t;

// Accessor functions

/*
 *-----------------------------------------------------------------------------
 * cram_fd
 */
sam_hdr_t* cram_fd_get_header(cram_fd* fd);

void cram_fd_set_header(cram_fd* fd, sam_hdr_t* hdr);

int cram_fd_get_version(cram_fd* fd);

void cram_fd_set_version(cram_fd* fd, int vers);

int cram_major_vers(cram_fd* fd);
int cram_minor_vers(cram_fd* fd);

hFILE* cram_fd_get_fp(cram_fd* fd);
void cram_fd_set_fp(cram_fd* fd, hFILE* fp);

/*
 *-----------------------------------------------------------------------------
 * cram_container
 */
int cram_container_get_length(cram_container* c);
void cram_container_set_length(cram_container* c, int length);
int cram_container_get_num_blocks(cram_container* c);
void cram_container_set_num_blocks(cram_container* c, int num_blocks);
int* cram_container_get_landmarks(cram_container* c, int* num_landmarks);
void cram_container_set_landmarks(
    cram_container* c,
    int num_landmarks,
    int* landmarks);

/* Returns true if the container is empty (EOF marker) */
int cram_container_is_empty(cram_fd* fd);

/*
 *-----------------------------------------------------------------------------
 * cram_block
 */
int cram_block_get_content_id(cram_block* b);
int cram_block_get_comp_size(cram_block* b);
int cram_block_get_uncomp_size(cram_block* b);
int cram_block_get_crc32(cram_block* b);
void* cram_block_get_data(cram_block* b);

cram_content_type cram_block_get_content_type(cram_block* b);

void cram_block_set_content_id(cram_block* b, int id);
void cram_block_set_comp_size(cram_block* b, int size);
void cram_block_set_uncomp_size(cram_block* b, int size);
void cram_block_set_crc32(cram_block* b, int crc);
void cram_block_set_data(cram_block* b, void* data);

int cram_block_append(cram_block* b, const(void)* data, int size);
void cram_block_update_size(cram_block* b);

// Offset is known as "size" internally, but it can be confusing.
size_t cram_block_get_offset(cram_block* b);
void cram_block_set_offset(cram_block* b, size_t offset);

/*
 * Computes the size of a cram block, including the block
 * header itself.
 */
uint cram_block_size(cram_block* b);

/*
 * Renumbers RG numbers in a cram compression header.
 *
 * CRAM stores RG as the Nth number in the header, rather than a
 * string holding the ID: tag.  This is smaller in space, but means
 * "samtools cat" to join files together that contain single but
 * different RG lines needs a way of renumbering them.
 *
 * The file descriptor is expected to be immediately after the
 * cram_container structure (ie before the cram compression header).
 * Due to the nature of the CRAM format, this needs to read and write
 * the blocks itself.  Note that there may be multiple slices within
 * the container, meaning multiple compression headers to manipulate.
 * Changing RG may change the size of the compression header and
 * therefore the length field in the container.  Hence we rewrite all
 * blocks just in case and also emit the adjusted container.
 *
 * The current implementation can only cope with renumbering a single
 * RG (and only then if it is using HUFFMAN or BETA codecs).  In
 * theory it *may* be possible to renumber multiple RGs if they use
 * HUFFMAN to the CORE block or use an external block unshared by any
 * other data series.  So we have an API that can be upgraded to
 * support this, but do not implement it for now.  An example
 * implementation of RG as an EXTERNAL block would be to find that
 * block and rewrite it, returning the number of blocks consumed.
 *
 * Returns 0 on success;
 *        -1 if unable to edit;
 *        -2 on other errors (eg I/O).
 */
int cram_transcode_rg(
    cram_fd* in_,
    cram_fd* out_,
    cram_container* c,
    int nrg,
    int* in_rg,
    int* out_rg);

/*
 * Copies the blocks representing the next num_slice slices from a
 * container from 'in' to 'out'.  It is expected that the file pointer
 * is just after the read of the cram_container and cram compression
 * header.
 *
 * Returns 0 on success
 *        -1 on failure
 */
int cram_copy_slice(cram_fd* in_, cram_fd* out_, int num_slice);

/*
 *-----------------------------------------------------------------------------
 * cram_io basics
 */

/**@{ ----------------------------------------------------------------------
 * CRAM blocks - the dynamically growable data block. We have code to
 * create, update, (un)compress and read/write.
 *
 * These are derived from the deflate_interlaced.c blocks, but with the
 * CRAM extension of content types and IDs.
 */

/*! Allocates a new cram_block structure with a specified content_type and
 * id.
 *
 * @return
 * Returns block pointer on success;
 *         NULL on failure
 *
 * The cram_block struct returned by a successful call should be freed
 * via cram_free_block() when it is no longer needed.
 */
cram_block* cram_new_block(cram_content_type content_type, int content_id);

/*! Reads a block from a cram file.
 *
 * @return
 * Returns cram_block pointer on success;
 *         NULL on failure
 *
 * The cram_block struct returned by a successful call should be freed
 * via cram_free_block() when it is no longer needed.
 */
cram_block* cram_read_block(cram_fd* fd);

/*! Writes a CRAM block.
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_write_block(cram_fd* fd, cram_block* b);

/*! Frees a CRAM block, deallocating internal data too.
 */
void cram_free_block(cram_block* b);

/*! Uncompresses a CRAM block, if compressed.
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_uncompress_block(cram_block* b);

/*! Compresses a block.
 *
 * Compresses a block using one of two different zlib strategies. If we only
 * want one choice set strat2 to be -1.
 *
 * The logic here is that sometimes Z_RLE does a better job than Z_FILTERED
 * or Z_DEFAULT_STRATEGY on quality data. If so, we'd rather use it as it is
 * significantly faster.
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_compress_block(
    cram_fd* fd,
    cram_block* b,
    cram_metrics* metrics,
    int method,
    int level);
int cram_compress_block2(
    cram_fd* fd,
    cram_slice* s,
    cram_block* b,
    cram_metrics* metrics,
    int method,
    int level);

/**@}*/
/**@{ ----------------------------------------------------------------------
 * Containers
 */

/*! Creates a new container, specifying the maximum number of slices
 * and records permitted.
 *
 * @return
 * Returns cram_container ptr on success;
 *         NULL on failure
 *
 * The cram_container struct returned by a successful call should be freed
 * via cram_free_container() when it is no longer needed.
 */
cram_container* cram_new_container(int nrec, int nslice);
void cram_free_container(cram_container* c);

/*! Reads a container header.
 *
 * @return
 * Returns cram_container on success;
 *         NULL on failure or no container left (fd->err == 0).
 *
 * The cram_container struct returned by a successful call should be freed
 * via cram_free_container() when it is no longer needed.
 */
cram_container* cram_read_container(cram_fd* fd);

/*! Writes a container structure.
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_write_container(cram_fd* fd, cram_container* h);

/*
 * Stores the container structure in dat and returns *size as the
 * number of bytes written to dat[].  The input size of dat is also
 * held in *size and should be initialised to cram_container_size(c).
 *
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_store_container(cram_fd* fd, cram_container* c, char* dat, int* size);

int cram_container_size(cram_container* c);

/**@}*/
/**@{ ----------------------------------------------------------------------
 * The top-level cram opening, closing and option handling
 */

/*! Opens a CRAM file for read (mode "rb") or write ("wb").
 *
 * The filename may be "-" to indicate stdin or stdout.
 *
 * @return
 * Returns file handle on success;
 *         NULL on failure.
 */
cram_fd* cram_open(const(char)* filename, const(char)* mode);

/*! Opens an existing stream for reading or writing.
 *
 * @return
 * Returns file handle on success;
 *         NULL on failure.
 */
cram_fd* cram_dopen(hFILE* fp, const(char)* filename, const(char)* mode);

/*! Closes a CRAM file.
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_close(cram_fd* fd);

/*
 * Seek within a CRAM file.
 *
 * Returns 0 on success
 *        -1 on failure
 */
int cram_seek(cram_fd* fd, off_t offset, int whence);

/*
 * Flushes a CRAM file.
 * Useful for when writing to stdout without wishing to close the stream.
 *
 * Returns 0 on success
 *        -1 on failure
 */
int cram_flush(cram_fd* fd);

/*! Checks for end of file on a cram_fd stream.
 *
 * @return
 * Returns 0 if not at end of file
 *         1 if we hit an expected EOF (end of range or EOF block)
 *         2 for other EOF (end of stream without EOF block)
 */
int cram_eof(cram_fd* fd);

/*! Sets options on the cram_fd.
 *
 * See CRAM_OPT_* definitions in hts.h.
 * Use this immediately after opening.
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_set_option(cram_fd* fd, hts_fmt_option opt, ...);

/*! Sets options on the cram_fd.
 *
 * See CRAM_OPT_* definitions in hts.h.
 * Use this immediately after opening.
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_set_voption(cram_fd* fd, hts_fmt_option opt, va_list args);

/*!
 * Attaches a header to a cram_fd.
 *
 * This should be used when creating a new cram_fd for writing where
 * we have an SAM_hdr already constructed (eg from a file we've read
 * in).
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
int cram_set_header(cram_fd* fd, sam_hdr_t* hdr);

/*! Check if this file has a proper EOF block
 *
 * @return
 * Returns 3 if the file is a version of CRAM that does not contain EOF blocks
 *         2 if the file is a stream and thus unseekable
 *         1 if the file contains an EOF block
 *         0 if the file does not contain an EOF block
 *        -1 if an error occurred whilst reading the file or we could not seek back to where we were
 *
 */
int cram_check_EOF(cram_fd* fd);

/* As int32_decoded/encode, but from/to blocks instead of cram_fd */
int int32_put_blk(cram_block* b, int val);

/**@}*/
/**@{ -------------------------------------------------------------------
 * Old typedef and function names for compatibility with existing code.
 * Header functionality is now provided by sam.h's sam_hdr_t functions.
 */

alias SAM_hdr = sam_hdr_t;

/*! Tokenises a SAM header into a hash table.
 *
 * Also extracts a few bits on specific data types, such as @RG lines.
 *
 * @return
 * Returns a SAM_hdr struct on success (free with sam_hdr_free());
 *         NULL on failure
 */
pragma(inline, true)
SAM_hdr* sam_hdr_parse_(const (char)* hdr, size_t len) { return sam_hdr_parse(len, hdr); }

/*! Deallocates all storage used by a SAM_hdr struct.
 *
 * This also decrements the header reference count. If after decrementing
 * it is still non-zero then the header is assumed to be in use by another
 * caller and the free is not done.
 */
pragma(inline, true)
void sam_hdr_free(SAM_hdr* hdr) { sam_hdr_destroy(hdr); }

/* sam_hdr_length() and sam_hdr_str() are now provided by sam.h. */

/*! Add an @PG line.
 *
 * If we wish complete control over this use sam_hdr_add_line() directly. This
 * function uses that, but attempts to do a lot of tedious house work for
 * you too.
 *
 * - It will generate a suitable ID if the supplied one clashes.
 * - It will generate multiple @PG records if we have multiple PG chains.
 *
 * Call it as per sam_hdr_add_line() with a series of key,value pairs ending
 * in NULL.
 *
 * @return
 * Returns 0 on success;
 *        -1 on failure
 */
alias sam_hdr_add_PG = sam_hdr_add_pg;

/**@{ -------------------------------------------------------------------*/

/*!
 * Returns the refs_t structure used by a cram file handle.
 *
 * This may be used in conjunction with option CRAM_OPT_SHARED_REF to
 * share reference memory between multiple file handles.
 *
 * @return
 * Returns NULL if none exists or the file handle is not a CRAM file.
 */
refs_t* cram_get_refs(htsFile* fd);

/**@}*/

