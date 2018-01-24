#!/usr/bin/env python

# This script provides functions/helpers to manage database creation/upgrading

import codecs
from datetime import datetime
import json
import mysql.connector
import os
import re
import subprocess
import sys
import tempfile
import traceback
import uuid

__dbvmap__ = {}
config = None
dba_apps_conn = None
dba_rep_conn = None
apps_conn = None
rep_conn = None

def build_database_connections_apps():
    """Build database connections for dba, applications"""

    global dba_apps_conn
    global apps_conn

    mysql_apps_config = config['db_octopus']['mysql_apps']

    # dba connection apps
    dba_apps_conn = json_deep_copy(mysql_apps_config)
    # connection apps
    apps_conn = json_deep_copy(mysql_apps_config)
    apps_conn["database"] = config['db_apps']['name']

def build_database_connections_reports():
    """Build database connections for dba, reports"""

    global dba_rep_conn
    global rep_conn

    mysql_rep_config = config['db_octopus']['mysql_rep']

    # dba connection reports
    dba_rep_conn = json_deep_copy(mysql_rep_config)
    # connection reports
    rep_conn = json_deep_copy(mysql_rep_config)
    rep_conn["database"] = config['db_reports']['name']

def build_db_apps():
    """Build MySQL database apps and related users (included privileges)"""

    print "dbv - build database apps"

    create_user_apps_service()
    db_create_or_upgrade_apps()
    create_user_and_privileges(dba_apps_conn, config['db_apps'])

def db_create_or_upgrade_apps():
    """Create or upgrade database apps"""

    print "dbv - create or upgrade database apps"
    if not mysql_test_database_exists(dba_apps_conn, config['db_apps']['name']):
        db_create_apps()
    else:
        db_upgrade_apps()

def db_create_apps():
    """Create database apps"""

    print "dbv - create database apps"
    _init_dbvmap()

    print "  creation database '{}' ... ".format(config['db_apps']['name']),
    mysql_new_database(dba_apps_conn, config['db_apps']['name'])
    print "done"

    mysql_apps_config = dba_apps_conn

    # get mysql command and arguments
    basedir = mysql_get_basedir(dba_apps_conn)
    mysql_cmd = mysql_get_mysql_cmd(basedir)
    config_options = config['options']
    config_options['my_option_file'] = create_my_option_file(mysql_apps_config, config_options, 'apps')
    config_options['db_name'] = config['db_apps']['name']
    mysql_args = mysql_get_mysql_cmd_args(mysql_apps_config, config_options)

    # run initialize sql file
    init_sql = os.path.join(__dbvmap__['data.revisions.initialize'], config['dbv']['init_sql'])
    print "  initialize database '{}' ... ".format(init_sql),
    mysql_run_batch_sql(mysql_cmd, mysql_args, init_sql)
    print "done"

    _apply_revisions_and_routines(mysql_cmd, mysql_args, config['dbv']['init_rev'], config['dbv']['last_rev'])

def db_upgrade_apps():
    """Upgrade database apps"""

    print "dbv - upgrade database apps"
    _init_dbvmap()

    print "  upgrading database '{}' ... ".format(config['db_apps']['name']),

    mysql_apps_config = dba_apps_conn

    # get mysql command and arguments
    basedir = mysql_get_basedir(mysql_apps_config)
    mysql_cmd = mysql_get_mysql_cmd(basedir)
    config_options = config['options']
    config_options['my_option_file'] = create_my_option_file(mysql_apps_config, config_options, 'apps')
    config_options['db_name'] = config['db_apps']['name']
    mysql_args = mysql_get_mysql_cmd_args(mysql_apps_config, config_options)

    # get current revision number
    init_rev = _get_current_dbv_version(apps_conn)
    print "current version '{}'".format(init_rev)

    _apply_revisions_and_routines(mysql_cmd, mysql_args, init_rev, config['dbv']['last_rev'])

