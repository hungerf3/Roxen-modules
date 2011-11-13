#include <module.h>
inherit "module";

constant cvs_version = "$Id: mailcloak.pike,v 1.15 2005/04/07 16:47:53 hungerf3 Exp $";

constant module_type = MODULE_TAG|MODULE_FILTER;
constant thread_safe=1;
string module_name = "mailcloak";
string module_doc = "Cloaks e-mail addresses by converting them to graphics, and provides a form to send a reply";

private int mail_sent_count=0;
private string dbname;

private constant table_definitions = 
  ([ "address": ({ "id  INT UNSIGNED PRIMARY KEY",
		   "email char(64)"
  })
  ]);


void create()
{
  defvar("database",
         Variable.DatabaseChoice("local", VAR_INITIAL,
				 "Database",
				 "This is the database in which the "
				 "email/id mapping is stored. local is "
				 "suggested, unless you are using more "
				 "than one front end, in which case "
				 "you should use shared."
				 ));
  defvar("CloakAll",
	 Variable.Flag(0, 0,"Cloak Everything",
		       "If set, then this module will check for and cloak "
		       "Email addresses on every page on this server, without "
		       "needing to do anything else.  Leave this unset if you want "
		       "to control what pages are cloaked."
		       ));


  set_module_creator("Jeff Hungerford <hungerf3@house.ofdoom.com>");
  set_module_url("http://house.ofdoom.com/~hungerf3/roxen/mailcloak");
}

void start(int occasion, Configuration conf)
{
  module_dependencies(conf, ({ "graphic_text","email","html_wash" }));
  set_my_db(QUERY(database));
  create_sql_tables( table_definitions );
  dbname=get_my_table("address",table_definitions->address);
}

/* Capcha Support */

string rs(int len)
{
  //  array chr = "abcdefghjklmnpqrstuvwxyz23456789"/"";
  array chr = "wku4vl7esq7pr5f2kubntwxhy9agvr54thd3l8sge6p2fzzmd8xm9j3"/"";
  mapping d = localtime(time(1));
  string output = "";
  int offset;
  int size = sizeof(chr);
  offset = ((d["yday"]*24+d["hour"])%size);
  output = chr[offset];
  for (int i=1; i<len; i++)
    {
      output+=chr[random(size)];
    }
  return output;
}

int cs(string lock)
{
  string c1="";
  string c2="";
  int result=0;
  array chr = "wku4vl7esq7pr5f2kubntwxhy9agvr54thd3l8sge6p2fzzmd8xm9j3"/"";

  string key=String.trim_all_whites(lock)[0..0];

  mapping d = localtime(time(1));
  int i = d["yday"]*24+d["hour"];
  c1=chr[i%sizeof(chr)];
  c2=chr[(i-1)%sizeof(chr)];
  if ((key[0]==c1[0])||
      (key[0]==c2[0])) result=1;
  return result;

}

string gen_chall(RequestID id)
{
  string output="";
  string chall=rs(5);
  output+="Please type these letters ";
  output+="<input type='hidden' name='lock' value='"+hash(chall)+"'>";
  output+=Roxen.parse_rxml("<gtext align=top alt=***** crop='t' fgcolor=grey bgcolor=white>"+chall+"</gtext>",id);
  output+="<input size=6 type='text' name='key'><br>\n";
  return output;
}


int check_chall(int lock, string key)
{
  lock = (int) lock;
  int  result = 0;
  if (((int)lock)==((int)hash(String.trim_all_whites(lower_case(key)))))
    {
      if (cs(key))
        {
          result = 1;
        }
      else
        {

        }
    }
  return result;

}

int IsEmail(string s)
{
  int result=0;
  mixed chunks=s/"@";
  if (sizeof(chunks)==2)
    {
      result=has_value(chunks[1],".");
    }
  
  return result;
}

string ScanInput(string s, RequestID id)
{
  string output="";
  foreach ((s/"\n"), string line)
    {
      if (has_value(line,"@"))
	{
	  foreach((line/" "), string word)
	    {
	      if (IsEmail(word))
		{
		  output+=simpletag_mailcloak("mailcloak",0 ,word,id);
		}
	      else
		{
		  output+=word;
		}
	      output+=" ";
	    }
	}
      else
	{
	  output+=line;
	}
      output+="\n";
    }
  return output;
}

  string status()
  {
  return "Cloaked Addresses: "+count_cloaked_addresses()+"<br>Messages Sent: "+mail_sent_count;
}

