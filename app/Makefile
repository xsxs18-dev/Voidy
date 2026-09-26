TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Purify

Purify_FILES = $(wildcard Sources/*.swift)
Purify_SWIFTFLAGS = -parse-as-library
Purify_FRAMEWORKS = UIKit SwiftUI
Purify_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
