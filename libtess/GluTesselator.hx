/**
 * Copyright 2000, Silicon Graphics, Inc. All Rights Reserved.
 * Copyright 2015, Google Inc. All Rights Reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice including the dates of first publication and
 * either this permission notice or a reference to http://oss.sgi.com/projects/FreeB/
 * shall be included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * SILICON GRAPHICS, INC. BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
 * IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * Original Code. The Original Code is: OpenGL Sample Implementation,
 * Version 1.2.1, released January 26, 2000, developed by Silicon Graphics,
 * Inc. The Original Code is Copyright (c) 1991-2000 Silicon Graphics, Inc.
 * Copyright in any portions created by third parties is as indicated
 * elsewhere herein. All Rights Reserved.
 */
/* global libtess */

package libtess;

import libtess.Constants.GLU_TESS_MAX_COORD;
import libtess.ErrorType;
import libtess.GluEnum;
import libtess.Mesh ;
import libtess.mesh.GluMesh ;
import libtess.Normal;
import libtess.Render ;
import libtess.Sweep;
import libtess.Tessmono ;
import libtess.Utils ;
import libtess.WindingRule;
import libtess.dict.Dict;
import libtess.priorityq.PriorityQ;
import libtess.mesh.GluVertex;
import libtess.mesh.GluHalfEdge;


// TODO(bckenny): create more javascript-y API, e.g. make gluTessEndPolygon
// async, don't require so many temp objects created

/**
 * The tesselator main class, providing the public API.
 * constructor
 * struct
 */
@:native
@:nativeChildren
@:nativeProperty
@:nativeGen
@:expose('libtess.GluTesselator')
class GluTesselator {
  // Only initialize fields which can be changed by the api. Other fields
  // are initialized where they are used.

  /*** state needed for collecting the input data ***/

  /**
   * Tesselator state, tracking what begin/end calls have been seen.
   * private {TessState}
   */
  public var  state_ = TessState.T_DORMANT;

  /**
   * lastEdge_.org is the most recent vertex
   * private {libtess.GluHalfEdge}
   */
  public var lastEdge_:GluHalfEdge = null;

  /**
   * stores the input contours, and eventually the tessellation itself
   * type {libtess.GluMesh}
   */
   public var mesh:GluMesh = null;

  /**
   * Error callback.
   * private {?function((ErrorType|GluEnum), Object=)}
   */
   public var errorCallback_ = null;

  /*** state needed for projecting onto the sweep plane ***/

  /**
   * user-specified normal (if provided)
   * private {!Array<number>}
   */
   public var normal_ = [0.0, 0.0, 0.0];

  /*** state needed for the line sweep ***/

  /**
   * rule for determining polygon interior
   * type {WindingRule}
   */
   public var windingRule = WindingRule.GLU_TESS_WINDING_ODD;

  /**
   * fatal error: needed combine callback
   * type {boolean}
   */
   public var fatalError = false;

  /**
   * edge dictionary for sweep line
   * type {libtess.Dict}
   */
   public var dict:Dict = null;
  // NOTE(bckenny): dict initialized in sweep.initEdgeDict_, removed in sweep.doneEdgeDict_

  /**
   * priority queue of vertex events
   * type {libtess.PriorityQ}
   */
   public var pq:PriorityQ = null;
  // NOTE(bckenny): pq initialized in sweep.initPriorityQ

  /**
   * current sweep event being processed
   * type {libtess.GluVertex}
   */
   public var event:GluVertex = null;

  /**
   * Combine callback.
   * private {?function(Array<number>, Array<Object>, Array<number>, Object=): Object}
   */
   public var combineCallback_:(coords:Array<Float>, data:Array<Any>, weight:Array<Float>, polygondata:Any)->Any = null;

  /*** state needed for rendering callbacks (see render.js) ***/

  /**
   * Extract contours, not triangles
   * private {boolean}
   */
   public var boundaryOnly_ = false;

