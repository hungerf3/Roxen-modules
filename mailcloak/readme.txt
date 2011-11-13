This is a e-mail address cloaking module for Roxen 2.2 or higher.
place <mailcloak></mailcloak> tags around an address to protect it.

Whole pages can be protected by putting a <mailcloakall /> tag somewhere
in the page.  All email addresses will be found and cloaked.

Whole servers can be protected by setting a flag in the module controls.

Addresses are replaced by gtext images linked to a form that can be used
to send a mail to that address.  Email addresses and their hash values
are stored in Roxen's internal database - hashes are used to identify 
the email address that mail should be sent to.

If you are interested in using this, feel free to try it out. 
You may use it under any version of the GPL.

-Jeff Hungerford