def _apply_revisions_and_routines(mysql_cmd, mysql_args, init_rev, last_rev):
    """Apply revisions and routines"""

    global config

    count = _count_revisions_available(init_rev, last_rev)
    if count > 0:
        if config['options']['disable_rev_stored_routines_when_proc']:
            proc_sql = os.path.join(__dbvmap__['dbv_base'], 'proc.sql')
            config['dbv']['rev_stored_routines'] = not os.path.exists(proc_sql)

        revs_file = extract_revisions(init_rev, last_rev)
        print "  run batch '{}' ... ".format(revs_file),
        mysql_run_batch_sql(mysql_cmd, mysql_args, revs_file)
        print "done"
        _create_or_upgrade_routines(mysql_cmd, mysql_args)
    else:
        print "  no new revisions available"

def cleanup_db_apps():
    """Clean up MySQL database apps and related users (included privileges)"""

    print "dbv - cleanup database apps"

    # Delete user apps and revoke privileges
    hostnames = config['db_apps']['host'].split(',')
    for hostname in hostnames:
        _delete_user(dba_apps_conn, config['db_apps']['user'], hostname)

    # Delete user application service and revoke privileges
    _delete_user(dba_apps_conn, config['db_apps_service']['user'], config['db_apps_service']['host'])

    # Flush privileges (clean cache)
    mysql_flush_privileges(dba_apps_conn)

    # Delete database apps
    delete_database(dba_apps_conn, config['db_apps']['name'])

def build_db_reports():
    """Build MySQL database reports and related users (included privileges)"""

    print "dbv - build database reports"

    db_create_or_upgrade_reports()
    create_user_and_privileges(dba_rep_conn, config['db_reports'])

def db_create_or_upgrade_reports():
    """Create or upgrade database reports"""

    print "dbv - create or upgrade database reports"
    if not mysql_test_database_exists(dba_rep_conn, config['db_reports']['name']):
        db_create_reports()
#    else:
#        db_upgrade_reports()

def db_create_reports():
    """Create database reports"""

    print "dbv - create database reports"
    print "  creation database reports '{}' ... ".format(config['db_reports']['name']),
    if not mysql_test_database_exists(dba_rep_conn, config['db_reports']['name']):
        mysql_new_database(dba_rep_conn, config['db_reports']['name'])
        print "done"
    else:
        print "already exists"

def cleanup_db_reports():
    """Clean up MySQL database reports and related users (included privileges)"""

    print "dbv - cleanup database reports"

    # Delete user reports and revoke privileges
    hostnames = config['db_reports']['host'].split(',')
    for hostname in hostnames:
        _delete_user(dba_rep_conn, config['db_reports']['user'], hostname)

    # Flush privileges (clean cache)
    mysql_flush_privileges(dba_rep_conn)

    # Delete database reports
    delete_database(dba_rep_conn, config['db_reports']['name'])

def create_user_apps_service():
    """Create user application service if not exists"""

    print "dbv - create user applications service"
    print "  creation user '{}@{}' ... ".format(config['db_apps_service']['user'], config['db_apps_service']['host']),
    if not mysql_test_user_exists(dba_apps_conn, config['db_apps_service']['user'], config['db_apps_service']['host']):
        mysql_new_user(dba_apps_conn, config['db_apps_service']['user'], config['db_apps_service']['host'], config['db_apps_service']['password'])
        print "done"
        # it's not possible testing global privileges as per database'
        print "  grant user '{}@{}' to '*.*' ... ".format(config['db_apps_service']['user'], config['db_apps_service']['host']),
        mysql_grant_privileges(dba_apps_conn, config['db_apps_service']['user'], config['db_apps_service']['host'], config['db_apps_service']['priv_type'])
        print "done"
        print "    priv_type: '{}'".format(config['db_apps_service']['priv_type'])
    else:
        print "already exists"

def create_user_and_privileges(connection, db_user):
    """Create user if not exists and grants privilges"""

    print "dbv - create user and privileges"
    hostnames = db_user['host'].split(',')
    for hostname in hostnames:
        _create_user(connection, db_user, hostname)
        _grant_user_privileges(connection, db_user, hostname)

