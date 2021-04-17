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

import libtess.Constants.TRUE_PROJECT;
import libtess.Constants.GLU_TESS_MAX_COORD;
import libtess.Utils ;

/** const */


// TODO(bckenny): Integrate SLANTED_SWEEP somehow?
/* The "feature merging" is not intended to be complete. There are
 * special cases where edges are nearly parallel to the sweep line
 * which are not implemented. The algorithm should still behave
 * robustly (ie. produce a reasonable tesselation) in the presence
 * of such edges, however it may miss features which could have been
 * merged. We could minimize this effect by choosing the sweep line
 * direction to be something unusual (ie. not parallel to one of the
 * coordinate axes).
 * #if defined(SLANTED_SWEEP)
 * #define S_UNIT_X  0.50941539564955385 // Pre-normalized
 * #define S_UNIT_Y  0.86052074622010633
 * #endif
 */

/**
 * X coordinate of local basis for polygon projection.
 * private {number}
 * const
 */
// import {GLU_TESS_MAX_COORD, TRUE_PROJECT} from './Constants';
// import Utils from './Utils';
@:native
@:nativeChildren
@:nativeProperty
@:nativeGen
@:expose('libtess.normal')
class Normal   {
    static public var S_UNIT_X_ = 1.0;

/**
 * Y coordinate of local basis for polygon projection.
 * private {number}
 * const
 */
    static public var S_UNIT_Y_ = 0.0;

/**
 * Determines a polygon normal and projects vertices onto the plane of the
 * polygon. A pre-computed normal for the data may be provided, or set to the
 * zero vector if one should be computed from it.
 * param {!libtess.GluTesselator} tess
 * param {number} normalX
 * param {number} normalY
 * param {number} normalZ
 */
static public  function projectPolygon(tess:GluTesselator, normalX:Float, normalY:Float, normalZ:Float) {
  var computedNormal = false;

  var norm = [
    normalX,
    normalY,
    normalZ
  ];
  if (normalX == 0 && normalY ==  0 && normalZ == 0) {
    Normal.computeNormal_(tess, norm);
    computedNormal = true;
  }

  var i = Normal.longAxis_(norm);
  var vHead = tess.mesh.vHead;
  var v;

  // NOTE(bckenny): This branch is never taken. See comment on
  // libtess.TRUE_PROJECT.
  /* istanbul ignore if */
  if (TRUE_PROJECT) {
    // Choose the initial sUnit vector to be approximately perpendicular
    // to the normal.
    Normal.normalize_(norm);

    var sUnit = [0.0, 0.0, 0.0];
    var tUnit = [0.0, 0.0, 0.0];

    sUnit[i] = 0;
    sUnit[(i + 1) % 3] = Normal.S_UNIT_X_;
    sUnit[(i + 2) % 3] = Normal.S_UNIT_Y_;

    // Now make it exactly perpendicular
    var w = Normal.dot_(sUnit, norm);
    sUnit[0] -= w * norm[0];
    sUnit[1] -= w * norm[1];
    sUnit[2] -= w * norm[2];
    Normal.normalize_(sUnit);

    // Choose tUnit so that (sUnit,tUnit,norm) form a right-handed frame
    tUnit[0] = norm[1] * sUnit[2] - norm[2] * sUnit[1];
    tUnit[1] = norm[2] * sUnit[0] - norm[0] * sUnit[2];
    tUnit[2] = norm[0] * sUnit[1] - norm[1] * sUnit[0];
    Normal.normalize_(tUnit);

    // Project the vertices onto the sweep plane
    v = vHead.next; 
    while (v != vHead) {
     
      v.s = Normal.dot_(v.coords, sUnit);
      v.t = Normal.dot_(v.coords, tUnit);
       v = v.next;
    }

  } else {
    // Project perpendicular to a coordinate axis -- better numerically
    var sAxis = (i + 1) % 3;
    var tAxis = (i + 2) % 3;
    var tNegate = norm[i] > 0 ? 1 : -1;

    // Project the vertices onto the sweep plane
    v = vHead.next;
    while ( v != vHead) {
      v.s = v.coords[sAxis];
      v.t = tNegate * v.coords[tAxis];
       v = v.next;
    }
  }

  if (computedNormal) {
    Normal.checkOrientation_(tess);
  }
};

// NOTE(bckenny): dot_ is no longer called in code without
// libtess.TRUE_PROJECT defined.
/* istanbul ignore next */
/**
 * Computes the dot product of vectors u and v.
 * private
 * param {!Array<number>} u
 * param {!Array<number>} v
 * return {number}
 */
static public function dot_(u:Array<Float>, v:Array<Float>):Float {
  return u[0] * v[0] + u[1] * v[1] + u[2] * v[2];
};

// NOTE(bckenny): only called from within projectPolygon's
// TRUE_PROJECT branch, so ignoring for code coverage.
/* istanbul ignore next */
/**
 * Normalize vector v.
 * private
 * param {!Array<number>} v
 */
static public  function normalize_(v:Array<Float>):Void{
  var len = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];

