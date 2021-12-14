/*******************************************************************************
 * Copyright 2011 See AUTHORS file.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *   http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * 
 * 
 * Adapted from https://github.com/libgdx/libgdx to fit this project's purpose.
 ******************************************************************************/

package cubyz.utils.algorithms;

import cubyz.utils.datastructures.BooleanFastList;
import cubyz.utils.datastructures.IntFastList;

/** Delaunay triangulation. Adapted from Paul Bourke's triangulate: http://paulbourke.net/papers/triangulate/
 * @author Nathan Sweet */
public class DelaunayTriangulator {
	static private final float EPSILON = 0.000001f;
	static private final int INSIDE = 0;
	static private final int COMPLETE = 1;
	static private final int INCOMPLETE = 2;

	/** Triangulates the given point cloud to a list of triangle indices that make up the Delaunay triangulation.
	 * @param points x, y pairs describing points. Duplicate points will result in undefined behavior.
	 * @param sorted If false, the points will be sorted by the x coordinate, which is required by the triangulation algorithm. If
	 *           sorting is done the input array is not modified, the returned indices are for the input array, and count*2
	 *           additional working memory is needed.
	 * @return triples of indices into the points that describe the triangles in clockwise order. Note the returned array is reused
	 *         for later calls to the same method. */
	public static int[] computeTriangles (int[] points, int offset, int count) {
		if (count > 32767) throw new IllegalArgumentException("count must be <= " + 32767);
		IntFastList triangles = new IntFastList(count);
		triangles.clear();
		if (count < 6) return triangles.toArray();
		int[] sortedPoints = new int[count];
		System.arraycopy(points, offset, sortedPoints, 0, count);
		points = sortedPoints;
		offset = 0;
		int[] originalIndices = new int[points.length/2];
		sort(points, originalIndices, count);

		int end = offset + count;

		// Determine bounds for super triangle.
		float xmin = points[0], ymin = points[1];
		float xmax = xmin, ymax = ymin;
		for (int i = offset + 2; i < end; i++) {
			float value = points[i];
			if (value < xmin) xmin = value;
			if (value > xmax) xmax = value;
			i++;
			value = points[i];
			if (value < ymin) ymin = value;
			if (value > ymax) ymax = value;
		}
		float dx = xmax - xmin, dy = ymax - ymin;
		float dmax = (dx > dy ? dx : dy) * 20f;
		float xmid = (xmax + xmin) / 2f, ymid = (ymax + ymin) / 2f;

		// Setup the super triangle, which contains all points.
		float[] superTriangle = new float[6];
		superTriangle[0] = xmid - dmax;
		superTriangle[1] = ymid - dmax;
		superTriangle[2] = xmid;
		superTriangle[3] = ymid + dmax;
		superTriangle[4] = xmid + dmax;
		superTriangle[5] = ymid - dmax;

		IntFastList edges = new IntFastList(count/2);

		BooleanFastList complete = new BooleanFastList(count);

		// Add super triangle.
		triangles.add(end);
		triangles.add(end + 2);
		triangles.add(end + 4);
		complete.add(false);

		// Include each point one at a time into the existing mesh.
		for (int pointIndex = offset; pointIndex < end; pointIndex += 2) {
			float x = points[pointIndex], y = points[pointIndex + 1];

			// If x, y lies inside the circumcircle of a triangle, the edges are stored and the triangle removed.
			int[] trianglesArray = triangles.array;
			boolean[] completeArray = complete.array;
			for (int triangleIndex = triangles.size - 1; triangleIndex >= 0; triangleIndex -= 3) {
				int completeIndex = triangleIndex / 3;
				if (completeArray[completeIndex]) continue;
				int p1 = trianglesArray[triangleIndex - 2];
				int p2 = trianglesArray[triangleIndex - 1];
				int p3 = trianglesArray[triangleIndex];
				float x1, y1, x2, y2, x3, y3;
				if (p1 >= end) {
					int i = p1 - end;
					x1 = superTriangle[i];
					y1 = superTriangle[i + 1];
				} else {
					x1 = points[p1];
					y1 = points[p1 + 1];
				}
				if (p2 >= end) {
					int i = p2 - end;
					x2 = superTriangle[i];
					y2 = superTriangle[i + 1];
				} else {
					x2 = points[p2];
					y2 = points[p2 + 1];
				}
				if (p3 >= end) {
					int i = p3 - end;
					x3 = superTriangle[i];
					y3 = superTriangle[i + 1];
				} else {
					x3 = points[p3];
					y3 = points[p3 + 1];
				}
				switch (circumCircle(x, y, x1, y1, x2, y2, x3, y3)) {
				case COMPLETE:
					completeArray[completeIndex] = true;
					break;
				case INSIDE:
					edges.add(p1, p2, p2, p3);
					edges.add(p3, p1);

					triangles.removeInd(triangleIndex);
					triangles.removeInd(triangleIndex-1);
					triangles.removeInd(triangleIndex-2);
					complete.remove(completeIndex);
					break;
				}
			}

			int[] edgesArray = edges.array;
			for (int i = 0, n = edges.size; i < n; i += 2) {
				// Skip multiple edges. If all triangles are anticlockwise then all interior edges are opposite pointing in direction.
				int p1 = edgesArray[i];
				if (p1 == -1) continue;
				int p2 = edgesArray[i + 1];
				boolean skip = false;
				for (int ii = i + 2; ii < n; ii += 2) {
					if (p1 == edgesArray[ii + 1] && p2 == edgesArray[ii]) {
						skip = true;
						edgesArray[ii] = -1;
					}
				}
				if (skip) continue;

				// Form new triangles for the current point. Edges are arranged in clockwise order.
				triangles.add(p1);
				triangles.add(edgesArray[i + 1]);
				triangles.add(pointIndex);
				complete.add(false);
			}
			edges.clear();
		}

		// Remove triangles with super triangle vertices.
		int[] trianglesArray = triangles.array;
		for (int i = triangles.size - 1; i >= 0; i -= 3) {
			if (trianglesArray[i] >= end || trianglesArray[i - 1] >= end || trianglesArray[i - 2] >= end) {
				triangles.removeInd(i);
				triangles.removeInd(i - 1);
				triangles.removeInd(i - 2);
			}
		}

		// Convert sorted to unsorted indices.
		for (int i = 0, n = triangles.size; i < n; i++)
			trianglesArray[i] = (short)(originalIndices[trianglesArray[i] / 2] * 2);

		// Adjust triangles to start from zero and count by 1, not by vertex x, y coordinate pairs.
		if (offset == 0) {
			for (int i = 0, n = triangles.size; i < n; i++)
				trianglesArray[i] = (short)(trianglesArray[i] / 2);
		} else {
			for (int i = 0, n = triangles.size; i < n; i++)
				trianglesArray[i] = (short)((trianglesArray[i] - offset) / 2);
		}

		return triangles.toArray();
	}

	/** Returns INSIDE if point xp, yp is inside the circumcircle made up of the points x1, y1, x2, y2, x3, y3. Returns COMPLETE if xp
	 * is to the right of the entire circumcircle. Otherwise returns INCOMPLETE. Note: a point on the circumcircle edge is
	 * considered inside. */
	private static int circumCircle (float xp, float yp, float x1, float y1, float x2, float y2, float x3, float y3) {
		float xc, yc;
		float y1y2 = Math.abs(y1 - y2);
		float y2y3 = Math.abs(y2 - y3);
		if (y1y2 < EPSILON) {
			if (y2y3 < EPSILON) return INCOMPLETE;
			float m2 = -(x3 - x2) / (y3 - y2);
			float mx2 = (x2 + x3) / 2f;
			float my2 = (y2 + y3) / 2f;
			xc = (x2 + x1) / 2f;
			yc = m2 * (xc - mx2) + my2;
		} else {
			float m1 = -(x2 - x1) / (y2 - y1);
			float mx1 = (x1 + x2) / 2f;
			float my1 = (y1 + y2) / 2f;
			if (y2y3 < EPSILON) {
				xc = (x3 + x2) / 2f;
				yc = m1 * (xc - mx1) + my1;
			} else {
				float m2 = -(x3 - x2) / (y3 - y2);
				float mx2 = (x2 + x3) / 2f;
				float my2 = (y2 + y3) / 2f;
				xc = (m1 * mx1 - m2 * mx2 + my2 - my1) / (m1 - m2);
				yc = m1 * (xc - mx1) + my1;
			}
		}

		float dx = x2 - xc;
		float dy = y2 - yc;
		float rsqr = dx * dx + dy * dy;

		dx = xp - xc;
		dx *= dx;
		dy = yp - yc;
		if (dx + dy * dy - rsqr <= EPSILON) return INSIDE;
		return xp > xc && dx > rsqr ? COMPLETE : INCOMPLETE;
	}

	/** Sorts x, y pairs of values by the x value.
	 * @param count Number of indices, must be even. */
	private static void sort (int[] values, int[] originalIndices, int count) {
		int pointCount = count / 2;
		for (short i = 0; i < pointCount; i++)
			originalIndices[i] = i;

		int lower = 0;
		int upper = count - 1;
		IntFastList stack = new IntFastList();
		stack.add(lower);
		stack.add(upper - 1);
		while (stack.size > 0) {
			upper = stack.array[--stack.size];
			lower = stack.array[--stack.size];
			if (upper <= lower) continue;
			int i = quicksortPartition(values, lower, upper, originalIndices);
			if (i - lower > upper - i) {
				stack.add(lower);
				stack.add(i - 2);
			}
			stack.add(i + 2);
			stack.add(upper);
			if (upper - i >= i - lower) {
				stack.add(lower);
				stack.add(i - 2);
			}
		}
	}

	private static int quicksortPartition (final int[] values, int lower, int upper, int[] originalIndices) {
		int value = values[lower];
		int up = upper;
		int down = lower + 2;
		int tempValue;
		int tempIndex;
		while (down < up) {
			while (down < up && values[down] <= value)
				down = down + 2;
			while (values[up] > value)
				up = up - 2;
			if (down < up) {
				tempValue = values[down];
				values[down] = values[up];
				values[up] = tempValue;

				tempValue = values[down + 1];
				values[down + 1] = values[up + 1];
				values[up + 1] = tempValue;

				tempIndex = originalIndices[down / 2];
				originalIndices[down / 2] = originalIndices[up / 2];
				originalIndices[up / 2] = tempIndex;
			}
		}
		if (value > values[up]) {
			values[lower] = values[up];
			values[up] = value;

			tempValue = values[lower + 1];
			values[lower + 1] = values[up + 1];
			values[up + 1] = tempValue;

			tempIndex = originalIndices[lower / 2];
			originalIndices[lower / 2] = originalIndices[up / 2];
			originalIndices[up / 2] = tempIndex;
		}
		return up;
	}
}
