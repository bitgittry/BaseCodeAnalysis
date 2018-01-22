#!/usr/bin/env python

from datetime import datetime
import dbv_lib
import sys
import traceback

def main():
    start_at = datetime.utcnow()
    try:
        print '*' * 60
        print 'dbv - start at {}'.format(start_at)
        print '*' * 60

        db_init()
    except:
        print '\n{}'.format('=' * 60)
        print "Exception occorred:"
        print '-' * 60
        traceback.print_exc(file=sys.stdout)
        print '\n{}'.format('=' * 60)
        sys.exit(1)
    finally:
        end_at = datetime.utcnow()
        print '\n{}'.format('*' * 60)
        print 'dbv - end at {}'.format(end_at)
        print '*' * 60
        print "dbv - duration: {}\n".format(end_at - start_at)

def db_init():
    """Drop and initialize a new database"""

    print "dbv - init"

    # Read config.json
    dbv_lib.read_config_json()

    # Database apps
    print "  script performed with mysql user (octopus) '{}'".format(dbv_lib.config['db_octopus']['mysql_apps']['user'])
    dbv_lib.build_database_connections_apps()
    dbv_lib.delete_database(dbv_lib.dba_apps_conn, dbv_lib.config['db_apps']['name'])
    dbv_lib.db_create_apps()

    # Database reports
    print "  script performed with mysql reports (octopus) '{}'".format(dbv_lib.config['db_octopus']['mysql_rep']['user'])
    dbv_lib.build_database_connections_reports()
    dbv_lib.delete_database(dbv_lib.dba_rep_conn, dbv_lib.config['db_reports']['name'])
    dbv_lib.db_create_reports()

if __name__ == '__main__':
    main()
