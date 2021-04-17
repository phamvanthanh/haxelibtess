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

package libtess.priorityq;

import libtess.Geom ;
import libtess.mesh.GluVertex;
import libtess.Utils;

/**
 * A priority queue of vertices, ordered by libtess.geom.vertLeq, implemented
 * with a binary heap. Used only within libtess.PriorityQ for prioritizing
 * vertices created by intersections (see libtess.sweep.checkForIntersect_).
 * constructor
 * struct
 */

@:native
@:nativeChildren
@:nativeProperty
@:nativeGen
@:expose('libtess.PriorityQHeap')
class PriorityQHeap  {

  /**
 * The initial allocated space for the queue.
 * const
 * private {number}
 */
  static public final INIT_SIZE_ = 32;
  /**
   * The heap itself. Active nodes are stored in the range 1..size, with the
   * minimum at 1. Each node stores only an index into verts_ and handles_.
   * private {!Array<number>}
   */
  public var  heap_ = PriorityQHeap.reallocNumeric_([0],
      PriorityQHeap.INIT_SIZE_ + 1);

  /**
   * An unordered list of vertices in the heap, with null in empty slots.
   * private {!Array<libtess.GluVertex>}
   */
  public var verts_:Array<GluVertex> = [null, null];

  /**
   * An unordered list of indices mapping vertex handles into the heap. An entry
   * at index i will map the vertex at i in verts_ to its place in the heap
   * (i.e. heap_[handles_[i]] == i).
   * Empty slots below size_ are a free list chain starting at freeList_.
   * private {!Array<number>}
   */
  public  var handles_:Array<Int> = [0, 0];

  /**
   * The size of the queue.
   * private {number}
   */
  public var size_:Int = 0;

  /**
   * The queue's current allocated space.
   * private {number}
   */
  public var max_ = PriorityQHeap.INIT_SIZE_;

  /**
   * The index of the next free hole in the verts_ array. That slot in handles_
   * has the next index in the free list. If there are no holes, freeList_ == 0
   * and a new vertex must be appended to the list.
   * private {libtess.PQHandle}
   */
  public var freeList_ = 0;

  /**
   * Indicates that the heap has been initialized via init. If false, inserts
   * are fast insertions at the end of a list. If true, all inserts will now be
   * correctly ordered in the queue before returning.
   * private {boolean}
   */
  public var initialized_ = false;

  // Point the first index at the first (currently null) vertex.


