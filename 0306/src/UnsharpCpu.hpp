#pragma once

// CPU implementations of unsharp masking (see UnsharpCore.hpp).
//
// Variants, all numerically equivalent to `unsharp_reference<uint8_t>`:
//
//   * scalar   - straightforward two-pass separable convolution (baseline);
//   * tiled    - the same math but the vertical pass walks cache-sized strips;
//   * openmp   - the scalar loops parallelised across rows;
//   * simd     - AVX2 horizontal pass processing 8 pixels at a time (falls back
//                to `tiled` on non-x86 or when AVX2 is unavailable).

#include "UnsharpCore.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <vector>

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__)
#	define DCS229_ARCH_X86 1
#	include <immintrin.h>
#endif

#if defined(_OPENMP)
#	include <omp.h>
#endif

namespace dcs229::proj0306 {
namespace cpu {
// Horizontal Gaussian pass, scalar. Reads `in` (interleaved `Channel`) and
// writes a float intermediate with the same layout.
template<typename Channel>
inline auto blur_h_scalar(
	const Channel* in, float* out, size_t width, size_t height, size_t channels, size_t stride,
	const float* taps, int radius
) -> void {
	for (size_t y = 0; y < height; ++y) {
		for (size_t x = 0; x < width; ++x) {
			for (size_t c = 0; c < channels; ++c) {
				float acc = 0.0f;
				for (int k = -radius; k <= radius; ++k) {
					const auto sx = clamp_index(static_cast<long long>(x) + k, width);
					acc +=
						taps[k + radius] * static_cast<float>(in[y * stride + sx * channels + c]);
				}
				out[y * stride + x * channels + c] = acc;
			}
		}
	}
}

// Vertical Gaussian pass + unsharp blend, scalar.
template<typename Channel>
inline auto blur_v_blend_scalar(
	const float* blurred, const Channel* original, Channel* dst, size_t width, size_t height,
	size_t channels, size_t stride, const float* taps, int radius, float amount
) -> void {
	for (size_t y = 0; y < height; ++y) {
		for (size_t x = 0; x < width; ++x) {
			for (size_t c = 0; c + 1 < channels; ++c) {	 // skip alpha
				float acc = 0.0f;
				for (int k = -radius; k <= radius; ++k) {
					const auto sy = clamp_index(static_cast<long long>(y) + k, height);
					acc += taps[k + radius] * blurred[sy * stride + x * channels + c];
				}
				const float f = static_cast<float>(original[y * stride + x * channels + c]);
				dst[y * stride + x * channels + c] = clamp_channel<Channel>(f + amount * (f - acc));
			}
			dst[y * stride + x * channels + (channels - 1)] =
				original[y * stride + x * channels + (channels - 1)];  // alpha
		}
	}
}

// Baseline: scalar horizontal then scalar vertical.
inline auto scalar(
	unsigned char* out, const unsigned char* in, size_t width, size_t height, float sigma,
	float amount
) -> void {
	const auto		   taps	  = gaussian_kernel(sigma);
	const int		   radius = gaussian_radius(sigma);
	std::vector<float> tmp(width * height * 4);
	blur_h_scalar(in, tmp.data(), width, height, 4, width * 4, taps.data(), radius);
	blur_v_blend_scalar(
		tmp.data(),
		in,
		out,
		width,
		height,
		4,
		width * 4,
		taps.data(),
		radius,
		amount
	);
}

// Tiled: same as scalar but the vertical pass runs in horizontal strips so the
// handful of float rows it needs stay in cache.
inline auto tiled(
	unsigned char* out, const unsigned char* in, size_t width, size_t height, float sigma,
	float amount, size_t tile_height = 32
) -> void {
	const auto		   taps	  = gaussian_kernel(sigma);
	const int		   radius = gaussian_radius(sigma);
	std::vector<float> tmp(width * height * 4);
	blur_h_scalar(in, tmp.data(), width, height, 4, width * 4, taps.data(), radius);

	for (size_t tile_y = 0; tile_y < height; tile_y += tile_height) {
		const size_t y_end = std::min(tile_y + tile_height, height);
		for (size_t y = tile_y; y < y_end; ++y) {
			for (size_t x = 0; x < width; ++x) {
				for (size_t c = 0; c + 1 < 4; ++c) {  // skip alpha
					float acc = 0.0f;
					for (int k = -radius; k <= radius; ++k) {
						const auto sy = clamp_index(static_cast<long long>(y) + k, height);
						acc += taps[k + radius] * tmp[sy * width * 4 + x * 4 + c];
					}
					const float f = static_cast<float>(in[y * width * 4 + x * 4 + c]);
					out[y * width * 4 + x * 4 + c] =
						clamp_channel<unsigned char>(f + amount * (f - acc));
				}
				out[y * width * 4 + x * 4 + 3] = in[y * width * 4 + x * 4 + 3];
			}
		}
	}
}

// OpenMP: the scalar passes parallelised across rows.
inline auto openmp(
	unsigned char* out, const unsigned char* in, size_t width, size_t height, float sigma,
	float amount
) -> void {
	const auto		   taps	  = gaussian_kernel(sigma);
	const int		   radius = gaussian_radius(sigma);
	std::vector<float> tmp(width * height * 4);

	const auto		   last_row = static_cast<long long>(height);
#if defined(_OPENMP)
#	pragma omp parallel for schedule(static)
#endif
	for (long long y = 0; y < last_row; ++y) {
		for (size_t x = 0; x < width; ++x) {
			for (size_t c = 0; c < 4; ++c) {
				float acc = 0.0f;
				for (int k = -radius; k <= radius; ++k) {
					const auto sx = clamp_index(static_cast<long long>(x) + k, width);
					acc += taps[k + radius] * static_cast<float>(in[y * width * 4 + sx * 4 + c]);
				}
				tmp[y * width * 4 + x * 4 + c] = acc;
			}
		}
	}

#if defined(_OPENMP)
#	pragma omp parallel for schedule(static)
#endif
	for (long long y = 0; y < last_row; ++y) {
		for (size_t x = 0; x < width; ++x) {
			for (size_t c = 0; c + 1 < 4; ++c) {
				float acc = 0.0f;
				for (int k = -radius; k <= radius; ++k) {
					const auto sy = clamp_index(static_cast<long long>(y) + k, height);
					acc += taps[k + radius] * tmp[sy * width * 4 + x * 4 + c];
				}
				const float f = static_cast<float>(in[y * width * 4 + x * 4 + c]);
				out[y * width * 4 + x * 4 + c] =
					clamp_channel<unsigned char>(f + amount * (f - acc));
			}
			out[y * width * 4 + x * 4 + 3] = in[y * width * 4 + x * 4 + 3];
		}
	}
}

#if defined(DCS229_ARCH_X86)
// AVX2 horizontal pass. For each channel we first gather the row's channel
// values into a padded float buffer (replicate borders), then run the taps as a
// sequence of vector FMAs eight pixels at a time. The vertical pass stays
// scalar, which dominates the runtime for typical sigma.
inline auto simd(
	unsigned char* out, const unsigned char* in, size_t width, size_t height, float sigma,
	float amount
) -> void {
	if (!__builtin_cpu_supports("avx2")) {
		tiled(out, in, width, height, sigma, amount);
		return;
	}

	const auto		   taps	  = gaussian_kernel(sigma);
	const int		   radius = gaussian_radius(sigma);
	std::vector<float> tmp(width * height * 4);

	// Padded channel row: `radius` replicated samples on each side.
	std::vector<float> row_buf(width + 2 * static_cast<size_t>(radius));

	for (size_t y = 0; y < height; ++y) {
		const auto* src_row = in + y * width * 4;
		auto*		out_row = tmp.data() + y * width * 4;

		for (size_t c = 0; c < 4; ++c) {
			for (size_t x = 0; x < width; ++x)
				row_buf[x + static_cast<size_t>(radius)] = static_cast<float>(src_row[x * 4 + c]);
			for (int k = 0; k < radius; ++k) {
				row_buf[static_cast<size_t>(radius - 1 - k)] = row_buf[static_cast<size_t>(radius)];
				row_buf[width + static_cast<size_t>(radius) + k] =
					row_buf[width + static_cast<size_t>(radius) - 1];
			}

			size_t x = 0;
			for (; x + 8 <= width; x += 8) {
				__m256 acc = _mm256_setzero_ps();
				for (int k = -radius; k <= radius; ++k) {
					const auto tap = _mm256_set1_ps(taps[static_cast<size_t>(k + radius)]);
					const auto v =
						_mm256_loadu_ps(row_buf.data() + x + static_cast<size_t>(radius + k));
					acc = _mm256_add_ps(acc, _mm256_mul_ps(tap, v));
				}
				// Scatter the 8 blurred channel values back to the RGBA layout.
				float lanes[8];
				_mm256_storeu_ps(lanes, acc);
				for (size_t i = 0; i < 8; ++i) out_row[(x + i) * 4 + c] = lanes[i];
			}
			// Scalar tail.
			for (; x < width; ++x) {
				float acc = 0.0f;
				for (int k = -radius; k <= radius; ++k)
					acc += taps[static_cast<size_t>(k + radius)]
						 * row_buf[x + static_cast<size_t>(radius + k)];
				out_row[x * 4 + c] = acc;
			}
		}
	}

	blur_v_blend_scalar(
		tmp.data(),
		in,
		out,
		width,
		height,
		4,
		width * 4,
		taps.data(),
		radius,
		amount
	);
}
#else
inline auto simd(
	unsigned char* out, const unsigned char* in, size_t width, size_t height, float sigma,
	float amount
) -> void {
	tiled(out, in, width, height, sigma, amount);
}
#endif
}  // namespace cpu

inline auto unsharp_scalar(
	const char* src, char* dst, size_t width, size_t height, float sigma, float amount
) -> void {
	cpu::scalar(
		reinterpret_cast<unsigned char*>(dst),
		reinterpret_cast<const unsigned char*>(src),
		width,
		height,
		sigma,
		amount
	);
}

inline auto unsharp_tiled(
	const char* src, char* dst, size_t width, size_t height, float sigma, float amount
) -> void {
	cpu::tiled(
		reinterpret_cast<unsigned char*>(dst),
		reinterpret_cast<const unsigned char*>(src),
		width,
		height,
		sigma,
		amount
	);
}

inline auto unsharp_openmp(
	const char* src, char* dst, size_t width, size_t height, float sigma, float amount
) -> void {
	cpu::openmp(
		reinterpret_cast<unsigned char*>(dst),
		reinterpret_cast<const unsigned char*>(src),
		width,
		height,
		sigma,
		amount
	);
}

inline auto unsharp_simd(
	const char* src, char* dst, size_t width, size_t height, float sigma, float amount
) -> void {
	cpu::simd(
		reinterpret_cast<unsigned char*>(dst),
		reinterpret_cast<const unsigned char*>(src),
		width,
		height,
		sigma,
		amount
	);
}
}  // namespace dcs229::proj0306