  /**
   * Begin callback.
   * private {?function(libtess.primitiveType, Object=)}
   */
 
   public var beginCallback_:(type : Int, data : Any) -> Void = null;

  /**
   * Edge flag callback.
   * private {?function(boolean, Object=)}
   */
   public var edgeFlagCallback_:(flag : Bool, data : Any) -> Void = null;

  /**
   * Vertex callback.
   * private {?function(Object/number, Object=)} 
   */
   public var vertexCallback_:(flag : Int, data : Any) -> Void  = null;

  /**
   * End callback.
   * private {?function(Object=)}
   */
   public var endCallback_:( data: Any)->Void  = null;

  /**
   * Mesh callback.
   * private {?function(libtess.GluMesh)}
   */
   public var meshCallback_: ( data: GluMesh)->Void = null;

  /**
   * client data for current polygon
   * private {Object}
   */
   public var polygonData_:Any = null;

  /* jscs:enable maximumLineLength */

  public function new(){}

/**
 * Call error callback, if specified, with errno.
 * param {(ErrorType|GluEnum)} errno
 */
public function callErrorCallback(errno) {
  if (this.errorCallback_ !=  null) {
    this.errorCallback_(errno, this.polygonData_);
  }
}

/* jscs:disable maximumLineLength */
/**
 * Call callback for combining vertices at edge intersection requiring the
 * creation of a new vertex.
 * param {!Array<number>} coords Intersection coordinates.
 * param {!Array<Object>} data Array of vertex data, one per edge vertices.
 * param {!Array<number>} weight Coefficients used for the linear combination of vertex coordinates that gives coords.
 * return {?Object} Interpolated vertex.
 */
public function callCombineCallback(coords:Array<Float>, data:Array<Any>, weight:Array<Float>):Any {
  if (this.combineCallback_ != null) {
    return this.combineCallback_(coords, data, weight, this.polygonData_);
        // null;
  }

  return null;
}

/**
 * Call callback to indicate the end of tessellation.
 */
public function callEndCallback() {
  if (this.endCallback_ != null) {
    this.endCallback_(this.polygonData_);
  }
}

/**
 * Call callback to indicate whether the vertices to follow begin edges which
 * lie on a polygon boundary.
 * param {boolean} flag
 */
public function callEdgeFlagCallback (flag:Bool) {
  if (this.edgeFlagCallback_ !=  null) {
    this.edgeFlagCallback_(flag, this.polygonData_);
  }
}

/**
 * Call callback to emit a vertex of the tessellated polygon.
 * param {Object} data
 */
public function callVertexCallback(data) {
  if (this.vertexCallback_ !=  null) {
    this.vertexCallback_(data, this.polygonData_);
  }
};

/**
 * Call callback to indicate the start of a primitive, to be followed by emitted
 * vertices, if any. In libtess.js, `type` will always be `GL_TRIANGLES`.
 * param {libtess.primitiveType} num type
 */
public function callBeginCallback(type:Int) {
 
  if (this.beginCallback_ != null) {
    this.beginCallback_(type, this.polygonData_);
  }
};

/**
 * [addVertex_ description]
 * private
 * param {!Array<number>} coords [description].
 * param {Object} data [description].
 */
public function addVertex_(coords, data) {
  var e = this.lastEdge_;
  if (e == null) {
    // Make a self-loop (one vertex, one edge).
    e = Mesh.makeEdge(this.mesh);
    Mesh.meshSplice(e, e.sym);

  } else {
    // Create a new vertex and edge which immediately follow e
    // in the ordering around the left face.
    Mesh.splitEdge(e);
    e = e.lNext;
  }

  // The new vertex is now e.org.
  e.org.data = data;
  e.org.coords[0] = coords[0];
  e.org.coords[1] = coords[1];
  e.org.coords[2] = coords[2];

  // The winding of an edge says how the winding number changes as we
  // cross from the edge''s right face to its left face.  We add the
  // vertices in such an order that a CCW contour will add +1 to
  // the winding number of the region inside the contour.
  e.winding = 1;
  e.sym.winding = -1;

  this.lastEdge_ = e;

  
}






/**
 * Change the tesselator state.
 * private
 * param {TessState} state
 */
public function requireState_(state) {
  if (this.state_ != state) {
    this.gotoState_(state);
  }
};

/**
 * Change the current tesselator state one level at a time to get to the
 * desired state. Only triggered when the API is not called in the correct order
 * so an error callback is made, however the tesselator will always attempt to
 * recover afterwards (see README).
 * private
 * param {TessState} newState
 */
public function gotoState_(newState) {
  while (this.state_ != newState) {
    if (this.state_ < newState) {
      switch (this.state_) {
        case TessState.T_DORMANT:
          this.callErrorCallback(
              ErrorType.GLU_TESS_MISSING_BEGIN_POLYGON);
          this.gluTessBeginPolygon(null);
          break;

        case TessState.T_IN_POLYGON:
          this.callErrorCallback(
              ErrorType.GLU_TESS_MISSING_BEGIN_CONTOUR);
          this.gluTessBeginContour();
          break;
      }

    } else {
      switch (this.state_) {
        case TessState.T_IN_CONTOUR:
          this.callErrorCallback(
              ErrorType.GLU_TESS_MISSING_END_CONTOUR);
          this.gluTessEndContour();
          break;

        case TessState.T_IN_POLYGON:
          this.callErrorCallback(
              ErrorType.GLU_TESS_MISSING_END_POLYGON);
          // NOTE(bckenny): libtess originally reset the tesselator, even though
          // the README claims it should spit out the tessellated results at
          // this point.
          // (see http://cgit.freedesktop.org/mesa/glu/tree/src/libtess/tess.c#n180)
          this.gluTessEndPolygon();
          break;
      }
    }
  }
}



/**
 * Lets the user supply the polygon normal, if known. All input data is
 * projected into a plane perpendicular to the normal before tesselation. All
 * output triangles are oriented CCW with respect to the normal (CW orientation
 * can be obtained by reversing the sign of the supplied normal). For example,
 * if you know that all polygons lie in the x-y plane, call
 * `tess.gluTessNormal(0.0, 0.0, 1.0)` before rendering any polygons.
 * param {number} x
 * param {number} y
 * param {number} z
 */
public function gluTessNormal(x:Float, y:Float, z:Float) {
  this.normal_[0] = x;
  this.normal_[1] = y;
  this.normal_[2] = z;
};


/**
 * Destory the tesselator object. See README.
 */
public function gluDeleteTess() {
  // TODO(bckenny): This does nothing but assert that it isn't called while
  // building the polygon since we rely on GC to handle memory. *If* the public
  // API changes, this should go.
  this.requireState_(TessState.T_DORMANT);
  // memFree(tess); TODO(bckenny)
};


/**
 * Set properties for control over tesselation. See README.
 * @param {GluEnum} which [description].
 * @param {number|boolean} value [description].
 */
public function gluTessProperty(which:Int, value:Int = -1) {
  // TODO(bckenny): split into more setters?
  // TODO(bckenny): in any case, we can do better than this switch statement

  switch (which) {
    case GluEnum.GLU_TESS_TOLERANCE:
      // NOTE(bckenny): libtess has never supported any tolerance but 0.
      return;

    case GluEnum.GLU_TESS_WINDING_RULE:
      {
        var windingRule = (value);

        switch (windingRule) {
          case WindingRule.GLU_TESS_WINDING_ODD:
          case WindingRule.GLU_TESS_WINDING_NONZERO:
          case WindingRule.GLU_TESS_WINDING_POSITIVE:
          case WindingRule.GLU_TESS_WINDING_NEGATIVE:
          case WindingRule.GLU_TESS_WINDING_ABS_GEQ_TWO:
            this.windingRule = windingRule;
            return;
          default:
        }
      }
      // break;

    case GluEnum.GLU_TESS_BOUNDARY_ONLY:
      this.boundaryOnly_ = value != -1;
      return;

    default:
      this.callErrorCallback(GluEnum.GLU_INVALID_ENUM);
      return;
  }
  this.callErrorCallback(GluEnum.GLU_INVALID_VALUE);
};


/**
 * Returns tessellator property
 * param {GluEnum} which [description].
 * return {number|boolean} [description].
 */
public function gluGetTessProperty(which:Int):Int {
  // TODO(bckenny): as above, split into more getters? and improve on switch statement
  // why are these being asserted in getter but not setter?

  switch (which) {
    case GluEnum.GLU_TESS_TOLERANCE:
      
      return 0;

    case GluEnum.GLU_TESS_WINDING_RULE:
      var rule = this.windingRule;
      Utils.assert(rule == WindingRule.GLU_TESS_WINDING_ODD ||
          rule == WindingRule.GLU_TESS_WINDING_NONZERO ||
          rule == WindingRule.GLU_TESS_WINDING_POSITIVE ||
          rule == WindingRule.GLU_TESS_WINDING_NEGATIVE ||
          rule == WindingRule.GLU_TESS_WINDING_ABS_GEQ_TWO);
      return rule;

    case GluEnum.GLU_TESS_BOUNDARY_ONLY:
      Utils.assert(this.boundaryOnly_ == true ||
          this.boundaryOnly_ == false);

      return this.boundaryOnly_?1:0;

    default:
      this.callErrorCallback(GluEnum.GLU_INVALID_ENUM);
      // break;
  }
  return 0;
}


/**
 * Specify callbacks. See README for callback descriptions. A null or undefined
 * opt_fn removes current callback.
 * param {GluEnum} which The callback-type gluEnum value.
 * param {?Function=} opt_fn
 */
public function gluTessCallback(which:Int, opt_fn:Any = null) {
  var fn =  opt_fn;
  // TODO(bckenny): better opt_fn typing?
  // TODO(bckenny): should add documentation that references in callback are volatile (or make a copy)

  switch (which) {
    case GluEnum.GLU_TESS_BEGIN:
    case GluEnum.GLU_TESS_BEGIN_DATA:
      this.beginCallback_ =  (fn);
      return;

    case GluEnum.GLU_TESS_EDGE_FLAG:
    case GluEnum.GLU_TESS_EDGE_FLAG_DATA:
      this.edgeFlagCallback_ = cast(fn );
      return;

    case GluEnum.GLU_TESS_VERTEX:
    case GluEnum.GLU_TESS_VERTEX_DATA:
      this.vertexCallback_ =  cast(fn);
      return;

    case GluEnum.GLU_TESS_END:
    case GluEnum.GLU_TESS_END_DATA:
      this.endCallback_ = cast (fn);
      return;

    case GluEnum.GLU_TESS_ERROR:
    case GluEnum.GLU_TESS_ERROR_DATA:
      this.errorCallback_ = (fn);
      return;

    case GluEnum.GLU_TESS_COMBINE:
    case GluEnum.GLU_TESS_COMBINE_DATA:
      this.combineCallback_ =  cast(fn);
      return;

    case GluEnum.GLU_TESS_MESH:
      this.meshCallback_ = cast (fn);
      return;

    default:
      this.callErrorCallback(GluEnum.GLU_INVALID_ENUM);
      return;
  }
};

/**
 * Specify a vertex and associated data. Must be within calls to
 * beginContour/endContour. See README.
 * param {!Array<number>} coords
 * param {Object} data
 */
public function gluTessVertex(coords, data) {
  var tooLarge = false;

  // TODO(bckenny): pool allocation?
  var clamped = [0.0, 0.0, 0.0];

  this.requireState_(TessState.T_IN_CONTOUR);

  for ( i in 0...3) {
    var x = coords[i];
    if (x < -GLU_TESS_MAX_COORD) {
      x = -GLU_TESS_MAX_COORD;
      tooLarge = true;
    }
    if (x > GLU_TESS_MAX_COORD) {
      x = GLU_TESS_MAX_COORD;
      tooLarge = true;
    }
    clamped[i] = x;
  }

  if (tooLarge) {
    this.callErrorCallback(ErrorType.GLU_TESS_COORD_TOO_LARGE);
  }

  this.addVertex_(clamped, data);
};

/**
 * [gluTessBeginPolygon description]
 * param {Object} data Client data for current polygon.
 */
public function gluTessBeginPolygon(data) {
  this.requireState_(TessState.T_DORMANT);

  this.state_ = TessState.T_IN_POLYGON;

  this.mesh = new GluMesh();

  this.polygonData_ = data;
};

/**
 * [gluTessBeginContour description]
 */
public  function gluTessBeginContour() {
  this.requireState_(TessState.T_IN_POLYGON);
  this.state_ = TessState.T_IN_CONTOUR;
  this.lastEdge_ = null;
};

/**
 * [gluTessEndContour description]
 */
public function gluTessEndContour() {
  this.requireState_(TessState.T_IN_CONTOUR);
  this.state_ = TessState.T_IN_POLYGON;
};

/**
 * [gluTessEndPolygon description]
 */
public function gluTessEndPolygon() {
  this.requireState_(TessState.T_IN_POLYGON);
  this.state_ = TessState.T_DORMANT;

  // Determine the polygon normal and project vertices onto the plane
  // of the polygon.
  Normal.projectPolygon(this, this.normal_[0], this.normal_[1],
      this.normal_[2]);

  // computeInterior(tess) computes the planar arrangement specified
  // by the given contours, and further subdivides this arrangement
  // into regions. Each region is marked "inside" if it belongs
  // to the polygon, according to the rule given by this.windingRule.
  // Each interior region is guaranteed be monotone.
  Sweep.computeInterior(this);

  if (!this.fatalError) {
    // If the user wants only the boundary contours, we throw away all edges
    // except those which separate the interior from the exterior.
    // Otherwise we tessellate all the regions marked "inside".
    // NOTE(bckenny): we know this.mesh has been initialized, so help closure out.
    var mesh = (this.mesh);
    if (this.boundaryOnly_) {
      Tessmono.setWindingNumber(mesh, 1, true);
    } else {
      Tessmono.tessellateInterior(mesh);
    }

    this.mesh.checkMesh();

    if (this.beginCallback_ !=  null || this.endCallback_  !=  null || this.vertexCallback_ != null||
        this.edgeFlagCallback_ != null) {

      if (this.boundaryOnly_) {
        // output boundary contours
        Render.renderBoundary(this, this.mesh);

      } else {
        // output triangles (with edge callback if one is set)
        var flagEdges = this.edgeFlagCallback_ != null;
        Render.renderMesh(this, this.mesh, flagEdges);
      }
    }

    if (this.meshCallback_ != null) {
      // Throw away the exterior faces, so that all faces are interior.
      // This way the user doesn't have to check the "inside" flag,
      // and we don't need to even reveal its existence. It also leaves
      // the freedom for an implementation to not generate the exterior
      // faces in the first place.
      Tessmono.discardExterior(this.mesh);
      // user wants the mesh itself
      this.meshCallback_(this.mesh);

      this.mesh = null;
      this.polygonData_ = null;
      return;
    }
  }

  Mesh.deleteMesh(this.mesh);
  this.polygonData_ = null;
  this.mesh = null;
}

/**
 * The begin/end calls must be properly nested. We keep track of the current
 * state to enforce the ordering.
 * enum {number}
 * private
 */




}














