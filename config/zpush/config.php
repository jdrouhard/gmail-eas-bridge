<?php
/*
 * Minimal z-push config.php for the Gmail EAS bridge stack.
 * This intentionally only sets the values this stack needs;
 * consult the upstream config.php.dist in the z-push repo for
 * the full list of options and their defaults.
 */

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

define('PROVISIONING', false);
define('LOOPDETECTION', true);

// Devices talk to this container over plain HTTP; terminate TLS in
// front of it (reverse proxy / load balancer) before exposing it
// to the internet. ActiveSync clients require HTTPS in practice.
define('USE_X_FORWARDED_FOR_HEADER', true);
