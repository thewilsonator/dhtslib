module dhtslib.sam.record;

import core.stdc.stdlib : calloc, free, realloc;
import core.stdc.string : memset;
import core.stdc.errno : EINVAL, EOVERFLOW, ENOMEM, ERANGE;
import std.string : fromStringz, toStringz;
import std.algorithm : filter;
import std.range.interfaces : InputRange, inputRangeObject;
import std.traits : isArray, isIntegral, isSomeString;

import htslib.hts : seq_nt16_str, seq_nt16_table;

import htslib.hts_log;
import htslib.sam;
import dhtslib.sam.cigar;
import dhtslib.sam.tagvalue;
import dhtslib.sam.header;
import dhtslib.coordinates;

/**
Encapsulates a SAM/BAM/CRAM record,
using the bam1_t type for memory efficiency,
and the htslib helper functions for speed.
**/
struct SAMRecord
{
    /// Backing SAM/BAM row record
    bam1_t* b;

    /// Corresponding SAM/BAM header data
    SAMHeader h;

    private int refct = 1;      // Postblit refcounting in case the object is passed around

    private Cigar p_cigar;

    private bool cigarInitialized;
    
    private TagValue p_tagval;

    this(this)
    {
        refct++;
    }

    invariant(){
        assert(refct >= 0);
    }
   
    /// ditto
    this(SAMHeader h)
    {
        this.b = bam_init1();
        this.h = h;
    }
 
    /// Construct SAMRecord from supplied bam1_t
    deprecated("Construct with sam_hdr_t* for mapped contig (tid) name support")
    this(bam1_t* b)
    {
        this.b = b;
    }

    /// Construct SAMRecord from supplied bam1_t and sam_hdr_type
    this(bam1_t* b, SAMHeader h)
    {
        this.b = b;
        this.h = h;
    }

    ~this()
    {
        if(refct > 0) refct--;
        // remove only if no references to this or underlying bam1_t data
        if (refct == 0 && p_cigar.references == 0 && p_tagval.references == 0)
            bam_destroy1(this.b); // we created our own in default ctor, or received copy via bam_dup1
    }


    /* bam1_core_t fields */

    /// chromosome ID, defined by sam_hdr_t
    pragma(inline, true)
    @nogc @safe nothrow
    @property int tid() { return this.b.core.tid; }
    /// ditto
    pragma(inline, true)
    @nogc @safe nothrow
    @property void tid(int tid) { this.b.core.tid = tid; }

    /// mapped contig (tid) name, defined by sam_hdr_t* h
    pragma(inline, true)
    @property const(char)[] referenceName()
    {
        assert(!this.h.isNull);
        return this.h.targetName(this.b.core.tid);
    }
 
    /// 0-based leftmost coordinate
    pragma(inline, true)
    @nogc @safe nothrow
    @property Coordinate!(Basis.zero) pos() { return Coordinate!(Basis.zero)(this.b.core.pos); }
    /// ditto
    pragma(inline, true)
    @nogc @safe nothrow
    @property void pos(Coordinate!(Basis.zero) pos) { this.b.core.pos = pos.pos; }

    /// 0-based, half-open coordinates that represent
    /// the mapped length of the alignment 
    pragma(inline, true)
    @property Coordinates!(CoordSystem.zbho) coordinates()
    {
        return Coordinates!(CoordSystem.zbho)(this.pos, this.pos + this.cigar.alignedLength);
    }

    // TODO: @field  bin     bin calculated by bam_reg2bin()

    /// mapping quality
    pragma(inline, true)
    @nogc @safe nothrow
    @property ubyte qual() { return this.b.core.qual; }
    /// ditto
    pragma(inline, true)
    @nogc @safe nothrow
    @property void qual(ubyte q) { this.b.core.qual = q; }

    /// length of query name. Terminated by 1-4 \0, see l_extranul. Never set directly.
    pragma(inline, true)
    @nogc @safe nothrow
    @property int l_qname() { return this.b.core.l_qname; }

