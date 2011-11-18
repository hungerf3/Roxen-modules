#include <module.h>
inherit "module";

constant cvs_version = "$Id: blacklist.pike,v 1.6 2005/01/03 12:49:01 hungerf3 Exp $";

constant module_type = MODULE_FIRST;
constant module_name = "Blacklisting Support";
constant module_doc  = "Denies requests to hosts listen on a specified IP Blocklist.";
constant thread_safe = 1;

constant default_template= #"
<html>
<head><title>Request from :ip: refused.</title>
</head>
<body>
<pre>
This request has been refused.

The requesting IP address :ip: is listed on :list:.
:list: has this information on the listing:

:reason:
</pre>
</body>
</html>
";

int passed;
int blocked;
int whitelist;


string status()
{
  return "Whitelists: " + sizeof(query("Deny")) + "<br>" +
    "Blacklists: " + sizeof(query("Allow")) + "<br>" +
    "Blocked Requests: " + blocked + "<br>" +
    "Passed Requests: " + passed + "<br>" +
    "Whitelisted: " + whitelist + "<br>";
}

void create(Configuration|void conf)
{
  passed=0;
  blocked=0;
  whitelist=0;
  set_module_creator("Jeff Hungerford <hungerf3@house.ofdoom.com>");
  set_module_url("http://house.ofdoom.com/~hungerf3/roxen/blacklist");
  
  defvar("Deny",
	 Variable.StringList(({}),VAR_INITIAL,
			     "Deny",
			     "These are the IP blocklists which this module should check and "
			     "refuse access if the client IP address is listed."));
  defvar("Allow",
	 Variable.StringList(({}),VAR_INITIAL,
			     "Allow",
			     "These are the IP blocklists which this module should check and "
			     "allow access if the client IP address is listed, even if the "
			     "IP address is listed on one of the Deny Blocklists."));
  defvar("Strict",
	 Variable.Flag(0,0,
		       "Strict",
		       "If checked, enforce strict checking of the blocklists. This will result in "
		       "The initial request to the server from an IP address being delayed until each "
		       "blocklist has responded.<br><br> "
		       "If this is not checked, then non-blocking requests will be used. "
		       "Responses will not be delayed, but there may be a window of a few seconds "
		       "or slightly longer where the data from some slow to respond blocklists will "
		       "not be consulted to determine if the request should be allowed or denied."));

  defvar("template", 
	 default_template, 
	 "Response Template", 
	 TYPE_TEXT, 
	 "The template for the reply to refused connections.<br><ul><li>:list: is replaced by the list name"
	 "<li>:ip: is replaced with the client IP address "
	 "<li>:reason: is replaced with the reason (if any) the list gives.");

}
  


mapping first_try( RequestID id)
{
  function lookup;
  int deny = 0;
  mapping reason=([]);

  if (query("Strict"))
    lookup = roxenp()->blocking_host_to_ip;
  else
    lookup = roxenp()->quick_host_to_ip;

  string reverse_ip = (reverse(id->remoteaddr/"."))*".";

  if (sizeof(query("Allow")))
    foreach (query("Allow"), string aBlocklist)
      {
	write("Checking "+reverse_ip+"."+aBlocklist+"\n");
	if (lookup(reverse_ip+"."+aBlocklist))
	  {
	    whitelist++;
	    return 0;
	  }
      }
  if (sizeof(query("Deny")))
    foreach (query("Deny"), string aBlocklist)
      {
	if (lookup(reverse_ip+"."+aBlocklist))
	  {
	    object d = Protocols.DNS.client();
	    deny=1;
	    reason[":list:"]=aBlocklist;
	    reason[":ip:"]=id->remoteaddr;
	    reason[":reason:"]="";
	    foreach (d->do_sync_query(d->mkquery(reverse_ip+"."+aBlocklist,
					      Protocols.DNS.C_IN, 
					      Protocols.DNS.T_TXT))["an"], mapping answer)
	      {
		reason[":reason:"]+=answer["txt"];
	      }
	  }
	
	if (deny)
	  break;
      }
  
  if (deny)
    {
      blocked++;
      return Roxen.http_low_answer(403, replace(query("template"),reason));
    }
  else
    {
      whitelist++;
      return 0;
    }
  
}


