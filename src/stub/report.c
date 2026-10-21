// Collects and prints the stub's report (D29): what the kernel sees of
// memory, huge pages, address randomization and PCI devices.

#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "wipeos.h"

#define PCI_MAX 1024

// Read a file the report needs. On failure, say which file and why, and
// mark the report incomplete so check.report fails (fail closed).
static bool need_file(struct facts *f, const char *path, char *buf,
		      size_t size)
{
	if (read_file(path, buf, size) >= 0) {
		chomp(buf);
		return true;
	}
	report("read_fail=\"%s\" errno=%d", path, errno);
	f->report_ok = false;
	return false;
}

// A value the report needs wasn't where it should be.
static void missing(struct facts *f, const char *key)
{
	report("%s=missing", key);
	f->report_ok = false;
}

static void report_meminfo(struct facts *f, const char *meminfo,
			   const char *field, const char *key)
{
	unsigned long long value;

	if (meminfo_value(meminfo, field, &value))
		report("%s=%llu", key, value);
	else
		missing(f, key);
}

static void report_basics(struct facts *f)
{
	char buf[4096];

	// /proc/uptime is "seconds.hundredths idle-time".
	if (need_file(f, "/proc/uptime", buf, sizeof(buf))) {
		unsigned long s, cs;
		if (sscanf(buf, "%lu.%2lu", &s, &cs) == 2)
			report("boot.uptime_ms=%lu", s * 1000 + cs * 10);
		else
			missing(f, "boot.uptime_ms");
	}

	long cpus = sysconf(_SC_NPROCESSORS_ONLN);
	if (cpus > 0)
		report("cpu.count=%ld", cpus);
	else
		missing(f, "cpu.count");

	if (need_file(f, "/proc/cmdline", buf, sizeof(buf))) {
		replace_quotes(buf);
		report("cmdline=\"%s\"", buf);
	}
}

// System RAM ranges and the kernel's own sections, as the kernel sees
// them. Process 1 runs as root, so /proc/iomem shows real addresses.
static void report_iomem(struct facts *f)
{
	static const struct {
		const char *name, *key;
	} kernel[] = {
		{ "Kernel code", "iomem.kernel_code" },
		{ "Kernel rodata", "iomem.kernel_rodata" },
		{ "Kernel data", "iomem.kernel_data" },
		{ "Kernel bss", "iomem.kernel_bss" },
	};
	enum { NKERNEL = sizeof(kernel) / sizeof(kernel[0]) };
	static char iomem[32768];
	bool found[NKERNEL] = { false };
	unsigned long long total = 0;
	unsigned ram = 0;

	if (!need_file(f, "/proc/iomem", iomem, sizeof(iomem)))
		return;

	char *save;
	for (char *line = strtok_r(iomem, "\n", &save); line != NULL;
	     line = strtok_r(NULL, "\n", &save)) {
		unsigned long long start, end;
		int name_at = -1;

		// Lines are "start-end : name". Anything else is skipped;
		// the ranges we need are checked for below.
		if (sscanf(line, " %llx-%llx : %n", &start, &end, &name_at) != 2 ||
		    name_at < 0)
			continue;
		const char *name = line + name_at;

		// Top-level ranges start in column 0; children are indented.
		if (line[0] != ' ' && strcmp(name, "System RAM") == 0)
			report("iomem.ram.%u=0x%llx-0x%llx", ram++, start, end);

		for (size_t i = 0; i < NKERNEL; i++) {
			if (!found[i] && strcmp(name, kernel[i].name) == 0) {
				found[i] = true;
				report("%s=0x%llx-0x%llx", kernel[i].key, start,
				       end);
				total += end - start + 1; // end is inclusive
			}
		}
	}

	if (ram == 0)
		missing(f, "iomem.ram");
	bool all = true;
	for (size_t i = 0; i < NKERNEL; i++) {
		if (!found[i]) {
			missing(f, kernel[i].key);
			all = false;
		}
	}
	if (all)
		report("iomem.kernel_total_bytes=%llu", total);
}

