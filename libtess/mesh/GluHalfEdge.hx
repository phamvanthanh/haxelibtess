/**
 * Copyright 2000, Silicon Graphics, Inc. All Rights Reserved.
 * Copyright 2014, Google Inc. All Rights Reserved.
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



/**
 * The fundamental data structure is the "half-edge". Two half-edges
 * go together to make an edge, but they point in opposite directions.
 * Each half-edge has a pointer to its mate (the "symmetric" half-edge sym),
 * its origin vertex (org), the face on its left side (lFace), and the
 * adjacent half-edges in the CCW direction around the origin vertex
 * (oNext) and around the left face (lNext). There is also a "next"
 * pointer for the global edge list (see below).
 *
 * The notation used for mesh navigation:
 *  sym   = the mate of a half-edge (same edge, but opposite direction)
 *  oNext = edge CCW around origin vertex (keep same origin)
 *  dNext = edge CCW around destination vertex (keep same dest)
 *  lNext = edge CCW around left face (dest becomes new origin)
 *  rNext = edge CCW around right face (origin becomes new dest)
 *
 * "prev" means to substitute CW for CCW in the definitions above.
 *
 * The circular edge list is special; since half-edges always occur
 * in pairs (e and e.sym), each half-edge stores a pointer in only
 * one direction. Starting at eHead and following the e.next pointers
 * will visit each *edge* once (ie. e or e.sym, but not both).
 * e.sym stores a pointer in the opposite direction, thus it is
 * always true that e.sym.next.sym.next === e.
 *
 * param {libtess.GluHalfEdge=} opt_nextEdge
 * constructor
 * struct
 */
package libtess.mesh;

import libtess.sweep.ActiveRegion;
import libtess.mesh.GluFace;
import libtess.mesh.GluVertex;

@:native
@:nativeGen
@:nativeChildren
@:nativeProperty
@:expose('libtess.GluHalfEdge')
class GluHalfEdge {
  // TODO(bckenny): are these the right defaults? (from gl_meshNewMesh requirements)

  /**
   * doubly-linked list (prev==sym->next)
   * type {!libtess.GluHalfEdge}
   */
  public var next:GluHalfEdge;

  // TODO(bckenny): how can this be required if created in pairs? move to factory creation only?
  /**
   * same edge, opposite direction
   * type {libtess.GluHalfEdge}
   */
   public var sym:GluHalfEdge = null;

  /**
   * next edge CCW around origin
   * type {libtess.GluHalfEdge}
   */
   public var oNext:GluHalfEdge = null;

  /**
   * next edge CCW around left face
   * type {libtess.GluHalfEdge}
   */
   public var lNext:GluHalfEdge= null;

  /**
   * origin vertex (oVertex too long)
   * type {libtess.GluVertex}
   */
   public var org:GluVertex = null;

  /**
   * left face
   * type {libtess.GluFace}
   */
   public var lFace:GluFace = null;

  // Internal data (keep hidden)
  // NOTE(bckenny): can't be private, though...

  /**
   * a region with this upper edge (see sweep.js)
   * type {libtess.ActiveRegion}
   */
   public var activeRegion:ActiveRegion = null;

  /**
   * change in winding number when crossing from the right face to the left face
   * type {number}
   */
  public var winding = 0;
  public function new(opt_nextEdge:GluHalfEdge = null) {
    if(opt_nextEdge != null)
      this.next = opt_nextEdge;
    else 
      this.next = this;
  }

  // NOTE(bckenny): the following came from macros in mesh
// TODO(bckenny): using methods as aliases for sym connections for now.
// not sure about this approach. getters? renames?


/**
 * [rFace description]
 * return {libtess.GluFace} [description].
 */
public  function rFace() {
  return this.sym.lFace;
};


/**
 * [dst description]
 * return {libtess.GluVertex} [description].
 */
public function dst() {
  return this.sym.org;
};


/**
 * [oPrev description]
 * return {libtess.GluHalfEdge} [description].
 */
public function oPrev() {
  return this.sym.lNext;
};


/**
 * [lPrev description]
 * return {libtess.GluHalfEdge} [description].
 */
public function lPrev() {
  return this.oNext.sym;
};

// NOTE(bckenny): libtess.GluHalfEdge.dPrev is called nowhere in libtess and
// isn't part of the current public API. It could be useful for mesh traversal
// and manipulation if made public, however.
/* istanbul ignore next */
/**
 * The edge clockwise around destination vertex (keep same dest).
 * return {libtess.GluHalfEdge}
 */
 public function dPrev() {
  return this.lNext.sym;
};


/**
 * [rPrev description]
 * return {libtess.GluHalfEdge} [description].
 */
 public function rPrev() {
  return this.sym.oNext;
};


/**
 * [dNext description]
 * return {libtess.GluHalfEdge} [description].
 */
 public function dNext() {
  return this.rPrev().sym;
};


// NOTE(bckenny): libtess.GluHalfEdge.rNext is called nowhere in libtess and
// isn't part of the current public API. It could be useful for mesh traversal
// and manipulation if made public, however.
/* istanbul ignore next */
/**
 * The edge CCW around the right face (origin of this becomes new dest).
 * return {libtess.GluHalfEdge}
 */
 public function rNext() {
  return this.oPrev().sym;
};

}

