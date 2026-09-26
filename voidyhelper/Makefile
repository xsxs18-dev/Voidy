TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = voidyhelper

voidyhelper_FILES = main.m
voidyhelper_CFLAGS = -fobjc-arc -Wall -Wno-unused-function
voidyhelper_FRAMEWORKS = Foundation
voidyhelper_CODESIGN_FLAGS = -Sentitlements.plist
voidyhelper_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
