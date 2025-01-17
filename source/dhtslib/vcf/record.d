/** Module provides VCF Reader/Writer

VCF version 4.2 (including BCF) reader and writer, including
a model with convenience functions for the header (metadata)
and individual VCF/BCF records (rows).

Specifications: https://samtools.github.io/hts-specs/VCFv4.2.pdf

*/
module dhtslib.vcf.record;

import core.stdc.string;
import core.vararg;

import std.conv: to, ConvException;
import std.format: format;
import std.range: ElementType;
import std.string: fromStringz, toStringz;
import std.traits: Unqual;

import dhtslib.coordinates;
import dhtslib.vcf.header;
import htslib.hts_log;
import htslib.kstring;
import htslib.vcf;

alias BCFRecord = VCFRecord;



/** Wrapper around bcf1_t 

    Because it uses bcf1_t internally, it must conform to the BCF2 part
    of the VCFv4.2 specs, rather than the loosey-goosey VCF specs. i.e.,
    INFO, CONTIG, FILTER records must exist in the header.

    TODO: Does this need to be kept in a consistent state?
    Ideally, VCFWriter would reject invalid ones, but we are informed
    that it is invalid (e.g. if contig not found) while building this
    struct; bcf_write1 will actually segfault, unfortunately. I'd like
    to avoid expensive validate() calls for every record before writing
    if possible, which means keeping this consistent. However, not
    sure what to do if error occurs when using the setters herein?

    2019-01-23 struct->class to mirror SAMRecord -- faster if reference type?

    2019-01-23 WIP: getters for chrom, pos, id, ref, alt are complete (untested)

After parsing a BCF or VCF line, bcf1_t must be unpacked. (not applicable when building bcf1_t from scratch)
Depending on information needed, this can be done to various levels with performance tradeoff.
Unpacking symbols:
BCF_UN_ALL: all
BCF_UN_SHR: all shared information (BCF_UN_STR|BCF_UN_FLT|BCF_UN_INFO)

                        BCF_UN_STR
                       /               BCF_UN_FLT
                      |               /      BCF_UN_INFO
                      |              |      /       ____________________________ BCF_UN_FMT
                      V              V     V       /       |       |       |
#CHROM  POS ID  REF ALT QUAL    FILTER  INFO    FORMAT  NA00001 NA00002 NA00003 ...

*/
struct VCFRecord
{
    bcf1_t* line;   /// htslib structured record TODO: change to 'b' for better internal consistency? (vcf.h/c actually use line quite a bit in fn params)

    VCFHeader *vcfheader;   /// corresponding header (required);
                            /// is ptr to avoid copying struct containing ptr to bcf_hdr_t (leads to double free())
    
    private int refct = 1;      // Postblit refcounting in case the object is passed around

    /** VCFRecord

    Construct a bcf/vcf record, backed by bcf1_t, from: an existing bcf1_t, parameters, or a VCF line.

    Internal backing by bcf1_t means it must conform to the BCF2 rules -- i.e., header must contain
    appropriate INFO, CONTIG, and FILTER lines.

    Protip: specifying alternate MAX_UNPACK can speed it tremendously
        as it will not unpack all fields, only up to those requested (see htslib.vcf)
        For example, BCF_UN_STR is up to ALT inclusive, and BCF_UN_STR is up to FILTER
    */
    this(T)(T *h, bcf1_t *b, int MAX_UNPACK = BCF_UN_ALL)
    if(is(T == VCFHeader) || is(T == bcf_hdr_t))
    {
        static if (is(T == VCFHeader)) this.vcfheader = h;
        //else static if (is(T == bcf_hdr_t)) this.vcfheader = new VCFHeader(h); // double free() bug if we don't own bcf_hdr_t h
        else static if (is(T == bcf_hdr_t)) assert(0);  // ferret out situations that will lead to free() crashes
        else assert(0);

        this.line = b;

        // Now it must be unpacked
        // Protip: specifying alternate MAX_UNPACK can speed it tremendously
        immutable int ret = bcf_unpack(this.line, MAX_UNPACK);    // unsure what to do c̄ return value // @suppress(dscanner.suspicious.unused_variable)
    }
    /// ditto
    this(SS)(VCFHeader *vcfhdr, string chrom, int pos, string id, string _ref, string alt, float qual, SS filter, )
    if (isSomeString!SS || is(SS == string[]))
    {
        this.line = bcf_init1();
        this.vcfheader = vcfhdr;
        
        this.chrom = chrom;
        this.pos = pos;
        this.id = id;

        this.setAlleles(_ref, alt);

        this.qual = qual;
        this.filter = filter;
    }
    /// ditto
    this(VCFHeader *vcfhdr, string line, int MAX_UNPACK = BCF_UN_ALL)
    {
        this.vcfheader = vcfhdr;

        kstring_t kline;
        auto dupline = line.dup; // slower, but safer than a cast // @suppress(dscanner.suspicious.unmodified)

        kline.l = dupline.length;
        kline.m = dupline.length;
        kline.s = dupline.ptr;

        this.line = bcf_init1();
        this.line.max_unpack = MAX_UNPACK;

        auto ret = vcf_parse(&kline, this.vcfheader.hdr, this.line);
        if (ret < 0) {
            hts_log_error(__FUNCTION__, "vcf_parse returned < 0 -- code error or malformed VCF line");
        } else {
            ret = bcf_unpack(this.line, MAX_UNPACK);    // unsure what to do c̄ return value
        }
    }

