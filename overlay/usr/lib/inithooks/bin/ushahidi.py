#!/usr/bin/python
"""Set Ushahidi admin password and email

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively

"""

import re
import sys
import getopt
import inithooks_cache
import subprocess
from subprocess import PIPE
from os.path import *

from dialog_wrapper import Dialog
from mysqlconf import MySQL

def usage(s=None):
    if s:
        print >> sys.stderr, "Error:", s
    print >> sys.stderr, "Syntax: %s [options]" % sys.argv[0]
    print >> sys.stderr, __doc__
    sys.exit(1)

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email='])
    except getopt.GetoptError, e:
        usage(e)

    password = ""
    email = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val
        elif opt == '--email':
            email = val

    if not password:
        d = Dialog('TurnKey Linux - First boot configuration')
        password = d.get_password(
            "Ushahidi Password",
            "Enter new password for the Ushahidi 'admin' account.")

    if not email:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        email = d.get_email(
            "Ushahidi Email",
            "Enter email address for the Ushahidi 'admin' account.",
            "admin@example.com")

    inithooks_cache.write('APP_EMAIL', email)

    command = ["php", join(dirname(__file__), 'ushahidi_pass.php'), password]
    p = subprocess.Popen(command, stdin=PIPE, stdout=PIPE, shell=False)
    stdout, stderr = p.communicate()
    if stderr:
        fatal(stderr)

    cryptpass = stdout.strip()

    m = MySQL()
    m.execute('UPDATE ushahidi.users SET password=\"%s\" WHERE username=\"admin\";' % cryptpass)
    m.execute('UPDATE ushahidi.users SET email=\"%s\" WHERE username=\"admin\";' % email)
    m.execute('UPDATE ushahidi.settings SET value=\"%s\" WHERE settings.key=\"site_email\";' % email)

if __name__ == "__main__":
    main()

