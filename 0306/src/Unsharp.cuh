#pragma once

// CUDA implementation of the unsharp masking described in UnsharpCore.hpp
// (g = f + amount * (f - Gaussian_blur(f)), separable, replicate borders).
//
// The kernels operate on the canonical RGBA8 layout: 4 bytes per pixel,
// row-major, so byte index = (y * width + x) * 4 + channel. The Gaussian is
// separable, so we run a horizontal kernel into a float intermediate, then a
// vertical kernel that also performs the blend with the original image.

#include "UnsharpCore.hpp"

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

#include <cuda_runtime.h>

namespace dcs229::proj0306 {
// Device copy of the normalised Gaussian taps.
struct DeviceKernel {
	float* taps	  = nullptr;
	int	   radius = 0;

	~DeviceKernel() {
		if (taps != nullptr)
			cudaFree(taps);
	}

	DeviceKernel(const DeviceKernel&)					 = delete;
	auto operator=(const DeviceKernel&) -> DeviceKernel& = delete;
	DeviceKernel()										 = default;
};

// Horizontal Gaussian pass: RGBA8 -> float RGBA.
__global__ void _unsharp_blur_h(
	const unsigned char* __restrict__ in, float* __restrict__ out, size_t width, size_t height,
	const float* __restrict__ taps, int radius
) {
	const size_t x = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	const size_t y = static_cast<size_t>(blockIdx.y) * blockDim.y + threadIdx.y;
	if (x >= width || y >= height)
		return;

	const size_t stride = width * 4;
	for (size_t c = 0; c < 4; ++c) {
		float acc = 0.0f;
		for (int k = -radius; k <= radius; ++k) {
			const long long sx = static_cast<long long>(x) + k;
			const size_t	cx =
				sx < 0 ?
					0 :
					(sx >= static_cast<long long>(width) ? width - 1 : static_cast<size_t>(sx));
			acc += taps[k + radius] * static_cast<float>(in[y * stride + cx * 4 + c]);
		}
		out[y * stride + x * 4 + c] = acc;
	}
}

// Vertical Gaussian pass fused with the unsharp blend and clamping.
__global__ void _unsharp_blur_v(
	const float* __restrict__ blurred_h, const unsigned char* __restrict__ original,
	unsigned char* __restrict__ out, size_t width, size_t height, const float* __restrict__ taps,
	int radius, float amount
) {
	const size_t x = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	const size_t y = static_cast<size_t>(blockIdx.y) * blockDim.y + threadIdx.y;
	if (x >= width || y >= height)
		return;

	const size_t stride = width * 4;
	for (size_t c = 0; c < 3; ++c) {
		float acc = 0.0f;
		for (int k = -radius; k <= radius; ++k) {
			const long long sy = static_cast<long long>(y) + k;
			const size_t	cy =
				sy < 0 ?
					0 :
					(sy >= static_cast<long long>(height) ? height - 1 : static_cast<size_t>(sy));
			acc += taps[k + radius] * blurred_h[cy * stride + x * 4 + c];
		}
		const float f	  = static_cast<float>(original[y * stride + x * 4 + c]);
		const float value = f + amount * (f - acc);
		out[y * stride + x * 4 + c] =
			value <= 0.0f ? 0 : (value >= 255.0f ? 255 : static_cast<unsigned char>(value + 0.5f));
	}
	out[y * stride + x * 4 + 3] = original[y * stride + x * 4 + 3];	 // alpha untouched
}

// Host launcher: uploads the kernel, runs both passes and copies the result.
inline auto unsharp_sharpen(
	const char* src, char* dst, size_t width, size_t height, float sigma, float amount
) -> void {
	const size_t bytes	= width * height * 4;
	const auto	 host	= gaussian_kernel(sigma);
	const int	 radius = gaussian_radius(sigma);
	const dim3	 threads(16, 16);
	const dim3	 grid((width + 15) / 16, (height + 15) / 16);

	DeviceKernel device_kernel;
	device_kernel.radius = radius;
	if (cudaMalloc(&device_kernel.taps, host.size() * sizeof(float)) != cudaSuccess)
		throw std::runtime_error("unsharp_sharpen: cudaMalloc(taps) failed");
	if (cudaMemcpy(
			device_kernel.taps,
			host.data(),
			host.size() * sizeof(float),
			cudaMemcpyHostToDevice
		)
		!= cudaSuccess)
		throw std::runtime_error("unsharp_sharpen: cudaMemcpy(taps) failed");

	unsigned char* dev_in  = nullptr;
	float*		   dev_h   = nullptr;
	unsigned char* dev_out = nullptr;
	const auto	   cleanup = [&] {
		if (dev_in != nullptr)
			cudaFree(dev_in);
		if (dev_h != nullptr)
			cudaFree(dev_h);
		if (dev_out != nullptr)
			cudaFree(dev_out);
	};

	if (cudaMalloc(&dev_in, bytes) != cudaSuccess
		|| cudaMalloc(&dev_h, bytes * sizeof(float)) != cudaSuccess
		|| cudaMalloc(&dev_out, bytes) != cudaSuccess) {
		cleanup();
		throw std::runtime_error("unsharp_sharpen: cudaMalloc failed");
	}

	const auto status = [&] {
		if (cudaMemcpy(dev_in, src, bytes, cudaMemcpyHostToDevice) != cudaSuccess)
			return cudaErrorUnknown;
		_unsharp_blur_h<<<grid, threads>>>(
			dev_in,
			dev_h,
			width,
			height,
			device_kernel.taps,
			radius
		);
		if (cudaGetLastError() != cudaSuccess)
			return cudaErrorUnknown;
		_unsharp_blur_v<<<grid, threads>>>(
			dev_h,
			dev_in,
			dev_out,
			width,
			height,
			device_kernel.taps,
			radius,
			amount
		);
		if (cudaGetLastError() != cudaSuccess)
			return cudaErrorUnknown;
		return cudaMemcpy(dst, dev_out, bytes, cudaMemcpyDeviceToHost);
	}();

	cleanup();
	if (status != cudaSuccess)
		throw std::runtime_error("unsharp_sharpen: kernel launch or copy failed");
}
}  // namespace dcs229::proj0306