def extract_revisions(init_rev, last_rev):
    """Extract revisions sql file based on given inputs"""

    print "dbv - extract revisions"
    _init_dbvmap()
    _guard_revisions(init_rev, last_rev)
    revs_file = os.path.join(__dbvmap__['deploy'], 'revs_{}_{}.sql'.format(init_rev, last_rev))
    _build_revisions_file(init_rev, last_rev, revs_file)
    return revs_file

def _init_dbvmap():
    global __dbvmap__

    dbv_base = _get_dbv_base_folder()
    __dbvmap__ = {
        'dbv_base':dbv_base,
        'compiled':os.path.join(dbv_base, 'compiled'),
        'data':os.path.join(dbv_base, 'data'),
        'data.revisions':'revisions',
        'data.revisions.initialize':'initialize',
        'deploy':os.path.join(dbv_base, 'deploy'),
        'stored_routines':os.path.join(dbv_base, 'stored_routines')
    }

    __dbvmap__['data.revisions'] = os.path.join(__dbvmap__['data'], __dbvmap__['data.revisions'])
    __dbvmap__['data.revisions.initialize'] = os.path.join(__dbvmap__['data.revisions'], __dbvmap__['data.revisions.initialize'])

def _get_dbv_base_folder():
    """Return base dbv folder"""

    dbv_base = os.path.join(config['extract_path'], 'dbv')
    return dbv_base

def delete_database(connection, schema):
    print "  deleting database '{}' ... ".format(schema),
    if mysql_test_database_exists(connection, schema):
        mysql_delete_database(connection, schema)
        print "done"
    else:
        print "not exists"

def _create_user(connection, db_user, hostname):
    print "  creation user '{}@{}' ... ".format(db_user['user'], hostname),
    if not mysql_test_user_exists(connection, db_user['user'], hostname):
        mysql_new_user(connection, db_user['user'], hostname, db_user['password'])
        print "done"
    else:
        print "already exists"

def _delete_user(connection, username, hostname):
    print "  deleting user '{}@{}' ... ".format(username, hostname),
    if mysql_test_user_exists(connection, username, hostname):
        mysql_delete_user(connection, username, hostname)
        print "done"
    else:
        print "not exists"

def _grant_user_privileges(connection, db_user, hostname):
    print "  grant user '{}@{}' to '{}' ... ".format(db_user['user'], hostname, db_user['name']),
    if not mysql_test_user_grants(connection, db_user['user'], db_user['name'], hostname):
        mysql_grant_privileges(connection, db_user['user'], hostname, db_user['priv_type'], db_user['priv_level'])
        print "done"
        print "    priv_type: '{}'".format(db_user['priv_type'])
        print "    priv_level: '{}'".format(db_user['priv_level'])
    else:
        print "already granted"

def _revoke_user_privileges(connection, db_user, hostname):
    print "  revoke on '{}' from '{}@{}' ... ".format(db_user['priv_level'], db_user['user'], hostname),
    if mysql_test_user_grants(connection, db_user['user'], db_user['name'], hostname):
        mysql_revoke_privileges(connection, db_user['user'], hostname, priv_level=db_user['priv_level'])
        print "done"
    else:
        print "no privileges"

def _count_revisions_available(init_rev, last_rev):
    """Count available revisions based on given inputs"""

    _guard_revisions(init_rev, last_rev)
    revs_dirs = os.listdir(__dbvmap__['data.revisions'])
    count = 0
    for d in revs_dirs:
        if ((re.match(r"^\d+$", d) and float(d) > float(init_rev)) 
            and (last_rev is None or (re.match(r"^\d+$", d) and float(d) <= float(last_rev)))):
            count += 1

    return count

def _guard_revisions(init_rev, last_rev):
    if re.match(r"^\d+$", init_rev) is None:
        raise TypeError('Revision init_rev is required as an integer')
    if not last_rev is None:
        if re.match(r"^\d+$", last_rev) is None:
            raise TypeError('Revision last_rev is required as an integer')