int count_cloaked_addresses()
{
  return sql_query_ro(sprintf("select count(*) as count from %s",dbname))[0]->count;
}

int is_hash_in_db(int hash)
{
  return sql_big_query_ro(sprintf("select id from %s  where (id = %d);",dbname,hash))->num_rows();
}

void store_email(string email)
{
  int email_hash=hash(email);
  if (is_hash_in_db(email_hash)==0) 
    {
      sql_query(sprintf("insert into %s (id,email) values(%d,'%s');",dbname,email_hash,Sql.sql_util.quote(email)));
    }
}

string get_email(int hash)
{
  return sql_query_ro(sprintf("select email from %s where id=%d",dbname,hash))[0]->email;
}

string simpletag_mailcloakall(string name, mapping arg, string contents, RequestID id)
{
  id->misc["mailcloak"]=1;
  return 0;
}

string simpletag_mailcloak(string name, mapping arg, string contents, RequestID id)
{
  string use_args=" ";
  if(arg)
    {
      if (arg["fgcolor"]) use_args+="fgcolor="+arg["fgcolor"]+" ";
      if (arg["bgcolor"]) use_args+="bgcolor="+arg["bgcolor"]+" ";
    }
  store_email(contents);
  return  Roxen.parse_rxml("<A target='_new'  HREF='" + query_absolute_internal_location(id) +hash(contents)+"/compose'><gtext format='png'" + use_args +" scale=0.5 alt='click to email'>"+contents+"</gtext></A>",id);
  
}

mapping|void filter(mapping|void result, RequestID id)
{
  return 0;
  if(!result || !stringp(result->data) || !equal("text/html", result->type)) return 0;
  if (has_index(id->misc,"mailcloak") && query("CloakAll")==0) return 0;

  //  result->data=ScanInput(result->data,id);
  //return result;

}

mapping find_internal( string path, RequestID id )
{
  switch(id->method)
    {
    case "GET":
    case "HEAD":
    case "POST":
      array(string) local_p = (path-query_absolute_internal_location(id))/"/";
      
      switch(local_p[1])
	{
	case "compose":
	  if (is_hash_in_db((int)local_p[0])==0)
	    {
	      return Roxen.http_low_answer(400, "Unknown ID");
	    }
	  else
	    {
	      return Roxen.http_string_answer(Roxen.parse_rxml("<html><head><title>Compose Email</title></head><body><center><table><form action='"+query_absolute_internal_location(id)+local_p[0]+"/send' method='post'><tr><td>To:</td><td><gtext scale='0.5' alt='cloaked'>"+get_email((int)local_p[0])+"</gtext></td></tr><tr><td>Your Name:</td><td><input type=text size=30 name=name /></td></tr><tr><td>Your Email:</td><td><input type=text size=30 name=email /></td></tr><tr><td>Your IP:</td><td>&client.ip;</td></tr><tr><td colspan=2>"+gen_chall(id)+"</td></tr><tr><td colspan=2><textarea name=comment rows=25 cols=40></textarea></td></tr><tr><td colspan=2><input type=submit value=send><br></td></tr></form></table></center></body></html>",id));
	    }
	  break;
	  
	  
	case "send":
	  if (is_hash_in_db((int)local_p[0])==0)
	    {
	      return Roxen.http_low_answer(400, "Unknown ID");
	    }
	  else
	    {
	      if(check_chall((int)(id->variables["lock"]),id->variables["key"]))
		{
		  mail_sent_count++;
		  return Roxen.http_string_answer(Roxen.parse_rxml("<html><head><title>mail sent</title></head><body><email subject='Mail from &form.name; via emailcloak' to='"+get_email((int)local_p[0])+"' from='&form.email;'><header name='X-Sending-IP' value='&client.ip;' /><wash-html unparagraphify='t' unlinkify='t'>&form.comment;</wash-html></email><center>Your message has been sent.<br>Please close this window.</center></body></html> ",id));
		}
	      else
		{
		  return Roxen.http_string_answer("<html><body>Wrong Code. Ip flagged.</body></html>");
		}
	    }
	  break;
	  
	default:
	  return Roxen.http_low_answer(400, "Unknown task");
	  
	}
      
      break;
      
    case "PUT":
      return Roxen.http_low_answer(405, "Method not allowed");
      break;
    default:
      return Roxen.http_low_answer(400, "Bad Request");
      break;
      
    }
}
