#!/usr/bin/env python

from datetime import datetime
import importlib
import pkgutil
import sys
import traceback

dbv_lib = None

def main():
    start_at = datetime.utcnow()
    try:
        print '*' * 60
        print 'dbv_deploy - start at {}'.format(start_at)
        print '*' * 60

        deploy_init()
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
        print 'dbv_deploy - end at {}'.format(end_at)
        print '*' * 60
        print "dbv_deploy - duration: {}\n".format(end_at - start_at)

def deploy_init():
    print "dbv_deploy - init"

    # Perform check dependencies
    _check_deps()

    # Read config.json
    dbv_lib.read_config_json()

    # Database apps
    print "dbv_deploy - script performed with mysql apps user (octopus) '{}'".format(dbv_lib.config['db_octopus']['mysql_apps']['user'])
    #dbv_lib.extract_revisions('0300900019043', None)
    dbv_lib.build_database_connections_apps()
    #dbv_lib.cleanup_db_apps()
    dbv_lib.build_db_apps()

    # Database reports
    print "dbv_deploy - script performed with mysql reports user (octopus) '{}'".format(dbv_lib.config['db_octopus']['mysql_rep']['user'])
    dbv_lib.build_database_connections_reports()
    #dbv_lib.cleanup_db_reports()
    dbv_lib.build_db_reports()

def _check_deps():
    """
    Check dependencies such as MySQL Connector
    
    Exception is raised if some module does not exist
    """

    global dbv_lib

    print "  check dep 'mysql.connector'"
    if _find_module('mysql.connector') is None:
        raise ImportError('MySQL Connector not found. Please, install or check your configuration')
    else:
        dbv_lib = importlib.import_module('dbv_lib')

def _find_module(full_module_name):
    """
    (source: http://stackoverflow.com/questions/14050281/how-to-check-if-a-python-module-exists-without-importing-it)
    Returns module object if module `full_module_name` can be imported. 

    Returns None if module does not exist. 

    Exception is raised if (existing) module raises exception during its import.
    """
    module = sys.modules.get(full_module_name)
    if module is None:
        module_path_tail = full_module_name.split('.')
        module_path_head = []
        loader = True
        while module_path_tail and loader:
            module_path_head.append(module_path_tail.pop(0))
            module_name = ".".join(module_path_head)
            loader = bool(pkgutil.find_loader(module_name))
            if not loader:
                # Double check if module realy does not exist
                # (case: full_module_name == 'paste.deploy')
                try:
                    importlib.import_module(module_name)
                except ImportError:
                    pass
                else:
                    loader = True
        if loader:
            module = importlib.import_module(full_module_name)

    return module

if __name__ == '__main__':
    main()