def _build_revisions_file(init_rev, last_rev, revs_file):
    """Build revisions file based on given inputs (init_rev < rev <= last_rev)"""

    print "  generate revisions file from '{}' to '{}' ... ".format(init_rev, last_rev),
    revs_txt = os.path.join(__dbvmap__['deploy'], 'revs_{}_{}.txt'.format(init_rev, last_rev))
    _build_revisions_file_available(init_rev, last_rev, revs_txt)

    work_file = os.path.join(__dbvmap__['deploy'], str(uuid.uuid4()) + ".tmp")
    with codecs.open(work_file, encoding='utf-8', mode='w+') as ftmp, open(revs_txt, 'r') as frev:
        ftmp.write(u"--  generate revisions file from '{}' to '{}'\n".format(init_rev, last_rev).encode('utf-8'))
        _dbv_revisions_header(ftmp)
        _dbv_revisions_content(ftmp, frev)

    print "done"

    if os.path.exists(revs_file):
        os.remove(revs_file)
    os.rename(work_file, revs_file)
    os.remove(revs_txt)

def _build_revisions_file_available(init_rev, last_rev, revs_txt):
    """Build file of available revisions based on given inputs"""

    with open(revs_txt, 'w') as frev:
        revs_dirs = os.listdir(__dbvmap__['data.revisions'])
        for d in revs_dirs:
            if ((re.match(r"^\d+$", d) and float(d) > float(init_rev))
                and (last_rev is None or (re.match(r"^\d+$", d)
                and float(d) <= float(last_rev)))):
                frev.write(d)
                frev.write('\n')

def _dbv_revisions_header(frev):
    """Write revisions header"""

    frev.write(u'SET character_set_client  = utf8;\n'.encode('utf-8'))
    frev.write(u'SET character_set_results = utf8;\n'.encode('utf-8'))
    frev.write(u'SET collation_connection  = utf8_general_ci;\n\n'.encode('utf-8'))

def _dbv_revisions_content(fout, frev):
    """Write revisions content given revisions file"""

    for rev in frev:
        rev = rev.rstrip('\n')
        base_path = os.path.join(__dbvmap__['data.revisions'], rev)

        fout.write(u'-- {{START}}: {}\n\n'.format(rev).encode('utf-8'))

        if config['dbv']['rev_schema']:
            _append_content_to_file(os.path.join(base_path, 'schema.sql'), fout)

        if config['dbv']['rev_stored_routines']:
            _append_content_to_file(os.path.join(base_path, 'storedProcedures.sql'), fout)

        if config['dbv']['rev_data']:
            _append_content_to_file(os.path.join(base_path, 'data.sql'), fout)

        if config['dbv']['rev_reports']:
            _append_content_to_file(os.path.join(base_path, 'reports.sql'), fout)

        if config['dbv']['rev_multilingual']:
            _append_content_to_file(os.path.join(base_path, 'multilingual_references.sql'), fout)

        if config['dbv']['rev_system_components']:
            _append_content_to_file(os.path.join(base_path, 'systemcomponents.sql'), fout)
            _append_content_to_file(os.path.join(base_path, 'controller_changes.sql'), fout)
            _append_content_to_file(os.path.join(base_path, 'method_changes.sql'), fout)
            _append_content_to_file(os.path.join(base_path, 'ribbon_changes.sql'), fout)
            _append_content_to_file(os.path.join(base_path, 'internal_page_changes.sql'), fout)
            _append_content_to_file(os.path.join(base_path, 'page_method_linking_changes.sql'), fout)

        fout.write(u"UPDATE gaming_system_versions SET dbv_version = '{}' WHERE system_version_id = 1;\n\n".format(rev).encode('utf-8'))
        fout.write(u'-- {{END}}: {}\n\n'.format(rev).encode('utf-8'))

