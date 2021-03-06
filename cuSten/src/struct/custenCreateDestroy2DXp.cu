// Andrew Gloster
// May 2018

//   Copyright 2018 Andrew Gloster

//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at

//       http://www.apache.org/licenses/LICENSE-2.0

//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.

/*! \file custenCreateDestroy2DXnp.cu
    Functions to create and destroy the cuSten_t that is used to give input to the compute kernels. 
    2D x direction, periodic
*/

// ---------------------------------------------------------------------
//  Standard Libraries and Headers
// ---------------------------------------------------------------------

#include <iostream>

// ---------------------------------------------------------------------
// Custom libraries and headers
// ---------------------------------------------------------------------

#include "cuSten_struct_type.h"
#include "cuSten_struct_functions.h"
#include "../util/util.h"

// ---------------------------------------------------------------------
// Function to create the struct
// ---------------------------------------------------------------------

/*! \fun __global__ void custenCreate2DXp
    \brief Function to set up cuSten_t
    \param pt_cuSten Pointer to cuSten type provided by user
	\param numTiles Number of tiles to divide the data into
	\param nx Total number of points in the x direction 
	\param ny Total number of points in the y direction 
	\param BLOCK_X Size of thread block in the x direction
	\param BLOCK_Y Size of thread block in the y direction
    \param dataOutput Pointer to data output by the function
	\param dataInput Pointer to data input to the function    
	\param weights Pointer to input weights for each point in the stencil
	\param numSten Total number of points in the stencil
	\param numStenLeft Number of points on the left side of the stencil
	\param numStenRight Number of points on the right side of the stencil
*/

void custenCreate2DXp(
	cuSten_t* pt_cuSten,
	int deviceNum,
	int numTiles,
	int nx,
	int ny,
	int BLOCK_X,
	int BLOCK_Y,
	double* dataNew,
	double* dataOld,
	double* weights,
	int numSten,
	int numStenLeft,
	int numStenRight
) 
{
	// Buffer used for error checking
	char msgStringBuffer[1024];

	// Set the device number associated with the struct
  	pt_cuSten->deviceNum = deviceNum;

  	// Set the number of streams
  	pt_cuSten->numStreams = 3;

  	// Set the number of tiles
  	pt_cuSten->numTiles = numTiles;

  	// Set the number points in x on the device
  	pt_cuSten->nx = nx;

  	// Set the number points in y on the device
  	pt_cuSten->ny = ny;

  	// Number of threads in x on the device
	pt_cuSten->BLOCK_X = BLOCK_X;

  	// Number of threads in y on the device
	pt_cuSten->BLOCK_Y = BLOCK_Y;

	// Set current active compute device
	cudaSetDevice(pt_cuSten->deviceNum);
	sprintf(msgStringBuffer, "Setting current device to GPU %d", pt_cuSten->deviceNum);
	checkError(msgStringBuffer);	

	// Create memeory for the streams
	pt_cuSten->streams = (cudaStream_t*)malloc(pt_cuSten->numStreams * sizeof(cudaStream_t*));

	// Create the streams
	for (int st = 0; st < pt_cuSten->numStreams; st++)
	{
		cudaStreamCreate(&pt_cuSten->streams[st]);
		sprintf(msgStringBuffer, "Creating stream %d on GPU %d", st, pt_cuSten->deviceNum);
		checkError(msgStringBuffer);	
	}

	// Create memeory for the events
	pt_cuSten->events = (cudaEvent_t*)malloc(2 * sizeof(cudaEvent_t*));

	// Create the events
	for (int ev = 0; ev < 2; ev++)
	{
		cudaEventCreate(&pt_cuSten->events[ev]);
		sprintf(msgStringBuffer, "Creating event %d on GPU %d", ev, pt_cuSten->deviceNum);
		checkError(msgStringBuffer);
	}

	// Set number of points in the stencil
	pt_cuSten->numSten = numSten;

	// Set number of points to the left in the stencil
	pt_cuSten->numStenLeft = numStenLeft;

	// Set number of points to the right in the stencil
	pt_cuSten->numStenRight = numStenRight;

	// Set the amount of shared memory required
	pt_cuSten->mem_shared = (pt_cuSten->BLOCK_Y * pt_cuSten->BLOCK_X + pt_cuSten->BLOCK_Y * (pt_cuSten->numStenLeft + pt_cuSten->numStenRight)) * sizeof(double) + pt_cuSten->numSten * sizeof(double);

	// Find number of points per tile
	pt_cuSten->nx = pt_cuSten->nx;

	// Find number of points per tile
	pt_cuSten->nyTile = pt_cuSten->ny / pt_cuSten->numTiles;	

	// Set the grid up
    pt_cuSten->xGrid = (pt_cuSten->nx % pt_cuSten->BLOCK_X == 0) ? (pt_cuSten->nx / pt_cuSten->BLOCK_X) : (pt_cuSten->nx / pt_cuSten->BLOCK_X + 1);
    pt_cuSten->yGrid = (pt_cuSten->nyTile % pt_cuSten->BLOCK_Y == 0) ? (pt_cuSten->nyTile / pt_cuSten->BLOCK_Y) : (pt_cuSten->nyTile / pt_cuSten->BLOCK_Y + 1);

	// Set the device weights pointer
	pt_cuSten->weights = weights;

	// Allocate the pointers for each input tile
	pt_cuSten->dataInput = (double**)malloc(pt_cuSten->numTiles * sizeof(double));

	// Allocate the pointers for each output tile
	pt_cuSten->dataOutput = (double**)malloc(pt_cuSten->numTiles * sizeof(double));

	// // Tile offset index
	int offset = pt_cuSten->nx * pt_cuSten->nyTile;

	// // Match the pointers to the data
	for (int tile = 0; tile < pt_cuSten->numTiles; tile++)
	{	
		// Set the input data
		pt_cuSten->dataInput[tile] = &dataOld[tile * offset];

		// Set the output data
		pt_cuSten->dataOutput[tile] = &dataNew[tile * offset];
	}
}

