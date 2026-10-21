// Shared declarations for the WipeOS stub (D25-D29).

#ifndef WIPEOS_H
#define WIPEOS_H

#include <stdbool.h>
#include <stddef.h>
#include <sys/types.h>

// What the report collects that the checks need afterwards.
struct facts {
	bool report_ok; // every file and value the report needs was read
	long aslr;      // /proc/sys/kernel/randomize_va_space, -1 if unread
};

// util.c
void report(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
bool report_lines_ok(void);
ssize_t read_file(const char *path, char *buf, size_t size);
void chomp(char *s);
void replace_quotes(char *s);
bool meminfo_value(const char *meminfo, const char *field,
		   unsigned long long *value);

// report.c
void collect_report(struct facts *f);

#endif