def _append_content_to_file(fin, fout):
    """Append content safely from input (fin) file to output (fout) file"""

    if os.path.exists(fin) and os.path.getsize(fin) > 0:
        with codecs.open(fin, mode='r', encoding='utf-8') as f:
            content = f.read()

            # Replace all references to DEFINER with DEFINER=`bit8_admin`@`127.0.0.1`
            if 'DEFINER' in content:
                content = re.sub(r'DEFINER[\s]*=[\s]*`[^`]+`@[\s]*`[^`]+`', r'DEFINER=`bit8_admin`@`127.0.0.1` ', content)

            # Replace all references of UpdateExistingReport to avoid issue during MySQL execution
            if 'UpdateExistingReport' in content:
                content = re.sub(r"(?s)((SELECT UpdateExistingReport).+?,\s1\));", r'\1 INTO @updateExistingReport;', content)

            ## ComponentsController
            if 'ComponentsControllerCreate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsControllerCreate).+?'\));", r'\1 INTO @ComponentsController;', content)
            if 'ComponentsControllerDelete' in content:
                content = re.sub(r"(?s)((SELECT ComponentsControllerDelete).+?'\));", r'\1 INTO @ComponentsController;', content)
            if 'ComponentsControllerUpdate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsControllerUpdate).+?'\));", r'$1 INTO @ComponentsController;', content)
            ## End-ComponentsController

            ## ComponentsFunction
            if 'ComponentsFunctionCreate' in content:
                content = re.sub(r'(?s)((SELECT ComponentsFunctionCreate).+?,\s(0|1)\));', r'\1 INTO @ComponentsFunction;', content)
            if 'ComponentsFunctionDelete' in content:
                content = re.sub(r"(?s)((SELECT ComponentsFunctionDelete).+?'\));", r'\1 INTO @ComponentsFunction;', content)
            if 'ComponentsFunctionUpdate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsFunctionUpdate).+?'\));", r'\1 INTO @ComponentsFunction;', content)
            ## End-ComponentsFunction

            ## ComponetsInternal
            if 'ComponentsInternalPageCreate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsInternalPageCreate).+?'\));", r'\1 INTO @ComponetsInternal;', content)
            if 'ComponentsInternalPageDelete' in content:
                content = re.sub(r"(?s)((SELECT ComponentsInternalPageDelete).+?'\));", r'\1 INTO @ComponetsInternal;', content)
            if 'ComponentsInternalPageUpdate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsInternalPageUpdate).+?'\));", r'\1 INTO @ComponetsInternal;', content)
            ## End-ComponetsInternal

            ## ComponentsPageMethodLinking
            if 'ComponentsPageMethodLinkingCreate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsPageMethodLinkingCreate).+?'\));", r'\1 INTO @ComponentsPageMethodLinking;', content)
            if 'ComponentsPageMethodLinkingDelete' in content:
                content = re.sub(r"(?s)((SELECT ComponentsPageMethodLinkingDelete).+?'\));", r'\1 INTO @ComponentsPageMethodLinking;', content)
            ## End-ComponentsPageMethodLinking

            ## ComponentsRibbon
            if 'ComponentsRibbonCreate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsRibbonCreate).+?'\));", r'\1 INTO @ComponentsRibbon;', content)
            if 'ComponentsRibbonDelete' in content:
                content = re.sub(r"(?s)((SELECT ComponentsRibbonDelete).+?'\));", r'\1 INTO @ComponentsRibbon;', content)
            if 'ComponentsRibbonSaveOrderUpdate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsRibbonSaveOrderUpdate).+?'\));", r'\1 INTO @ComponentsRibbon;', content)
            if 'ComponentsRibbonUpdate' in content:
                content = re.sub(r"(?s)((SELECT ComponentsRibbonUpdate).+?'\));", r'\1 INTO @ComponentsRibbon;', content)
            ## End-ComponentsRibbon

        fout.write(content)
        fout.write(u'\n\n'.encode('utf-8'))

def _create_or_upgrade_routines(mysql_cmd, mysql_args):
    """Create or upgrade routines"""

    proc_sql = os.path.join(__dbvmap__['dbv_base'], 'proc.sql')
    if os.path.exists(proc_sql):
        print "  deleting procedures ... ",
        mysql_delete_procedures(dba_apps_conn, config['db_apps']['name'])
        print "done"
        print "  run batch '{}' ... ".format(proc_sql),
        mysql_run_batch_sql(mysql_cmd, mysql_args, proc_sql)
        print "done"

def _get_current_dbv_version(connection):
    """Return current dbv version"""

    sqlText = "SELECT dbv_version FROM gaming_system_versions WHERE system_version_id = 1;"
    result = mysql_run_db_command_scalar(connection, sqlText)
    if result is None:
        result = 0

    return result

