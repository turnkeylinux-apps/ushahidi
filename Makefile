PHP56 = y

COMMON_CONF = apache-credit

CREDIT_LOCATION = ~ "^/(?!(.*login|.*admin))"
define CREDIT_STYLE_EXTRA
#turnkey-credit, #turnkey-credit a {
    color: white;
}
endef

include $(FAB_PATH)/common/mk/turnkey/lamp.mk
include $(FAB_PATH)/common/mk/turnkey.mk