    // post-blit reference counting
    this(this)
    {
        refct++;
    }

    invariant(){
        assert(refct >= 0);
    }

    /// dtor
    ~this(){
        if(--refct == 0 && this.line)
            bcf_destroy1(this.line);
    }

    //----- FIXED FIELDS -----//
    
    /* CHROM */
    /// Get chromosome (CHROM)
    @property
    string chrom()
    {
        if (!this.line.unpacked)
            bcf_unpack(this.line, BCF_UN_STR);
        
        return fromStringz(bcf_hdr_id2name(this.vcfheader.hdr, this.line.rid)).idup;
    }
    /// Set chromosome (CHROM)
    @property
    void chrom(const(char)[] c)
    {
        auto rid = bcf_hdr_name2id(this.vcfheader.hdr, toStringz(c));
        if (rid == -1) {
            hts_log_error(__FUNCTION__, format("contig not found: %s", c));
            throw new Exception("contig not found");
        }
        else line.rid = rid;
    }


    /* POS */
    /** Get position (POS, column 2)
     *
     * NB: internally BCF is uzing 0 based coordinates; we only show +1 when printing a VCF line with toString (which calls vcf_format)
    */
    @property
    Coordinate!(Basis.zero) pos()
    out(coord) { assert(coord >= 0); }
    do
    {
        if (!this.line.unpacked) bcf_unpack(this.line, BCF_UN_STR);
        return Coordinate!(Basis.zero)(this.line.pos);
    }
    /// Set position (POS, column 2)
    @property
    void pos(Coordinate!(Basis.zero) p)
    in { assert(p >= 0); }
    do
    {
        // TODO: should we check for pos >= 0 && pos < contig length? Could really hamper performance.
        // TODO: if writing out the file with invalid POS values crashes htslib, will consider it
        this.line.pos = p.pos;
    }


    /* ID */
    /// Get ID string
    @property string id()
    {
        if (!this.line.unpacked) bcf_unpack(this.line, BCF_UN_STR);
        return fromStringz(this.line.d.id).idup;
    }
    /// Sets new ID string; comma-separated list allowed but no dup checking performed
    @property int id(const(char)[] id)
    {
        // bcf_update_id expects null pointer instead of empty string to mean "no value"
        if (id == "") return bcf_update_id(this.vcfheader.hdr, this.line, null);
        else return bcf_update_id(this.vcfheader.hdr, this.line, toStringz(id));
    }
    /// Append an ID (column 3) to the record.
    ///
    /// NOTE: htslib performs duplicate checking
    int addID(const(char)[] id)
    {
        if(id == "") return 0;
        return bcf_add_id(this.vcfheader.hdr, this.line, toStringz(id));
    }


    /* Alleles (REF, ALT)
    
        Internally, alleles are stored as a \0 separated array:
        [C \0 T \0 T T \0.. \0]
         ^    ^    ^ ^
         |    |    L L ALT_1 = "TT"
         |    L ALT_0 
         L REF

        TODO: Getters and setters poorly or inconsistently (?) named at this time or there are too many overloads?
        TODO: need non-overwriting setter for ref and alt alleles
        TODO: some of these may be inefficent; since they may be used in hot inner loops, pls optimize
    */
    /// REF allele length
    @property long refLen()
    {
        version(DigitalMars) pragma(inline);
        version(LDC) pragma(inline, true);
        version(GNU) pragma(inline, true);
        return this.line.rlen;
    }

    /// Coordinate range of the reference allele
    @property Coordinates!(CoordSystem.zbho) coordinates()
    {
        return Coordinates!(CoordSystem.zbho)(this.pos, this.pos + this.refLen);
    }
    
    /// All alleles getter (array)
    @property string[] allelesAsArray()
    {
        string[] ret;
        ret.length = this.line.n_allele;        // n=0, no reference; n=1, ref but no alt
        foreach(int i; 0 .. this.line.n_allele) // ref allele is index 0
        {
            ret[i] = fromStringz(this.line.d.allele[i]).idup;
        }
        return ret;
    }
    /// Reference allele getter
    @property string refAllele()
    {
        if (!this.line.unpacked) bcf_unpack(this.line, BCF_UN_STR);
        if (this.line.n_allele < 1) return ""; // a valid record could have no ref (or alt) alleles
        else return fromStringz(this.line.d.als).idup;
    }
    // NB WIP: there could be zero, or multiple alt alleles
    /+@property string altAlleles()
    {
        if (!this.line.unpacked) bcf_unpack(this.line, BCF_UN_STR);
        return fromStringz(this.line.d.als)
    }+/
    /// Alternate alleles getter version 1: ["A", "ACTG", ...]
    @property string[] altAllelesAsArray()
    {
        if (!this.line.unpacked) bcf_unpack(this.line, BCF_UN_STR);

        string[] ret;
        if (this.line.n_allele < 2) return ret; // n=0, no reference; n=1, ref but no alt
        return this.allelesAsArray[1 .. $];     // trim off REF
    }
    /// Alternate alleles getter version 2: "A,ACTG,..."
    @property string altAllelesAsString()
    {
        if (!this.line.unpacked) bcf_unpack(this.line, BCF_UN_STR);

        string ret;
        if (this.line.n_allele < 2) return ret; // n=0, no reference; n=1, ref but no alt

        char[] tmp;
        tmp.length = this.line.d.m_allele;    // max allocated size in htslib

        char *a = this.line.d.allele[1];    // ref allele is index 0
        const char *last = this.line.d.allele[this.line.n_allele - 1];    // pointer to start of last allele
        size_t i = 0;

        assert( this.line.d.allele[1] == (this.line.d.als + this.line.rlen + 1) );  // ensue data structure is as we think (+1: past ref's term \0)

        while (i < this.line.d.m_allele)    // safety stop at max allocated size
        {
            if (*a) tmp[i] = *a;
            else {  // '\0'
                if (a < last) tmp[i] = ',';
                else break;
            }
            i++;
            a++;
        }
        tmp.length = i;

        return tmp.idup;
    }
    /// Set alleles; comma-separated list
    @property void alleles(string a)
    {
        if (a == "") {
            this.line.n_allele = 0;
            if (this.line.d.m_allele) this.line.d.als[0] = '\0';    // if storage allocated, zero out the REF
        }
        else
            bcf_update_alleles_str(this.vcfheader.hdr, this.line, toStringz(a));
    }
    /// Set alleles; array
    @property void alleles(string[] a)
    {
        if (a.length == 0) {
            this.line.n_allele = 0;
            if (this.line.d.m_allele) this.line.d.als[0] = '\0';    // if storage allocated, zero out the REF
        }
        else {
            const(char)*[64] allelesp;  // will fail if a locus has more than 63 ALT alleles :-O
            foreach(i; 0 .. a.length ) {
                // In order to zero out all alleles, pass a zero-length allele to the string version,
                // or a zero-length array to this version. Zero length string member of nonempty allele array is an error.
                if (a[i].length == 0) {
                    hts_log_error(__FUNCTION__, "Zero-length allele in nonempty allele array. Setting to '.'");
                    allelesp[i] = ".".ptr;
                }
                else allelesp[i] = toStringz(a[i]);
            }
            bcf_update_alleles(this.vcfheader.hdr, this.line, &allelesp[0], cast(int)a.length);
        }
    }
    /// Set REF allele only
    /// param r is \0-term Cstring
    /// TODO: UNTESTED
    void setRefAllele(const(char)* r)
    {
        // first, get REF
        if (!this.line.unpacked) bcf_unpack(this.line, BCF_UN_STR);
        // a valid record could have no ref (or alt) alleles
        if (this.line.n_allele < 2) // if none or 1 (=REF only), just add the REF we receieved
            bcf_update_alleles(this.vcfheader.hdr, this.line, &r, 1);
        else {
            // length of REF allele is allele[1] - allele[0], (minus one more for \0)
            // TODO ** TODO ** : there is a property line.refLen already
            const auto reflen = (this.line.d.allele[1] - this.line.d.allele[0]) - 1;
            if (strlen(r) <= reflen) {
                memcpy(this.line.d.allele[0], r, reflen + 1);   // +1 -> copy a trailing \0 in case original REF was longer than new 
                // TODO: do we need to call _sync ?
            } else {
                // slower way: replace allele[0] with r, but keep rest of pointers poitning at existing allele block,
                // then call bcf_update_alleles; this will make complete new copy of this.line.d.allele, so forgive the casts
                this.line.d.allele[0] = cast(char*) r;
                bcf_update_alleles(this.vcfheader.hdr, this.line,
                    cast( const(char)** ) this.line.d.allele, this.line.n_allele);
            }
        }
    }
    /// Set alleles; alt can be comma separated
    void setAlleles(string _ref, string alt)
    {
        immutable string alleles = _ref ~ "," ~ alt ~ "\0";
        bcf_update_alleles_str(this.vcfheader.hdr, this.line, alleles.ptr);
    }
    /// Set alleles; min. 2 alleles (ref, alt1); unlimited alts may be specified
    void setAlleles(string _ref, string alt, ...)
    {
        string alleles = _ref ~ "," ~ alt;

        for (int i = 0; i < _arguments.length; i++)
        {
            alleles ~= "," ~ va_arg!string(_argptr);
        }

        alleles ~= "\0";

        bcf_update_alleles_str(this.vcfheader.hdr, this.line, alleles.ptr);
    }


