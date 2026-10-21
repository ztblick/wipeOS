# Builds the WipeOS stub (D25-D27). Buildroot passes CC, CFLAGS and
# LDFLAGS on the make command line (TARGET_CONFIGURE_OPTS), and
# command-line variables override assignments made here. So our own
# flags live in STUB_* and are added in the rules.

WIPEOS_VERSION ?= unknown

STUB_CFLAGS = -std=c17 -O2 -Wall -Wextra -Werror \
	-ffile-prefix-map=$(CURDIR)=. \
	-DWIPEOS_VERSION='"$(WIPEOS_VERSION)"'
STUB_LDFLAGS = -static

OBJS = main.o report.o util.o

wipeos-init: $(OBJS)
	$(CC) $(LDFLAGS) $(STUB_LDFLAGS) -o $@ $(OBJS)

$(OBJS): wipeos.h

%.o: %.c
	$(CC) $(CFLAGS) $(STUB_CFLAGS) -c -o $@ $<

clean:
	rm -f wipeos-init $(OBJS)

.PHONY: clean
