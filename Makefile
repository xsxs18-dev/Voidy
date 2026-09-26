TARGET := iphone:clang:latest:15.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = Voidy

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += voidyhelper app

include $(THEOS_MAKE_PATH)/aggregate.mk
