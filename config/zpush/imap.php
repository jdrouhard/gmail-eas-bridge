<?php
/*
 * z-push IMAP backend config.
 * Deliberately points at the LOCAL Dovecot instance (127.0.0.1),
 * not at Gmail directly. Dovecot serves the mbsync-maintained
 * Maildir over IMAP and relays outgoing mail to Gmail's SMTP via
 * its submission service. See README.md for the full picture.
 *
 * NOTE: field names below match the BackendIMAP config format as of
 * the Z-Hub/Z-Push "develop" branch at the time this was written.
 * z-push's config format has drifted across releases before -
 * diff this against src/backend/imap/config.php in whatever
 * ZPUSH_REF you actually build against.
 */

define('IMAP_SERVER', '127.0.0.1');
define('IMAP_PORT', 143);
define('IMAP_OPTIONS', '/notls/novalidate-cert');
define('IMAP_AUTOSEEN_ON_DELETE', false);

// --- Outbound mail -----------------------------------------------------
// 'mail' | 'sendmail' | 'smtp' - we want a direct SMTP submit to the
// local Dovecot submission service, not PHP mail()/sendmail.
define('IMAP_SMTP_METHOD', 'smtp');

global $imap_smtp_params;
// 'imap_username' / 'imap_password' are literal sentinel strings that
// BackendIMAP substitutes at runtime with the credentials the EAS
// device authenticated with - do not replace them with real values.
$imap_smtp_params = array(
    'host'              => 'localhost',
    'port'              => 587,
    'auth'              => true,
    'username'          => 'imap_username',
    'password'          => 'imap_password',
    'verify_peer'       => false,
    'verify_peer_name'  => false,
    'allow_self_signed' => true,
);

// --- Folder mapping ------------------------------------------------------
// Must match how mbsync names things locally - see
// config/mbsync/mbsyncrc.template "Patterns" line.
define('IMAP_FOLDER_CONFIGURED', true);
define('IMAP_FOLDER_PREFIX', '');
define('IMAP_FOLDER_PREFIX_IN_INBOX', false);
define('IMAP_FOLDER_INBOX',   'INBOX');
define('IMAP_FOLDER_SENT',    'Sent');
define('IMAP_FOLDER_DRAFT',   'Drafts');
define('IMAP_FOLDER_TRASH',   'Trash');
define('IMAP_FOLDER_SPAM',    'Spam');
define('IMAP_FOLDER_ARCHIVE', 'Archive');

define('SYSTEM_MIME_TYPES_MAPPING', '/etc/mime.types');
