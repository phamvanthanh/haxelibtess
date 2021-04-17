package libtess;
import libtess.GluTesselator;
import libtess.WindingRule;
import libtess.GluEnum;
import libtess.PrimitiveType;

@:native
@:nativeGen
@:nativeChildren
@:nativeProperty
@:expose('Libtess')
class Libtess {
    public static var tessy:GluTesselator = null;

    static function main() {
      trace("Hello libtess");
      initializeValues();
    }

    public static function windingRule():WindingRule {
      return new WindingRule();
    }

    static function initializeValues(){
      
     
  }

    public static function triangulate(contours: Array<Array<Float>>, coordSize:Int = 2, normal:Array<Float>):Array<Float>{

        // libtess will take 3d verts and flatten to a plane for tesselation
        // since only doing 2d tesselation here, provide z=1 normal to skip
        // iterating over verts only to get the same answer.
        // comment out to test normal-generation code
        if(coordSize == 2){
          return triagulate2D(contours, normal);
        }
        else if(coordSize == 3){
         return triagulate3D(contours, normal);
        }
        else{
          throw "coord size must be 2 or 3";
        }

      
        return null;

    }

    private static function triagulate2D(contours: Array<Array<Float>>,normal:Array<Float>):Array<Float>{
      if(tessy == null){
        tessy = initTesselator();
      }
      
      tessy.gluTessNormal(normal[0], normal[1], normal[2]);

      var triangleVerts = [];
      tessy.gluTessBeginPolygon(triangleVerts);

      for ( i in 0...contours.length) {
        tessy.gluTessBeginContour();
        var contour = contours[i];
        var j = 0;
        while (j < contour.length) {
          var coords;
          coords = [contour[j], contour[j + 1], 0];
          tessy.gluTessVertex(coords, coords);
          j += 2;
        }
        tessy.gluTessEndContour();
      }

    // finish polygon (and time triangulation process)
    //  var startTime = window.nowish();
     tessy.gluTessEndPolygon();
    //  var endTime = window.nowish();
    //  console.log('tesselation time: ' + (endTime - startTime).toFixed(2) + 'ms');

     return triangleVerts;
    }

    private static function triagulate3D(contours: Array<Array<Float>>,normal:Array<Float>):Array<Float>{
      if(tessy == null){
        tessy = initTesselator();
      }
      
      tessy.gluTessNormal(normal[0], normal[1], normal[2]);

      var triangleVerts = [];
      tessy.gluTessBeginPolygon(triangleVerts);

      for ( i in 0...contours.length) {
        tessy.gluTessBeginContour();
        var contour = contours[i];
        var j = 0;
        while (j < contour.length) {
          var coords;
          coords = [contour[j], contour[j + 1], contour[j + 2]];
          tessy.gluTessVertex(coords, coords);
          j += 3;
        }
        tessy.gluTessEndContour();
      }

    // finish polygon (and time triangulation process)
    //  var startTime = window.nowish();
     tessy.gluTessEndPolygon();
    //  var endTime = window.nowish();
    //  console.log('tesselation time: ' + (endTime - startTime).toFixed(2) + 'ms');

     return triangleVerts;
    }

    public static function initTesselator(){

      // function called for each vertex of tesselator output
      function vertexCallback(data:Array<Float>, polyVertArray:Array<Float>) {
        // console.log(data[0], data[1]);
        polyVertArray[polyVertArray.length] = data[0];
        polyVertArray[polyVertArray.length] = data[1];
      }
      function begincallback(type) {
        if (type != PrimitiveType.GL_TRIANGLES) {
          trace('expected TRIANGLES but got type: ' + type);
        }
      }
      function errorcallback(errno) {
        trace('error callback');
        trace('error number: ' + errno);
      }
      // callback for when segments intersect and must be split
      function combinecallback(coords:Array<Float>, data, weight) {
        // console.log('combine callback');
        return [coords[0], coords[1], coords[2]];
      }
      function edgeCallback(flag) {
        // don't really care about the flag, but need no-strip/no-fan behavior
        // console.log('edge flag: ' + flag);
      }


      var tessy = new GluTesselator();
      // tessy.gluTessProperty(libtess.gluEnum.GLU_TESS_WINDING_RULE, libtess.windingRule.GLU_TESS_WINDING_POSITIVE);
      tessy.gluTessCallback(GluEnum.GLU_TESS_VERTEX_DATA, vertexCallback);
      tessy.gluTessCallback(GluEnum.GLU_TESS_BEGIN, begincallback);
      tessy.gluTessCallback(GluEnum.GLU_TESS_ERROR, errorcallback);
      tessy.gluTessCallback(GluEnum.GLU_TESS_COMBINE, combinecallback);
      tessy.gluTessCallback(GluEnum.GLU_TESS_EDGE_FLAG, edgeCallback);

      return tessy;

    }




}