static void report_vmemmap(struct facts *f)
{
	static const char path[] = "/proc/sys/vm/hugetlb_optimize_vmemmap";
	char buf[64];

	// The file only exists when the kernel has the HugeTLB vmemmap
	// optimization; its absence is reported, not a failure.
	if (read_file(path, buf, sizeof(buf)) >= 0) {
		chomp(buf);
		report("hugetlb.vmemmap_optimize=%s", buf);
	} else if (errno == ENOENT) {
		report("hugetlb.vmemmap_optimize=absent");
	} else {
		report("read_fail=\"%s\" errno=%d", path, errno);
		f->report_ok = false;
	}
}

static void report_aslr(struct facts *f)
{
	char buf[64];

	if (!need_file(f, "/proc/sys/kernel/randomize_va_space", buf,
		       sizeof(buf)))
		return;
	char *end;
	errno = 0;
	long v = strtol(buf, &end, 10);
	if (errno != 0 || end == buf || *end != '\0') {
		missing(f, "aslr.randomize_va_space");
		return;
	}
	f->aslr = v;
	report("aslr.randomize_va_space=%ld", v);
}

static int compare_names(const void *a, const void *b)
{
	return strcmp(a, b);
}

static void report_pci(struct facts *f)
{
	static const char dir[] = "/sys/bus/pci/devices";
	static char slots[PCI_MAX][32];
	size_t n = 0;

	DIR *d = opendir(dir);
	if (d == NULL) {
		report("read_fail=\"%s\" errno=%d", dir, errno);
		f->report_ok = false;
		return;
	}
	for (;;) {
		errno = 0;
		struct dirent *e = readdir(d);
		if (e == NULL) {
			if (errno != 0) {
				report("read_fail=\"%s\" errno=%d", dir, errno);
				f->report_ok = false;
			}
			break;
		}
		if (e->d_name[0] == '.')
			continue;
		// Fail closed rather than report a partial device list.
		if (n == PCI_MAX || strlen(e->d_name) >= sizeof(slots[0])) {
			report("pci.count=too_many max=%d", PCI_MAX);
			f->report_ok = false;
			closedir(d);
			return;
		}
		strcpy(slots[n++], e->d_name);
	}
	closedir(d);

	// Directory order isn't guaranteed. Sort, so the report is the same
	// on every boot (D24).
	qsort(slots, n, sizeof(slots[0]), compare_names);

	report("pci.count=%zu", n);
	for (size_t i = 0; i < n; i++) {
		static const char *const attr[] = { "vendor", "device", "class" };
		char val[3][32];
		bool ok = true;

		for (size_t a = 0; a < 3; a++) {
			char path[128];
			int len = snprintf(path, sizeof(path), "%s/%s/%s", dir,
					   slots[i], attr[a]);
			if (len < 0 || (size_t)len >= sizeof(path)) {
				missing(f, "pci.path");
				ok = false;
				continue;
			}
			ok = need_file(f, path, val[a], sizeof(val[a])) && ok;
		}
		if (ok)
			report("pci.%s=%s:%s:%s", slots[i], val[0], val[1],
			       val[2]);
	}
}

void collect_report(struct facts *f)
{
	static char meminfo[8192];

	f->report_ok = true;
	f->aslr = -1;

	report_basics(f);

	bool have_meminfo =
		need_file(f, "/proc/meminfo", meminfo, sizeof(meminfo));
	if (have_meminfo) {
		report_meminfo(f, meminfo, "MemTotal", "mem.total_kb");
		report_meminfo(f, meminfo, "MemFree", "mem.free_kb");
		report_meminfo(f, meminfo, "MemAvailable", "mem.available_kb");
	}

	report_iomem(f);

	if (have_meminfo) {
		// The initramfs is unpacked into a RAM-backed rootfs, which
		// the kernel counts as shared memory.
		report_meminfo(f, meminfo, "Shmem", "initramfs.shmem_kb");
		report_meminfo(f, meminfo, "Hugepagesize", "hugetlb.page_size_kb");
		report_meminfo(f, meminfo, "HugePages_Total", "hugetlb.pages_total");
		report_meminfo(f, meminfo, "HugePages_Free", "hugetlb.pages_free");
	}
	report_vmemmap(f);

	report_aslr(f);
	report_pci(f);
}
