TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Voidy

Voidy_FILES = $(wildcard Sources/*.swift Sources/*.m)
Voidy_CFLAGS = -fobjc-arc -fobjc-exceptions
Voidy_SWIFTFLAGS = -parse-as-library -import-objc-header Sources/AppMetadataBridge.h
Voidy_FRAMEWORKS = UIKit SwiftUI
Voidy_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