def read_config_json():
    """Read config file in json format"""

    global config
    print "  read config.json"

    base_path = os.path.abspath(__file__)
    base_path = os.path.dirname(base_path)
    with open(os.path.join(base_path, 'config.json'), 'r') as fp:
        config = json.load(fp)

def json_deep_copy(data):
    """Deep clone of JSON object"""
    if data is None:
        return data

    data_copy = json.loads(json.dumps(data))
    return data_copy

#===========================================================================
# MySQL utilities
#===========================================================================

#=============================================================================
# Run database commands
#=============================================================================

def mysql_run_db_command_scalar(connection, sqlText, kwargs=None):
    """Run a sql query that return just one value"""

    cnx = None
    cursor = None
    try:
        cnx = mysql.connector.connect(**connection)
        cursor = cnx.cursor()
        cursor.execute(sqlText, kwargs)
        scalar = cursor.fetchone()
        return scalar[0]
    except (ValueError, mysql.connector.Error):
        print "\nTry to execute sql scalar '{}'".format(sqlText)
        raise
    finally:
        if (not cursor is None):
            cursor.close()
        if (not cnx is None):
            cnx.close()

def mysql_run_db_command_no_query(connection, sqlText, kwargs=None):
    """Run a sql query don't need to retrieve data"""

    cnx = None
    cursor = None
    try:
        cnx = mysql.connector.connect(**connection)
        cursor = cnx.cursor()
        cursor.execute(sqlText, kwargs)
        rows_affected = cursor.rowcount
        return rows_affected
    except (ValueError, mysql.connector.Error):
        print "\nTry to execute sql no query '{}'".format(sqlText)
        raise
    finally:
        if (not cursor is None):
            cursor.close()
        if (not cnx is None):
            cnx.close()

