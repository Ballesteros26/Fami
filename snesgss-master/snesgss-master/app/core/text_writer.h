// Formatted text output with Windows text-mode line endings: every '\n'
// becomes "\r\n", matching the files the original editor wrote with
// fopen(..., "wt"). Used for everything that must be byte-identical.
#pragma once

#include <cstdarg>
#include <cstdio>
#include <string>
#include <vector>

namespace gss {

class TextWriter {
public:
#if defined(__GNUC__)
	__attribute__((format(printf, 2, 3)))
#endif
	void printf(const char* fmt, ...)
	{
		char buf[1024];
		va_list ap;
		va_start(ap, fmt);
		const int n = std::vsnprintf(buf, sizeof(buf), fmt, ap);
		va_end(ap);
		if (n < 0) return;
		if ((size_t)n < sizeof(buf)) {
			put(buf, (size_t)n);
		} else {
			std::vector<char> big((size_t)n + 1);
			va_start(ap, fmt);
			std::vsnprintf(big.data(), big.size(), fmt, ap);
			va_end(ap);
			put(big.data(), (size_t)n);
		}
	}

	void str(const std::string& s) { put(s.data(), s.size()); }

	std::string take() { return std::move(out_); }

private:
	void put(const char* s, size_t n)
	{
		for (size_t i = 0; i < n; ++i) {
			if (s[i] == '\n') out_ += '\r';
			out_ += s[i];
		}
	}

	std::string out_;
};

}  // namespace gss