    /// number of EXTRA trailing \0 in qname; 0 <= l_extranul <= 3, see l_qname. Never set directly.
    pragma(inline, true)
    @nogc @safe nothrow
    @property int l_extranul() { return this.b.core.l_extranul; }

    /// bitwise flag
    pragma(inline, true)
    @nogc @safe nothrow
    @property ushort flag() { return this.b.core.flag; }
    /// ditto
    pragma(inline, true)
    @nogc @safe nothrow
    @property void flag(ushort fl) { this.b.core.flag = fl; }

    /// is read paired?
    pragma(inline, true)
    @property bool isPaired()
    {
        return (b.core.flag & BAM_FPAIRED);
    }
    
    /// is read reversed?
    /// bool bam_is_rev(bam1_t *b) { return ( ((*b).core.flag & BAM_FREVERSE) != 0 ); }
    @property bool isReversed()
    {
        version(LDC) pragma(inline, true);
        return bam_is_rev(this.b);
    }

    /// is read mapped?
    @property bool isMapped()
    {
        version(LDC){
            pragma(inline, true);
        }
        return (b.core.flag & BAM_FUNMAP) == 0;
    }

    /// is read mate mapped?
    @property bool isMateMapped()
    {
        version(LDC){
            pragma(inline, true);
        }
        return (b.core.flag & BAM_FMUNMAP) == 0;
    }

    /// is mate reversed?
    /// bool bam_is_mrev(bam1_t *b) { return( ((*b).core.flag & BAM_FMREVERSE) != 0); }
    pragma(inline, true)
    @property bool mateReversed()
    {
        return bam_is_mrev(this.b);
    }
    
    /// is read secondary?
    @property bool isSecondary()
    {
        version(LDC){
            pragma(inline, true);
        }
        return cast(bool)(b.core.flag & BAM_FSECONDARY);
    }

    /// is read supplementary?
    @property bool isSupplementary()
    {
        version(LDC){
            pragma(inline, true);
        }
        return cast(bool)(b.core.flag & BAM_FSUPPLEMENTARY);
    }

    /// Return read strand + or - (as char)
    @property char strand(){
        return ['+','-'][isReversed()];
    }

    /// Get query name (read name)
    /// -- wraps bam_get_qname(bam1_t *b)
    pragma(inline, true)
    @property const(char)[] queryName()
    {
        // auto bam_get_qname(bam1_t *b) { return (cast(char*)(*b).data); }
        return fromStringz(bam_get_qname(this.b));
    }
    
    /// Set query name (read name)
    pragma(inline, true)
    @property void queryName(string qname)
    {
        assert(qname.length<252);

        //make cstring
        auto qname_n=qname.dup~'\0';

        //append extra nulls to 32bit align cigar
        auto extranul=0;
        for (; qname_n.length % 4 != 0; extranul++) qname_n~='\0';
        assert(extranul<=3);

        //get length of rest of data
        auto l_rest=b.l_data-b.core.l_qname;

        //copy rest of data
        ubyte[] rest=b.data[b.core.l_qname..b.l_data].dup;
        
        //if not enough space
        if(qname_n.length+l_rest>b.m_data){
            auto ptr=cast(ubyte*)realloc(b.data,qname_n.length+l_rest);
            assert(ptr!=null);
            b.data=ptr;
            b.m_data=cast(uint)qname_n.length+l_rest;
        }

        //reassign q_name and rest of data
        b.data[0..qname_n.length]=(cast(ubyte[])qname_n);
        b.data[qname_n.length..qname_n.length+l_rest]=rest;

        //reset data length, qname length, extra nul length
        b.l_data=cast(uint)qname_n.length+l_rest;
        b.core.l_qname=cast(ubyte)(qname_n.length);
        b.core.l_extranul=cast(ubyte)extranul;
    }

    /// query (and quality string) length
    pragma(inline, true)
    @property int length()
    {
        return this.b.core.l_qseq;
    }