def mysql_run_batch_sql(mysql_cmd, mysql_args, batch_sql):
    """Run batch (script) sql using mysql command"""

    try:
        pargs = '"%s" %s < %s' % (mysql_cmd, mysql_args, batch_sql)
        process = subprocess.Popen(pargs, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
        out, err = process.communicate()
        print "\n\n  run batch out:\n%s" % out
        if (not process.returncode == 0):
            print "\n\n  run batch err:\n%s" % err
            raise ValueError(err)
    except:
        print "\nTry to run batch script '{}'".format(batch_sql)
        raise

#=============================================================================
# MySQL metadata or other info related to
#=============================================================================

def mysql_get_basedir(connection):
    """Return basedir's value of MySQL variable"""

    sqlText = "SELECT @@basedir"
    basedir = mysql_run_db_command_scalar(connection, sqlText)
    return basedir

def mysql_get_mysql_cmd(basedir):
    """Return mysql command"""

    mysql_cmd = os.path.join(basedir, 'bin', 'mysql.exe' if not os.name == 'posix' else 'mysql')
    return mysql_cmd

def create_my_option_file(db_config, options, prefix):
    """Create mysql option file"""

    option_file = None
    if options['use_mysql_option_file']:
        option_file = os.path.join(__dbvmap__['deploy'], prefix + '_my.cnf')
        with open(option_file, mode='w') as f:
            f.write('[client]\n')
            f.write('user={}\n'.format(db_config['user']))
            f.write('password={}\n'.format(db_config['password']))
            f.write('host={}\n'.format(db_config['host']))
            f.write('port={}\n'.format(db_config['port']))

    return option_file

def mysql_get_mysql_cmd_args(db_config, options):
    """Return mysql args to be used on command line"""

    my_args = []

    if options['use_mysql_option_file']:
        my_args.append('--defaults-file={}'.format(options['my_option_file']))
    else:
        my_args.append('--user={}'.format(db_config['user']))
        my_args.append('--password={}'.format(db_config['password']))
        my_args.append('--host={}'.format(db_config['host']))
        my_args.append('--port={}'.format(db_config['port']))

    my_args.append('--batch')
    my_args.append('--comments')
    my_args.append('--compress')
    my_args.append('--default-character-set=utf8')
    my_args.append('--line-numbers')

    if options['db_name']:
        my_args.append('--database={}'.format(options['db_name']))

    mysql_args = ' '.join(my_args)
    return mysql_args

#=============================================================================
# Operative functions
#=============================================================================

def mysql_new_database(connection, new_schema):
    """Add new MySQL database"""

    sqlText = "CREATE DATABASE {} DEFAULT CHARACTER SET 'utf8';".format(new_schema)
    mysql_run_db_command_no_query(connection, sqlText)

def mysql_delete_database(connection, schema):
    """Delete MySQL database"""

    sqlText = "DROP DATABASE {};".format(schema)
    mysql_run_db_command_no_query(connection, sqlText)

def mysql_new_user(connection, username, hostname='%', password=None):
    """Add new MySQL user"""

    is_native_password = password is None or not password
    if (is_native_password):
        sqlText = "CREATE USER %s@%s IDENTIFIED WITH mysql_native_password AS '*ABCDEFGHIJKLMNOPQRSTUVWXYZ';" # the "AS..." part to bypass validate_password plugin in case no password set
        data = (username, hostname)
    else:
        sqlText = "CREATE USER %s@%s IDENTIFIED BY %s;"
        data = (username, hostname, password)

    mysql_run_db_command_no_query(connection, sqlText, data)

def mysql_delete_user(connection, username, hostname='%'):
    """Delete a MySQL user and their privileges"""

    sqlText = "DROP USER %s@%s;"
    data = (username, hostname)
    mysql_run_db_command_no_query(connection, sqlText, data)

def mysql_grant_privileges(connection, username, hostname='%', priv_type='ALL', priv_level='*.*'):
    """Grant MySQL privileges to specified user"""

    sqlText = "GRANT {} ON {} TO '{}'@'{}';".format(priv_type, priv_level, username, hostname)
    mysql_run_db_command_no_query(connection, sqlText)

def mysql_revoke_privileges(connection, username, hostname='%', priv_type='ALL', priv_level='*.*', auto_flush=False):
    """Revoke MySQL privileges to specified user"""

    if 'ALL' == priv_type:
        sqlText = "REVOKE ALL, GRANT OPTION FROM '{}'@'{}';".format(username, hostname)
    else:
        sqlText = "REVOKE {} ON {} FROM '{}'@'{}';".format(priv_type, priv_level, username, hostname)
    mysql_run_db_command_no_query(connection, sqlText)

    if auto_flush:
        mysql_flush_privileges(connection)

def mysql_flush_privileges(connection):
    """Reloads the privileges from the grant tables in the mysql database"""

    sqlText = "FLUSH PRIVILEGES;"
    mysql_run_db_command_no_query(connection, sqlText)

def mysql_delete_procedures(connection, database):
    """Delete MySQL procedures from specified database"""

    sqlText = "DELETE FROM mysql.proc WHERE db = %(db)s;"
    data = {
        'db': database
    }
    mysql_run_db_command_no_query(connection, sqlText, data)

#=============================================================================
# Test functions
#=============================================================================

def mysql_test_database_exists(connection, schema):
    """Test if MySQL database exists"""

    sqlText = "SELECT COUNT(*) AS counter FROM information_schema.SCHEMATA where `schema_name` = %(schema_name)s;"
    data = {
        'schema_name': schema
    }
    result = mysql_run_db_command_scalar(connection, sqlText, data)
    return (result == 1)

def mysql_test_user_exists(connection, username, hostname):
    """Test if MySQL user exists"""

    sqlText = "SELECT COUNT(*) AS counter FROM mysql.user WHERE `user` = %s and `host` = %s;"
    data = (username, hostname)
    result = mysql_run_db_command_scalar(connection, sqlText, data)
    return (result == 1)

def mysql_test_user_grants(connection, username, database, hostname='%'):
    """Test if MySQL user grants access to specified database"""

    sqlText = "SELECT COUNT(*) AS counter FROM mysql.db WHERE `user` = %s AND `host` = %s AND db = %s;"
    data = (username, hostname, database)
    result = mysql_run_db_command_scalar(connection, sqlText, data)
    return (result == 1)
