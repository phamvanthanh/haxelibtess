package libtess;


/**
 * The input contours parition the plane into regions. A winding
 * rule determines which of these regions are inside the polygon.
 *
 * For a single contour C, the winding number of a point x is simply
 * the signed number of revolutions we make around x as we travel
 * once around C (where CCW is positive). When there are several
 * contours, the individual winding numbers are summed. This
 * procedure associates a signed integer value with each point x in
 * the plane. Note that the winding number is the same for all
 * points in a single region.
 *
 * The winding rule classifies a region as "inside" if its winding
 * number belongs to the chosen category (odd, nonzero, positive,
 * negative, or absolute value of at least two). The current GLU
 * tesselator implements the "odd" rule. The "nonzero" rule is another
 * common way to define the interior. The other three rules are
 * useful for polygon CSG operations.
 * enum {number}
 */
@:native
@:nativeChildren
@:nativeProperty
@:nativeGen
@:expose('libtess.windingRule')



class WindingRule  {
 // NOTE(bckenny): values from enumglu.spec
 public static final GLU_TESS_WINDING_ODD = 100130;
 public static final GLU_TESS_WINDING_NONZERO = 100131;
 public static final GLU_TESS_WINDING_POSITIVE = 100132;
 public static final GLU_TESS_WINDING_NEGATIVE = 100133;
 public static final GLU_TESS_WINDING_ABS_GEQ_TWO = 100134;

 public function new(){}

}