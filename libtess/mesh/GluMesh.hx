/**
 * Copyright 2000, Silicon Graphics, Inc. All Rights Reserved.
 * Copyright 2012, Google Inc. All Rights Reserved.
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
 * Creates a new mesh with no edges, no vertices,
 * and no loops (what we usually call a "face").
 */
// import GluVertex from './GluVertex';
// import GluFace from './GluFace';
// import GluHalfEdge from './GluHalfEdge';
// import Utils from '../Utils';
package libtess.mesh;

import libtess.mesh.GluVertex;
import libtess.mesh.GluFace;
import libtess.mesh.GluHalfEdge;
import libtess.Utils;


@:native
@:nativeGen
@:nativeChildren
@:nativeProperty
@:expose('libtess.GluMesh')
class GluMesh  {
  /**
   * dummy header for vertex list
   * type {libtess.GluVertex}
   */
  public var vHead = new GluVertex();

  /**
   * dummy header for face list
   * type {libtess.GluFace}
   */
   public var fHead = new GluFace();

  /**
   * dummy header for edge list
   * type {libtess.GluHalfEdge}
   */
   public var eHead = new GluHalfEdge();

  /**
   * and its symmetric counterpart
   * type {libtess.GluHalfEdge}
   */
   public var eHeadSym = new GluHalfEdge();

  // TODO(bckenny): better way to pair these?
 
  public function new(){
    this.eHead.sym = this.eHeadSym;
    this.eHeadSym.sym = this.eHead;
  }

  // TODO(bckenny): #ifndef NDEBUG
/**
 * Checks mesh for self-consistency.
 */
public  function checkMesh() {
    if (!Utils.isDebug()) {
      return;
    }

    var fHead = this.fHead;
    var vHead = this.vHead;
    var eHead = this.eHead;

    var e;

    // faces
    var f;
    var fPrev = fHead;
    while ( (f = fPrev.next) != fHead) {
      fPrev = fHead;
      Utils.assert(f.prev == fPrev);
      e = f.anEdge;
      do {
        Utils.assert(e.sym != e);
        Utils.assert(e.sym.sym == e);
        Utils.assert(e.lNext.oNext.sym == e);
        Utils.assert(e.oNext.sym.lNext == e);
        Utils.assert(e.lFace == f);
        e = e.lNext;
      } while (e != f.anEdge);
      
      fPrev = f;
    }
    Utils.assert(f.prev == fPrev && f.anEdge == null);

    // vertices
    var v;
    var vPrev = vHead;
    while ( (v = vPrev.next) != vHead) {
      vPrev = vHead;
      Utils.assert(v.prev == vPrev);
      e = v.anEdge;
      do {
        Utils.assert(e.sym != e);
        Utils.assert(e.sym.sym == e);
        Utils.assert(e.lNext.oNext.sym == e);
        Utils.assert(e.oNext.sym.lNext == e);
        Utils.assert(e.org == v);
        e = e.oNext;
      } while (e != v.anEdge);
      vPrev = v;
    }
    Utils.assert(v.prev == vPrev && v.anEdge == null && v.data == null);

    // edges
    var ePrev = eHead;
    while ((e = ePrev.next) != eHead) {
      ePrev = eHead; 
      Utils.assert(e.sym.next == ePrev.sym);
      Utils.assert(e.sym != e);
      Utils.assert(e.sym.sym == e);
      Utils.assert(e.org != null);
      Utils.assert(e.dst() != null);
      Utils.assert(e.lNext.oNext.sym == e);
      Utils.assert(e.oNext.sym.lNext == e);
       ePrev = e;
    }
    Utils.assert(e.sym.next == ePrev.sym &&
        e.sym == this.eHeadSym &&
        e.sym.sym == e &&
        e.org == null && e.dst() == null &&
        e.lFace == null && e.rFace() == null);
  };

}


