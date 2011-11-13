#include <module.h>
inherit "module";

constant cvs_version = "$Id: delay_sql.pike,v 1.4 2003/04/15 09:03:45 hungerf3 Exp $";

constant module_type = MODULE_TAG;
constant thread_safe=1;
string module_name = "Delayed SQL tag";
string module_doc = "Similar to sqlquery tag, but runs in the roxen backend instead"+"<br>options:<br><tt>host</tt> - host to connect to<br><tt>delay</tt> - seconds to try to delay<br><tt>query</tt> - sql query to run."
;

private int queries_done=0;
private int errors=0;
private string last_query="";
private object backend;


void create()
{
  defvar("database",
         Variable.DatabaseChoice("local", VAR_INITIAL,
				 "Database",
				 "This is the  default database to use"
				 "for the delayed queries, if none is"
				 "specified in the tag"
				 ));
  defvar("delay",
         Variable.Int(0, 0,
		      "Delay",
		      "This is the default time for the backend "
		      "to wait before it executes the query, unless "
		      "a time is specified in the tag"
		      ));

  set_module_creator("Jeff Hungerford <hungerf3@house.ofdoom.com>");
  set_module_url("http://house.ofdoom.com/~hungerf3/roxen/delay_sql");
}

void start(int occasion, Configuration conf)
{
  backend=roxenp();
}


  string status()
  {
  return "Queries Executed: "+queries_done+"\n<br>Errors: "+errors+
         "\n<br> The last query executed was: " +last_query; 
}


void run_query(string DB, string query)
{
  last_query=query;
  Sql.Sql sql = DBManager.cached_get(DB);
  if (sql) 
    {
      sql->query(query);
      if (!sql->error())
	{
	  queries_done++;
	}
      else
	{
	  errors++;
	  report_warning("Unable to connect to database "+DB);
	}
    }
  else
    {
      errors++;
      report_warning("Query "+query+"Failed on database "+DB);
    }
}

string simpletag_delaysql(string name, mapping arg, string contents, RequestID id)
{
  if (!has_index(arg,"host")) arg["host"]=QUERY(database);
  if (!has_index(arg,"delay")) arg["delay"]=QUERY(delay);

  if(has_index(arg,"query"))  backend->background_run(arg["delay"],
						      local::run_query, 
						      arg["host"],
						      arg["query"]);
  return "";
}

