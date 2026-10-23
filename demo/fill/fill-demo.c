// Temporary demo for a team meeting (demo/fill/PLAN.md): fill nearly all
// free RAM with a seeded pattern, verify it, and report what was left
// untouched. Not PoSE: no challenge, no labels, no fingerprints.

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#ifndef MAP_HUGE_1GB
#define MAP_HUGE_1GB (30 << MAP_HUGE_SHIFT)
#endif

#define MIB (1024ULL * 1024)
#define GIB (1024 * MIB)
#define CHUNK (64 * MIB)
#define PAGE 4096ULL
#define MAX_REGIONS 4096

typedef unsigned long long ull;

struct region {
	uint64_t *words;
	size_t bytes;
};

static struct region regions[MAX_REGIONS];
static size_t nregions;

// One write() per line, so a kernel message on the same console can't
// land inside it.
static void vemit(const char *prefix, const char *fmt, va_list ap)
{
	char line[1024];
	size_t len = strlen(prefix);
	size_t room = sizeof(line) - len - 1; // keep one byte for '\n'

	memcpy(line, prefix, len);
	int n = vsnprintf(line + len, room, fmt, ap);
	if (n > 0)
		len += (size_t)n < room ? (size_t)n : room - 1;
	line[len++] = '\n';
	ssize_t w = write(STDOUT_FILENO, line, len);
	(void)w;
}

