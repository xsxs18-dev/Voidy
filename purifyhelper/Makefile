TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = purifyhelper

purifyhelper_FILES = main.m
purifyhelper_CFLAGS = -fobjc-arc -Wall -Wno-unused-function
purifyhelper_FRAMEWORKS = Foundation
purifyhelper_CODESIGN_FLAGS = -Sentitlements.plist
purifyhelper_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