    /* Quality (QUAL) */
    /// Get variant quality (QUAL, column 6)
    @property float qual()
    out(result) { assert(result >= 0); }
    do
    {
        if (this.line.max_unpack < BCF_UN_FLT) bcf_unpack(this.line, BCF_UN_FLT);
        return this.line.qual;
    }
    /// Set variant quality (QUAL, column 6)
    @property void qual(float q)
    in { assert(q >= 0); }
    do { this.line.qual = q; }


    /* FILTER */
    /// Get FILTER column (nothing in htslib sadly)
    @property string filter()
    {
        const(char)[] ret;

        if (this.line.max_unpack < BCF_UN_FLT) bcf_unpack(this.line, BCF_UN_FLT);

        if (this.line.d.n_flt) {
            for(int i; i< this.line.d.n_flt; i++) {
                if (i) ret ~= ";";
                ret ~= fromStringz(this.vcfheader.hdr.id[BCF_DT_ID][ this.line.d.flt[0] ].key);
            }
        } else {
            ret = ".";
        }

        return ret.idup;
    }
    /// Remove all entries in FILTER
    void removeAllFilters()
    {
        // always returns zero
        bcf_update_filter(this.vcfheader.hdr, this.line, null, 0);
    }
    /// Set the FILTER column to f
    @property void filter(string f)
    {
        this.filter([f]);
    }
    /// Set the FILTER column to f0,f1,f2...
    /// TODO: determine definitiely whether "." is replaced with "PASS"
    @property void filter(string[] fs)
    {
        int[] fids;
        foreach(f; fs) {
            if(f == "") continue;
            const int fid = bcf_hdr_id2int(this.vcfheader.hdr, BCF_DT_ID, toStringz(f));
            if (fid == -1) hts_log_warning(__FUNCTION__, format("filter not found in header (ignoring): %s", f) );
            else fids ~= fid;
        }
        if (fids.length > 0)
            bcf_update_filter(this.vcfheader.hdr, this.line, fids.ptr, cast(int)fids.length);
        else
            hts_log_warning(__FUNCTION__, "No FILTER update was performed due to empty list");
    }
    /// Add a filter; from htslib: 
    /// "If flt_id is PASS, all existing filters are removed first. If other than PASS, existing PASS is removed."
    int addFilter(string f)
    {
        return bcf_add_filter(this.vcfheader.hdr, this.line, 
            bcf_hdr_id2int(this.vcfheader.hdr, BCF_DT_ID, toStringz(f)));
    }
    /// Remove a filter by name
    int removeFilter(string f)
    {
        const int fid = bcf_hdr_id2int(this.vcfheader.hdr, BCF_DT_ID, toStringz(f));
        return removeFilter(fid);
    }
    /// Remove a filter by numeric id
    int removeFilter(int fid)
    {
        return bcf_remove_filter(this.vcfheader.hdr, this.line, fid, 0);
    }
    /// Determine whether FILTER is present. log warning if filter does not exist. "PASS" and "." can be used interchangeably.
    bool hasFilter(string filter)
    {
        char[] f = filter.dup ~ '\0';
        //const auto id = bcf_hdr_id2int(this.vcfheader.hdr, BCF_DT_ID, f.ptr);
        const auto ret = bcf_has_filter(this.vcfheader.hdr, this.line, f.ptr);

        if (ret > 0) return true;
        else if (ret == 0) return false;
        else {
            hts_log_warning(__FUNCTION__, format("FILTER %s does not exist in the header", filter));
            return false;
        }
    }


