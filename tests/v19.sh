#!/bin/bash -e

set -o pipefail

SOURCE_RECORD=/usr/local/share/turnkey-ushahidi/source
PHP_RUNTIME_RECORD=/usr/local/share/turnkey-ushahidi/php-runtime
LARAVEL_RECORD=/usr/local/share/turnkey-ushahidi/laravel-runtime
LARAVEL_REPO=/usr/local/share/turnkey-ushahidi/laravel-framework.git
WEBROOT=/var/www/ushahidi
BASE_URL=https://127.0.0.1
ADMIN_EMAIL=admin@example.invalid
ADMIN_PASSWORD=${TKL_TEST_APP_PASS:?missing exact-harness application password}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

record_value() {
    key=$1
    value=$(sed -n "s/^${key}=//p" "$SOURCE_RECORD")
    [ -n "$value" ] || fail "missing source record key: $key"
    printf '%s\n' "$value"
}

runtime_value() {
    key=$1
    value=$(sed -n "s/^${key}=//p" "$PHP_RUNTIME_RECORD")
    [ -n "$value" ] || fail "missing PHP runtime record key: $key"
    printf '%s\n' "$value"
}

apt_candidate_has_priority() {
    expected=$1
    awk -v expected="$expected" '
        $1 == "Candidate:" { candidate = $2; next }
        $1 == "***" && $2 == candidate && $3 == expected { found = 1 }
        $1 == candidate && $2 == expected { found = 1 }
        END { exit candidate == "" || candidate == "(none)" || !found }
    '
}

[ -f "$SOURCE_RECORD" ] || fail "missing installed source record"
[ -f "$PHP_RUNTIME_RECORD" ] || fail "missing installed PHP runtime record"
[ -f "$LARAVEL_RECORD" ] || fail "missing installed Laravel runtime record"
[ "$(record_value version)" = v6.0.17 ] || fail "unexpected Ushahidi version"
[ "$(record_value tag_commit)" = 8b50289a360cd6a17d64f663dd7ec68369863f2f ] || fail "unexpected release tag commit"
[ "$(record_value archive_sha256)" = 9dd9fdfdb563400d0bdc2ba991a2552661541c304c4cadfd79c29539315a8e4e ] || fail "unexpected release archive digest"
lock_sha256=$(sha256sum "$WEBROOT/platform/composer.lock" | awk '{print $1}')
[ "$(record_value upstream_composer_lock_sha256)" = cf38243e034da38b939ef548d8acd0531f26a8b5676d747b29d028000992440c ] || fail "unexpected upstream Composer lock digest"
[ "$lock_sha256" = "$(record_value composer_lock_sha256)" ] || fail "installed lock differs from source record"
[ "$lock_sha256" = "$(sed -n 's/^composer_lock_sha256=//p' "$LARAVEL_RECORD")" ] || fail "installed lock differs from Laravel record"

[ "$(stat -c '%U:%G %a' "$WEBROOT/platform/.env")" = "root:www-data 640" ] || fail "unsafe application environment ownership or mode"
grep -qx 'QUEUE_DRIVER=redis' "$WEBROOT/platform/.env" || fail "Redis queue is not configured"
grep -qx 'CACHE_DRIVER=redis' "$WEBROOT/platform/.env" || fail "Redis cache is not configured"

apache2ctl configtest >/dev/null
apache2ctl -S 2>&1 | grep -q '/etc/apache2/sites-enabled/ushahidi.conf' || fail "Ushahidi Apache site is not enabled"
redis-cli ping | grep -qx PONG || fail "Redis is not responding"
mysqladmin ping >/dev/null || fail "MariaDB is not responding"

