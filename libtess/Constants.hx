 /**
 * The maximum vertex coordinate size, 1e150. Anything larger will trigger a
 * GLU_TESS_COORD_TOO_LARGE error callback and the vertex will be clamped to
 * this value for all tessellation calculations.
 * const {number}
 * 
 * 
 */
package libtess;

@:native
@:nativeGen
@:nativeChildren
@:nativeProperty
@:expose('libtess.Constants')
class Constants  {

 public static final GLU_TESS_MAX_COORD = 1e150;

// NOTE(bckenny): value from glu.pl generator

/**
 * Normally the polygon is projected to a plane perpendicular to one of the
 * three coordinate axes before tessellating in 2d. This helps numerical
 * accuracy by forgoing a transformation step by simply dropping one coordinate
 * dimension.
 *
 * However, this can affect the placement of intersection points for non-axis-
 * aligned polygons. Setting TRUE_PROJECT to true will instead project onto a
 * plane actually perpendicular to the polygon's normal.
 *
 * NOTE(bckenny): I can find no instances on the internet in which this mode has
 * been used, but it's difficult to search for. This was a compile-time setting
 * in the original, so setting this as constant. If this is exposed in the
 * public API, remove the ignore coverage directives on
 * libtess.normal.projectPolygon and libtess.normal.normalize_.
 * const {boolean}
 */
public static final TRUE_PROJECT = false;


/**
 * The default tolerance for merging features, 0, meaning vertices are only
 * merged if they are exactly coincident
 * If a higher tolerance is needed, significant rewriting will need to occur.
 * See libtess.sweep.TOLERANCE_NONZERO_ as a starting place.
 * const {number}
 */
 public static final GLU_TESS_DEFAULT_TOLERANCE = 0;

 }