    /** Update INFO (pan-sample info; column 8) 
     *
     *  Add a tag:value to the INFO column
     *  NOTE: tag must already exist in the header
     *
     *  Templated on data type, calls one of bcf_update_info_{int32,float,string,flag}
     *  Both singletons and arrays are supported.
    */
    void addInfo(T)(string tag, T data)
    {
        int ret = -1;

        static if(isIntegral!T) {
            auto integer = cast(int) data;
            ret = bcf_update_info_int32(this.vcfheader.hdr, this.line, toStringz(tag), &integer, 1);
        }
        
        else static if(isFloatingPoint!T) {
            auto flt = cast(float) data;    // simply passing "2.0" (or whatever) => data is a double
            ret = bcf_update_info_float(this.vcfheader.hdr, this.line, toStringz(tag), &flt, 1);
        }

        else static if(isSomeString!T)
            ret = bcf_update_info_string(this.vcfheader.hdr, this.line, toStringz(tag), toStringz(data));
        
        else static if(isBoolean!T) {
            immutable int set = data ? 1 : 0; // if data == true, pass 1 to bcf_update_info_flag(n=); n=0 => clear flag 
            ret = bcf_update_info_flag(this.vcfheader.hdr, this.line, toStringz(tag), null, set);
        }
        
        if (ret == -1)
            hts_log_warning(__FUNCTION__, format("Couldn't add tag (ignoring): %s with value %s", tag, data));
    }
    /// ditto
    void addInfo(T)(string tag, T[] data)
    if(!is(T==immutable(char)))             // otherwise string::immutable(char)[] will match the other template
    {
        int ret = -1;

        static if(isIntegral!T) {
            auto integer = cast(int) data;
            ret = bcf_update_info_int32(this.vcfheader.hdr, this.line, toStringz(tag), &integer, data.length);
        }
        
        else static if(isFloatingPoint!T) {
            auto flt = cast(float) data;    // simply passing "2.0" (or whatever) => data is a double
            ret = bcf_update_info_float(this.vcfheader.hdr, this.line, toStringz(tag), &flt, data.length);
        }
        
        if (ret == -1)
            hts_log_warning(__FUNCTION__, format("Couldn't add tag (ignoring): %s with value %s", tag, data));
    }