  Utils.assert(len > 0);
  len = Math.sqrt(len);
  v[0] /= len;
  v[1] /= len;
  v[2] /= len;
};
/**
 * Returns the index of the longest component of vector v.
 * private
 * param {!Array<number>} v
 * return {number}
 */
static public  function longAxis_(v:Array<Float>):Int {
  var i = 0;

  if (Math.abs(v[1]) > Math.abs(v[0])) {
    i = 1;
  }
  if (Math.abs(v[2]) > Math.abs(v[i])) {
    i = 2;
  }

  return i;
}

/**
 * Compute an approximate normal of the polygon from the vertices themselves.
 * Result returned in norm.
 * private
 * param {!libtess.GluTesselator} tess
 * param {!Array<number>} norm
 */
static public function computeNormal_(tess:GluTesselator, norm:Array<Float>) {
  var maxVal = [
    -2 * GLU_TESS_MAX_COORD,
    -2 * GLU_TESS_MAX_COORD,
    -2 * GLU_TESS_MAX_COORD
  ];
  var minVal = [
    2 * GLU_TESS_MAX_COORD,
    2 * GLU_TESS_MAX_COORD,
    2 * GLU_TESS_MAX_COORD
  ];
  var maxVert = [];
  var minVert = [];

  
  var vHead = tess.mesh.vHead;
  var v = vHead.next; 
  while (v != vHead) {
    for ( i in 0...3) {
      var c = v.coords[i];
      if (c < minVal[i]) { minVal[i] = c; minVert[i] = v; }
      if (c > maxVal[i]) { maxVal[i] = c; maxVert[i] = v; }
    }
    v = v.next;
  }

  // Find two vertices separated by at least 1/sqrt(3) of the maximum
  // distance between any two vertices
  var index = 0;
  if (maxVal[1] - minVal[1] > maxVal[0] - minVal[0]) { index = 1; }
  if (maxVal[2] - minVal[2] > maxVal[index] - minVal[index]) { index = 2; }
  if (minVal[index] >= maxVal[index]) {
    // All vertices are the same -- normal doesn't matter
    norm[0] = 0; norm[1] = 0; norm[2] = 1;
    return;
  }

  // Look for a third vertex which forms the triangle with maximum area
  // (Length of normal == twice the triangle area)
  var maxLen2 = 0.0;
  var v1 = minVert[index];
  var v2 = maxVert[index];
  var tNorm = [0.0, 0.0, 0.0];
  var d1 = [
    v1.coords[0] - v2.coords[0],
    v1.coords[1] - v2.coords[1],
    v1.coords[2] - v2.coords[2]
  ];
  var d2 = [0.0, 0.0, 0.0];
  v = vHead.next;
  while ( v != vHead) {
    d2[0] = v.coords[0] - v2.coords[0];
    d2[1] = v.coords[1] - v2.coords[1];
    d2[2] = v.coords[2] - v2.coords[2];
    tNorm[0] = d1[1] * d2[2] - d1[2] * d2[1];
    tNorm[1] = d1[2] * d2[0] - d1[0] * d2[2];
    tNorm[2] = d1[0] * d2[1] - d1[1] * d2[0];
    var tLen2 = tNorm[0] * tNorm[0] + tNorm[1] * tNorm[1] + tNorm[2] * tNorm[2];
    if (tLen2 > maxLen2) {
      maxLen2 = tLen2;
      norm[0] = tNorm[0];
      norm[1] = tNorm[1];
      norm[2] = tNorm[2];
    }

     v = v.next;
  }

  if (maxLen2 <= 0) {
    // All points lie on a single line -- any decent normal will do
    norm[0] = norm[1] = norm[2] = 0;
    norm[Normal.longAxis_(d1)] = 1;
  }
}

/**
 * Check that the sum of the signed area of all projected contours is
 * non-negative. If not, negate the t-coordinates to reverse the orientation and
 * make it so.
 * private
 * param {!libtess.GluTesselator} tess
 */
static public function checkOrientation_(tess:GluTesselator) {
  var area = 0.0;
  var fHead = tess.mesh.fHead;
  var f = fHead.next;
  while ( f != fHead) {
    var e = f.anEdge;
    if (e.winding <= 0) { continue; }
    do {
      area += (e.org.s - e.dst().s) * (e.org.t + e.dst().t);
      e = e.lNext;
    } while (e != f.anEdge);

    f = f.next;
  }

  if (area < 0) {
    // Reverse the orientation by flipping all the t-coordinates
    var vHead = tess.mesh.vHead;
    var v = vHead.next;
    while ( v != vHead) {
      v.t = -v.t;
      v = v.next;
    }
  }
}
}
