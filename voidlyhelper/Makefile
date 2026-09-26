TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = voidlyhelper

voidlyhelper_FILES = main.m
voidlyhelper_CFLAGS = -fobjc-arc -Wall -Wno-unused-function
voidlyhelper_FRAMEWORKS = Foundation
voidlyhelper_CODESIGN_FLAGS = -Sentitlements.plist
voidlyhelper_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