    /// Return char array of the sequence
    /// see samtools/sam_view.c: get_read
    @property const(char)[] sequence()
    {
        // calloc fills with \0; +1 len for Cstring
        // char* s = cast(char*) calloc(1, this.b.core.l_qseq + 1);
        char[] s;
        s.length = this.b.core.l_qseq;

        // auto bam_get_seq(bam1_t *b) { return ((*b).data + ((*b).core.n_cigar<<2) + (*b).core.l_qname); }
        auto seqdata = bam_get_seq(this.b);

        for (int i; i < this.b.core.l_qseq; i++)
        {
            s[i] = seq_nt16_str[bam_seqi(seqdata, i)];
        }
        return s;
    }

    /// Assigns sequence and resets quality score
    pragma(inline, true)
    @property void sequence(const(char)[] seq)
    {
        //nibble encode sequence
        ubyte[] en_seq;
        en_seq.length=(seq.length+1)>>1;
        for(auto i=0;i<seq.length;i++){
            en_seq[i>>1]|=seq_nt16_table[seq[i]]<< ((~i&1)<<2);
        }

        //get length of data before seq
        uint l_prev=b.core.l_qname + cast(uint)(b.core.n_cigar*uint.sizeof);

        //get starting point after seq
        uint start_rest=l_prev+((b.core.l_qseq+1)>>1)+b.core.l_qseq;

        //copy previous data
        ubyte[] prev=b.data[0..l_prev].dup;

        //copy rest of data
        ubyte[] rest=b.data[start_rest..b.l_data].dup;
        
        //if not enough space
        if(en_seq.length+seq.length+l_prev+(b.l_data-start_rest)>b.m_data){
            auto ptr=cast(ubyte*)realloc(b.data,en_seq.length+seq.length+l_prev+(b.l_data-start_rest));
            assert(ptr!=null);
            b.data=ptr;
            b.m_data=cast(uint)en_seq.length+cast(uint)seq.length+l_prev+(b.l_data-start_rest);
        }

        //reassign q_name and rest of data
        b.data[0..l_prev]=prev;
        b.data[l_prev..en_seq.length+l_prev]=en_seq;
        //set qscores to 255 
        memset(b.data+en_seq.length+l_prev,255,seq.length);
        b.data[l_prev+en_seq.length+seq.length..l_prev+en_seq.length+seq.length+(b.l_data-start_rest)]=rest;

        //reset data length, seq length
        b.l_data=cast(uint)en_seq.length+cast(uint)seq.length+l_prev+(b.l_data-start_rest);
        b.core.l_qseq=cast(int)(seq.length);
    }

    /// Return array of the quality scores
    /// see samtools/sam_view.c: get_quality
    /// TODO: Discussion -- should we return const(ubyte[]) or const(ubyte)[] instead?
    @property const(ubyte)[] qscores()
    {

        auto slice = bam_get_qual(this.b)[0 .. this.b.core.l_qseq];
        return slice;
    }

    /// Set quality scores from raw ubyte quality score array given that it is the same length as the bam sequence
    pragma(inline, true)
    @property void qscores(const(ubyte)[] seq)
    {
        if(seq.length != b.core.l_qseq){
            hts_log_error(__FUNCTION__,"qscore length does not match sequence length");
            return;
        }
        
        //get length of data before seq
        uint l_prev = b.core.l_qname + cast(uint)(b.core.n_cigar * uint.sizeof) + ((b.core.l_qseq + 1) >> 1);
        b.data[l_prev .. seq.length + l_prev] = seq;
    }

    /// get phred-scaled base qualities as char array
    pragma(inline, true)
    const(char)[] qscoresPhredScaled()
    {
        auto bqs = this.qscores.dup;
        bqs[] += 33;
        return cast(const(char)[]) bqs;
    }

