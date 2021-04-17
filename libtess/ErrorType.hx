/**
 * The types of errors provided in the error callback.
 * enum {number}
 */
package libtess;

@:native
@:nativeChildren
@:nativeProperty
@:nativeGen
@:expose('libtess.ErrorType')
class ErrorType {
    // TODO(bckenny) doc types
    // NOTE(bckenny): values from enumglu.spec
    public static var GLU_TESS_MISSING_BEGIN_POLYGON = 100151;
    public static var GLU_TESS_MISSING_END_POLYGON = 100153;
    public static var GLU_TESS_MISSING_BEGIN_CONTOUR = 100152;
    public static var GLU_TESS_MISSING_END_CONTOUR = 100154;
    public static var GLU_TESS_COORD_TOO_LARGE = 100155;
    public static var GLU_TESS_NEED_COMBINE_CALLBACK = 100156;
}