// A "WIPEOS demo.key=value" line.
static void line(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void line(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vemit("WIPEOS demo.", fmt, ap);
	va_end(ap);
}

// The one plain-English line for the audience.
static void plain(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void plain(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vemit("", fmt, ap);
	va_end(ap);
}

// Read a whole small file into buf as a NUL-terminated string.
static bool read_file(const char *path, char *buf, size_t size)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return false;
	size_t len = 0;
	ssize_t r;
	while (len < size - 1 && (r = read(fd, buf + len, size - 1 - len)) > 0)
		len += (size_t)r;
	close(fd);
	buf[len] = '\0';
	return len < size - 1; // a full buffer may mean a cut-off file
}

static bool meminfo(const char *text, const char *field, ull *value)
{
	size_t flen = strlen(field);
	for (const char *p = text; p != NULL && *p != '\0';) {
		if (strncmp(p, field, flen) == 0 && p[flen] == ':') {
			char *end;
			*value = strtoull(p + flen + 1, &end, 10);
			return end != p + flen + 1;
		}
		p = strchr(p, '\n');
		if (p != NULL)
			p++;
	}
	return false;
}

// The machine's RAM: the sum of the top-level "System RAM" ranges in
// /proc/iomem (end addresses are inclusive). Needs root to see them.
static ull ram_bytes(void)
{
	static char buf[32768];
	ull total = 0;

	if (!read_file("/proc/iomem", buf, sizeof(buf)))
		return 0;
	char *save;
	for (char *l = strtok_r(buf, "\n", &save); l != NULL;
	     l = strtok_r(NULL, "\n", &save)) {
		ull start, end;
		int name_at = -1;
		if (l[0] == ' ' ||
		    sscanf(l, "%llx-%llx : %n", &start, &end, &name_at) != 2 ||
		    name_at < 0)
			continue;
		if (strcmp(l + name_at, "System RAM") == 0)
			total += end - start + 1;
	}
	return total;
}

static double now_s(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static inline uint64_t splitmix64(uint64_t x)
{
	uint64_t z = x + 0x9e3779b97f4a7c15ULL;
	z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
	z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
	return z ^ (z >> 31);
}

static void fill_words(uint64_t *w, size_t n, uint64_t first)
{
	for (size_t k = 0; k < n; k++)
		w[k] = splitmix64(first + k);
}

static uint64_t check_words(const uint64_t *w, size_t n, uint64_t first)
{
	uint64_t bad = 0;
	for (size_t k = 0; k < n; k++)
		bad += w[k] != splitmix64(first + k);
	return bad;
}

// Fill (or verify) every word of every region, word i getting
// splitmix64(seed + i), with a progress line at each 10%. Returns the
// mismatch count (0 when filling). noinline, so the verify pass can't be
// merged with the fill that just wrote the same values.
static __attribute__((noinline)) uint64_t
sweep(bool verify, uint64_t seed, ull total_bytes, double *mb_per_s)
{
	const char *phase = verify ? "verify" : "fill";
	uint64_t total_words = total_bytes / 8, i = 0, bad = 0;
	int pct = 10;
	uint64_t next = total_words * 10 / 100;
	double start = now_s();

	for (size_t r = 0; r < nregions; r++) {
		uint64_t *w = regions[r].words;
		size_t n = regions[r].bytes / 8, j = 0;
		while (j < n) {
			size_t len = n - j;
			if (pct <= 100 && next > i && len > next - i)
				len = next - i;
			if (verify)
				bad += check_words(w + j, len, seed + i);
			else
				fill_words(w + j, len, seed + i);
			j += len;
			i += len;
			while (pct <= 100 && i >= next) {
				double t = now_s() - start;
				char pct_f[24], bytes_f[32], ms_f[32];
				snprintf(pct_f, sizeof(pct_f), "%s_pct=%d", phase, pct);
				snprintf(bytes_f, sizeof(bytes_f), "bytes=%llu", (ull)i * 8);
				snprintf(ms_f, sizeof(ms_f), "elapsed_ms=%llu",
					 (ull)(t * 1000));
				// Pad each field to a fixed width so the columns line
				// up in a terminal. Only the gaps between fields grow,
				// so every field is still one key=value token.
				line("%-16s %-20s %-18s mb_per_s=%.1f", pct_f, bytes_f,
				     ms_f, t > 0 ? (double)i * 8 / t / 1e6 : 0.0);
				pct += 10;
				next = total_words * (uint64_t)pct / 100;
			}
		}
	}
	double t = now_s() - start;
	*mb_per_s = t > 0 ? (double)total_bytes / t / 1e6 : 0.0;
	return bad;
}

static bool add_region(void *p, size_t bytes)
{
	if (nregions == MAX_REGIONS)
		return false;
	regions[nregions++] = (struct region){ p, bytes };
	return true;
}

static ull parse_number(const char *s, const char *name)
{
	char *end;
	errno = 0;
	ull v = strtoull(s, &end, 10);
	if (errno != 0 || end == s || *end != '\0') {
		fprintf(stderr, "fill-demo: %s needs a whole number\n", name);
		exit(2);
	}
	return v;
}

int main(int argc, char **argv)
{
	ull seed = 1, margin_mb = 64;

	for (int a = 1; a < argc; a++) {
		if (strcmp(argv[a], "--seed") == 0 && a + 1 < argc)
			seed = parse_number(argv[++a], "--seed");
		else if (strcmp(argv[a], "--margin-mb") == 0 && a + 1 < argc)
			margin_mb = parse_number(argv[++a], "--margin-mb");
		else {
			fprintf(stderr,
				"usage: wipeos-fill-demo [--seed N] [--margin-mb N]\n");
			return 2;
		}
	}

	// Process 1 must never exit, and this program does.
	if (getpid() == 1) {
		line("error=\"refusing to run as process 1\"");
		return 1;
	}
	line("note=\"not PoSE: plain pattern fill, no challenge\"");

	static char mi[8192];
	ull total_kb, avail_kb, huge_free, huge_kb;
	if (!read_file("/proc/meminfo", mi, sizeof(mi)) ||
	    !meminfo(mi, "MemTotal", &total_kb) ||
	    !meminfo(mi, "MemAvailable", &avail_kb) ||
	    !meminfo(mi, "HugePages_Free", &huge_free) ||
	    !meminfo(mi, "Hugepagesize", &huge_kb)) {
		line("error=\"can't read /proc/meminfo\"");
		return 1;
	}
	ull ram = ram_bytes();
	if (ram == 0) {
		line("error=\"can't read System RAM from /proc/iomem\"");
		return 1;
	}
	// HugePages_Free counts pages of the default huge page size; only
	// 1 GB pages are used here.
	if (huge_kb != GIB / 1024)
		huge_free = 0;

	// Huge pages aren't counted in MemAvailable, so the two pools add up.
	// Stopping margin_mb short keeps the out-of-memory killer away.
	ull margin = margin_mb * MIB;
	ull avail = avail_kb * 1024;
	ull ordinary = avail > margin ? (avail - margin) / PAGE * PAGE : 0;
	ull target = huge_free * GIB + ordinary;

	line("ram_bytes=%llu", ram);
	line("mem_total_kb=%llu", total_kb);
	line("mem_available_kb=%llu", avail_kb);
	line("hugepages_free=%llu", huge_free);
	line("target_bytes=%llu", target);

	ull got_huge = 0, got_4k = 0;
	for (ull k = 0; k < huge_free; k++) {
		void *p = mmap(NULL, GIB, PROT_READ | PROT_WRITE,
			       MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB |
				       MAP_HUGE_1GB,
			       -1, 0);
		if (p == MAP_FAILED) {
			line("alloc.hugetlb_stopped errno=%d", errno);
			break;
		}
		if (!add_region(p, GIB))
			break;
		got_huge += GIB;
	}
	while (got_4k < ordinary) {
		size_t size = ordinary - got_4k < CHUNK ? ordinary - got_4k : CHUNK;
		// MAP_POPULATE backs the chunk with real pages right away.
		void *p = mmap(NULL, size, PROT_READ | PROT_WRITE,
			       MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
		if (p == MAP_FAILED) {
			line("alloc.4k_stopped errno=%d", errno);
			break;
		}
		if (!add_region(p, size)) {
			line("alloc.4k_stopped regions=%d", MAX_REGIONS);
			munmap(p, size);
			break;
		}
		got_4k += size;
	}
	line("alloc_hugetlb_bytes=%llu", got_huge);
	line("alloc_4k_bytes=%llu", got_4k);

	ull filled = got_huge + got_4k;
	double fill_mbps, verify_mbps;
	sweep(false, seed, filled, &fill_mbps);
	// Belt and braces with noinline: verify must read memory back, not
	// reuse values the compiler knows it just wrote.
	__asm__ volatile("" ::: "memory");
	uint64_t bad = sweep(true, seed, filled, &verify_mbps);

	bool pass = bad == 0 && filled > 0;
	ull unfilled = ram > filled ? ram - filled : 0;
	double coverage = 100.0 * (double)filled / (double)ram;

	line("filled_bytes=%llu", filled);
	line("filled_hugetlb_bytes=%llu", got_huge);
	line("filled_4k_bytes=%llu", got_4k);
	line("unfilled_bytes=%llu", unfilled);
	line("margin_bytes=%llu", margin);
	line("coverage_pct=%.1f", coverage);
	line("fill_mb_per_s=%.1f", fill_mbps);
	line("verify_mb_per_s=%.1f", verify_mbps);
	line("verify_mismatches=%llu", (ull)bad);
	line("result=%s", pass ? "PASS" : "FAIL");

	if (pass)
		plain("Filled and verified %.2f GiB of %.2f GiB (%.1f%%). "
		      "%llu MiB untouched: kernel, initramfs, page bookkeeping, "
		      "shell, and the %llu MiB safety margin.",
		      (double)filled / GIB, (double)ram / GIB, coverage,
		      unfilled / MIB, margin_mb);
	else
		plain("Verification FAILED: %llu of %llu words did not match.",
		      (ull)bad, filled / 8);

	// The memory is released when the process exits.
	return pass ? 0 : 1;
}
