Ushahidi - Crowdsourcing Crisis Information
===========================================

`Ushahidi`_ (Swahili for "testimony" or "witness") is a crowdsourcing
application created in the aftermath of Kenya's disputed 2007
presidential election that enables local observers to submit reports
using their mobile phones or the internet, while simultaneously creating
a temporal and geospatial archive of events.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- Ushahidi configurations:
   
   - Ushahidi Platform v6 is installed from the pinned official release
     archive in ``/var/www/ushahidi``.
   - PHP 7.4 is installed from the deb.sury.org Trixie repository because the
     current Ushahidi backend requires PHP 7.4 and excludes PHP 8. Debian is
     preferred, but cannot satisfy that contract; Sury is a third-party,
     best-effort source without a guaranteed security-coverage window.
   - Laravel is updated from the official ``laravel/framework`` Git repository
     to stable v8.83.29. The complete Laravel 8.x repository is retained at
     ``/usr/local/share/turnkey-ushahidi/laravel-framework.git`` for update,
     recovery, and provenance auditing.
   - ``turnkey-ushahidi-update`` checks or applies official v6 stable patch
     releases whose complete artifact tuple has been vetted in a TurnKey
     package update, without replacing the database, uploads, or local secrets.
   - ``turnkey-ushahidi-laravel-update`` independently checks or applies stable
     Laravel 8.x tags from the official Git history. It never pulls into live
     files: a verified generation is staged and activated atomically, with
     automatic rollback when its health check fails.

- SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA configured as a localhost-only application submission service.
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL: username **root**
-  Adminer: username **adminer**
-  Ushahidi: username is email set on first boot

Application security updates
----------------------------

Operating-system and PHP package updates continue through APT. The two
application-local update channels have different trust and compatibility
boundaries::

    turnkey-ushahidi-update --check
    turnkey-ushahidi-update --apply --dry-run

    turnkey-ushahidi-laravel-update --check
    turnkey-ushahidi-laravel-update --apply --dry-run
    turnkey-ushahidi-laravel-update --apply
    turnkey-ushahidi-laravel-update --rollback

The Laravel command accepts only non-prerelease ``v8.*`` tags that descend from
the installed version and the CVE-2024-52301 fix, remain on the official 8.x
history, and keep the package dependency/autoload contract unchanged. It keeps
the previous verified generation for explicit recovery. See
``man turnkey-ushahidi-laravel-update`` for verification and recovery details.

Laravel 8 is beyond its formal support window. TurnKey accepts the official
8.x repository as a best-effort humanitarian-appliance maintenance channel
because upstream has made post-EOL security releases, including v8.83.28 for
CVE-2024-52301. There is no SLA or guarantee that every present or future issue
will be fixed. If upstream stops publishing acceptable stable tags, the command
fails closed; administrators should not install branch HEAD or an unverified
fork in place. TurnKey must then review/backport the issue, migrate Ushahidi, or
withdraw the affected update path.


.. _Ushahidi: https://ushahidi.com/
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Adminer: https://www.adminer.org/
