    /**
 * The type of primitive return from a "begin" callback. GL_LINE_LOOP is only
 * returned when GLU_TESS_BOUNDARY_ONLY is true. GL_TRIANGLE_STRIP and
 * GL_TRIANGLE_FAN are no longer returned since 1.1.0 (see release notes).
 * enum {number}
 */
 package libtess;
 
 @:native
 @:nativeChildren
 @:nativeGen
 @:nativeProperty

 @:expose('libtess.primitiveType')
 class  PrimitiveType   {
   static public final GL_LINE_LOOP = 2;
   static public final GL_TRIANGLES = 4;
   static public final GL_TRIANGLE_STRIP = 5;
   static public final GL_TRIANGLE_FAN = 6;
  
}