#include <module.h>
inherit "module";

constant cvs_version = "$Id:$";

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



// Templates

constant CAPTCHA_TEMPLATE = #"
Please type these letters
<input type='hidden' name='lock' value=':lock:'>
img src=':src:' width=:width: height=:height:>
<input size=6 type='text' name='key'><br>\n";
  

constant COMPOSE_TEMPLATE = #"
<html><head><title>Compose Email</title></head><body>
<center><table><form action=':send_location:' method='post'>
<tr><td>To:</td><td>
<img src=':email_graphic:'</td></tr><tr><td>
Your Name:</td><td><input type=text size=30 name=name /></td></tr><tr><td>
Your Email:</td><td><input type=text size=30 name=email /></td></tr><tr><td>
Your IP:</td><td>&client.ip;</td></tr><tr><td colspan=2>:captcha:</td></tr><tr><td colspan=2>
<textarea name=comment rows=25 cols=40></textarea></td></tr><tr><td colspan=2><input type=submit value=send><br></td></tr></form></table></center></body></html>";

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



  defvar("CaptchaTemplate",
         Variable.Text(CAPTCHA_TEMPLATE,
                       0, "Captcha Template",
                       "The template to be used for the captcha. "
		       "<ul>"
                       "<li><tt>:src:</tt> is replaced with the image path. "
                       "<li><tt>:lock:</tt> is the hash that needs to be retured as \"lock\" "
                       "<li><tt>:width:</tt> and <tt>:height:</tt> are the dimensions of the image"
		       "</ul>"));

  defvar("ComposeTemplate",
         Variable.Text(COMPOSE_TEMPLATE,
                       0, "Compose Template",
                       "The template to be used for the Email compose page. "
		       "<ul>"
                       "<li><tt>:send_location:</tt> is replaced with the path to post the form to "
                       "<li><tt>:email_graphic:</tt> is replaced with a graphic of the desitnation address "
                       "<li><tt>:captcha:</tt> is replaced by the captcha."
		       "</ul>"
                       "The form should contain fields <tt>name</tt>, <tt>email</tt> and <tt>comment</tt>"));
  
  defvar("EmailRegex",
         Variable.String("([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+)", 0,
                         "Email Regular Expression",
                         "When asked to cloak all addresses on a page, this regular "
                         "expression is used to find email addresses."));


  set_module_creator("Jeff Hungerford <hungerf3@house.ofdoom.com>");
  set_module_url("http://house.ofdoom.com/~hungerf3/roxen/mailcloak");
}

void start(int occasion, Configuration conf)
{
  module_dependencies(conf, ({ "email","html_wash","captcha", "graphic_text" }));
  set_my_db(query("database"));
  create_sql_tables( table_definitions );
  dbname=get_my_table("address",table_definitions->address);
}


string gen_chall(RequestID id)
{
  mapping chall = id->configuration()
    ->find_module("captcha")
    ->get_captcha(id);


  return replace(query("CaptchaTemplate"),
                 ([":lock:":(string)(chall["secret"]),
                   ":src:":(string)(chall["url"]),
                   ":width:":(string)(chall["image-width"]),
                   ":height:":(string)(chall["image-height"])
                 ])
                 );
}


int check_chall(string lock, string key, RequestID id)
{
  return id->configuration()
    ->find_module("captcha")
    ->verify_captcha(key, lock);
}


string status()
{
  return "Cloaked Addresses: " + count_cloaked_addresses() + "<br>Messages Sent: " + mail_sent_count;
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
  int email_hash = hash(email);
  if (is_hash_in_db(email_hash) == 0) 
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
  id->misc["mailcloak"] = 1;
  return "<!-- Cloaking all addresses -->";;
}

string simpletag_mailcloak(string name, mapping arg, string contents, RequestID id)
{
  string use_args = " ";
  if(arg)
    {
      if (arg["fgcolor"]) use_args+="fgcolor="+arg["fgcolor"]+" ";
      if (arg["bgcolor"]) use_args+="bgcolor="+arg["bgcolor"]+" ";
    }
  store_email(contents);
  return  Roxen.parse_rxml("<A target='_new'  HREF='" +
			   query_absolute_internal_location(id) +hash(contents) + 
			   "/compose'><gtext format='png'" +
			   use_args + 
			   " scale=0.5 alt='click to email'>" + 
			   contents + 
			   "</gtext></A>",id);
  
}

mapping|void filter(mapping|void result, RequestID id)
{
  // Skip non HTML documents
  if(!result || !stringp(result->data) || !equal("text/html", result->type)) return 0;
  // Are we supposed to scan for addresses?
  if (has_index(id->misc,"mailcloak") || query("CloakAll")==1)
    {
      // Scan for addresses, and cloak all of them.
      string _cloak_address(string address)
      {
        return simpletag_mailcloak("mailcloak",
                                   0,
                                   address,
                                   id);
      };
      
      result->data = Regexp.SimpleRegexp(query("EmailRegex"))
        ->replace(result->data, _cloak_address);
    }
  return result;
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
              return Roxen.http_string_answer(
                                              Roxen.parse_rxml(
                                                               replace ( query("ComposeTemplate"),
									 ([":send_location:": query_absolute_internal_location(id)+local_p[0]+"/send",
									   ":email_graphic:": Roxen.parse_rxml("<gtext-url>"+
													       get_email((int)local_p[0])+
													       "</gtext-url>",id),
									   ":captcha:": gen_chall(id)
									 ])),
                                                               id)
                                              );
            }
          break;
          
          
        case "send":
          if (is_hash_in_db((int)local_p[0]) == 0)
            {
              return Roxen.http_low_answer(400, "Unknown ID");
            }
          else
            {
              if(check_chall(id->variables["lock"],
			     id->variables["key"],
			     id))
                {
                  mail_sent_count++;
                  Roxen.parse_rxml("<email subject='Mail from &form.name; via emailcloak' to='" + 
				   get_email((int)local_p[0]) + 
				   "' from='&form.email;'><header name='X-Sending-IP' value='&client.ip;' /><wash-html unparagraphify='t' unlinkify='t'>&form.comment;</wash-html></email>",id);
                  return Roxen.http_string_answer("<html><head><title>mail sent</title></head><body><center>Your message has been sent.<br>Please close this window.</center></body></html>");
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
