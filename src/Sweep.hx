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
import libtess.dict.Dict ;
import libtess.ErrorType;
import libtess.Geom;
import libtess.Mesh;
import libtess.GluTesselator;
import libtess.mesh.GluMesh;
import libtess.mesh.GluVertex ;
import libtess.mesh.GluHalfEdge;
import libtess.priorityq.PriorityQ;
import libtess.sweep.ActiveRegion;
import libtess.Utils ;
import libtess.WindingRule;


// TODO(bckenny): a number of these never return null (as opposed to original) and should be typed appropriately

/*
 * Invariants for the Edge Dictionary.
 * - each pair of adjacent edges e2=succ(e1) satisfies edgeLeq_(e1,e2)
 *   at any valid location of the Sweep event
 * - if edgeLeq_(e2,e1) as well (at any valid Sweep event), then e1 and e2
 *   share a common endpoint
 * - for each e, e.dst() has been processed, but not e.org
 * - each edge e satisfies vertLeq(e.dst(),event) && vertLeq(event,e.org)
 *   where "event" is the current Sweep line event.
 * - no edge e has zero length
 *
 * Invariants for the Mesh (the processed portion).
 * - the portion of the mesh left of the Sweep line is a planar graph,
 *   ie. there is *some* way to embed it in the plane
 * - no processed edge has zero length
 * - no two processed vertices have identical coordinates
 * - each "inside" region is monotone, ie. can be broken into two chains
 *   of monotonically increasing vertices according to VertLeq(v1,v2)
 *   - a non-invariant: these chains may intersect (very slightly)
 *
 * Invariants for the Sweep.
 * - if none of the edges incident to the event vertex have an activeRegion
 *   (ie. none of these edges are in the edge dictionary), then the vertex
 *   has only right-going edges.
 * - if an edge is marked "fixUpperEdge" (it is a temporary edge introduced
 *   by ConnectRightVertex), then it is the only right-going edge from
 *   its associated vertex.  (This says that these edges exist only
 *   when it is necessary.)
 */

/** const */
@:native
@:nativeChildren
@:nativeProperty
@:nativeGen
@:expose('libtess.sweep')