  /**
 * Allocate a numeric index array of size size. oldArray's contents are copied
 * to the beginning of the new array. The rest of the array is filled with
 * zeroes.
 * private
 * param {!Array<number>} oldArray
 * param {number} size
 * return {!Array<number>}
 */
 static public function reallocNumeric_(oldArray:Array<Int>, size:Int):Array<Int> {
  var newArray:Array<Int> = [];

  // NOTE(bckenny): V8 likes this significantly more than simply growing the
  // array element-by-element or expanding the existing array all at once, so,
  // for now, emulating realloc.
  var index = 0;
  while ( index < oldArray.length) {
    newArray[index] = oldArray[index];
    index++;
  }

  while (index < size) {
    newArray[index] = 0;
    index++;
  }

  return newArray;
};

public function new(){
  this.heap_[1] = 1;
}

/**
 * Initializing ordering of the heap. Must be called before any method other
 * than insert is called to ensure correctness when removing or querying.
 */
public function init() {
  // This method of building a heap is O(n), rather than O(n lg n).
  var i = this.size_;
  while ( i >= 1) {
    // TODO(bckenny): since init is called before anything is inserted (see
    // PriorityQ.init), this will always be empty. Better to lazily init?
    this.floatDown_(i);
     --i;
  }

  this.initialized_ = true;
};

/**
 * Insert a new vertex into the heap.
 * param {libtess.GluVertex} vert The vertex to insert.
 * return {libtess.PQHandle} A handle that can be used to remove the vertex.
 */
public  function insert(vert:GluVertex) {
  var endIndex = ++this.size_;

  // If the heap overflows, double its size.
  if ((endIndex * 2) > this.max_) {
    this.max_ *= 2;

    this.handles_ = PriorityQHeap.reallocNumeric_(this.handles_,
        this.max_ + 1);
  }

  var newVertSlot;
  if (this.freeList_ == 0) {
    // No free slots, append vertex.
    newVertSlot = endIndex;
  } else {
    // Put vertex in free slot, update freeList_ to next free slot.
    newVertSlot = this.freeList_;
    this.freeList_ = this.handles_[this.freeList_];
  }

  this.verts_[newVertSlot] = vert;
  this.handles_[newVertSlot] = endIndex;
  this.heap_[endIndex] = newVertSlot;

  if (this.initialized_) {
    this.floatUp_(endIndex);
  }
  return newVertSlot;
}

/**
 * return {boolean} Whether the heap is empty.
 */
public function isEmpty() {
  return this.size_ == 0;
};

/**
 * Returns the minimum vertex in the heap. If the heap is empty, null will be
 * returned.
 * return {libtess.GluVertex}
 */
public function minimum() {
  return this.verts_[this.heap_[1]];
};

/**
 * Removes the minimum vertex from the heap and returns it. If the heap is
 * empty, null will be returned.
 * return {libtess.GluVertex}
 */
public function extractMin() {
  var heap = this.heap_;
  var verts = this.verts_;
  var handles = this.handles_;

  var minHandle = heap[1];
  var minVertex = verts[minHandle];

  if (this.size_ > 0) {
    // Replace min with last vertex.
    heap[1] = heap[this.size_];
    handles[heap[1]] = 1;

    // Clear min vertex and put slot at front of freeList_.
    verts[minHandle] = null;
    handles[minHandle] = this.freeList_;
    this.freeList_ = minHandle;

    // Restore heap.
    if (--this.size_ > 0) {
      this.floatDown_(1);
    }
  }

  return minVertex;
}

/**
 * Remove vertex with handle removeHandle from heap.
 * param {libtess.PQHandle} removeHandle
 */
public function remove(removeHandle:Int) {
  var heap = this.heap_;
  var verts = this.verts_;
  var handles = this.handles_;

  Utils.assert(removeHandle >= 1 && removeHandle <= this.max_ &&
      verts[removeHandle] != null);

  var heapIndex = handles[removeHandle];

  // Replace with last vertex.
  heap[heapIndex] = heap[this.size_];
  handles[heap[heapIndex]] = heapIndex;

  // Restore heap.
  if (heapIndex <= --this.size_) {
    if (heapIndex <= 1) {
      this.floatDown_(heapIndex);
    } else {
      var vert = verts[heap[heapIndex]];
      var parentVert = verts[heap[heapIndex >> 1]];
      if (Geom.vertLeq(parentVert, vert)) {
        this.floatDown_(heapIndex);
      } else {
        this.floatUp_(heapIndex);
      }
    }
  }

  // Clear vertex and put slot at front of freeList_.
  verts[removeHandle] = null;
  handles[removeHandle] = this.freeList_;
  this.freeList_ = removeHandle;
}

/**
 * Restore heap by moving the vertex at index in the heap downwards to a valid
 * slot.
 * private
 * param {libtess.PQHandle} index
 */
public function floatDown_(index:Int) {
  var heap = this.heap_;
  var verts = this.verts_;
  var handles = this.handles_;

  var currIndex = index;
  var currHandle = heap[currIndex];
  while (true) {
    // The children of node i are nodes 2i and 2i+1.
    var childIndex:Int = currIndex << 1;
    if (childIndex < this.size_) {
      // Set child to the index of the child with the minimum vertex.
      if (Geom.vertLeq(verts[heap[childIndex + 1]],
          verts[heap[childIndex]])) {
        childIndex = childIndex + 1;
      }
    }

    Utils.assert(childIndex <= this.max_);

    var childHandle = heap[childIndex];
    if (childIndex > this.size_ ||
        Geom.vertLeq(verts[currHandle], verts[childHandle])) {
      // Heap restored.
      heap[currIndex] = currHandle;
      handles[currHandle] = currIndex;
      return;
    }

    // Swap current node and child; repeat from childIndex.
    heap[currIndex] = childHandle;
    handles[childHandle] = currIndex;
    currIndex = childIndex;
  }
};

/**
 * Restore heap by moving the vertex at index in the heap upwards to a valid
 * slot.
 * private
 * param {libtess.PQHandle} index
 */
public function floatUp_(index:Int) {
  var heap = this.heap_;
  var verts = this.verts_;
  var handles = this.handles_;

  var currIndex = index;
  var currHandle = heap[currIndex];
  while (true) {
    // The parent of node i is node floor(i/2).
    var parentIndex = currIndex >> 1;
    var parentHandle = heap[parentIndex];

    if (parentIndex == 0 ||
        Geom.vertLeq(verts[parentHandle], verts[currHandle])) {
      // Heap restored.
      heap[currIndex] = currHandle;
      handles[currHandle] = currIndex;
      return;
    }

    // Swap current node and parent; repeat from parentIndex.
    heap[currIndex] = parentHandle;
    handles[parentHandle] = currIndex;
    currIndex = parentIndex;
  }
}

}