laravel_version=$(turnkey-artisan --version | sed -n 's/^Laravel Framework //p')
[ "$laravel_version" = 8.83.29 ] || fail "unexpected Laravel runtime version"
laravel_tag=$(sed -n 's/^tag=//p' "$LARAVEL_RECORD")
laravel_commit=$(sed -n 's/^commit=//p' "$LARAVEL_RECORD")
laravel_tree=$(sed -n 's/^tree=//p' "$LARAVEL_RECORD")
[ "$laravel_tag" = v8.83.29 ] || fail "unexpected Laravel runtime tag"
[ "$laravel_commit" = d841a226a50c715431952a10260ba4fac9e91cc4 ] || fail "unexpected Laravel runtime commit"
[ "$(sed -n 's/^remote=//p' "$LARAVEL_RECORD")" = https://github.com/laravel/framework.git ] || fail "unexpected Laravel runtime remote"
[ "$(sed -n 's/^repo_path=//p' "$LARAVEL_RECORD")" = "$LARAVEL_REPO" ] || fail "unexpected Laravel repository path"
[ "$(sed -n 's/^security_baseline=//p' "$LARAVEL_RECORD")" = eded6bdfc05af9b5437d107b4d092558fe46292c ] || fail "unexpected Laravel security baseline"
[ "$(git --git-dir="$LARAVEL_REPO" config --get remote.origin.url)" = https://github.com/laravel/framework.git ] || fail "packaged Laravel repository remote mismatch"
[ "$(git --git-dir="$LARAVEL_REPO" rev-parse 'refs/tags/v8.83.29^{commit}')" = "$laravel_commit" ] || fail "packaged Laravel tag binding mismatch"
[ "$(git --git-dir="$LARAVEL_REPO" rev-parse "$laravel_commit^{tree}")" = "$laravel_tree" ] || fail "packaged Laravel tree binding mismatch"
git --git-dir="$LARAVEL_REPO" merge-base --is-ancestor eded6bdfc05af9b5437d107b4d092558fe46292c "$laravel_commit" || fail "Laravel security baseline is not an ancestor"
git --git-dir="$LARAVEL_REPO" merge-base --is-ancestor "$laravel_commit" refs/heads/8.x || fail "Laravel runtime is not on official 8.x history"
[ "$(git --git-dir="$LARAVEL_REPO" show "$laravel_commit:composer.json" | jq -r .name)" = laravel/framework ] || fail "packaged Git tag is not laravel/framework"
grep -Fq '$this->runningInConsole() && $_SERVER['"'"'argv'"'"']' "$WEBROOT/platform/vendor/laravel/framework/src/Illuminate/Foundation/Application.php" || fail "CVE-2024-52301 regression guard is absent"
[ "$(jq -r '.packages[] | select(.name == "laravel/framework") | .version' "$WEBROOT/platform/composer.lock")" = v8.83.29 ] || fail "Composer lock Laravel version mismatch"
[ "$(jq -r '.packages[] | select(.name == "laravel/framework") | .source.reference' "$WEBROOT/platform/composer.lock")" = "$laravel_commit" ] || fail "Composer lock Laravel commit mismatch"
[ "$(jq -r '.packages[] | select(.name == "laravel/framework") | .version' "$WEBROOT/platform/vendor/composer/installed.json")" = v8.83.29 ] || fail "Composer installed Laravel version mismatch"
[ "$(php -r 'require $argv[1]; echo Composer\InstalledVersions::getPrettyVersion("laravel/framework");' "$WEBROOT/platform/vendor/autoload.php")" = v8.83.29 ] || fail "Composer runtime metadata Laravel version mismatch"
php_version=$(php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')
[ "$php_version" = 7.4 ] || fail "unexpected PHP runtime version"
php_package_version=$(dpkg-query -W -f='${Version}' php7.4-cli)
[ "$php_package_version" = "$(runtime_value version)" ] || fail "installed PHP package differs from runtime record"
case "$php_package_version" in
    1:7.4.33-*) ;;
    *) fail "unexpected Sury PHP package version: $php_package_version" ;;
esac
[ "$(runtime_value source)" = "deb.sury.org PHP repository for Debian Trixie" ] || fail "unexpected PHP package source"
[ "$(runtime_value suite)" = trixie ] || fail "unexpected PHP repository suite"
[ "$(runtime_value key_fingerprint)" = 15058500A0235D97F5D10063B188E2B695BD4743 ] || fail "unexpected PHP repository key"
grep -qx 'URIs: https://packages.sury.org/php/' /etc/apt/sources.list.d/php.sources || fail "Sury PHP repository URL is missing"
grep -qx 'Suites: trixie' /etc/apt/sources.list.d/php.sources || fail "Sury PHP repository is not bound to Trixie"
grep -qx 'Enabled: yes' /etc/apt/sources.list.d/php.sources || fail "Sury PHP repository is not enabled"
grep -qx 'Signed-By: /usr/share/keyrings/debsuryorg-archive-keyring.gpg' /etc/apt/sources.list.d/php.sources || fail "Sury PHP repository key binding is missing"
gpg --batch --show-keys --with-colons /usr/share/keyrings/debsuryorg-archive-keyring.gpg 2>/dev/null \
    | grep -q '^fpr:::::::::15058500A0235D97F5D10063B188E2B695BD4743:$' \
    || fail "Sury PHP repository signing-key fingerprint mismatch"
grep -Fqx 'Package: php7.4-* libapache2-mod-php7.4 php-common mlock libc-client2007e libgd3' \
    /etc/apt/preferences.d/php-sury.pref || fail "exact Sury runtime-closure pin is missing"
if [ -e /etc/apt/trusted.gpg.d/debsuryorg-archive.gpg ]; then
    fail "Sury key is also present in apt's global trust directory"
fi
apache2ctl -M 2>/dev/null | grep -q 'php7_module' || fail "Apache is not using the PHP 7.4 module"
if dpkg-query -W -f='${binary:Package} ${db:Status}\n' 'php[89].*' 'libapache2-mod-php[89].*' 2>/dev/null \
    | grep -E '^(php[89]\.|libapache2-mod-php[89]\.)[^ ]* install ok installed$'; then
    fail "a PHP 8+ runtime package is installed alongside PHP 7.4"
fi
zgrep -q 'CVE-2026-6735' /usr/share/doc/php7.4-common/changelog.Debian.gz || fail "Sury PHP security-backport evidence is missing"
apt-get update >/dev/null
upgrade_plan=$(apt-get --simulate upgrade)
if printf '%s\n' "$upgrade_plan" | grep -q '^Remv '; then
    fail "ordinary package upgrade would remove an installed package"
fi
for sury_package in php7.4-cli php7.4-common php7.4-redis libapache2-mod-php7.4 php-common mlock libc-client2007e libgd3; do
    apt-cache policy "$sury_package" | apt_candidate_has_priority 550 \
        || fail "Sury update candidate is not priority 550 for $sury_package"
done

front_page=$(curl -kfsS "$BASE_URL/")
grep -q '<title>PlatformClient</title>' <<< "$front_page" || fail "Ushahidi browser client title is missing"
grep -q '<app-root></app-root>' <<< "$front_page" || fail "Ushahidi browser client root is missing"

token_response=$(curl -ksS -X POST "$BASE_URL/oauth/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode grant_type=password \
    --data-urlencode client_id=ushahidiui \
    --data-urlencode client_secret=35e7f0bca957836d05ca0492211b0ac707671261 \
    --data-urlencode "username=$ADMIN_EMAIL" \
    --data-urlencode "password=$ADMIN_PASSWORD" \
    --data-urlencode 'scope=forms posts' \
    --write-out $'\n%{http_code}')
token_status=${token_response##*$'\n'}
token_json=${token_response%$'\n'*}
if [ "$token_status" != 200 ]; then
    printf 'OAuth response (%s): %s\n' "$token_status" "$token_json" >&2
    find "$WEBROOT/platform/storage/logs" -maxdepth 1 -type f -name '*.log' \
        -exec tail -n 80 {} + >&2
    fail "administrator login returned HTTP $token_status"
fi
access_token=$(printf '%s' "$token_json" | jq -er '.access_token') || fail "administrator login did not return an access token"
[ -n "$access_token" ] || fail "administrator access token is empty"

survey_payload='{"name":"Wave 2 Acceptance Survey","type":"report","description":"TurnKey v19 main-flow check","disabled":false,"color":"#A51A1A"}'
survey_json=$(curl -kfsS -X POST "$BASE_URL/api/v5/surveys" \
    -H "Authorization: Bearer $access_token" \
    -H 'Content-Type: application/json' \
    --data "$survey_payload")
survey_id=$(printf '%s' "$survey_json" | jq -er '.result.id') || fail "survey creation did not return an id"
[ "$(printf '%s' "$survey_json" | jq -r '.result.name')" = "Wave 2 Acceptance Survey" ] || fail "created survey name differs"

survey_read=$(curl -kfsS "$BASE_URL/api/v5/surveys/$survey_id" \
    -H "Authorization: Bearer $access_token")
[ "$(printf '%s' "$survey_read" | jq -r '.result.id')" = "$survey_id" ] || fail "created survey could not be read"
[ "$(printf '%s' "$survey_read" | jq -r '.result.name')" = "Wave 2 Acceptance Survey" ] || fail "survey name was not persisted"
[ "$(printf '%s' "$survey_read" | jq -r '.result.type')" = report ] || fail "survey type was not persisted"
[ "$(printf '%s' "$survey_read" | jq -r '.result.description')" = "TurnKey v19 main-flow check" ] || fail "survey description was not persisted"
[ "$(printf '%s' "$survey_read" | jq -r '.result.disabled')" = false ] || fail "survey enabled state was not persisted"
[ "$(printf '%s' "$survey_read" | jq -r '.result.color')" = '#A51A1A' ] || fail "survey color was not persisted"

post_payload=$(printf '{"title":"Wave 2 Acceptance Post","content":"TurnKey v19 round trip","locale":"en_US","post_content":[],"completed_stages":[],"enabled_languages":{},"base_language":"","type":"report","form_id":%s}' "$survey_id")
post_json=$(curl -kfsS -X POST "$BASE_URL/api/v5/posts" \
    -H "Authorization: Bearer $access_token" \
    -H 'Content-Type: application/json' \
    --data "$post_payload")
post_id=$(printf '%s' "$post_json" | jq -er '.result.id') || fail "post creation did not return an id"
[ "$(printf '%s' "$post_json" | jq -r '.result.title')" = "Wave 2 Acceptance Post" ] || fail "created post title differs"

post_read=$(curl -kfsS "$BASE_URL/api/v5/posts/$post_id" \
    -H "Authorization: Bearer $access_token")
[ "$(printf '%s' "$post_read" | jq -r '.result.id')" = "$post_id" ] || fail "created post could not be read"
[ "$(printf '%s' "$post_read" | jq -r '.result.title')" = "Wave 2 Acceptance Post" ] || fail "post title was not persisted"
[ "$(printf '%s' "$post_read" | jq -r '.result.content')" = "TurnKey v19 round trip" ] || fail "post content was not persisted"
[ "$(printf '%s' "$post_read" | jq -r '.result.locale')" = en_us ] || fail "post locale was not persisted"
[ "$(printf '%s' "$post_read" | jq -r '.result.type')" = report ] || fail "post type was not persisted"
[ "$(printf '%s' "$post_read" | jq -r '.result.form_id')" = "$survey_id" ] || fail "post-to-survey relationship was not persisted"

[ "$(mysql ushahidi -NBe "SELECT COUNT(*) FROM forms WHERE id=$survey_id")" = 1 ] || fail "survey is absent from MariaDB"
[ "$(mysql ushahidi -NBe "SELECT COUNT(*) FROM posts WHERE id=$post_id")" = 1 ] || fail "post is absent from MariaDB"
[ "$(mysql ushahidi -NBe "SELECT COUNT(*) FROM posts WHERE id=$post_id AND form_id=$survey_id")" = 1 ] || fail "post-to-survey relationship is absent from MariaDB"

queue_before=$(redis-cli LLEN queues:default)
turnkey-artisan test:multisitejob >/dev/null
[ "$(redis-cli LLEN queues:default)" -eq $((queue_before + 1)) ] || fail "test job was not queued in Redis"
timeout 30 turnkey-artisan queue:work --once >/dev/null
[ "$(redis-cli LLEN queues:default)" -eq "$queue_before" ] || fail "queued test job was not consumed"
[ "$(grep -Ec '^[^#[:space:]].*www-data /usr/bin/php /var/www/ushahidi/platform/artisan ' /etc/cron.d/ushahidi)" -eq 5 ] || fail "Ushahidi scheduler entries are incomplete"
for scheduled_command in datasource:outgoing datasource:incoming savedsearch:sync notification:queue webhook:send; do
    grep -Eq "^[*]/5  [*] [*] [*] [*] www-data /usr/bin/php /var/www/ushahidi/platform/artisan ${scheduled_command} >/dev/null$" /etc/cron.d/ushahidi \
        || fail "missing exact scheduler entry: $scheduled_command"
done
timeout 30 turnkey-artisan notification:queue >/dev/null

postconf -h inet_interfaces | grep -qx localhost || fail "Postfix is not restricted to localhost"
systemctl is-active --quiet postfix || fail "Postfix local submission service is inactive"
mail_subject="TurnKey Ushahidi acceptance $(date +%s)-$$"
/usr/sbin/sendmail -Am -i -f root@localhost -- www-data@localhost <<EOF
From: root@localhost
To: www-data@localhost
Subject: $mail_subject

Local application submission acceptance transaction.
EOF

# Exercise the packaged Ushahidi updater against a real older release in the
# disposable acceptance container. The fixture is independently bound to the
# official v6.0.16 tag, release archive, and upstream Composer lock. Only the
# paths that the updater promises to preserve remain from the installed v6.0.17
# state; the managed Laravel generation and repository stay separately owned.
ushahidi_fixture=$(mktemp -d /var/lib/turnkey-ushahidi/ushahidi-fixture.XXXXXX)
cleanup_ushahidi_fixture() {
    find "$ushahidi_fixture" -depth -delete
}
trap cleanup_ushahidi_fixture EXIT HUP INT TERM
fixture_archive="$ushahidi_fixture/ushahidi-platform-release-v6.0.16.tar.gz"
fixture_url=https://github.com/ushahidi/platform-release/releases/download/v6.0.16/ushahidi-platform-release-v6.0.16.tar.gz
curl -LfsS "$fixture_url" -o "$fixture_archive"
printf '%s  %s\n' e3abced965cd8dbbea6f619eacc0a9d4363855c952f545bed47b8d53f3e05f2a "$fixture_archive" | sha256sum -c -
[ "$(git ls-remote https://github.com/ushahidi/platform-release.git refs/tags/v6.0.16 | awk 'NR == 1 {print $1}')" = c4bece4dc57d50409628be21079fe4018945cb1b ] \
    || fail "official v6.0.16 tag commit mismatch"
fixture_root=ushahidi-platform-release-v6.0.16
tar -tzf "$fixture_archive" | grep -x "$fixture_root/html/platform/composer.lock" >/dev/null \
    || fail "v6.0.16 fixture lacks Composer lock"
[ "$(tar -xOzf "$fixture_archive" "$fixture_root/html/platform/composer.lock" | sha256sum | awk '{print $1}')" = cf38243e034da38b939ef548d8acd0531f26a8b5676d747b29d028000992440c ] \
    || fail "v6.0.16 upstream Composer lock mismatch"
tar -xzf "$fixture_archive" -C "$ushahidi_fixture"
fixture_webroot="$ushahidi_fixture/$fixture_root/html"

env_sha256_before=$(sha256sum "$WEBROOT/platform/.env" | awk '{print $1}')
laravel_record_sha256_before=$(sha256sum "$LARAVEL_RECORD" | awk '{print $1}')
laravel_refs_sha256_before=$(git --git-dir="$LARAVEL_REPO" show-ref | sha256sum | awk '{print $1}')
git --git-dir="$LARAVEL_REPO" fsck --full --no-dangling >/dev/null || fail "packaged Laravel repository is incomplete before Ushahidi update"
upload_sentinel="$WEBROOT/platform/storage/app/public/turnkey-v19-updater-preservation.txt"
install -o www-data -g www-data -m 0640 /dev/null "$upload_sentinel"
printf 'survey=%s post=%s\n' "$survey_id" "$post_id" > "$upload_sentinel"
upload_sha256_before=$(sha256sum "$upload_sentinel" | awk '{print $1}')

rsync -a --delete \
    --exclude platform/.env \
    --exclude platform/storage/ \
    --exclude platform/composer.lock \
    --exclude platform/vendor/laravel/framework \
    --exclude platform/vendor/composer/installed.json \
    --exclude platform/vendor/composer/installed.php \
    "$fixture_webroot/" "$WEBROOT/"
if rsync -ani --delete \
    --exclude platform/.env \
    --exclude platform/storage/ \
    --exclude platform/composer.lock \
    --exclude platform/vendor/laravel/framework \
    --exclude platform/vendor/composer/installed.json \
    --exclude platform/vendor/composer/installed.php \
    "$fixture_webroot/" "$WEBROOT/" | grep -q .; then
    fail "disposable runtime does not exactly match v6.0.16 outside preserved paths"
fi
cat > "$SOURCE_RECORD" <<EOF
version=v6.0.16
tag_commit=c4bece4dc57d50409628be21079fe4018945cb1b
archive_sha256=e3abced965cd8dbbea6f619eacc0a9d4363855c952f545bed47b8d53f3e05f2a
upstream_composer_lock_sha256=cf38243e034da38b939ef548d8acd0531f26a8b5676d747b29d028000992440c
composer_lock_sha256=$lock_sha256
channel=official Ushahidi v6 stable releases
EOF
[ "$(record_value version)" = v6.0.16 ] || fail "fixture did not enter v6.0.16 state"
[ "$(sha256sum "$WEBROOT/platform/.env" | awk '{print $1}')" = "$env_sha256_before" ] || fail "v6.0.16 fixture replaced application secrets"
[ "$(sha256sum "$upload_sentinel" | awk '{print $1}')" = "$upload_sha256_before" ] || fail "v6.0.16 fixture replaced uploaded data"
[ "$(sha256sum "$LARAVEL_RECORD" | awk '{print $1}')" = "$laravel_record_sha256_before" ] || fail "v6.0.16 fixture replaced managed Laravel state"

update_check=$(turnkey-ushahidi-update --check)
printf '%s\n' "$update_check" | grep -qx 'installed=v6.0.16' || fail "updater fixture installed version mismatch"
printf '%s\n' "$update_check" | grep -qx 'candidate=v6.0.17' || fail "updater candidate version mismatch"
printf '%s\n' "$update_check" | grep -qx 'candidate_commit=8b50289a360cd6a17d64f663dd7ec68369863f2f' || fail "updater tag commit mismatch"
printf '%s\n' "$update_check" | grep -qx 'candidate_archive_sha256=9dd9fdfdb563400d0bdc2ba991a2552661541c304c4cadfd79c29539315a8e4e' || fail "updater archive digest mismatch"
printf '%s\n' "$update_check" | grep -qx 'candidate_composer_lock_sha256=cf38243e034da38b939ef548d8acd0531f26a8b5676d747b29d028000992440c' || fail "updater Composer lock mismatch"
printf '%s\n' "$update_check" | grep -qx 'channel=TurnKey-vetted official Ushahidi v6 stable releases' || fail "updater trust channel mismatch"
printf '%s\n' "$update_check" | grep -qx 'status=update-available' || fail "updater fixture did not report update"

update_apply=$(turnkey-ushahidi-update --apply --dry-run)
printf '%s\n' "$update_apply" | grep -qx 'candidate=v6.0.17' || fail "apply plan candidate mismatch"
printf '%s\n' "$update_apply" | grep -qx 'apply=dry-run verified exact candidate' || fail "apply plan was not verified"
turnkey-ushahidi-update --apply | grep -qx 'apply=complete' || fail "real v6.0.16 to v6.0.17 update did not complete"
[ "$(record_value version)" = v6.0.17 ] || fail "real update did not record v6.0.17"
[ "$(record_value tag_commit)" = 8b50289a360cd6a17d64f663dd7ec68369863f2f ] || fail "real update recorded the wrong tag commit"
[ "$(record_value archive_sha256)" = 9dd9fdfdb563400d0bdc2ba991a2552661541c304c4cadfd79c29539315a8e4e ] || fail "real update recorded the wrong archive digest"
[ "$(record_value upstream_composer_lock_sha256)" = cf38243e034da38b939ef548d8acd0531f26a8b5676d747b29d028000992440c ] || fail "real update recorded the wrong upstream lock"
[ "$(record_value composer_lock_sha256)" = "$lock_sha256" ] || fail "real update replaced the managed Composer lock"
[ "$(sha256sum "$WEBROOT/platform/.env" | awk '{print $1}')" = "$env_sha256_before" ] || fail "real update replaced application secrets"
[ "$(sha256sum "$upload_sentinel" | awk '{print $1}')" = "$upload_sha256_before" ] || fail "real update replaced uploaded data"
[ "$(sha256sum "$LARAVEL_RECORD" | awk '{print $1}')" = "$laravel_record_sha256_before" ] || fail "real update replaced the managed Laravel generation"
[ "$(git --git-dir="$LARAVEL_REPO" show-ref | sha256sum | awk '{print $1}')" = "$laravel_refs_sha256_before" ] || fail "real update changed the packaged Laravel repository refs"
git --git-dir="$LARAVEL_REPO" fsck --full --no-dangling >/dev/null || fail "real update damaged the packaged Laravel repository"
[ "$(turnkey-artisan --version)" = 'Laravel Framework 8.83.29' ] || fail "real update replaced the managed Laravel runtime"

post_update_token_response=$(curl -ksS -X POST "$BASE_URL/oauth/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode grant_type=password \
    --data-urlencode client_id=ushahidiui \
    --data-urlencode client_secret=35e7f0bca957836d05ca0492211b0ac707671261 \
    --data-urlencode "username=$ADMIN_EMAIL" \
    --data-urlencode "password=$ADMIN_PASSWORD" \
    --data-urlencode 'scope=forms posts' \
    --write-out $'\n%{http_code}')
[ "${post_update_token_response##*$'\n'}" = 200 ] || fail "administrator login failed after real update"
post_update_token=$(printf '%s' "${post_update_token_response%$'\n'*}" | jq -er '.access_token') || fail "post-update login returned no access token"
post_update_survey=$(curl -kfsS "$BASE_URL/api/v5/surveys/$survey_id" -H "Authorization: Bearer $post_update_token")
[ "$(printf '%s' "$post_update_survey" | jq -r '.result.name')" = "Wave 2 Acceptance Survey" ] || fail "real update did not preserve the created survey"
post_update_post=$(curl -kfsS "$BASE_URL/api/v5/posts/$post_id" -H "Authorization: Bearer $post_update_token")
[ "$(printf '%s' "$post_update_post" | jq -r '.result.form_id')" = "$survey_id" ] || fail "real update did not preserve the post-to-survey relationship"
[ "$(printf '%s' "$post_update_post" | jq -r '.result.content')" = "TurnKey v19 round trip" ] || fail "real update did not preserve post data"
[ "$(mysql ushahidi -NBe "SELECT COUNT(*) FROM posts WHERE id=$post_id AND form_id=$survey_id")" = 1 ] || fail "real update did not preserve database data"
cleanup_ushahidi_fixture
trap - EXIT HUP INT TERM

laravel_check=$(turnkey-ushahidi-laravel-update --check)
printf '%s\n' "$laravel_check" | grep -qx 'installed=v8.83.29' || fail "Laravel updater installed version mismatch"
printf '%s\n' "$laravel_check" | grep -qx 'installed_commit=d841a226a50c715431952a10260ba4fac9e91cc4' || fail "Laravel updater installed commit mismatch"
printf '%s\n' "$laravel_check" | grep -qx 'candidate=v8.83.29' || fail "Laravel updater stable candidate mismatch"
printf '%s\n' "$laravel_check" | grep -qx 'candidate_commit=d841a226a50c715431952a10260ba4fac9e91cc4' || fail "Laravel updater candidate commit mismatch"
printf '%s\n' "$laravel_check" | grep -qx 'status=up-to-date' || fail "Laravel updater current status mismatch"
laravel_dry_run=$(turnkey-ushahidi-laravel-update --apply --dry-run)
printf '%s\n' "$laravel_dry_run" | grep -qx 'apply=dry-run verified stable candidate' || fail "Laravel updater dry-run was not verified"

# Exercise the updater without relying on future network state. The fixture
# uses the packaged Git objects, rewrites only Git transport to a local bare
# origin, and keeps the updater-visible origin identity official.
laravel_fixture=$(mktemp -d /var/lib/turnkey-ushahidi/laravel-fixture.XXXXXX)
cleanup_laravel_fixture() {
    find "$laravel_fixture" -depth -delete
}
trap cleanup_laravel_fixture EXIT HUP INT TERM
mkdir -p "$laravel_fixture/platform/vendor/composer" "$laravel_fixture/platform/vendor/laravel" "$laravel_fixture/share"
cp -L "$WEBROOT/platform/composer.lock" "$laravel_fixture/platform/composer.lock"
cp -L "$WEBROOT/platform/vendor/composer/installed.json" "$laravel_fixture/platform/vendor/composer/installed.json"
cp -L "$WEBROOT/platform/vendor/composer/installed.php" "$laravel_fixture/platform/vendor/composer/installed.php"
cp -a "$LARAVEL_REPO" "$laravel_fixture/repo.git"
cp -a "$LARAVEL_REPO" "$laravel_fixture/upstream.git"

fixture_env=(
    TURNKEY_LARAVEL_TEST_MODE=1
    TURNKEY_LARAVEL_PLATFORM="$laravel_fixture/platform"
    TURNKEY_LARAVEL_REPO="$laravel_fixture/repo.git"
    TURNKEY_LARAVEL_STATE="$laravel_fixture/state"
    TURNKEY_LARAVEL_RECORD="$laravel_fixture/share/record"
    TURNKEY_LARAVEL_HEALTHCHECK=/bin/true
    TURNKEY_LARAVEL_PHP=/bin/true
    GIT_CONFIG_COUNT=2
    GIT_CONFIG_KEY_0=url.file://$laravel_fixture/upstream.git.insteadOf
    GIT_CONFIG_VALUE_0=https://github.com/laravel/framework.git
    GIT_CONFIG_KEY_1=protocol.file.allow
    GIT_CONFIG_VALUE_1=always
)

env "${fixture_env[@]}" turnkey-ushahidi-laravel-update --bootstrap v8.83.28 --offline >/dev/null
fixture_check=$(env "${fixture_env[@]}" turnkey-ushahidi-laravel-update --check)
printf '%s\n' "$fixture_check" | grep -qx 'installed=v8.83.28' || fail "Laravel fixture did not start on older stable tag"
printf '%s\n' "$fixture_check" | grep -qx 'candidate=v8.83.29' || fail "Laravel fixture did not select newer stable tag"
printf '%s\n' "$fixture_check" | grep -qx 'status=update-available' || fail "Laravel fixture did not report update"
env "${fixture_env[@]}" turnkey-ushahidi-laravel-update --apply --dry-run | grep -qx 'apply=dry-run verified stable candidate' || fail "Laravel fixture dry-run failed"

if env "${fixture_env[@]}" TURNKEY_LARAVEL_HEALTHCHECK=/bin/false turnkey-ushahidi-laravel-update --apply >/dev/null 2>&1; then
    fail "Laravel fixture accepted a failing post-activation health check"
fi
[ "$(sed -n 's/^tag=//p' "$laravel_fixture/share/record")" = v8.83.28 ] || fail "Laravel fixture did not automatically roll back"
env "${fixture_env[@]}" turnkey-ushahidi-laravel-update --apply >/dev/null
[ "$(sed -n 's/^tag=//p' "$laravel_fixture/share/record")" = v8.83.29 ] || fail "Laravel fixture did not apply the stable update"
env "${fixture_env[@]}" turnkey-ushahidi-laravel-update --rollback >/dev/null
[ "$(sed -n 's/^tag=//p' "$laravel_fixture/share/record")" = v8.83.28 ] || fail "Laravel fixture explicit rollback failed"
env "${fixture_env[@]}" turnkey-ushahidi-laravel-update --apply >/dev/null

git --git-dir="$laravel_fixture/upstream.git" update-ref refs/tags/v8.99.1-rc1 "$laravel_commit"
prerelease_check=$(env "${fixture_env[@]}" turnkey-ushahidi-laravel-update --check)
printf '%s\n' "$prerelease_check" | grep -qx 'candidate=v8.83.29' || fail "Laravel updater selected a prerelease tag"
unrelated_commit=$(printf 'unrelated fixture\n' | GIT_AUTHOR_NAME=TurnKey GIT_AUTHOR_EMAIL=release-engineering@turnkeylinux.org GIT_COMMITTER_NAME=TurnKey GIT_COMMITTER_EMAIL=release-engineering@turnkeylinux.org git --git-dir="$laravel_fixture/upstream.git" commit-tree "$laravel_tree")
git --git-dir="$laravel_fixture/upstream.git" update-ref refs/tags/v8.99.0 "$unrelated_commit"
if env "${fixture_env[@]}" turnkey-ushahidi-laravel-update --check >/dev/null 2>&1; then
    fail "Laravel updater accepted an unrelated stable-looking tag"
fi
[ "$(sed -n 's/^tag=//p' "$laravel_fixture/share/record")" = v8.83.29 ] || fail "fail-closed fixture changed the active runtime"
cleanup_laravel_fixture
trap - EXIT HUP INT TERM

if [ -n "${TKL_TEST_RESULT:-}" ]; then
    cat > "$TKL_TEST_RESULT" <<EOF
package_source=official Ushahidi platform-release v6.0.17 tag 8b50289a360cd6a17d64f663dd7ec68369863f2f
installed_version=Ushahidi v6.0.17, Laravel 8.83.29 ($laravel_commit from official Git), PHP 7.4 ($php_package_version from deb.sury.org)
runtime_checks=administrator OAuth login, survey and post create-read, MariaDB, Redis queue, cron scheduler, Apache client, and accepted localhost-only mail submission passed
updater_command=turnkey-ushahidi-update --check/--apply --dry-run; real v6.0.16 to v6.0.17 apply; turnkey-ushahidi-laravel-update --check/--apply --dry-run/--rollback
updater_result=verified real Ushahidi v6.0.16 to v6.0.17 transition with database, upload, secret, and managed Laravel preservation; verified Laravel stable-tag update, rollback, and fail-closed fixture
updater_channel=official Ushahidi v6 stable releases plus official Laravel 8.x stable Git tags (best-effort, no guaranteed coverage)
integrity_evidence=Ushahidi archive SHA256 9dd9fdfdb563400d0bdc2ba991a2552661541c304c4cadfd79c29539315a8e4e; upstream Composer lock SHA256 cf38243e034da38b939ef548d8acd0531f26a8b5676d747b29d028000992440c; Laravel commit $laravel_commit tree $laravel_tree; installed Composer lock SHA256 $lock_sha256
EOF
fi

echo "PASS: Ushahidi login, survey/post round trip, database, queue, scheduler, and both update channels"
echo "ushahidi=v6.0.17 tag_commit=8b50289a360cd6a17d64f663dd7ec68369863f2f laravel=v8.83.29 laravel_commit=$laravel_commit"