// ---------------------------------------------------------------------
// Swap pointers
// ---------------------------------------------------------------------

/*! \fun __global__ void custenSwap2DXp
    \brief Function to swap pointers necessary for timesteppint
    \param pt_cuSten Pointer to cuSten type provided by user
	\param dataInput Pointer to data input to the on the next compute
*/

void custenSwap2DXp(
	cuSten_t* pt_cuSten,

	double* dataInput
) 
{
	for (int tile = 0; tile < pt_cuSten->numTiles; tile++)
	{	
		// Swap the input and output data
		std::swap(pt_cuSten->dataInput[tile], pt_cuSten->dataOutput[tile]);
	}
}

// ---------------------------------------------------------------------
// Function to destroy the struct
// ---------------------------------------------------------------------

/*! \fun __global__ void custenDestroy2DXnp
    \brief Function to destroy data associated with cuSten_t
    \param pt_cuSten Pointer to cuSten type provided by user
*/

void custenDestroy2DXp(
	cuSten_t* pt_cuSten
) 
{
	// Buffer used for error checking
	char msgStringBuffer[1024];

	// Set current active compute device
	cudaSetDevice(pt_cuSten->deviceNum);
	sprintf(msgStringBuffer, "Setting current device to GPU %d", pt_cuSten->deviceNum);
	checkError(msgStringBuffer);	


	// Destroy the streams
	for (int st = 0; st < pt_cuSten->numStreams; st++)
	{
		cudaStreamDestroy(pt_cuSten->streams[st]);
		sprintf(msgStringBuffer, "Destroying stream %d on GPU %d", st, pt_cuSten->deviceNum);
		checkError(msgStringBuffer);	
	}

	// Free the main memory
	free(pt_cuSten->streams);

	// // Create the events
	for (int ev = 0; ev < 2; ev++)
	{
		cudaEventDestroy(pt_cuSten->events[ev]);
		sprintf(msgStringBuffer, "Destroying event %d on GPU %d", ev, pt_cuSten->deviceNum);
		checkError(msgStringBuffer);
	}

	// Free the main memory
	free(pt_cuSten->events);

	// Free the pointers for each input tile
	free(pt_cuSten->dataInput);

	// Free the pointers for each output tile
	free(pt_cuSten->dataOutput);
}


// ---------------------------------------------------------------------
// End of file
// ---------------------------------------------------------------------