    /** Update FORMAT (sample info; column 9+)
     *  
     *  Templated on data type, calls one of bc_update_format_{int32,float,string,flag}
    */
    void addFormat(T)(string tag, T data)
    if(!isArray!T)
    {
        int ret = -1;

        static if(isIntegral!T) {
            auto integer = cast(int) data;
            ret = bcf_update_format_int32(this.vcfheader.hdr, this.line, toStringz(tag), &integer, 1);
        }
        
        else static if(isFloatingPoint!T) {
            auto flt = cast(float) data;    // simply passing "2.0" (or whatever) => data is a double
            ret = bcf_update_format_float(this.vcfheader.hdr, this.line, toStringz(tag), &flt, 1);
        }

        else static if(isSomeString!T)
            ret = bcf_update_format_string(this.vcfheader.hdr, this.line, toStringz(tag), toStringz(data));
        
        else static if(isBoolean!T) {
            immutable int set = data ? 1 : 0; // if data == true, pass 1 to bcf_update_info_flag(n=); n=0 => clear flag 
            ret = bcf_update_format_flag(this.vcfheader.hdr, this.line, toStringz(tag), null, set);
        }
        
        if (ret == -1) hts_log_warning(__FUNCTION__, format("Couldn't add format (ignoring): %s", data));
    }
    /// ditto
    void addFormat(T)(string tag, T[] data)
    {
                int ret = -1;

        static if(isIntegral!T) {
            auto integer = cast(int[]) data;
            ret = bcf_update_format_int32(this.vcfheader.hdr, this.line, toStringz(tag),
                                            integer.ptr, cast(int)data.length);
        }
        
        else static if(isFloatingPoint!T) {
            auto flt = cast(float[]) data;    // simply passing "2.0" (or whatever) => data is a double
            ret = bcf_update_format_float(this.vcfheader.hdr, this.line, toStringz(tag),
                                            flt.ptr, cast(int)data.length);
        }
        
        if (ret == -1) hts_log_warning(__FUNCTION__, format("Couldn't add format (ignoring): %s", data));

    }

    /// add INFO or FORMAT key:value pairs to a record
    /// add a single datapoint OR vector of values, OR, values to each sample (if tagType == FORMAT)
    void add(string tagType, T)(const(char)[] tag, T data)
    if((tagType == "INFO" || tagType == "FORMAT") &&
        (isIntegral!T       || isIntegral!(ElementType!T)   ||
        isFloatingPoint!T   || isFloatingPoint!(ElementType!T) ||
        isSomeString!T      || isSomeString!(ElementType!T) ||
        isBoolean!T         || isBoolean!(ElementType!T)))
    {
        int ret = -1;
        int len;

        static if (!isDynamicArray!T) {
            len = 1;
            static if (isIntegral!T) auto d = data.to!int;
            else static if (isFloatingPoint!T) auto d = data.to!float;
            else static if (isSomeString!T) auto d = toStringz(data);
            else static if (isBoolean!T) immutable int d = data ? 1 : 0; // if data == true, pass 1 to bcf_update_info_flag(n=); n=0 => clear flag
            else static assert(0);

            const auto ptr = &d;
        }
        else static if (isDynamicArray!T) {
            assert(data.length < int.max);
            len = cast(int) data.length;
            static if (isIntegral!(ElementType!T)) auto d = data.to!(int[]);
            else static if (isFloatingPoint!(ElementType!T)) auto d = data.to!(float[]);
            else static if (isSomeString!(ElementType!T)) {
                char[] d;
                foreach(s; data) {
                    d ~= s ~ "\0";
                }
                if(d.length == 0) d ~= "\0";    // TODO replace with asserts on data length earlier
            }
            else static if (isBoolean!(ElementType!T)) {
                int[] d;
                foreach(b; data) {
                    d ~= (b ? 1 : 0);
                }
            }

            const auto ptr = d.ptr;
        }
        else static assert(0);

        static if (tagType == "INFO") {
            static if (is(Unqual!T == int) || is(Unqual!(ElementType!T) == int))
                ret = bcf_update_info_int32(this.vcfheader.hdr, this.line, toStringz(tag), ptr, len);
            else static if (is(Unqual!T == float) || is(Unqual!(ElementType!T) == float))
                ret = bcf_update_info_float(this.vcfheader.hdr, this.line, toStringz(tag), ptr, len);
            else static if (isSomeString!T || isSomeString!(ElementType!T))
                ret = bcf_update_info_string(this.vcfheader.hdr, this.line, toStringz(tag), ptr);
            else static if (is(T == bool) || is(ElementType!T == bool))
                ret = bcf_update_info_flag(this.vcfheader.hdr, this.line, toStringz(tag), ptr, len);
            else static assert(0, "Type not recognized for INFO tag");
        }
        else static if (tagType == "FORMAT") {
            static if (is(Unqual!T == int) || is(Unqual!(ElementType!T) == int))
                ret = bcf_update_format_int32(this.vcfheader.hdr, this.line, toStringz(tag), ptr, len);
            else static if (is(Unqual!T == float) || is(Unqual!(ElementType!T) == float))
                ret = bcf_update_format_float(this.vcfheader.hdr, this.line, toStringz(tag), ptr, len);
            else static if (isSomeString!T || isSomeString!(ElementType!T))
                ret = bcf_update_format_string(this.vcfheader.hdr, this.line, toStringz(tag), ptr, len);
            else static assert(0, "Type not recognized for FORMAT tag");
        }
        else static assert(0);

        if (ret == -1)
            hts_log_warning(__FUNCTION__, format("Couldn't add tag (ignoring): %s with value %s", tag, data));
    }

