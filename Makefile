TARGET := iphone:clang:latest:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = TikTok

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidGlassToggle
LiquidGlassToggle_FILES = Tweak.x
LiquidGlassToggle_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
