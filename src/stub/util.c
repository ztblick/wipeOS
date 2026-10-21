// Line output and file reading for the WipeOS stub.

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "wipeos.h"

static bool lines_ok = true;

// Print one "WIPEOS ..." line with a single write(), so a kernel
// message on the same console can't land inside it (D29). A line that
// doesn't fit is cut short and remembered, so check.report fails
// instead of a value being truncated silently.
void report(const char *fmt, ...)
{
	static const char prefix[] = "WIPEOS ";
	char line[4096];
	size_t len = sizeof(prefix) - 1;
	size_t room = sizeof(line) - len - 1; // keep one byte for '\n'

	memcpy(line, prefix, len);
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(line + len, room, fmt, ap);
	va_end(ap);
	if (n < 0 || (size_t)n >= room) {
		lines_ok = false;
		n = n < 0 ? 0 : (int)(room - 1);
	}
	len += (size_t)n;
	line[len++] = '\n';

	// Nothing useful to do if the console write fails.
	ssize_t w = write(STDOUT_FILENO, line, len);
	(void)w;
}

bool report_lines_ok(void)
{
	return lines_ok;
}

// Read a whole small file into buf as a NUL-terminated string. Returns
// its length, or -1 with errno set. A file that doesn't fit is an error
// (EFBIG), never a silent truncation.
ssize_t read_file(const char *path, char *buf, size_t size)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;

	// /proc and sysfs files can arrive in several pieces, so read
	// until end of file.
	size_t len = 0;
	int err = 0;
	for (;;) {
		ssize_t r = read(fd, buf + len, size - 1 - len);
		if (r < 0) {
			err = errno;
			break;
		}
		if (r == 0)
			break;
		len += (size_t)r;
		if (len == size - 1) {
			// Buffer full: only fine if the file ends exactly here.
			char extra;
			r = read(fd, &extra, 1);
			if (r != 0)
				err = r > 0 ? EFBIG : errno;
			break;
		}
	}
	close(fd);
	if (err != 0) {
		errno = err;
		return -1;
	}
	buf[len] = '\0';
	return (ssize_t)len;
}

// Drop trailing newlines, which /proc and sysfs values end with.
void chomp(char *s)
{
	size_t len = strlen(s);
	while (len > 0 && s[len - 1] == '\n')
		s[--len] = '\0';
}

// Report values that come from outside, such as the kernel command
// line, are printed in double quotes, so a '"' inside one would end it
// early. Kernel command lines rarely contain one; swap it for '\''.
void replace_quotes(char *s)
{
	for (; *s != '\0'; s++)
		if (*s == '"')
			*s = '\'';
}

// Find "Field:   <number>" in /proc/meminfo text. Returns false if the
// field is missing or has no number.
bool meminfo_value(const char *meminfo, const char *field,
		   unsigned long long *value)
{
	size_t flen = strlen(field);

	for (const char *line = meminfo; line != NULL && *line != '\0';) {
		if (strncmp(line, field, flen) == 0 && line[flen] == ':') {
			const char *num = line + flen + 1;
			char *end;
			errno = 0;
			*value = strtoull(num, &end, 10);
			return errno == 0 && end != num;
		}
		line = strchr(line, '\n');
		if (line != NULL)
			line++;
	}
	return false;
}
