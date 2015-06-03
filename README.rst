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
   
   - Installed from upstream source code to /var/www/ushahidi

- SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL, phpMyAdmin: username **root**
-  Ushahidi: username is email set on first boot


.. _Ushahidi: http://ushahidi.com/
.. _TurnKey Core: http://www.turnkeylinux.org/core
.. _Adminer: http://www.adminer.org/
