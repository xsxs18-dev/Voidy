TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Voidly

Voidly_FILES = $(wildcard Sources/*.swift)
Voidly_SWIFTFLAGS = -parse-as-library
Voidly_FRAMEWORKS = UIKit SwiftUI
Voidly_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
