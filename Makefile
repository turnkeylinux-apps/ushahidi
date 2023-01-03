COMMON_CONF += apache-credit

CREDIT_LOCATION = ~ "^/(?!(.*login|.*admin))"
define CREDIT_STYLE_EXTRA
#turnkey-credit, #turnkey-credit a {
    color: white;
}
endef

PHP_VERSION=7.3
PHP_EXTRA_PINS=libpcre2-8-0 libgd3

include $(FAB_PATH)/common/mk/turnkey/lamp.mk
include $(FAB_PATH)/common/mk/turnkey/composer.mk
include $(FAB_PATH)/common/mk/turnkey/laravel.mk
include $(FAB_PATH)/common/mk/turnkey.mk
