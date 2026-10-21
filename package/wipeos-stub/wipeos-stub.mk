################################################################################
#
# wipeos-stub
#
################################################################################

# Local source in our external tree (D26, D31).
WIPEOS_STUB_SITE = $(BR2_EXTERNAL_WIPEOS_PATH)/src/stub
WIPEOS_STUB_SITE_METHOD = local

# Git commit of the repo, reported in the stub's BEGIN line (D29).
WIPEOS_STUB_GIT_VERSION = $(shell git -C $(BR2_EXTERNAL_WIPEOS_PATH) describe --always --dirty 2>/dev/null || echo unknown)

define WIPEOS_STUB_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) WIPEOS_VERSION="$(WIPEOS_STUB_GIT_VERSION)" -C $(@D)
endef

define WIPEOS_STUB_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/wipeos-init $(TARGET_DIR)/sbin/wipeos-init
endef

$(eval $(generic-package))
