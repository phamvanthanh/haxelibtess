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


// TODO(bckenny): apparently only visible outside of sweep for debugging routines.
// find out if we can hide

/**
 * For each pair of adjacent edges crossing the sweep line, there is
 * an ActiveRegion to represent the region between them. The active
 * regions are kept in sorted order in a dynamic dictionary. As the
 * sweep line crosses each vertex, we update the affected regions.

 */
package libtess.sweep;

import libtess.dict.DictNode;
import libtess.mesh.GluHalfEdge;

@:native
@:nativeGen
@:nativeChildren
@:nativeProperty
@:expose('libtess.ActiveRegion')
class ActiveRegion {
  // TODO(bckenny): I *think* eUp and nodeUp could be passed in as constructor params
// @type {libtess.GluHalfEdge}
  /**
   * The upper edge of the region, directed right to left
   * 
   * 
   */
  public var eUp:GluHalfEdge = null;

  // @type {libtess.DictNode}
  /**
   * Dictionary node corresponding to eUp edge.
   * 
   */
  public var nodeUp:DictNode = null;

  /**
   * Used to determine which regions are inside the polygon.
   * 
   */
  public var windingNumber = 0;

  /**
   * Whether this region is inside the polygon.
   * 
   */
  public var inside:Bool = false;

  /**
   * Marks fake edges at t = +/-infinity.
   * 
   */
  public var sentinel:Bool = false;

  /**
   * Marks regions where the upper or lower edge has changed, but we haven't
   * checked whether they intersect yet.
   * @type {boolean}
   */
  public var dirty = false;

  /**
   * marks temporary edges introduced when we process a "right vertex" (one
   * without any edges leaving to the right)
   * 
   */
  public var fixUpperEdge:Bool = false;




  /**
 * Returns the ActiveRegion below this one.
 * 
 */

  public  function new(){
    
  }

  public  function regionBelow():ActiveRegion {
    return this.nodeUp.getPredecessor().getKey();
  }

    /**
   * Returns the ActiveRegion above this one.
   * 
   */
  public function regionAbove():ActiveRegion {
    return this.nodeUp.getSuccessor().getKey();
  }
}



