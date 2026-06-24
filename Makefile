THEOS_DEVICE_IP = localhost
THEOS_DEVICE_PORT = 2222

ARCHS = arm64 arm64e
TARGET = iphone:latest:latest

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = xhbb
xhbb_FILES = Tweak.xm
xhbb_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk