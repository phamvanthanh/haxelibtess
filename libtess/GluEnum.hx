package libtess;


/**
 * Enum values necessary for providing settings and callbacks. See the readme
 * for details.
 * enum {number}
 */
@:native
@:nativeChildren
@:nativeProperty
@:nativeGen
@:expose('libtess.gluEnum')
class GluEnum {
    // TODO(bckenny): rename so not always typing libtess.gluEnum.*?
  
    // NOTE(bckenny): values from enumglu.spec
    public static final GLU_TESS_BEGIN = 100100;
    public static final GLU_TESS_VERTEX = 100101;
    public static final GLU_TESS_END = 100102;
    public static final GLU_TESS_ERROR = 100103;
    public static final GLU_TESS_EDGE_FLAG = 100104;
    public static final GLU_TESS_COMBINE = 100105;
    public static final GLU_TESS_BEGIN_DATA = 100106;
    public static final GLU_TESS_VERTEX_DATA = 100107;
    public static final GLU_TESS_END_DATA = 100108;
    public static final GLU_TESS_ERROR_DATA = 100109;
    public static final GLU_TESS_EDGE_FLAG_DATA = 100110;
    public static final GLU_TESS_COMBINE_DATA = 100111;
  
    public static final GLU_TESS_MESH = 100112;  //  NOTE(bckenny): from tess.c
    public static final GLU_TESS_TOLERANCE = 100142;
    public static final GLU_TESS_WINDING_RULE = 100140;
    public static final GLU_TESS_BOUNDARY_ONLY = 100141;
  
    // TODO(bckenny): move this to libtess.errorType?
    public static final GLU_INVALID_ENUM = 100900;
    public static final GLU_INVALID_VALUE = 100901;

    


}