    /// Return a string representation of the VCFRecord (i.e. as would appear in .vcf)
    ///
    /// As a bonus, there is a kstring_t memory leak
    string toString() const
    {
        kstring_t s;

        const int ret = vcf_format(this.vcfheader.hdr, this.line, &s);
        if (ret)
        {
            hts_log_error(__FUNCTION__,
                format("vcf_format returned nonzero (%d) (likely EINVAL, invalid bcf1_t struct?)", ret));
            return "[VCFRecord vcf_format parse_error]";
        }

        return cast(string) s.s[0 .. s.l];
    }
}





///
debug(dhtslib_unittest)
unittest
{
    import std.exception: assertThrown;
    import std.stdio: writeln, writefln;
    import dhtslib.vcf.writer;

    hts_set_log_level(htsLogLevel.HTS_LOG_TRACE);


    auto vw = VCFWriter("/dev/null");

    vw.addHeaderLineRaw("##INFO=<ID=NS,Number=1,Type=Integer,Description=\"Number of Samples With Data\">");
    vw.addHeaderLineKV("INFO", "<ID=DP,Number=1,Type=Integer,Description=\"Total Depth\">");
    // ##INFO=<ID=AF,Number=A,Type=Float,Description="Allele Frequency">
    vw.addTag!"INFO"("AF", "A", "Integer", "Number of Samples With Data");
    vw.addHeaderLineRaw("##contig=<ID=20,length=62435964,assembly=B36,md5=f126cdf8a6e0c7f379d618ff66beb2da,species=\"Homo sapiens\",taxonomy=x>"); // @suppress(dscanner.style.long_line)
    vw.addHeaderLineRaw("##FILTER=<ID=q10,Description=\"Quality below 10\">");

    // Exercise header
    assert(vw.vcfhdr.nsamples == 0);
    vw.addSample("NA12878");
    assert(vw.vcfhdr.nsamples == 1);

    auto r = new VCFRecord(vw.vcfhdr, bcf_init1());
    
    r.chrom = "20";
    assert(r.chrom == "20");
    assertThrown(r.chrom = "chr20");   // headerline chromosome is "20" not "chr20"

    r.pos = Coordinate!(Basis.zero)(999_999);
    assert(r.pos == Coordinate!(Basis.zero)(999_999));
    r.pos = Coordinate!(Basis.zero)(62_435_964 + 1);     // Exceeds contig length

    // Test ID field
    // note that in an empty freshly initialized bcf1_t, the ID field is "" rather than "."
    // Will consider adding initialization code
    //writefln("ID: %s", r.id);
    r.id = "";
    assert(r.id == ".");
    r.id = ".";
    assert(r.id == ".");
    r.id = "rs001";
    assert(r.id == "rs001");
    r.addID("rs999");
    assert(r.id == "rs001;rs999");
    r.addID("rs001");   // test duplicate checking
    assert(r.id == "rs001;rs999");

    // Test REF/ALT allele setters and getters
    // many overloads to test for good coverage
    // Test matrix: Set {zero, one, two, three} alleles * {set by string, set by array} = 8 test cases
    //  * also, there is setAlleles(ref, alt) and setAlleles(ref, alt1, ...) 
    //  * TODO: will also need to retreive alt alleles as array and string

    string[] alleles_array;

    // Zero alleles
    r.alleles("");
    const auto zs = r.allelesAsArray;
    const auto zsr = r.refAllele;
    assert(zs.length == 0);
    assert(zsr == "");

    r.alleles(alleles_array);
    const auto za = r.allelesAsArray;
    const auto zar = r.refAllele;
    assert(za.length == 0);
    assert(zar == "");
    
    // One allele
    r.alleles("C");
    const auto os = r.allelesAsArray;
    const auto osr = r.refAllele;
    assert(os.length == 1 && os[0] == "C");
    assert(osr == "C");

    r.alleles(["C"]);
    const auto oa = r.allelesAsArray;
    const auto oar = r.refAllele;
    assert(oa.length == 1 && oa[0] == "C");
    assert(oar == "C");

    // Two alleles
    r.alleles("C,T");
    const auto ts = r.allelesAsArray;
    const auto tsr= r.refAllele;
    assert(ts == ["C", "T"]);
    assert(tsr== "C");

    r.alleles(["C", "T"]);
    const auto ta = r.allelesAsArray;
    const auto tar= r.refAllele;
    assert(ta == ["C", "T"]);
    assert(tar== "C");

    const taaa = r.altAllelesAsArray;
    const taas = r.altAllelesAsString;
    assert(taaa == ["T"]);
    assert(taas == "T");

    // alternate setter for >= 2 alleles
    r.setAlleles("A", "G");
    assert(r.allelesAsArray == ["A", "G"]);

    // Three alleles
    r.alleles("A,C,T");
    assert(r.allelesAsArray == ["A", "C", "T"]);
    assert(r.refAllele == "A");
    assert(r.altAllelesAsString == "C,T");

    // alternate the alleles for testing purposes
    r.alleles(["G", "A", "C"]);
    assert(r.allelesAsArray == ["G", "A", "C"]);
    assert(r.refAllele == "G");
    assert(r.altAllelesAsString == "A,C");

    r.setAlleles("A", "C", "T");
    assert(r.allelesAsArray == ["A", "C", "T"]);
    assert(r.refAllele == "A");
    assert(r.altAllelesAsString == "C,T");


    // Test QUAL
    r.qual = 1.0;
    assert(r.qual == 1.0);
    // now test setting qual without unpacking
    // TODO: see https://forum.dlang.org/post/hebouvswxlslqhovzaia@forum.dlang.org, once resolved (or once factory function written),
    //  add template value param BCF_UN_STR
    auto rr = new VCFRecord(vw.vcfhdr, "20\t17330\t.\tT\tA\t3\t.\tNS=3;DP=11;AF=0.017\n"); // @suppress(dscanner.style.long_line)
    rr.qual = 3.0;
    assert(rr.qual == 3.0);


    // Test FILTER
    assert(r.hasFilter("PASS"));
    assert(r.hasFilter("."));
    // add q10 filter (is in header)
    r.filter = "q10";
    assert(r.filter == "q10");
    assert(!r.hasFilter("PASS"));   // if has another filter, no longer PASS (unless added explicitly)
    assert(!r.hasFilter("."));      // if has another filter, no longer has . (which is PASS, or no filter [spec conflict?])

    // add q30 filteR (not in header)
    r.filter = "q30";
    assert(r.filter == "q10");  // i.e., unchanged

    assert(r.hasFilter("q10"));
    assert(!r.hasFilter("q30"));

    r.removeAllFilters();
    assert(r.hasFilter("."));
    r.addFilter("q10");
    assert(r.hasFilter("q10"));
    r.removeFilter("q10");
    assert(r.hasFilter("PASS"));


    // Finally, print the records:
    writefln("VCF records via toString:\n%s%s", r, rr);

    writeln("\ndhtslib.vcf: all tests passed\n");
}
