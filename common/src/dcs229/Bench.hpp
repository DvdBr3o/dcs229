#pragma once

// Small, dependency-free timing helpers shared by the 0305/0306 benchmarks.
//
// The benches compare a few hand-written implementations of the same operator,
// so we only need a reliable wall-clock measurement and a way to report a
// stable number: each variant is run several times and we report the best
// (minimum) run, which is the least noisy summary for CPU/GPU kernels.

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace dcs229::bench {
using Clock	  = std::chrono::steady_clock;
using Seconds = std::chrono::duration<double>;

// Run `fn` once and return the elapsed wall-clock seconds.
template<typename Fn>
[[nodiscard]] auto time_once(Fn&& fn) -> double {
	const auto start = Clock::now();
	fn();
	const auto stop = Clock::now();
	return Seconds(stop - start).count();
}

struct Result {
	std::string name;
	double		seconds = 0.0;
};

// Run `fn` `repeats` times, returning the best (minimum) time. `warmup` runs
// discard their timings so caches/JIT-like effects settle before measuring.
template<typename Fn>
[[nodiscard]] auto best_of(Fn&& fn, size_t repeats = 5, size_t warmup = 1) -> double {
	for (size_t i = 0; i < warmup; ++i) fn();

	double best = time_once(fn);
	for (size_t i = 1; i < repeats; ++i) best = std::min(best, time_once(fn));
	return best;
}

// Convenience: build a Result by timing `fn`.
template<typename Fn>
[[nodiscard]] auto measure(std::string name, Fn&& fn, size_t repeats = 5, size_t warmup = 1)
	-> Result {
	return {std::move(name), best_of(std::forward<Fn>(fn), repeats, warmup)};
}

// Throughput in megapixels per second for a `width` x `height` image.
[[nodiscard]] inline auto megapixels_per_second(size_t width, size_t height, double seconds)
	-> double {
	if (seconds <= 0.0)
		return 0.0;
	const double megapixels = static_cast<double>(width) * static_cast<double>(height) / 1e6;
	return megapixels / seconds;
}

// Print a small aligned table of results.
inline auto print_table(const std::vector<Result>& results, size_t width, size_t height) -> void {
	std::printf("%-24s %12s %14s %10s\n", "variant", "best (ms)", "Mpixel/s", "speedup");
	if (results.empty())
		return;
	const double baseline = results.front().seconds;
	for (const auto& result : results) {
		const double ms		 = result.seconds * 1e3;
		const double speedup = result.seconds > 0.0 ? baseline / result.seconds : 0.0;
		std::printf(
			"%-24s %12.3f %14.1f %9.2fx\n",
			result.name.c_str(),
			ms,
			megapixels_per_second(width, height, result.seconds),
			speedup
		);
	}
}
}  // namespace dcs229::bench
