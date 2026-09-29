#pragma once

// CPU implementations of the Laplacian enhancement (see LaplacianCore.hpp).
//
// Four variants are provided so the benchmark can compare them:
//
//   * scalar   - the straightforward per-pixel loop (the baseline);
//   * tiled    - walks the image in cache-sized tiles to reuse rows;
//   * openmp   - the scalar loop parallelised across rows;
//   * simd     - 8 pixels at a time with AVX2 intrinsics (falls back to the
//                scalar/tiled path on non-x86 or when AVX2 is unavailable).
//
// All of them produce exactly the same result as `sharpen_reference<uint8_t>`,
// so tests can assert parity.

#include "LaplacianCore.hpp"

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

namespace dcs229::proj0305 {
namespace cpu {
// Baseline: one thread, row-major, recomputing neighbours on every access.
inline auto scalar(unsigned char* out, const unsigned char* in, size_t width, size_t height)
	-> void {
	const size_t stride = width * 4;

	// Borders pass through unchanged.
	for (size_t x = 0; x < width; ++x) {
		for (size_t c = 0; c < 4; ++c) {
			out[x * 4 + c]						   = in[x * 4 + c];
			out[(height - 1) * stride + x * 4 + c] = in[(height - 1) * stride + x * 4 + c];
		}
	}
	for (size_t y = 0; y < height; ++y) {
		for (size_t c = 0; c < 4; ++c) {
			out[y * stride + c]					  = in[y * stride + c];
			out[y * stride + (width - 1) * 4 + c] = in[y * stride + (width - 1) * 4 + c];
		}
	}

	for (size_t y = 1; y + 1 < height; ++y) {
		const auto* above = in + (y - 1) * stride;
		const auto* row	  = in + y * stride;
		const auto* below = in + (y + 1) * stride;
		auto*		dst	  = out + y * stride;
		for (size_t x = 1; x + 1 < width; ++x) {
			const size_t base = x * 4;
			for (size_t c = 0; c < 3; ++c) {
				const int center = row[base + c];
				const int lap	 = above[base + c] + below[base + c] + row[base - 4 + c]
								 + row[base + 4 + c] - 4 * center;
				int		  value	 = center - lap;
				value			 = value < 0 ? 0 : (value > 255 ? 255 : value);
				dst[base + c]	 = static_cast<unsigned char>(value);
			}
			dst[base + 3] = row[base + 3];
		}
	}
}

// Cache-friendly variant: process the image in horizontal strips so the three
// source rows and the destination row stay hot in L1/L2. Uses the same math as
// `scalar`; the only difference is the loop nest.
inline auto tiled(
	unsigned char* out, const unsigned char* in, size_t width, size_t height,
	size_t tile_height = 16
) -> void {
	const size_t stride = width * 4;

	// Copy the whole buffer first, then only overwrite the interior. This keeps
	// the border handling identical to `scalar` and is cheap relative to the
	// convolution for non-trivial sizes.
	std::copy(in, in + stride * height, out);

	for (size_t tile_y = 1; tile_y + 1 < height; tile_y += tile_height) {
		const size_t y_end = std::min(tile_y + tile_height, height - 1);
		for (size_t y = tile_y; y < y_end; ++y) {
			const auto* above = in + (y - 1) * stride;
			const auto* row	  = in + y * stride;
			const auto* below = in + (y + 1) * stride;
			auto*		dst	  = out + y * stride;
			for (size_t x = 1; x + 1 < width; ++x) {
				const size_t base = x * 4;
				for (size_t c = 0; c < 3; ++c) {
					const int center = row[base + c];
					const int lap	 = above[base + c] + below[base + c] + row[base - 4 + c]
									 + row[base + 4 + c] - 4 * center;
					int		  value	 = center - lap;
					value			 = value < 0 ? 0 : (value > 255 ? 255 : value);
					dst[base + c]	 = static_cast<unsigned char>(value);
				}
				dst[base + 3] = row[base + 3];
			}
		}
	}
}

// OpenMP: the scalar interior loop parallelised across rows (when compiled with
// OpenMP; otherwise identical to `scalar`).
inline auto openmp(unsigned char* out, const unsigned char* in, size_t width, size_t height)
	-> void {
	const size_t stride = width * 4;

	for (size_t x = 0; x < width; ++x)
		for (size_t c = 0; c < 4; ++c) {
			out[x * 4 + c]						   = in[x * 4 + c];
			out[(height - 1) * stride + x * 4 + c] = in[(height - 1) * stride + x * 4 + c];
		}
	for (size_t y = 0; y < height; ++y)
		for (size_t c = 0; c < 4; ++c) {
			out[y * stride + c]					  = in[y * stride + c];
			out[y * stride + (width - 1) * 4 + c] = in[y * stride + (width - 1) * 4 + c];
		}

	const auto last_row = static_cast<long long>(height) - 1;
#if defined(_OPENMP)
#	pragma omp parallel for schedule(static)
#endif
	for (long long y = 1; y < last_row; ++y) {
		const auto* above = in + (y - 1) * stride;
		const auto* row	  = in + y * stride;
		const auto* below = in + (y + 1) * stride;
		auto*		dst	  = out + y * stride;
		for (size_t x = 1; x + 1 < width; ++x) {
			const size_t base = x * 4;
			for (size_t c = 0; c < 3; ++c) {
				const int center = row[base + c];
				const int lap	 = above[base + c] + below[base + c] + row[base - 4 + c]
								 + row[base + 4 + c] - 4 * center;
				int		  value	 = center - lap;
				value			 = value < 0 ? 0 : (value > 255 ? 255 : value);
				dst[base + c]	 = static_cast<unsigned char>(value);
			}
			dst[base + 3] = row[base + 3];
		}
	}
}

#if defined(DCS229_ARCH_X86)
// AVX2 path: process 8 pixels (32 bytes) at a time. Each 128-bit lane holds two
// pixels (RGBA, so 4 bytes each), and the neighbour offsets are single-pixel
// shifts. Falls back to `tiled` if AVX2 is not available at run time.
inline auto simd(unsigned char* out, const unsigned char* in, size_t width, size_t height) -> void {
	if (!__builtin_cpu_supports("avx2")) {
		tiled(out, in, width, height);
		return;
	}

	const size_t stride = width * 4;
	std::copy(in, in + stride * height, out);

	const __m256i zero = _mm256_setzero_si256();
	const __m256i max  = _mm256_set1_epi16(255);

	for (size_t y = 1; y + 1 < height; ++y) {
		const auto* above = in + (y - 1) * stride;
		const auto* row	  = in + y * stride;
		const auto* below = in + (y + 1) * stride;
		auto*		dst	  = out + y * stride;

		size_t		x	  = 1;
		for (; x + 8 < width; x += 8) {
			const size_t base = x * 4;
			auto		 load = [](const unsigned char* p) {
				return _mm256_loadu_si256(reinterpret_cast<const __m256i*>(p));
			};
			const __m256i center = load(row + base);
			const __m256i up	 = load(above + base);
			const __m256i down	 = load(below + base);
			const __m256i left	 = load(row + base - 4);
			const __m256i right	 = load(row + base + 4);

			// Widen to 16-bit before summing: each neighbour is <= 255, so the
			// four-way sum needs more than 8 bits. `lo` covers bytes 0..15,
			// `hi` covers bytes 16..31.
			const __m256i c_lo = _mm256_unpacklo_epi8(center, zero);
			const __m256i c_hi = _mm256_unpackhi_epi8(center, zero);
			const auto	  sum16 =
				[&](const __m256i a, const __m256i b, const __m256i c, const __m256i d, bool high) {
					const auto lo = [&](const __m256i v) {
						return high ? _mm256_unpackhi_epi8(v, zero) : _mm256_unpacklo_epi8(v, zero);
					};
					return _mm256_add_epi16(
						_mm256_add_epi16(lo(a), lo(b)),
						_mm256_add_epi16(lo(c), lo(d))
					);
				};

			const __m256i s_lo = sum16(up, down, left, right, false);
			const __m256i s_hi = sum16(up, down, left, right, true);

			// value = 5*center - (up + down + left + right), per 16-bit lane.
			const __m256i five	 = _mm256_set1_epi16(5);
			__m256i		  lo	 = _mm256_sub_epi16(_mm256_mullo_epi16(c_lo, five), s_lo);
			__m256i		  hi	 = _mm256_sub_epi16(_mm256_mullo_epi16(c_hi, five), s_hi);

			lo					 = _mm256_min_epi16(_mm256_max_epi16(lo, zero), max);
			hi					 = _mm256_min_epi16(_mm256_max_epi16(hi, zero), max);

			const __m256i packed = _mm256_packus_epi16(lo, hi);
			// `unpacklo/unpackhi` work per 128-bit lane, so `lo` holds bytes
			// {0-7,16-23} and `hi` holds {8-15,24-31}; packus_epi16 then
			// re-interleaves them back into the original byte order. No
			// cross-lane permute is required.

			// Keep the original alpha bytes.
			const __m256i alpha_mask = _mm256_set1_epi32(static_cast<int>(0xFF000000u));
			const __m256i blended	 = _mm256_blendv_epi8(packed, center, alpha_mask);
			_mm256_storeu_si256(reinterpret_cast<__m256i*>(dst + base), blended);
		}

		// Scalar tail.
		for (; x + 1 < width; ++x) {
			const size_t base = x * 4;
			for (size_t c = 0; c < 3; ++c) {
				const int center = row[base + c];
				const int lap	 = above[base + c] + below[base + c] + row[base - 4 + c]
								 + row[base + 4 + c] - 4 * center;
				int		  value	 = center - lap;
				value			 = value < 0 ? 0 : (value > 255 ? 255 : value);
				dst[base + c]	 = static_cast<unsigned char>(value);
			}
			dst[base + 3] = row[base + 3];
		}
	}
}
#else
inline auto simd(unsigned char* out, const unsigned char* in, size_t width, size_t height) -> void {
	tiled(out, in, width, height);
}
#endif
}  // namespace cpu

// Public entry points, mirroring the CUDA `laplacian_sharpen` signature.
inline auto laplacian_scalar(const char* src, char* dst, size_t width, size_t height) -> void {
	cpu::scalar(
		reinterpret_cast<unsigned char*>(dst),
		reinterpret_cast<const unsigned char*>(src),
		width,
		height
	);
}

inline auto laplacian_tiled(const char* src, char* dst, size_t width, size_t height) -> void {
	cpu::tiled(
		reinterpret_cast<unsigned char*>(dst),
		reinterpret_cast<const unsigned char*>(src),
		width,
		height
	);
}

inline auto laplacian_openmp(const char* src, char* dst, size_t width, size_t height) -> void {
	cpu::openmp(
		reinterpret_cast<unsigned char*>(dst),
		reinterpret_cast<const unsigned char*>(src),
		width,
		height
	);
}

inline auto laplacian_simd(const char* src, char* dst, size_t width, size_t height) -> void {
	cpu::simd(
		reinterpret_cast<unsigned char*>(dst),
		reinterpret_cast<const unsigned char*>(src),
		width,
		height
	);
}
}  // namespace dcs229::proj0305
