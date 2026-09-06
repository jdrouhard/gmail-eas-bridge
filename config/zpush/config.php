<?php
/*
 * Minimal z-push config.php for the Gmail EAS bridge stack.
 * This intentionally only sets the values this stack needs;
 * consult the upstream config.php.dist in the z-push repo for
 * the full list of options and their defaults.
 */

define('BASE_PATH', dirname($_SERVER['SCRIPT_FILENAME']). '/');
define('SCRIPT_TIMEOUT', 0);

define('TIMEZONE', getenv('TZ') ?: 'UTC');
define('BACKEND_PROVIDER', 'BackendIMAP');

define('USE_FULLEMAIL_FOR_LOGIN', true);

define('STATE_MACHINE', 'FILE');
define('STATE_DIR', '/data/zpush-state/');

define('LOGFILEDIR', '/var/log/z-push/');
define('LOGFILE', LOGFILEDIR . 'z-push.log');
define('LOGERRORFILE', LOGFILEDIR . 'z-push-error.log');
define('LOGLEVEL', LOGLEVEL_WARN);
define('LOGUSERLEVEL', LOGLEVEL_WARN);
$specialLogUsers = array();

define('PROVISIONING', false);
define('SYNC_CONFLICT_DEFAULT', SYNC_CONFLICT_OVERWRITE_PIM);
define('SYNC_TIMEOUT_MEDIUM_DEVICETYPES', "SAMSUNGGTI");
define('SYNC_TIMEOUT_LONG_DEVICETYPES',   "iPod, iPad, iPhone, WP, WindowsOutlook, WindowsMail");