class Sweep   {
  /**
 * Delete any degenerate faces with only two edges. walkDirtyRegions()
 * will catch almost all of these, but it won't catch degenerate faces
 * produced by splice operations on already-processed edges.
 * The two places this can happen are in finishLeftRegions(), when
 * we splice in a "temporary" edge produced by connectRightVertex(),
 * and in checkForLeftSplice(), where we splice already-processed
 * edges to ensure that our dictionary invariants are not violated
 * by numerical errors.
 *
 * In both these cases it is *very* dangerous to delete the offending
 * edge at the time, since one of the routines further up the stack
 * will sometimes be keeping a pointer to that edge.
 *
 * private
 * param {GluMesh} mesh [description].
 */
static function removeDegenerateFaces_ (msh:GluMesh) {
  var fNext;
  var f = msh.fHead.next;
  while ( f != msh.fHead) {
    fNext = f.next;
    var e = f.anEdge;
    Utils.assert(e.lNext != e);

    if (e.lNext.lNext == e) {
      // A face with only two edges
      Sweep.addWinding_(e.oNext, e);
      Mesh.deleteEdge(e);
    }
    
    f = fNext;
  }
};

/**
 * When we merge two edges into one, we need to compute the combined
 * winding of the new edge.
 * private
 * param {GluHalfEdge} eDst [description].
 * param {GluHalfEdge} eSrc [description].
 */
static  public function addWinding_(eDst:GluHalfEdge, eSrc:GluHalfEdge) {
  // NOTE(bckenny): from AddWinding macro
  eDst.winding += eSrc.winding;
  eDst.sym.winding += eSrc.sym.winding;
};
/**
 * computeInterior(tess) computes the planar arrangement specified
 * by the given contours, and further subdivides this arrangement
 * into regions. Each region is marked "inside" if it belongs
 * to the polygon, according to the rule given by tess.windingRule.
 * Each interior region is guaranteed be monotone.
 *
 * param {GluTesselator} tess [description].
 */
static  public function computeInterior(tess:GluTesselator) {
  tess.fatalError = false;

  // Each vertex defines an event for our Sweep line. Start by inserting
  // all the vertices in a priority queue. Events are processed in
  // lexicographic order, ie.
  // e1 < e2  iff  e1.x < e2.x || (e1.x == e2.x && e1.y < e2.y)
  Sweep.removeDegenerateEdges_(tess);
  Sweep.initPriorityQ_(tess);
  Sweep.initEdgeDict_(tess);

  var v;
  while ((v = tess.pq.extractMin()) != null) {
    while (true) {
      var vNext = tess.pq.minimum();
      if (vNext == null || !Geom.vertEq(vNext, v)) {
        break;
      }

      /* Merge together all vertices at exactly the same location.
       * This is more efficient than processing them one at a time,
       * simplifies the code (see connectLeftDegenerate), and is also
       * important for correct handling of certain degenerate cases.
       * For example, suppose there are two identical edges A and B
       * that belong to different contours (so without this code they would
       * be processed by separate Sweep events).  Suppose another edge C
       * crosses A and B from above.  When A is processed, we split it
       * at its intersection point with C.  However this also splits C,
       * so when we insert B we may compute a slightly different
       * intersection point.  This might leave two edges with a small
       * gap between them.  This kind of error is especially obvious
       * when using boundary extraction (GLU_TESS_BOUNDARY_ONLY).
       */
      vNext = tess.pq.extractMin();
      Sweep.spliceMergeVertices_(tess, v.anEdge, vNext.anEdge);
    }
    Sweep.SweepEvent_(tess, v);
  }

  // TODO(bckenny): what does the next comment mean? can we eliminate event except when debugging?
  // Set tess.event for debugging purposes
  var minRegion = tess.dict.getMin().getKey();
  tess.event = minRegion.eUp.org;
  Sweep.doneEdgeDict_(tess);
  Sweep.donePriorityQ_(tess);

  Sweep.removeDegenerateFaces_(tess.mesh);
  tess.mesh.checkMesh();
};


/**
 * Both edges must be directed from right to left (this is the canonical
 * direction for the upper edge of each region).
 *
 * The strategy is to evaluate a "t" value for each edge at the
 * current Sweep line position, given by tess.event.  The calculations
 * are designed to be very stable, but of course they are not perfect.
 *
 * Special case: if both edge destinations are at the Sweep event,
 * we sort the edges by slope (they would otherwise compare equally).
 *
 * private
 * param {!GluTesselator} tess
 * param {!ActiveRegion} reg1
 * param {!ActiveRegion} reg2
 * return {boolean}
 */
static public function edgeLeq_(tess:GluTesselator, reg1:ActiveRegion, reg2:ActiveRegion):Bool {
  var event = tess.event;
  var e1 = reg1.eUp;
  var e2 = reg2.eUp;

  if (e1.dst() == event) {
    if (e2.dst() == event) {
      // Two edges right of the Sweep line which meet at the Sweep event.
      // Sort them by slope.
      if (Geom.vertLeq(e1.org, e2.org)) {
        return Geom.edgeSign(e2.dst(), e1.org, e2.org) <= 0;
      }

      return Geom.edgeSign(e1.dst(), e2.org, e1.org) >= 0;
    }

    return Geom.edgeSign(e2.dst(), event, e2.org) <= 0;
  }

  if (e2.dst() == event) {
    return Geom.edgeSign(e1.dst(), event, e1.org) >= 0;
  }

  // General case - compute signed distance *from* e1, e2 to event
  var t1 = Geom.edgeEval(e1.dst(), event, e1.org);
  var t2 = Geom.edgeEval(e2.dst(), event, e2.org);
  return (t1 >= t2);
};

/**
 * [deleteRegion_ description]
 * private
 * param {GluTesselator} tess [description].
 * param {ActiveRegion} reg [description].
 */
static public function deleteRegion_(tess:GluTesselator, reg:ActiveRegion) {
  if (reg.fixUpperEdge) {
    // It was created with zero winding number, so it better be
    // deleted with zero winding number (ie. it better not get merged
    // with a real edge).
    Utils.assert(reg.eUp.winding == 0);
  }

  reg.eUp.activeRegion = null;

  tess.dict.deleteNode(reg.nodeUp);
  reg.nodeUp = null;

  // memFree( reg ); TODO(bckenny)
  // TODO(bckenny): may need to null at callsite
};

/**
 * Replace an upper edge which needs fixing (see connectRightVertex).
 * @private
 * param {ActiveRegion} reg [description].
 * @param {GluHalfEdge} newEdge [description].
 */
static public function fixUpperEdge_(reg:ActiveRegion, newEdge:GluHalfEdge) {
  Utils.assert(reg.fixUpperEdge);
  Mesh.deleteEdge(reg.eUp);

  reg.fixUpperEdge = false;
  reg.eUp = newEdge;
  newEdge.activeRegion = reg;
};


/**
 * Find the region above the uppermost edge with the same origin.
 * @private
 * param {ActiveRegion} reg [description].
 * return {ActiveRegion} [description].
 */
static public function topLeftRegion_(reg:ActiveRegion):ActiveRegion {
  var org = reg.eUp.org;

  // Find the region above the uppermost edge with the same origin
  do {
    reg = reg.regionAbove();
  } while (reg.eUp.org == org);

  // If the edge above was a temporary edge introduced by connectRightVertex,
  // now is the time to fix it.
  if (reg.fixUpperEdge) {
    var e = Mesh.connect(reg.regionBelow().eUp.sym, reg.eUp.lNext);
    Sweep.fixUpperEdge_(reg, e);
    reg = reg.regionAbove();
  }

  return reg;
};

/**
 * Find the region above the uppermost edge with the same destination.
 * @private
 * param {ActiveRegion} reg [description].
 * return {ActiveRegion} [description].
 */
static public function topRightRegion_(reg:ActiveRegion):ActiveRegion {
  var dst = reg.eUp.dst();

  do {
    reg = reg.regionAbove();
  } while (reg.eUp.dst() == dst);

  return reg;
};
/**
 * Add a new active region to the Sweep line, *somewhere* below "regAbove"
 * (according to where the new edge belongs in the Sweep-line dictionary).
 * The upper edge of the new region will be "eNewUp".
 * Winding number and "inside" flag are not updated.
 *
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} regAbove [description].
 * @param {GluHalfEdge} eNewUp [description].
 * return {ActiveRegion} regNew.
 */
static public function  addRegionBelow_(tess:GluTesselator, regAbove:ActiveRegion, eNewUp:GluHalfEdge):ActiveRegion {
  var regNew = new ActiveRegion();

  regNew.eUp = eNewUp;
  regNew.nodeUp = tess.dict.insertBefore(regAbove.nodeUp, regNew);
  eNewUp.activeRegion = regNew;

  return regNew;
};

/**
 * [computeWinding_ description]
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} reg [description].
 */
static public function computeWinding_(tess:GluTesselator, reg:ActiveRegion) {
  reg.windingNumber = reg.regionAbove().windingNumber + reg.eUp.winding;
  reg.inside = Sweep.isWindingInside_(tess, reg.windingNumber);
};

/**
 * [isWindingInside_ description]
 * @private
 * @param {GluTesselator} tess [description].
 * @param {number} n int.
 * @return {boolean} [description].
 */
static public function isWindingInside_(tess:GluTesselator, n:Int):Bool {
  switch (tess.windingRule) {
    case WindingRule.GLU_TESS_WINDING_ODD:
      return ((n & 1) != 0);
    case WindingRule.GLU_TESS_WINDING_NONZERO:
      return (n != 0);
    case WindingRule.GLU_TESS_WINDING_POSITIVE:
      return (n > 0);
    case WindingRule.GLU_TESS_WINDING_NEGATIVE:
      return (n < 0);
    case WindingRule.GLU_TESS_WINDING_ABS_GEQ_TWO:
      return (n >= 2) || (n <= -2);
  }

  // TODO(bckenny): not reached
  Utils.assert(false);
  return false;
};


/**
 * Delete a region from the Sweep line. This happens when the upper
 * and lower chains of a region meet (at a vertex on the Sweep line).
 * The "inside" flag is copied to the appropriate mesh face (we could
 * not do this before -- since the structure of the mesh is always
 * changing, this face may not have even existed until now).
 *
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} reg [description].
 */
static public function finishRegion_(tess:GluTesselator, reg:ActiveRegion) {
  // TODO(bckenny): may need to null reg at callsite

  var e = reg.eUp;
  var f = e.lFace;

  f.inside = reg.inside;
  f.anEdge = e;   // optimization for tessmono.tessellateMonoRegion() // TODO(bckenny): how so?
  Sweep.deleteRegion_(tess, reg);
};

/**
 * We are given a vertex with one or more left-going edges. All affected
 * edges should be in the edge dictionary. Starting at regFirst.eUp,
 * we walk down deleting all regions where both edges have the same
 * origin vOrg. At the same time we copy the "inside" flag from the
 * active region to the face, since at this point each face will belong
 * to at most one region (this was not necessarily true until this point
 * in the Sweep). The walk stops at the region above regLast; if regLast
 * is null we walk as far as possible. At the same time we relink the
 * mesh if necessary, so that the ordering of edges around vOrg is the
 * same as in the dictionary.
 *
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} regFirst [description].
 * param {ActiveRegion} regLast [description].
 * @return {GluHalfEdge} [description].
 */
static  public function finishLeftRegions_(tess:GluTesselator, regFirst:ActiveRegion, regLast:ActiveRegion):GluHalfEdge {
  var regPrev = regFirst;
  var ePrev = regFirst.eUp;
  while (regPrev != regLast) {
    // placement was OK
    regPrev.fixUpperEdge = false;
    var reg = regPrev.regionBelow();
    var e = reg.eUp;
    if (e.org != ePrev.org) {
      if (!reg.fixUpperEdge) {
        /* Remove the last left-going edge. Even though there are no further
         * edges in the dictionary with this origin, there may be further
         * such edges in the mesh (if we are adding left edges to a vertex
         * that has already been processed). Thus it is important to call
         * finishRegion rather than just deleteRegion.
         */
        Sweep.finishRegion_(tess, regPrev);
        break;
      }

      // If the edge below was a temporary edge introduced by
      // connectRightVertex, now is the time to fix it.
      e = Mesh.connect(ePrev.lPrev(), e.sym);
      Sweep.fixUpperEdge_(reg, e);
    }

    // Relink edges so that ePrev.oNext == e
    if (ePrev.oNext != e) {
      Mesh.meshSplice(e.oPrev(), e);
      Mesh.meshSplice(ePrev, e);
    }

    // may change reg.eUp
    Sweep.finishRegion_(tess, regPrev);
    ePrev = reg.eUp;
    regPrev = reg;
  }

  return ePrev;
};

/**
 * Purpose: insert right-going edges into the edge dictionary, and update
 * winding numbers and mesh connectivity appropriately. All right-going
 * edges share a common origin vOrg. Edges are inserted CCW starting at
 * eFirst; the last edge inserted is eLast.oPrev. If vOrg has any
 * left-going edges already processed, then eTopLeft must be the edge
 * such that an imaginary upward vertical segment from vOrg would be
 * contained between eTopLeft.oPrev and eTopLeft; otherwise eTopLeft
 * should be null.
 *
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} regUp [description].
 * @param {GluHalfEdge} eFirst [description].
 * @param {GluHalfEdge} eLast [description].
 * @param {GluHalfEdge} eTopLeft [description].
 * @param {boolean} cleanUp [description].
 */
static  public function addRightEdges_(tess:GluTesselator, regUp:ActiveRegion, eFirst:GluHalfEdge, eLast:GluHalfEdge, eTopLeft:GluHalfEdge,
  cleanUp:Bool) {

var firstTime = true;

// Insert the new right-going edges in the dictionary
var e = eFirst;
do {
  Utils.assert(Geom.vertLeq(e.org, e.dst()));
  Sweep.addRegionBelow_(tess, regUp, e.sym);
  e = e.oNext;
} while (e != eLast);

// Walk *all* right-going edges from e.org, in the dictionary order,
// updating the winding numbers of each region, and re-linking the mesh
// edges to match the dictionary ordering (if necessary).
if (eTopLeft == null) {
  eTopLeft = regUp.regionBelow().eUp.rPrev();
}
var regPrev = regUp;
var ePrev = eTopLeft;
var reg = regPrev.regionBelow();
while (true) {
  reg = regPrev.regionBelow();
  e = reg.eUp.sym;
  if (e.org != ePrev.org) {
    break;
  }

  if (e.oNext != ePrev) {
    // Unlink e from its current position, and relink below ePrev
    Mesh.meshSplice(e.oPrev(), e);
    Mesh.meshSplice(ePrev.oPrev(), e);
  }
  // Compute the winding number and "inside" flag for the new regions
  reg.windingNumber = regPrev.windingNumber - e.winding;
  reg.inside = Sweep.isWindingInside_(tess, reg.windingNumber);

  // Check for two outgoing edges with same slope -- process these
  // before any intersection tests (see example in Sweep.computeInterior).
  regPrev.dirty = true;
  if (!firstTime && Sweep.checkForRightSplice_(tess, regPrev)) {
    Sweep.addWinding_(e, ePrev);
    Sweep.deleteRegion_(tess, regPrev); // TODO(bckenny): need to null regPrev anywhere else?
    Mesh.deleteEdge(ePrev);
  }
  firstTime = false;
  regPrev = reg;
  ePrev = e;
}

regPrev.dirty = true;
Utils.assert(regPrev.windingNumber - e.winding == reg.windingNumber);

if (cleanUp) {
  // Check for intersections between newly adjacent edges.
  Sweep.walkDirtyRegions_(tess, regPrev);
}
};

/**
 * Set up data for and call GLU_TESS_COMBINE callback on GluTesselator.
 * @private
 * @param {!GluTesselator} tess
 * @param {!GluVertex} isect A raw vertex at the intersection.
 * @param {!Array<Object>} data The vertices of the intersecting edges.
 * @param {!Array<number>} weights The linear combination coefficients for this intersection.
 * @param {boolean} needed Whether a returned vertex is necessary in this case.
 */
static  public function callCombine_(tess:GluTesselator, isect:GluVertex, data:Array<Any>, weights:Array<Float>, needed:Bool) {
  // Copy coord data in case the callback changes it.
  var coords = [
    isect.coords[0],
    isect.coords[1],
    isect.coords[2]
  ];

  isect.data = null;
  isect.data = tess.callCombineCallback(coords, data, weights);
  if (isect.data == null) {
    if (!needed) {
      // not needed, so just use data from first vertex
      isect.data = data[0];

    } else if (!tess.fatalError) {
      // The only way fatal error is when two edges are found to intersect,
      // but the user has not provided the callback necessary to handle
      // generated intersection points.
      tess.callErrorCallback(ErrorType.GLU_TESS_NEED_COMBINE_CALLBACK);
      tess.fatalError = true;
    }
  }
};

/**
 * Two vertices with idential coordinates are combined into one.
 * e1.org is kept, while e2.org is discarded.
 * @private
 * @param {!GluTesselator} tess
 * @param {GluHalfEdge} e1 [description].
 * @param {GluHalfEdge} e2 [description].
 */
static  public function spliceMergeVertices_(tess:GluTesselator, e1:GluHalfEdge, e2:GluHalfEdge) {
  // TODO(bckenny): better way to init these? save them?
  var data:Array<Any> = [null, null, null, null];
  var weights = [0.5, 0.5, 0, 0];

  data[0] = e1.org.data;
  data[1] = e2.org.data;
  Sweep.callCombine_(tess, e1.org, data, weights, false);
  Mesh.meshSplice(e1, e2);
};


/**
 * Find some weights which describe how the intersection vertex is
 * a linear combination of org and dst. Each of the two edges
 * which generated "isect" is allocated 50% of the weight; each edge
 * splits the weight between its org and dst according to the
 * relative distance to "isect".
 *
 * @private
 * @param {GluVertex} isect [description].
 * @param {GluVertex} org [description].
 * @param {GluVertex} dst [description].
 * @param {Array.<number>} weights [description].
 * @param {number} weightIndex Index into weights for first weight to supply.
 */
static  public function vertexWeights_(isect:GluVertex, org:GluVertex, dst:GluVertex, weights:Array<Float>, weightIndex:Int) {
  // TODO(bckenny): think through how we can use L1dist here and be correct for coords
  var t1 = Geom.vertL1dist(org, isect);
  var t2 = Geom.vertL1dist(dst, isect);

  // TODO(bckenny): introduced weightIndex to mimic addressing in original
  // 1) document (though it is private and only used from getIntersectData)
  // 2) better way? manually inline into getIntersectData? supply two two-length tmp arrays?
  var i0 = weightIndex;
  var i1 = weightIndex + 1;
  weights[i0] = 0.5 * t2 / (t1 + t2);
  weights[i1] = 0.5 * t1 / (t1 + t2);
  isect.coords[0] += weights[i0] * org.coords[0] + weights[i1] * dst.coords[0];
  isect.coords[1] += weights[i0] * org.coords[1] + weights[i1] * dst.coords[1];
  isect.coords[2] += weights[i0] * org.coords[2] + weights[i1] * dst.coords[2];
};


/**
 * We've computed a new intersection point, now we need a "data" pointer
 * from the user so that we can refer to this new vertex in the
 * rendering callbacks.
 * @private
 * @param {!GluTesselator} tess
 * @param {GluVertex} isect [description].
 * @param {GluVertex} orgUp [description].
 * @param {GluVertex} dstUp [description].
 * @param {GluVertex} orgLo [description].
 * @param {GluVertex} dstLo [description].
 */
static  public function getIntersectData_(tess:GluTesselator, isect:GluVertex, orgUp:GluVertex, dstUp:GluVertex, orgLo:GluVertex,
    dstLo:GluVertex) {

  // TODO(bckenny): called for every intersection event, should these be from a pool?
  // TODO(bckenny): better way to init these?
  var weights = [0.0, 0.0, 0.0, 0.0];
  var data = [
    orgUp.data,
    dstUp.data,
    orgLo.data,
    dstLo.data
  ];

  // TODO(bckenny): it appears isect is a reappropriated vertex, so does need to be zeroed.
  // double check this.
  isect.coords[0] = isect.coords[1] = isect.coords[2] = 0;

  // TODO(bckenny): see note in Sweep.vertexWeights_ for explanation of weightIndex. fix?
  Sweep.vertexWeights_(isect, orgUp, dstUp, weights, 0);
  Sweep.vertexWeights_(isect, orgLo, dstLo, weights, 2);

  Sweep.callCombine_(tess, isect, data, weights, true);
};


/**
 * Check the upper and lower edge of regUp, to make sure that the
 * eUp.org is above eLo, or eLo.org is below eUp (depending on which
 * origin is leftmost).
 *
 * The main purpose is to splice right-going edges with the same
 * dest vertex and nearly identical slopes (ie. we can't distinguish
 * the slopes numerically). However the splicing can also help us
 * to recover from numerical errors. For example, suppose at one
 * point we checked eUp and eLo, and decided that eUp.org is barely
 * above eLo. Then later, we split eLo into two edges (eg. from
 * a splice operation like this one). This can change the result of
 * our test so that now eUp.org is incident to eLo, or barely below it.
 * We must correct this condition to maintain the dictionary invariants.
 *
 * One possibility is to check these edges for intersection again
 * (i.e. checkForIntersect). This is what we do if possible. However
 * checkForIntersect requires that tess.event lies between eUp and eLo,
 * so that it has something to fall back on when the intersection
 * calculation gives us an unusable answer. So, for those cases where
 * we can't check for intersection, this routine fixes the problem
 * by just splicing the offending vertex into the other edge.
 * This is a guaranteed solution, no matter how degenerate things get.
 * Basically this is a combinatorial solution to a numerical problem.
 *
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} regUp [description].
 * @return {boolean} [description].
 */
static  public function checkForRightSplice_(tess:GluTesselator, regUp:ActiveRegion):Bool {
  // TODO(bckenny): fully learn how these two checks work

  var regLo = regUp.regionBelow();
  var eUp = regUp.eUp;
  var eLo = regLo.eUp;

  if (Geom.vertLeq(eUp.org, eLo.org)) {
    if (Geom.edgeSign(eLo.dst(), eUp.org, eLo.org) > 0) {
      return false;
    }

    // eUp.org appears to be below eLo
    if (!Geom.vertEq(eUp.org, eLo.org)) {
      // Splice eUp.org into eLo
      Mesh.splitEdge(eLo.sym);
      Mesh.meshSplice(eUp, eLo.oPrev());
      regUp.dirty = regLo.dirty = true;

    } else if (eUp.org != eLo.org) {
      // merge the two vertices, discarding eUp.org
      tess.pq.remove(eUp.org.pqHandle);
      Sweep.spliceMergeVertices_(tess, eLo.oPrev(), eUp);
    }

  } else {
    if (Geom.edgeSign(eUp.dst(), eLo.org, eUp.org) < 0) {
      return false;
    }

    // eLo.org appears to be above eUp, so splice eLo.org into eUp
    regUp.regionAbove().dirty = regUp.dirty = true;
    Mesh.splitEdge(eUp.sym);
    Mesh.meshSplice(eLo.oPrev(), eUp);
  }

  return true;
};


/**
 * Check the upper and lower edge of regUp to make sure that the
 * eUp.dst() is above eLo, or eLo.dst() is below eUp (depending on which
 * destination is rightmost).
 *
 * Theoretically, this should always be true. However, splitting an edge
 * into two pieces can change the results of previous tests. For example,
 * suppose at one point we checked eUp and eLo, and decided that eUp.dst()
 * is barely above eLo. Then later, we split eLo into two edges (eg. from
 * a splice operation like this one). This can change the result of
 * the test so that now eUp.dst() is incident to eLo, or barely below it.
 * We must correct this condition to maintain the dictionary invariants
 * (otherwise new edges might get inserted in the wrong place in the
 * dictionary, and bad stuff will happen).
 *
 * We fix the problem by just splicing the offending vertex into the
 * other edge.
 *
 * @private
 * @param {GluTesselator} tess description].
 * param {ActiveRegion} regUp [description].
 * @return {boolean} [description].
 */
static  public function checkForLeftSplice_(tess:GluTesselator, regUp:ActiveRegion):Bool {
  var regLo = regUp.regionBelow();
  var eUp = regUp.eUp;
  var eLo = regLo.eUp;
  var e;

  Utils.assert(!Geom.vertEq(eUp.dst(), eLo.dst()));

  if (Geom.vertLeq(eUp.dst(), eLo.dst())) {
    if (Geom.edgeSign(eUp.dst(), eLo.dst(), eUp.org) < 0) {
      return false;
    }

    // eLo.dst() is above eUp, so splice eLo.dst() into eUp
    regUp.regionAbove().dirty = regUp.dirty = true;
    e = Mesh.splitEdge(eUp);
    Mesh.meshSplice(eLo.sym, e);
    e.lFace.inside = regUp.inside;

  } else {
    if (Geom.edgeSign(eLo.dst(), eUp.dst(), eLo.org) > 0) {
      return false;
    }

    // eUp.dst() is below eLo, so splice eUp.dst() into eLo
    regUp.dirty = regLo.dirty = true;
    e = Mesh.splitEdge(eLo);
    Mesh.meshSplice(eUp.lNext, eLo.sym);
    e.rFace().inside = regUp.inside;
  }

  return true;
};


/**
 * Check the upper and lower edges of the given region to see if
 * they intersect. If so, create the intersection and add it
 * to the data structures.
 *
 * Returns true if adding the new intersection resulted in a recursive
 * call to addRightEdges_(); in this case all "dirty" regions have been
 * checked for intersections, and possibly regUp has been deleted.
 *
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} regUp [description].
 * @return {boolean} [description].
 */
static public function checkForIntersect_(tess:GluTesselator, regUp:ActiveRegion):Bool {
  var regLo = regUp.regionBelow();
  var eUp = regUp.eUp;
  var eLo = regLo.eUp;
  var orgUp = eUp.org;
  var orgLo = eLo.org;
  var dstUp = eUp.dst();
  var dstLo = eLo.dst();

  var isect = new GluVertex();

  Utils.assert(!Geom.vertEq(dstLo, dstUp));
  Utils.assert(Geom.edgeSign(dstUp, tess.event, orgUp) <= 0);
  Utils.assert(Geom.edgeSign(dstLo, tess.event, orgLo) >= 0);
  Utils.assert(orgUp != tess.event && orgLo != tess.event);
  Utils.assert(!regUp.fixUpperEdge && !regLo.fixUpperEdge);

  if (orgUp == orgLo) {
    // right endpoints are the same
    return false;
  }

  var tMinUp = Math.min(orgUp.t, dstUp.t);
  var tMaxLo = Math.max(orgLo.t, dstLo.t);
  if (tMinUp > tMaxLo) {
    // t ranges do not overlap
    return false;
  }

  if (Geom.vertLeq(orgUp, orgLo)) {
    if (Geom.edgeSign(dstLo, orgUp, orgLo) > 0) {
      return false;
    }
  } else {
    if (Geom.edgeSign(dstUp, orgLo, orgUp) < 0) {
      return false;
    }
  }

  // At this point the edges intersect, at least marginally
  Geom.edgeIntersect(dstUp, orgUp, dstLo, orgLo, isect);

  // The following properties are guaranteed:
  Utils.assert(Math.min(orgUp.t, dstUp.t) <= isect.t);
  Utils.assert(isect.t <= Math.max(orgLo.t, dstLo.t));
  Utils.assert(Math.min(dstLo.s, dstUp.s) <= isect.s);
  Utils.assert(isect.s <= Math.max(orgLo.s, orgUp.s));

  if (Geom.vertLeq(isect, tess.event)) {
    /* The intersection point lies slightly to the left of the Sweep line,
     * so move it until it's slightly to the right of the Sweep line.
     * (If we had perfect numerical precision, this would never happen
     * in the first place). The easiest and safest thing to do is
     * replace the intersection by tess.event.
     */
    isect.s = tess.event.s;
    isect.t = tess.event.t;
  }

  // TODO(bckenny): try to find test54.d
  /* Similarly, if the computed intersection lies to the right of the
   * rightmost origin (which should rarely happen), it can cause
   * unbelievable inefficiency on sufficiently degenerate inputs.
   * (If you have the test program, try running test54.d with the
   * "X zoom" option turned on).
   */
  var orgMin = Geom.vertLeq(orgUp, orgLo) ? orgUp : orgLo;
  if (Geom.vertLeq(orgMin, isect)) {
    isect.s = orgMin.s;
    isect.t = orgMin.t;
  }

  if (Geom.vertEq(isect, orgUp) || Geom.vertEq(isect, orgLo)) {
    // Easy case -- intersection at one of the right endpoints
    Sweep.checkForRightSplice_(tess, regUp);
    return false;
  }

  // TODO(bckenny): clean this up; length is distracting
  if ((!Geom.vertEq(dstUp, tess.event) &&
      Geom.edgeSign(dstUp, tess.event, isect) >= 0) ||
      (!Geom.vertEq(dstLo, tess.event) &&
      Geom.edgeSign(dstLo, tess.event, isect) <= 0)) {

    /* Very unusual -- the new upper or lower edge would pass on the
     * wrong side of the Sweep event, or through it. This can happen
     * due to very small numerical errors in the intersection calculation.
     */
    if (dstLo == tess.event) {
      // Splice dstLo into eUp, and process the new region(s)
      Mesh.splitEdge(eUp.sym);
      Mesh.meshSplice(eLo.sym, eUp);
      regUp = Sweep.topLeftRegion_(regUp);
      eUp = regUp.regionBelow().eUp;
      Sweep.finishLeftRegions_(tess, regUp.regionBelow(), regLo);
      Sweep.addRightEdges_(tess, regUp, eUp.oPrev(), eUp, eUp, true);
      return true;
    }

    if (dstUp == tess.event) {
      // Splice dstUp into eLo, and process the new region(s)
      Mesh.splitEdge(eLo.sym);
      Mesh.meshSplice(eUp.lNext, eLo.oPrev());
      regLo = regUp;
      regUp = Sweep.topRightRegion_(regUp);
      var e = regUp.regionBelow().eUp.rPrev();
      regLo.eUp = eLo.oPrev();
      eLo = Sweep.finishLeftRegions_(tess, regLo, null);
      Sweep.addRightEdges_(tess, regUp, eLo.oNext, eUp.rPrev(), e,
          true);
      return true;
    }

    /* Special case: called from connectRightVertex. If either
     * edge passes on the wrong side of tess.event, split it
     * (and wait for connectRightVertex to splice it appropriately).
     */
    if (Geom.edgeSign(dstUp, tess.event, isect) >= 0) {
      regUp.regionAbove().dirty = regUp.dirty = true;
      Mesh.splitEdge(eUp.sym);
      eUp.org.s = tess.event.s;
      eUp.org.t = tess.event.t;
    }

    if (Geom.edgeSign(dstLo, tess.event, isect) <= 0) {
      regUp.dirty = regLo.dirty = true;
      Mesh.splitEdge(eLo.sym);
      eLo.org.s = tess.event.s;
      eLo.org.t = tess.event.t;
    }

    // leave the rest for connectRightVertex
    return false;
  }

  /* General case -- split both edges, splice into new vertex.
   * When we do the splice operation, the order of the arguments is
   * arbitrary as far as correctness goes. However, when the operation
   * creates a new face, the work done is proportional to the size of
   * the new face. We expect the faces in the processed part of
   * the mesh (ie. eUp.lFace) to be smaller than the faces in the
   * unprocessed original contours (which will be eLo.oPrev.lFace).
   */
  Mesh.splitEdge(eUp.sym);
  Mesh.splitEdge(eLo.sym);
  Mesh.meshSplice(eLo.oPrev(), eUp);
  eUp.org.s = isect.s;
  eUp.org.t = isect.t;
  eUp.org.pqHandle = tess.pq.insert(eUp.org);
  Sweep.getIntersectData_(tess, eUp.org, orgUp, dstUp, orgLo, dstLo);
  regUp.regionAbove().dirty = regUp.dirty = regLo.dirty = true;

  return false;
};


/**
 * When the upper or lower edge of any region changes, the region is
 * marked "dirty". This routine walks through all the dirty regions
 * and makes sure that the dictionary invariants are satisfied
 * (see the comments at the beginning of this file). Of course,
 * new dirty regions can be created as we make changes to restore
 * the invariants.
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} regUp [description].
 */
static  public function walkDirtyRegions_(tess:GluTesselator, regUp:ActiveRegion) {
  var regLo = regUp.regionBelow();

  while (true) {
    // Find the lowest dirty region (we walk from the bottom up).
    while (regLo.dirty) {
      regUp = regLo;
      regLo = regLo.regionBelow();
    }
    if (!regUp.dirty) {
      regLo = regUp;
      regUp = regUp.regionAbove();
      if (regUp == null || !regUp.dirty) {
        // We've walked all the dirty regions
        return;
      }
    }

    regUp.dirty = false;
    var eUp = regUp.eUp;
    var eLo = regLo.eUp;

    if (eUp.dst() != eLo.dst()) {
      // Check that the edge ordering is obeyed at the dst vertices.
      if (Sweep.checkForLeftSplice_(tess, regUp)) {
        // If the upper or lower edge was marked fixUpperEdge, then
        // we no longer need it (since these edges are needed only for
        // vertices which otherwise have no right-going edges).
        if (regLo.fixUpperEdge) {
          Sweep.deleteRegion_(tess, regLo);
          Mesh.deleteEdge(eLo);
          regLo = regUp.regionBelow();
          eLo = regLo.eUp;

        } else if (regUp.fixUpperEdge) {
          Sweep.deleteRegion_(tess, regUp);
          Mesh.deleteEdge(eUp);
          regUp = regLo.regionAbove();
          eUp = regUp.eUp;
        }
      }
    }

    if (eUp.org != eLo.org) {
      if (eUp.dst() != eLo.dst() && !regUp.fixUpperEdge &&
          !regLo.fixUpperEdge &&
          (eUp.dst() == tess.event || eLo.dst() == tess.event)) {
        /* When all else fails in checkForIntersect(), it uses tess.event
         * as the intersection location. To make this possible, it requires
         * that tess.event lie between the upper and lower edges, and also
         * that neither of these is marked fixUpperEdge (since in the worst
         * case it might splice one of these edges into tess.event, and
         * violate the invariant that fixable edges are the only right-going
         * edge from their associated vertex).
         */
        if (Sweep.checkForIntersect_(tess, regUp)) {
          // walkDirtyRegions() was called recursively; we're done
          return;
        }

      } else {
        // Even though we can't use checkForIntersect(), the org vertices
        // may violate the dictionary edge ordering. Check and correct this.
        Sweep.checkForRightSplice_(tess, regUp);
      }
    }

    if (eUp.org == eLo.org && eUp.dst() == eLo.dst()) {
      // A degenerate loop consisting of only two edges -- delete it.
      Sweep.addWinding_(eLo, eUp);
      Sweep.deleteRegion_(tess, regUp);
      Mesh.deleteEdge(eUp);
      regUp = regLo.regionAbove();
    }
  }
};


/**
 * Purpose: connect a "right" vertex vEvent (one where all edges go left)
 * to the unprocessed portion of the mesh. Since there are no right-going
 * edges, two regions (one above vEvent and one below) are being merged
 * into one. regUp is the upper of these two regions.
 *
 * There are two reasons for doing this (adding a right-going edge):
 *  - if the two regions being merged are "inside", we must add an edge
 *    to keep them separated (the combined region would not be monotone).
 *  - in any case, we must leave some record of vEvent in the dictionary,
 *    so that we can merge vEvent with features that we have not seen yet.
 *    For example, maybe there is a vertical edge which passes just to
 *    the right of vEvent; we would like to splice vEvent into this edge.
 *
 * However, we don't want to connect vEvent to just any vertex. We don't
 * want the new edge to cross any other edges; otherwise we will create
 * intersection vertices even when the input data had no self-intersections.
 * (This is a bad thing; if the user's input data has no intersections,
 * we don't want to generate any false intersections ourselves.)
 *
 * Our eventual goal is to connect vEvent to the leftmost unprocessed
 * vertex of the combined region (the union of regUp and regLo).
 * But because of unseen vertices with all right-going edges, and also
 * new vertices which may be created by edge intersections, we don't
 * know where that leftmost unprocessed vertex is. In the meantime, we
 * connect vEvent to the closest vertex of either chain, and mark the region
 * as "fixUpperEdge". This flag says to delete and reconnect this edge
 * to the next processed vertex on the boundary of the combined region.
 * Quite possibly the vertex we connected to will turn out to be the
 * closest one, in which case we won't need to make any changes.
 *
 * @private
 * @param {GluTesselator} tess [description].
 * param {ActiveRegion} regUp [description].
 * @param {GluHalfEdge} eBottomLeft [description].
 */
static  public function connectRightVertex_(tess:GluTesselator, regUp:ActiveRegion, eBottomLeft:GluHalfEdge) {
  var eTopLeft = eBottomLeft.oNext;
  var regLo = regUp.regionBelow();
  var eUp = regUp.eUp;
  var eLo = regLo.eUp;
  var degenerate = false;

  if (eUp.dst() != eLo.dst()) {
    Sweep.checkForIntersect_(tess, regUp);
  }

  // Possible new degeneracies: upper or lower edge of regUp may pass
  // through vEvent, or may coincide with new intersection vertex
  if (Geom.vertEq(eUp.org, tess.event)) {
    Mesh.meshSplice(eTopLeft.oPrev(), eUp);
    regUp = Sweep.topLeftRegion_(regUp);
    eTopLeft = regUp.regionBelow().eUp;
    Sweep.finishLeftRegions_(tess, regUp.regionBelow(), regLo);
    degenerate = true;
  }
  if (Geom.vertEq(eLo.org, tess.event)) {
    Mesh.meshSplice(eBottomLeft, eLo.oPrev());
    eBottomLeft = Sweep.finishLeftRegions_(tess, regLo, null);
    degenerate = true;
  }
  if (degenerate) {
    Sweep.addRightEdges_(tess, regUp, eBottomLeft.oNext, eTopLeft,
        eTopLeft, true);
    return;
  }

  // Non-degenerate situation -- need to add a temporary, fixable edge.
  // Connect to the closer of eLo.org, eUp.org.
  var eNew;
  if (Geom.vertLeq(eLo.org, eUp.org)) {
    eNew = eLo.oPrev();
  } else {
    eNew = eUp;
  }
  eNew = Mesh.connect(eBottomLeft.lPrev(), eNew);

  // Prevent cleanup, otherwise eNew might disappear before we've even
  // had a chance to mark it as a temporary edge.
  Sweep.addRightEdges_(tess, regUp, eNew, eNew.oNext, eNew.oNext,
      false);
  eNew.sym.activeRegion.fixUpperEdge = true;
  Sweep.walkDirtyRegions_(tess, regUp);
};


/**
 * The event vertex lies exacty on an already-processed edge or vertex.
 * Adding the new vertex involves splicing it into the already-processed
 * part of the mesh.
 * @private
 * @param {!GluTesselator} tess
 * param {ActiveRegion} regUp [description].
 * @param {GluVertex} vEvent [description].
 */
static public function connectLeftDegenerate_(tess:GluTesselator, regUp:ActiveRegion, vEvent:GluVertex) {
  var e = regUp.eUp;
  /* istanbul ignore if */
  if (Geom.vertEq(e.org, vEvent)) {
    // NOTE(bckenny): this code is unreachable but remains for a hypothetical
    // future extension of  See docs on Sweep.TOLERANCE_NONZERO_
    // for more information. Conditional on TOLERANCE_NONZERO_ to help Closure
    // Compiler eliminate dead code.
    // e.org is an unprocessed vertex - just combine them, and wait
    // for e.org to be pulled from the queue
    Utils.assert(Sweep.TOLERANCE_NONZERO_);
    if (Sweep.TOLERANCE_NONZERO_) {
      Sweep.spliceMergeVertices_(tess, e, vEvent.anEdge);
    }
    return;
  }

  if (!Geom.vertEq(e.dst(), vEvent)) {
    // General case -- splice vEvent into edge e which passes through it
    Mesh.splitEdge(e.sym);

    if (regUp.fixUpperEdge) {
      // This edge was fixable -- delete unused portion of original edge
      Mesh.deleteEdge(e.oNext);
      regUp.fixUpperEdge = false;
    }

    Mesh.meshSplice(vEvent.anEdge, e);

    // recurse
    Sweep.SweepEvent_(tess, vEvent);
    return;
  }

  // NOTE(bckenny): this code is unreachable but remains for a hypothetical
  // future extension of  See docs on Sweep.TOLERANCE_NONZERO_
  // for more information. Conditional on TOLERANCE_NONZERO_ to help Closure
  // Compiler eliminate dead code.
  // vEvent coincides with e.dst(), which has already been processed.
  // Splice in the additional right-going edges.
  /* istanbul ignore next */
  Utils.assert(Sweep.TOLERANCE_NONZERO_);

  /* istanbul ignore next */
  if (Sweep.TOLERANCE_NONZERO_) {
    regUp = Sweep.topRightRegion_(regUp);
    var reg = regUp.regionBelow();
    var eTopRight = reg.eUp.sym;
    var eTopLeft = eTopRight.oNext;
    var eLast = eTopLeft;

    if (reg.fixUpperEdge) {
      // Here e.dst() has only a single fixable edge going right.
      // We can delete it since now we have some real right-going edges.

      // there are some left edges too
      Utils.assert(eTopLeft != eTopRight);
      Sweep.deleteRegion_(tess, reg); // TODO(bckenny): something to null?
      Mesh.deleteEdge(eTopRight);
      eTopRight = eTopLeft.oPrev();
    }

    Mesh.meshSplice(vEvent.anEdge, eTopRight);
    if (!Geom.edgeGoesLeft(eTopLeft)) {
      // e.dst() had no left-going edges -- indicate this to addRightEdges()
      eTopLeft = null;
    }

    Sweep.addRightEdges_(tess, regUp, eTopRight.oNext, eLast, eTopLeft,
        true);
  }
};


/**
 * Connect a "left" vertex (one where both edges go right)
 * to the processed portion of the mesh. Let R be the active region
 * containing vEvent, and let U and L be the upper and lower edge
 * chains of R. There are two possibilities:
 *
 * - the normal case: split R into two regions, by connecting vEvent to
 *   the rightmost vertex of U or L lying to the left of the Sweep line
 *
 * - the degenerate case: if vEvent is close enough to U or L, we
 *   merge vEvent into that edge chain. The subcases are:
 *  - merging with the rightmost vertex of U or L
 *  - merging with the active edge of U or L
 *  - merging with an already-processed portion of U or L
 *
 * @private
 * @param {GluTesselator} tess   [description].
 * @param {GluVertex} vEvent [description].
 */
static  public function connectLeftVertex_(tess:GluTesselator, vEvent:GluVertex) {
  // TODO(bckenny): tmp only used for Sweep. better to keep tmp across calls?
  var tmp = new ActiveRegion();

  // NOTE(bckenny): this was commented out in the original
  // assert(vEvent.anEdge.oNext.oNext == vEvent.anEdge);

  // Get a pointer to the active region containing vEvent
  tmp.eUp = vEvent.anEdge.sym;
  var regUp = tess.dict.search(tmp).getKey();
  var regLo = regUp.regionBelow();
  var eUp = regUp.eUp;
  var eLo = regLo.eUp;

  // try merging with U or L first
  if (Geom.edgeSign(eUp.dst(), vEvent, eUp.org) == 0) {
    Sweep.connectLeftDegenerate_(tess, regUp, vEvent);
    return;
  }

  // Connect vEvent to rightmost processed vertex of either chain.
  // e.dst() is the vertex that we will connect to vEvent.
  var reg = Geom.vertLeq(eLo.dst(), eUp.dst()) ? regUp : regLo;
  var eNew;
  if (regUp.inside || reg.fixUpperEdge) {
    if (reg == regUp) {
      eNew = Mesh.connect(vEvent.anEdge.sym, eUp.lNext);

    } else {
      var tempHalfEdge = Mesh.connect(eLo.dNext(), vEvent.anEdge);
      eNew = tempHalfEdge.sym;
    }

    if (reg.fixUpperEdge) {
      Sweep.fixUpperEdge_(reg, eNew);

    } else {
      Sweep.computeWinding_(tess,
          Sweep.addRegionBelow_(tess, regUp, eNew));
    }
    Sweep.SweepEvent_(tess, vEvent);

  } else {
    // The new vertex is in a region which does not belong to the polygon.
    // We don''t need to connect this vertex to the rest of the mesh.
    Sweep.addRightEdges_(tess, regUp, vEvent.anEdge, vEvent.anEdge,
        null, true);
  }
};


/**
 * Does everything necessary when the Sweep line crosses a vertex.
 * Updates the mesh and the edge dictionary.
 * @private
 * @param {GluTesselator} tess [description].
 * @param {GluVertex} vEvent [description].
 */
static public function SweepEvent_(tess:GluTesselator, vEvent:GluVertex) {
  tess.event = vEvent; // for access in edgeLeq_ // TODO(bckenny): wuh?

  /* Check if this vertex is the right endpoint of an edge that is
   * already in the dictionary.  In this case we don't need to waste
   * time searching for the location to insert new edges.
   */
  var e = vEvent.anEdge;
  while (e.activeRegion == null) {
    e = e.oNext;
    if (e == vEvent.anEdge) {
      // All edges go right -- not incident to any processed edges
      Sweep.connectLeftVertex_(tess, vEvent);
      return;
    }
  }

  /* Processing consists of two phases: first we "finish" all the
   * active regions where both the upper and lower edges terminate
   * at vEvent (ie. vEvent is closing off these regions).
   * We mark these faces "inside" or "outside" the polygon according
   * to their winding number, and delete the edges from the dictionary.
   * This takes care of all the left-going edges from vEvent.
   */
  var regUp = Sweep.topLeftRegion_(e.activeRegion);
  var reg = regUp.regionBelow();
  var eTopLeft = reg.eUp;
  var eBottomLeft = Sweep.finishLeftRegions_(tess, reg, null);

  /* Next we process all the right-going edges from vEvent. This
   * involves adding the edges to the dictionary, and creating the
   * associated "active regions" which record information about the
   * regions between adjacent dictionary edges.
   */
  if (eBottomLeft.oNext == eTopLeft) {
    // No right-going edges -- add a temporary "fixable" edge
    Sweep.connectRightVertex_(tess, regUp, eBottomLeft);

  } else {
    Sweep.addRightEdges_(tess, regUp, eBottomLeft.oNext, eTopLeft,
        eTopLeft, true);
  }
};


/**
 * We add two sentinel edges above and below all other edges,
 * to avoid special cases at the top and bottom.
 * @private
 * @param {GluTesselator} tess [description].
 * @param {number} t [description].
 */
static public function addSentinel_(tess:GluTesselator, t:Any) {
  var reg = new ActiveRegion();

  var e = Mesh.makeEdge(tess.mesh);

  e.org.s = Sweep.SENTINEL_COORD_;
  e.org.t = t;
  e.dst().s = -Sweep.SENTINEL_COORD_;
  e.dst().t = t;
  tess.event = e.dst(); //initialize it

  reg.eUp = e;
  reg.windingNumber = 0;
  reg.inside = false;
  reg.fixUpperEdge = false;
  reg.sentinel = true;
  reg.dirty = false;
  reg.nodeUp = tess.dict.insert(reg);
};


/**
 * We maintain an ordering of edge intersections with the Sweep line.
 * This order is maintained in a dynamic dictionary.
 * @private
 * @param {GluTesselator} tess [description].
 */
static public function initEdgeDict_(tess:GluTesselator) {
  tess.dict = new Dict(tess, Sweep.edgeLeq_);

  Sweep.addSentinel_(tess, -Sweep.SENTINEL_COORD_);
  Sweep.addSentinel_(tess, Sweep.SENTINEL_COORD_);
};


/**
 * [doneEdgeDict_ description]
 * @private
 * @param {GluTesselator} tess [description].
 */
static  public function doneEdgeDict_(tess:GluTesselator) {
  // NOTE(bckenny): fixedEdges is only used in the assert below, so ignore so
  // when asserts are removed jshint won't error.
  /* jshint unused:false */
  var fixedEdges = 0;

  var reg;
  while ((reg = tess.dict.getMin().getKey()) != null) {
    // At the end of all processing, the dictionary should contain
    // only the two sentinel edges, plus at most one "fixable" edge
    // created by connectRightVertex().
    if (!reg.sentinel) {
      Utils.assert(reg.fixUpperEdge);
      Utils.assert(++fixedEdges == 1);
    }
    Utils.assert(reg.windingNumber == 0);
    Sweep.deleteRegion_(tess, reg);
  }

  // NOTE(bckenny): see tess.dict.deleteDict_() for old delete dict function
  tess.dict = null;
};


/**
 * Remove zero-length edges, and contours with fewer than 3 vertices.
 * @private
 * @param {GluTesselator} tess [description].
 */
static public function removeDegenerateEdges_(tess:GluTesselator) {
  var eHead = tess.mesh.eHead;

  var eNext;
  var e = eHead.next;
  while ( e != eHead) {
    eNext = e.next;
    var eLNext = e.lNext;

    if (Geom.vertEq(e.org, e.dst()) && e.lNext.lNext != e) {
      // Zero-length edge, contour has at least 3 edges
      Sweep.spliceMergeVertices_(tess, eLNext, e); // deletes e.org
      Mesh.deleteEdge(e); // e is a self-loop TODO(bckenny): does this comment really apply here?
      e = eLNext;
      eLNext = e.lNext;
    }

    if (eLNext.lNext == e) {
      // Degenerate contour (one or two edges)
      if (eLNext != e) {
        if (eLNext == eNext || eLNext == eNext.sym) {
          eNext = eNext.next;
        }
        Mesh.deleteEdge(eLNext);
      }

      if (e == eNext || e == eNext.sym) {
        eNext = eNext.next;
      }
      Mesh.deleteEdge(e);
    }
    e = eNext;
  }
}


/**
 * Construct priority queue and insert all vertices into it, which determines
 * the order in which vertices cross the Sweep line.
 * @private
 * @param {GluTesselator} tess [description].
 */
static public function initPriorityQ_(tess:GluTesselator) {
  var pq = new PriorityQ();
  tess.pq = pq;

  var vHead = tess.mesh.vHead;
  var v = vHead.next;
  while ( v != vHead) {
    v.pqHandle = pq.insert(v);
    v = v.next;
  }

  pq.init();
}


/**
 * [donePriorityQ_ description]
 * @private
 * @param {GluTesselator} tess [description].
 */
static public function donePriorityQ_(tess:GluTesselator) {
  // TODO(bckenny): probably don't need deleteQ. check that function for comment
  tess.pq.deleteQ();
  tess.pq = null;
}


/**
 * Make the sentinel coordinates big enough that they will never be
 * merged with real input features.  (Even with the largest possible
 * input contour and the maximum tolerance of 1.0, no merging will be
 * done with coordinates larger than 3 * GLU_TESS_MAX_COORD).
 * @private
 * @const
 * @type {number}
 */
static final SENTINEL_COORD_ = 4 * GLU_TESS_MAX_COORD;

/**
 * Because vertices at exactly the same location are merged together
 * before we process the Sweep event, some degenerate cases can't occur.
 * However if someone eventually makes the modifications required to
 * merge features which are close together, the cases below marked
 * TOLERANCE_NONZERO will be useful.  They were debugged before the
 * code to merge identical vertices in the main loop was added.
 * @private
 * @const
 * @type {boolean}
 */
static final TOLERANCE_NONZERO_ = false;





}









