    /// Create cigar from bam1_t record
    @property Cigar cigar()
    {
        // see if cigar is already initialized
        if(!cigarInitialized) 
            p_cigar = Cigar(bam_get_cigar(b), (*b).core.n_cigar);
            this.cigarInitialized = true;
        return p_cigar;
    }

    /// Assign a cigar string
    pragma(inline, true)
    @property void cigar(Cigar cigar)
    {
        
        //get length of data before seq
        uint l_prev=b.core.l_qname;

        //get starting point after seq
        uint start_rest=l_prev+cast(uint)(b.core.n_cigar*uint.sizeof);

        //copy previous data
        ubyte[] prev=b.data[0..l_prev].dup;

        //copy rest of data
        ubyte[] rest=b.data[start_rest..b.l_data].dup;

        //if not enough space
        if(uint.sizeof * cigar.length + l_prev + (b.l_data - start_rest) > b.m_data){
            auto ptr = cast(ubyte*) realloc(b.data, uint.sizeof * cigar.length + l_prev + (b.l_data - start_rest));
            assert(ptr != null);
            b.data = ptr;
            b.m_data=cast(uint)(uint.sizeof * cigar.length) + l_prev + (b.l_data - start_rest);
        }

        //reassign q_name and rest of data
        b.data[0 .. l_prev]=prev;
        //without cigar.ops.dup we get the overlapping array copy error
        b.data[l_prev .. uint.sizeof * cigar.length + l_prev] = cast(ubyte[])( cast(uint[]) cigar.dup[]);
        b.data[l_prev + uint.sizeof * cigar.length .. l_prev + uint.sizeof * cigar.length + (b.l_data - start_rest)] = rest;

        //reset data length, seq length
        b.l_data = cast(uint)(uint.sizeof * cigar.length) + l_prev + (b.l_data - start_rest);
        b.core.n_cigar=cast(uint)(cigar.length);
        p_cigar = Cigar(bam_get_cigar(b), (*b).core.n_cigar);
    }

    /// Get aux tag from bam1_t record and return a TagValue
    TagValue opIndex(string val)
    {
        p_tagval = TagValue(b, val[0..2]);
        return p_tagval;
    }

    /// Assign a tag key value pair
    void opIndexAssign(T)(T value, string index)
    if(!isArray!T || isSomeString!T)
    {
        static if(isIntegral!T){
            auto err = bam_aux_update_int(b,index[0..2],value);
        }else static if(is(T==float)){
            auto err = bam_aux_update_float(b,index[0..2],value);
        }else static if(isSomeString!T){
            auto err = bam_aux_update_str(b,index[0..2],cast(int)value.length+1,toStringz(value));
        }
        switch(err){
            case EINVAL:
                throw new Exception("The bam record's aux data is corrupt or an existing tag" ~ 
                " with the given ID is not of an integer type (c, C, s, S, i or I).");
            case ENOMEM:
                throw new Exception("The bam data needs to be expanded and either the attempt" ~
                " to reallocate the data buffer failed or the resulting buffer would be longer" ~
                " than the maximum size allowed in a bam record (2Gbytes).");
            case ERANGE:
            case EOVERFLOW:
                throw new Exception("val is outside the range that can be stored in an integer" ~ 
                " bam tag (-2147483647 to 4294967295).");
            case -1:
                throw new Exception("Something went wrong adding the bam tag.");
            case 0:
                return;
            default:
                throw new Exception("Something went wrong adding the bam tag.");
        }
    }

    /// Assign a tag key array pair
    void opIndexAssign(T)(T[] value, string index)
    if(!isSomeString!(T[]))
    {
        auto err = bam_aux_update_array(b,index[0..2],TypeChars[TypeIndex!T],cast(int) value.length,value.ptr);
        switch(err){
            case EINVAL:
                throw new Exception("The bam record's aux data is corrupt or an existing tag" ~ 
                " with the given ID is not of an integer type (c, C, s, S, i or I).");
            case ENOMEM:
                throw new Exception("The bam data needs to be expanded and either the attempt" ~
                " to reallocate the data buffer failed or the resulting buffer would be longer" ~
                " than the maximum size allowed in a bam record (2Gbytes).");
            case ERANGE:
            case EOVERFLOW:
                throw new Exception("val is outside the range that can be stored in an integer" ~ 
                " bam tag (-2147483647 to 4294967295).");
            case -1:
                throw new Exception("Something went wrong adding the bam tag.");
            case 0:
                return;
            default:
                throw new Exception("Something went wrong adding the bam tag.");
        }
    }

