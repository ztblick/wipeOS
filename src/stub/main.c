// WipeOS process 1 (D25): mount the virtual filesystems, print the
// report (D29), run the checks, print the result, then end the run the
// way the mode says (D28).

// mount(), reboot() and sync() are not ISO C, so -std=c17 hides their
// declarations unless a feature-test macro asks for them.
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "wipeos.h"

#ifndef WIPEOS_VERSION
#define WIPEOS_VERSION "unknown"
#endif

// What the kernel command line asks for (D28).
struct options {
	bool dev;         // wipeos.mode=dev
	char *bad_mode;   // a wipeos.mode value that isn't dev or prod
	bool test_fail;   // wipeos.test_fail=1: the negative test
};

// Mount one virtual filesystem, creating the mount point if needed.
// Returns 0 or an errno. EBUSY means it is already mounted, which is
// the state we want.
static int mount_fs(const char *type, const char *target)
{
	if (mkdir(target, 0755) != 0 && errno != EEXIST)
		return errno;
	if (mount(type, target, type, 0, NULL) != 0 && errno != EBUSY)
		return errno;
	return 0;
}

// The kernel normally opens /dev/console as fds 0-2 for process 1. If
// it couldn't, open it ourselves now that devtmpfs is mounted. With no
// console at all there is nowhere to report to, and the run still goes
// on to its normal end.
// gcc's analyzer reports fd as leaked when open() returns 0, 1 or 2.
// That case is intended: fd is then itself a standard stream and must
// stay open.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wanalyzer-fd-leak"
static void ensure_console(void)
{
	if (fcntl(STDOUT_FILENO, F_GETFD) != -1 &&
	    fcntl(STDERR_FILENO, F_GETFD) != -1)
		return;

	int fd = open("/dev/console", O_RDWR | O_NOCTTY);
	if (fd < 0)
		return;
	for (int i = 0; i <= STDERR_FILENO; i++)
		if (fd != i)
			dup2(fd, i);
	if (fd > STDERR_FILENO)
		close(fd);
}
#pragma GCC diagnostic pop

// If tok is "name=value" for the given "name=", return value.
static char *param(char *tok, const char *name_eq)
{
	size_t n = strlen(name_eq);
	return strncmp(tok, name_eq, n) == 0 ? tok + n : NULL;
}

// Read our options from /proc/cmdline, last occurrence winning. The
// kernel keeps parameters with a '.' in their name out of process 1's
// arguments, so /proc/cmdline is the only place to find them. If it
// can't be read, the defaults stand (prod, no test failure), and
// check.mounts or check.report fails the run.
static void parse_cmdline(struct options *o)
{
	static char cmdline[4096];
	char *mode = NULL;

	o->dev = false;
	o->bad_mode = NULL;
	o->test_fail = false;
	if (read_file("/proc/cmdline", cmdline, sizeof(cmdline)) < 0)
		return;
	chomp(cmdline);

	char *save;
	for (char *tok = strtok_r(cmdline, " \t", &save); tok != NULL;
	     tok = strtok_r(NULL, " \t", &save)) {
		char *v;
		if ((v = param(tok, "wipeos.mode=")) != NULL)
			mode = v;
		else if ((v = param(tok, "wipeos.test_fail=")) != NULL)
			o->test_fail = strcmp(v, "1") == 0;
	}

	if (mode == NULL || strcmp(mode, "prod") == 0)
		return;
	if (strcmp(mode, "dev") == 0)
		o->dev = true;
	else
		o->bad_mode = mode; // a FAIL, and the run ends as in prod
}

// Process 1 must never return or exit: the kernel panics if it does.
static _Noreturn void power_off(void)
{
	sync();
	reboot(RB_POWER_OFF);
	// reboot() only returns on failure. Say so, then wait forever.
	report("poweroff=fail errno=%d", errno);
	for (;;)
		pause();
}

// Dev mode's ending (D28): the console goes to a shell started as a
// child of process 1, and the run ends when that shell exits.
static _Noreturn void run_shell(void)
{
	pid_t shell = fork();
	if (shell < 0) {
		report("shell.fork=fail errno=%d", errno);
		power_off();
	}

	if (shell == 0) {
		// The shell needs its own session with the console as its
		// controlling terminal, or job control and Ctrl-C don't work.
		// TIOCSCTTY's argument 1 takes the console over even if the
		// kernel left it attached to process 1.
		setsid();
		int fd = open("/dev/console", O_RDWR);
		if (fd >= 0) {
			ioctl(fd, TIOCSCTTY, 1);
			for (int i = 0; i <= STDERR_FILENO; i++)
				if (fd != i)
					dup2(fd, i);
			if (fd > STDERR_FILENO)
				close(fd);
		}
		char *const argv[] = { "sh", NULL };
		execv("/bin/sh", argv);
		report("shell.exec=fail errno=%d", errno);
		_exit(127);
	}

	// Process 1 inherits every orphaned process, so reap them all.
	// Power off once the shell itself has exited, or if wait() fails.
	for (;;) {
		pid_t done = wait(NULL);
		if (done == shell || done < 0)
			power_off();
	}
}

int main(void)
{
	// The kernel only auto-mounts devtmpfs for a disk root, not for an
	// initramfs, so process 1 mounts all three itself.
	static const struct {
		const char *type, *target;
	} fs[] = {
		{ "proc", "/proc" },
		{ "sysfs", "/sys" },
		{ "devtmpfs", "/dev" },
	};
	enum { NFS = sizeof(fs) / sizeof(fs[0]) };
	int err[NFS];
	bool mounted = true;

	for (size_t i = 0; i < NFS; i++) {
		err[i] = mount_fs(fs[i].type, fs[i].target);
		if (err[i] != 0)
			mounted = false;
	}
	ensure_console();

	struct options o;
	parse_cmdline(&o);

	// BEGIN must be the first line, so mount failures are reported
	// after it rather than as they happen.
	report("BEGIN format=1 version=%s", WIPEOS_VERSION);
	report("mode=%s", o.dev ? "dev" : "prod");
	if (o.bad_mode != NULL) {
		replace_quotes(o.bad_mode);
		report("mode.invalid=\"%s\"", o.bad_mode);
	}
	for (size_t i = 0; i < NFS; i++)
		if (err[i] != 0)
			report("mount.%s=fail errno=%d", fs[i].type, err[i]);

	struct facts f;
	collect_report(&f);

	// Fail closed: every check is printed, and the first one that
	// failed gives the reason (D29). check.shell runs in dev mode only,
	// because it tests dev mode's own ending (D28).
	struct check {
		const char *name;
		bool pass;
		const char *reason;
	} checks[6];
	size_t n = 0;

	checks[n++] = (struct check){ "mode", o.bad_mode == NULL, "mode" };
	checks[n++] = (struct check){ "mounts", mounted, "mounts" };
	checks[n++] = (struct check){ "aslr_off", f.aslr == 0, "aslr_off" };
	checks[n++] = (struct check){ "report", f.report_ok && report_lines_ok(),
				      "report" };
	if (o.test_fail)
		checks[n++] = (struct check){ "test_fail", false, "test_fail" };
	bool shell_ok = false;
	if (o.dev) {
		shell_ok = access("/bin/sh", X_OK) == 0;
		checks[n++] = (struct check){ "shell", shell_ok, "no_shell" };
	}

	const char *failed = NULL;
	for (size_t i = 0; i < n; i++) {
		report("check.%s=%s", checks[i].name,
		       checks[i].pass ? "pass" : "fail");
		if (!checks[i].pass && failed == NULL)
			failed = checks[i].reason;
	}

	if (failed != NULL)
		report("RESULT=FAIL reason=%s", failed);
	else
		report("RESULT=SUCCESS");

	// Dev mode gets its shell whatever the result, so a failure can be
	// examined; without a shell it ends like prod.
	if (o.dev && shell_ok)
		run_shell();
	power_off();
}
