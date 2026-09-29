#pragma once

// CUDA implementation of the Laplacian image enhancement described in
// LaplacianCore.hpp (g = f - Lap{f}, 4-neighbour stencil, borders untouched).
//
// The kernels operate on the canonical RGBA8 layout: 4 bytes per pixel,
// row-major, so byte index = (y * width + x) * 4 + channel.

#include "LaplacianCore.hpp"

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

#include <cuda_runtime.h>

namespace dcs229::proj0305 {
namespace detail {
// 4-neighbour Laplacian of one channel, clamped to [0, 255].
__device__ inline auto sharpen_pixel(
	const unsigned char* rgba, size_t x, size_t y, size_t width, size_t stride, size_t channel
) noexcept -> unsigned char {
	const auto index  = [&](size_t sx, size_t sy) { return sy * stride + sx * 4 + channel; };
	const int  center = rgba[index(x, y)];
	const int  lap	  = rgba[index(x, y - 1)] + rgba[index(x, y + 1)] + rgba[index(x - 1, y)]
					  + rgba[index(x + 1, y)] - 4 * center;
	const int  value  = center - lap;
	if (value < 0)
		return 0;
	if (value > 255)
		return 255;
	return static_cast<unsigned char>(value);
}
}  // namespace detail

// One thread per interior pixel; border pixels are copied through untouched.
__global__ void _laplacian(
	unsigned char* out, const unsigned char* image, size_t width, size_t height
) {
	const size_t x = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	const size_t y = static_cast<size_t>(blockIdx.y) * blockDim.y + threadIdx.y;
	if (x >= width || y >= height)
		return;

	const size_t stride = width * 4;
	const size_t pixel	= (y * width + x) * 4;
	const bool	 border = (x == 0 || y == 0 || x + 1 == width || y + 1 == height);
	for (size_t c = 0; c < 3; ++c) {
		out[pixel + c] =
			border ? image[pixel + c] : detail::sharpen_pixel(image, x, y, width, stride, c);
	}
	out[pixel + 3] = image[pixel + 3];	// alpha untouched
}

// Launch helper kept separate so callers can drive their own stream.
inline auto laplacian_launch(
	unsigned char* dev_out, const unsigned char* dev_in, size_t width, size_t height,
	cudaStream_t stream
) -> cudaError_t {
	constexpr unsigned block = 16;
	const dim3		   threads(block, block);
	const dim3		   grid((width + block - 1) / block, (height + block - 1) / block);
	_laplacian<<<grid, threads, 0, stream>>>(dev_out, dev_in, width, height);
	return cudaGetLastError();
}

// Host launcher: allocates device memory, runs the kernel and copies the result
// into `dst` (the caller owns `dst`, which must hold width*height*4 bytes).
inline auto laplacian_sharpen(const char* src, char* dst, size_t width, size_t height) -> void {
	const size_t   bytes   = width * height * 4;

	unsigned char* dev_in  = nullptr;
	unsigned char* dev_out = nullptr;
	if (cudaMalloc(&dev_in, bytes) != cudaSuccess)
		throw std::runtime_error("laplacian_sharpen: cudaMalloc(input) failed");
	if (cudaMalloc(&dev_out, bytes) != cudaSuccess) {
		cudaFree(dev_in);
		throw std::runtime_error("laplacian_sharpen: cudaMalloc(output) failed");
	}

	if (cudaMemcpy(dev_in, src, bytes, cudaMemcpyHostToDevice) != cudaSuccess
		|| laplacian_launch(dev_out, dev_in, width, height, nullptr) != cudaSuccess) {
		cudaFree(dev_in);
		cudaFree(dev_out);
		throw std::runtime_error("laplacian_sharpen: kernel launch failed");
	}

	const auto copy_status = cudaMemcpy(dst, dev_out, bytes, cudaMemcpyDeviceToHost);
	cudaFree(dev_in);
	cudaFree(dev_out);
	if (copy_status != cudaSuccess)
		throw std::runtime_error("laplacian_sharpen: cudaMemcpy(device-to-host) failed");
}
}  // namespace dcs229::proj0305