    /// chromosome ID of next read in template, defined by bam_hdr_t
    pragma(inline, true)
    @nogc @safe nothrow
    @property int mateTID() { return this.b.core.mtid; }
    /// ditto
    pragma(inline, true)
    @nogc @safe nothrow
    @property void mateTID(int mtid) { this.b.core.mtid = mtid; }

    /// 0-based leftmost coordinate of next read in template
    pragma(inline, true)
    @nogc @safe nothrow
    @property long matePos() { return this.b.core.mpos; }
    /// ditto
    pragma(inline, true)
    @nogc @safe nothrow
    @property void matePos(long mpos) { this.b.core.mpos = mpos; }

    /// Presumably Insert size, but is undocumented.
    /// Per samtools source, is measured 5' to 5'
    /// https://github.com/samtools/samtools/blob/bd1a409aa750d25d70a093405d174db8709a3f2c/bam_mate.c#L320
    pragma(inline, true)
    @nogc @safe nothrow
    @property long insertSize() { return this.b.core.isize; }
    /// ditto
    pragma(inline, true)
    @nogc @safe nothrow
    @property void insertSize(long isize) { this.b.core.isize = isize; }
/+ BEGIN CHERRY-PICK: TODO: confirm below chunk with htslib-1.10 (mainly long coordinates +/
    /// get aligned coordinates per each cigar op
    InputRange!AlignedCoordinate getAlignedCoordinates(){
        return AlignedCoordinatesItr(this.cigar).inputRangeObject;
    }

    /// get aligned coordinates per each cigar op within range
    /// range is 0-based half open using chromosomal coordinates
    InputRange!AlignedCoordinate getAlignedCoordinates(long start, long end){
        assert(start >= 0);
        assert(end <= this.cigar.ref_bases_covered);
        return this.getAlignedCoordinates.filter!(x=> x.rpos >= start).filter!(x=> x.rpos < end).inputRangeObject;
    }

    struct AlignedPair(bool refSeq)
    {
        Coordinate!(Basis.zero) qpos, rpos;
        Ops cigar_op;
        char queryBase;
        static if(refSeq) char refBase;

        string toString(){
            import std.conv : to;
            static if(refSeq) return rpos.pos.to!string ~ ":" ~ refBase ~ " > " ~ qpos.pos.to!string ~ ":" ~ queryBase;
            else return rpos.pos.to!string ~ ":" ~ qpos.pos.to!string ~ ":" ~ queryBase;
        }
    }

    /// get a range of aligned read and reference positions
    /// this is meant to recreate functionality from pysam:
    /// https://pysam.readthedocs.io/en/latest/api.html#pysam.AlignedSegment.get_aligned_pairs
    /// range is 0-based half open using chromosomal coordinates
    auto  getAlignedPairs(bool withRefSeq)(long start, long end)
    {
        import dhtslib.sam.md : MDItr;
        import std.range : dropExactly;
        struct AlignedPairs(bool refSeq)
        {
            InputRange!AlignedCoordinate coords;
            static if(refSeq) MDItr mdItr;
            AlignedPair!refSeq current;
            const(char)[] qseq;
            
            this(InputRange!AlignedCoordinate coords, SAMRecord rec, long start, long end){
                assert(start < end);
                assert(start >= 0);
                assert(end <= rec.cigar.ref_bases_covered);
                this.coords = coords;
                qseq = rec.sequence;
                static if(refSeq){
                    assert(rec["MD"].exists,"MD tag must exist for record");
                    mdItr = MDItr(rec);
                    mdItr = mdItr.dropExactly(start);
                } 
                current.qpos = coords.front.qpos;
                current.rpos = coords.front.rpos;
                current.cigar_op = coords.front.cigar_op;
                if(!CigarOp(0, current.cigar_op).is_query_consuming) current.queryBase = '-';
                else current.queryBase = qseq[current.qpos];
                
                static if(refSeq){
                    if(!CigarOp(0, current.cigar_op).is_reference_consuming) current.refBase = '-';
                    else if(mdItr.front == '=') current.refBase = current.queryBase;
                    else current.refBase = mdItr.front;
                }
            }

            AlignedPair!refSeq front(){
                return current;
            }

            void popFront(){
                coords.popFront;
                if(coords.empty) return;
                current.qpos = coords.front.qpos;
                current.rpos = coords.front.rpos;
                current.cigar_op = coords.front.cigar_op;
                if(!CigarOp(0, current.cigar_op).is_query_consuming) current.queryBase = '-';
                else current.queryBase = qseq[current.qpos];
                
                static if(refSeq){
                    if(CigarOp(0, current.cigar_op).is_reference_consuming) mdItr.popFront;
                    if(!CigarOp(0, current.cigar_op).is_reference_consuming) current.refBase = '-';
                    else if(mdItr.front == '=') current.refBase = current.queryBase;
                    else current.refBase = mdItr.front;
                }

            }

            bool empty(){
                return coords.empty;
            }

        }
        auto coords = this.getAlignedCoordinates(start, end);
        return AlignedPairs!withRefSeq(coords,this,start,end).inputRangeObject;
    }
    /// get a range of aligned read and reference positions
    /// this is meant to recreate functionality from pysam:
    /// https://pysam.readthedocs.io/en/latest/api.html#pysam.AlignedSegment.get_aligned_pairs
    auto getAlignedPairs(bool withRefSeq)(){
        return getAlignedPairs!withRefSeq(0, this.cigar.ref_bases_covered);
    }
/+ END CHERRY-PICK +/
}

///
debug(dhtslib_unittest) unittest
{
    import dhtslib.sam;
    import htslib.hts_log : hts_log_info;
    import std.path:buildPath,dirName;

    hts_set_log_level(htsLogLevel.HTS_LOG_TRACE);
    hts_log_info(__FUNCTION__, "Testing SAMRecord mutation");
    hts_log_info(__FUNCTION__, "Loading test file");
    auto bam = SAMFile(buildPath(dirName(dirName(dirName(dirName(__FILE__)))),"htslib","test","range.bam"), 0);
    auto ar = bam.allRecords;
    assert(ar.empty == false);
    auto read = ar.front;

    //change queryname
    hts_log_info(__FUNCTION__, "Testing queryname");
    assert(read.queryName=="HS18_09653:4:1315:19857:61712");
    read.queryName="HS18_09653:4:1315:19857:6171";
    assert(read.queryName=="HS18_09653:4:1315:19857:6171");
    assert(read.cigar.toString() == "78M1D22M");
    read.queryName="HS18_09653:4:1315:19857:617122";
    assert(read.queryName=="HS18_09653:4:1315:19857:617122");
    assert(read.cigar.toString() == "78M1D22M");
    assert(read["RG"].check!string);
    assert(read["RG"].to!string=="1");

    //change sequence
    hts_log_info(__FUNCTION__, "Testing sequence");
    assert(read.sequence=="AGCTAGGGCACTTTTTGTCTGCCCAAATATAGGCAACCAAAAATAATTTCCAAGTTTTTAATGATTTGTTGCATATTGAAAAAACATTTTTTGGGTTTTT");
    read.sequence=read.sequence[0..10];
    assert(read.sequence=="AGCTAGGGCA");

    ubyte[] q=[255,255,255,255,255,255,255,255,255,255];
    assert(read.qscores == q);
    q = [1, 14, 20, 40, 30, 10, 14, 20, 40, 30];
    read.qscores(q);
    assert(read.qscores == q);
    q[] += 33;
    
    assert(read.qscoresPhredScaled == cast(char[])(q));

    assert(read.cigar.toString() == "78M1D22M");
    assert(read["RG"].check!string);
    assert(read["RG"].to!string=="1");

    //change cigar
    hts_log_info(__FUNCTION__, "Testing cigar");
    auto c=read.cigar;
    c[$-1].length=21;
    read.cigar=c;
    assert(read.cigar.toString() == "78M1D21M");
    assert(read["RG"].check!string);
    assert(read["RG"].to!string=="1");
    
    //change tag
    hts_log_info(__FUNCTION__, "Testing tags");
    read["X0"]=2;
    assert(read["X0"].to!ubyte==2);
    assert(read["RG"].check!string);
    
    read["RG"]="test";
    assert(read["RG"].to!string=="test");
    hts_log_info(__FUNCTION__, "Cigar:" ~ read.cigar.toString());
}

///
debug(dhtslib_unittest) unittest
{
    import dhtslib.sam;
    import htslib.hts_log : hts_log_info;
    import std.path:buildPath,dirName;

    hts_set_log_level(htsLogLevel.HTS_LOG_TRACE);
    hts_log_info(__FUNCTION__, "Testing SAMRecord mutation w/ realloc");
    hts_log_info(__FUNCTION__, "Loading test file");
    auto bam = SAMFile(buildPath(dirName(dirName(dirName(dirName(__FILE__)))),"htslib","test","range.bam"), 0);
    auto ar = bam.allRecords;
    assert(ar.empty == false);
    auto read = ar.front;

    //change queryname
    hts_log_info(__FUNCTION__, "Testing queryname");
    assert(read.queryName=="HS18_09653:4:1315:19857:61712");

    //we do this only to force realloc
    read.b.m_data=read.b.l_data;


    auto prev_m=read.b.m_data;
    read.queryName="HS18_09653:4:1315:19857:61712HS18_09653:4:1315:19857:61712";
    assert(read.b.m_data >prev_m);
    assert(read.queryName=="HS18_09653:4:1315:19857:61712HS18_09653:4:1315:19857:61712");
    assert(read.cigar.toString() == "78M1D22M");
    assert(read["RG"].check!string);
    assert(read["RG"].to!string=="1");

    //change sequence
    hts_log_info(__FUNCTION__, "Testing sequence");
    assert(read.sequence=="AGCTAGGGCACTTTTTGTCTGCCCAAATATAGGCAACCAAAAATAATTTCCAAGTTTTTAATGATTTGTTGCATATTGAAAAAACATTTTTTGGGTTTTT");
    prev_m=read.b.m_data;
    read.sequence="AGCTAGGGCACTTTTTGTCTGCCCAAATATAGGCAACCAAAAATAATTTCCAAGTTTTTAATGATTTGTTGCATATTGAAAAAACATTTTTTGGGTTTTTAGCTAGGGCACTTTTTGTCTGCCCAAATATAGGCAACCAAAAATAATTTCCAAGTTTTTAATGATTTGTTGCATATTGAAAAAACATTTTTTGGGTTTTT";
    assert(read.b.m_data >prev_m);
    assert(read.sequence=="AGCTAGGGCACTTTTTGTCTGCCCAAATATAGGCAACCAAAAATAATTTCCAAGTTTTTAATGATTTGTTGCATATTGAAAAAACATTTTTTGGGTTTTTAGCTAGGGCACTTTTTGTCTGCCCAAATATAGGCAACCAAAAATAATTTCCAAGTTTTTAATGATTTGTTGCATATTGAAAAAACATTTTTTGGGTTTTT");
    assert(read.cigar.toString() == "78M1D22M");
    assert(read["RG"].check!string);
    assert(read["RG"].to!string=="1");

    //change cigar
    hts_log_info(__FUNCTION__, "Testing cigar");
    auto c=read.cigar;
    c=c~c;
    prev_m=read.b.m_data;
    read.cigar=c;
    assert(read.b.m_data >prev_m);
    assert(read.cigar.toString() == "78M1D22M78M1D22M");
    assert(read["RG"].check!string);
    assert(read["RG"].to!string=="1");
    
    //change tag
    hts_log_info(__FUNCTION__, "Testing tags");
    read["X0"]=2;
    assert(read["X0"].to!ubyte==2);
    assert(read["RG"].check!string);
    
    read["RG"]="test";
    assert(read["RG"].to!string=="test");
    hts_log_info(__FUNCTION__, "Cigar:" ~ read.cigar.toString());
}

///
debug(dhtslib_unittest) unittest
{
    import std.stdio;
    import dhtslib.sam;
    import dhtslib.sam.md : MDItr;
    import std.algorithm: map;
    import std.array: array;
    import std.path:buildPath,dirName;
    hts_set_log_level(htsLogLevel.HTS_LOG_TRACE);

    auto bam = SAMFile(buildPath(dirName(dirName(dirName(dirName(__FILE__)))),"htslib","test","range.bam"), 0);
    auto ar = bam.allRecords;
    assert(ar.empty == false);
    SAMRecord read = ar.front;
    
    auto pairs = read.getAlignedPairs!true(77, 77 + 5);

    assert(pairs.map!(x => x.qpos).array == [77,77,78,79,80]);
    pairs = read.getAlignedPairs!true(77, 77 + 5);
    assert(pairs.map!(x => x.rpos).array == [77,78,79,80,81]);
    pairs = read.getAlignedPairs!true(77, 77 + 5);
    assert(pairs.map!(x => x.refBase).array == "GAAAA");
    pairs = read.getAlignedPairs!true(77, 77 + 5);
    assert(pairs.map!(x => x.queryBase).array == "G-AAA");
}

///
debug(dhtslib_unittest) unittest
{
    import std.stdio : writeln, File;
    import std.range : drop;
    import std.utf : toUTFz;
    import htslib.hts_log; // @suppress(dscanner.suspicious.local_imports)
    import std.path:buildPath,dirName;
    import std.conv:to;
    import dhtslib.sam : parseSam;

    hts_set_log_level(htsLogLevel.HTS_LOG_TRACE);
    hts_log_info(__FUNCTION__, "Loading sam file");
    auto range = File(buildPath(dirName(dirName(dirName(dirName(__FILE__)))),"htslib","test","realn01_exp-a.sam")).byLineCopy();
    auto b = bam_init1();
    auto hdr = bam_hdr_init();
    string hdr_str;
    assert(range.empty == false);
    for (auto i = 0; i < 4; i++)
    {
        hdr_str ~= range.front ~ "\n";
        range.popFront;
    }
    hts_log_info(__FUNCTION__, "Header");
    writeln(hdr_str);
    hdr = sam_hdr_parse(cast(int) hdr_str.length, toUTFz!(char*)(hdr_str));
    hts_log_info(__FUNCTION__, "Read status:" ~ parseSam(range.front, hdr, b).to!string);
    auto r = new SAMRecord(b);
    hts_log_info(__FUNCTION__, "Cigar" ~ r.cigar.toString);
    assert(r.cigar.toString == "6M1D117M5D28M");
}

///
debug(dhtslib_unittest) unittest
{
    import std.stdio;
    import dhtslib.sam;
    import dhtslib.sam.md : MDItr;
    import std.algorithm: map;
    import std.array: array;
    import std.parallelism : parallel; 
    import std.path:buildPath,dirName;
    hts_set_log_level(htsLogLevel.HTS_LOG_TRACE);

    auto bam = SAMFile(buildPath(dirName(dirName(dirName(dirName(__FILE__)))),"htslib","test","range.bam"), 0);
    foreach(rec;parallel(bam.allRecords)){
        rec.queryName = "multithreading test";
    }

}